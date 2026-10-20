-- =====================================================================
-- Pruebas industriales · v2 · Migración 7
-- Permisos por puesto (matriz de autoridades), folio PI-AAAA-NNN, reglas
-- de cada etapa (triggers), acciones del flujo (RPC prubind_accion),
-- protección de recetas oficiales, vistas, tablero, RLS y privilegios.
-- El perfil de administrador NO confiere autoridad técnica.
-- =====================================================================

drop function if exists public.prubind_tiene_funcion(text);

-- ---------- Textos ------------------------------------------------------
create or replace function public.prubind_estado_txt(p text)
returns text language sql immutable set search_path = '' as $$
  select case p when 'registrada' then 'Registrada' when 'en_preparacion' then 'En preparación' when 'preparada' then 'Preparada'
    when 'en_ejecucion' then 'En ejecución' when 'en_evaluacion' then 'En evaluación' when 'pendiente_resultados' then 'Pendiente de resultados'
    when 'pendiente_dictamen' then 'Pendiente de dictamen' when 'aprobada' then 'Aprobada (por cerrar)' when 'rechazada' then 'Rechazada (por cerrar)'
    when 'requiere_repeticion' then 'Requiere repetición' when 'cerrada_aprobada' then 'Cerrada y aprobada'
    when 'cerrada_rechazada' then 'Cerrada y rechazada' when 'cancelada' then 'Cancelada' else p end
$$;
create or replace function public.prubind_accion_txt(p text)
returns text language sql immutable set search_path = '' as $$
  select case p when 'preparar' then 'preparar la prueba' when 'abastecer' then 'abastecimiento de materiales'
    when 'autorizar_ejecucion' then 'autorizar la ejecución' when 'ejecutar' then 'registrar la ejecución' when 'evaluar' then 'capturar evaluaciones'
    when 'dictaminar' then 'emitir el dictamen' when 'cerrar' then 'cerrar la prueba' when 'autorizar_implementacion' then 'autorizar la implementación'
    when 'cancelar' then 'cancelar la prueba' else p end
$$;

-- ---------- Identidad y autoridad ---------------------------------------
create or replace function public.prubind_puesto_actual()
returns uuid language sql stable security definer set search_path = '' as $$
  select u.puesto_id from public.usuarios_prubind u
  where lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', '')) and u.activo limit 1
$$;

create or replace function public.prubind_tiene_autoridad(p_tipo text, p_accion text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.autoridades_prubind a
    where a.activo and a.accion = p_accion and (a.tipo is null or a.tipo = p_tipo)
      and ((a.usuario_id is not null and a.usuario_id = public.prubind_usuario_actual_id())
        or (a.puesto_id is not null and a.puesto_id = public.prubind_puesto_actual())))
$$;

create or replace function public.prubind_tiene_autoridad_alguna(p_accion text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.autoridades_prubind a
    where a.activo and a.accion = p_accion
      and ((a.usuario_id is not null and a.usuario_id = public.prubind_usuario_actual_id())
        or (a.puesto_id is not null and a.puesto_id = public.prubind_puesto_actual())))
$$;

-- ¿Puede el usuario actual realizar la acción sobre la prueba?
create or replace function public.prubind_puede(p_prueba uuid, p_accion text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare
  v   public.pruebas_prubind%rowtype;
  uid uuid := public.prubind_usuario_actual_id();
begin
  if uid is null then return false; end if;
  select * into v from public.pruebas_prubind where id = p_prueba;
  if not found then return false; end if;
  return case p_accion
    when 'preparar' then uid = v.registrado_por or uid = v.responsable_inicial_id or uid = v.responsable_ejecucion_id
                         or public.prubind_tiene_autoridad(v.tipo, 'preparar')
    when 'abastecer' then public.prubind_tiene_autoridad(v.tipo, 'abastecer') or public.prubind_puede(p_prueba, 'preparar')
    when 'ejecutar'  then uid = v.responsable_ejecucion_id or public.prubind_tiene_autoridad(v.tipo, 'ejecutar')
    when 'cancelar'  then uid = v.registrado_por or uid = v.responsable_inicial_id
                         or public.prubind_tiene_autoridad(v.tipo, 'cerrar') or public.prubind_tiene_autoridad(v.tipo, 'dictaminar')
    else public.prubind_tiene_autoridad(v.tipo, p_accion)
  end;
end $$;

create or replace function public.prubind_puede_crear_tipo(p_tipo text)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.prubind_es_miembro() and exists (select 1 from public.tipos_prueba_prubind t where t.codigo = p_tipo and t.activo)
$$;

drop function if exists public.prubind_mi_perfil();
create function public.prubind_mi_perfil()
returns table (id uuid, email text, nombre text, rol text, area_id uuid, area text, puesto_id uuid, puesto text, foto_url text, autoridades jsonb)
language sql stable security definer set search_path = '' as $$
  select u.id, u.email, u.nombre, u.rol, u.area_id, a.nombre, u.puesto_id, p.nombre, u.foto_url,
         coalesce((select jsonb_agg(distinct jsonb_build_object('tipo', x.tipo, 'accion', x.accion))
                   from public.autoridades_prubind x
                   where x.activo and (x.usuario_id = u.id or (x.puesto_id is not null and x.puesto_id = u.puesto_id))), '[]'::jsonb)
  from public.usuarios_prubind u
  left join public.areas_prubind a on a.id = u.area_id
  left join public.puestos_prubind p on p.id = u.puesto_id
  where lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', '')) and u.activo
$$;

-- Carga una prueba validando estado y autoridad (uso interno)
create or replace function public.prubind_req(p_prueba uuid, p_accion text, p_estados text[], p_msg text default null)
returns public.pruebas_prubind language plpgsql security definer set search_path = '' as $$
declare v public.pruebas_prubind%rowtype;
begin
  select * into v from public.pruebas_prubind where id = p_prueba;
  if not found then raise exception 'La prueba no existe.' using errcode = 'P0001'; end if;
  if p_estados is not null and not (v.estado = any (p_estados)) then
    raise exception '%', coalesce(p_msg, 'Acción no disponible: la prueba está "' || public.prubind_estado_txt(v.estado) || '".') using errcode = 'P0001';
  end if;
  if p_accion is not null and not public.prubind_puede(p_prueba, p_accion) then
    raise exception 'No tiene autoridad para %. La autoridad se asigna por puesto en "Autoridades".', public.prubind_accion_txt(p_accion) using errcode = '42501';
  end if;
  return v;
end $$;

-- Cambia el estado (uso interno; registra el evento)
create or replace function public.prubind_set_estado(p_prueba uuid, p_estado text, p_txt text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform set_config('prubind.rpc', '1', true);
  update public.pruebas_prubind set estado = p_estado where id = p_prueba and estado is distinct from p_estado;
  perform set_config('prubind.rpc', '', true);
  if p_txt is not null then perform public.prubind_log(p_prueba, 'estado', p_txt); end if;
end $$;

-- ---------- updated_at y auditoría --------------------------------------
do $$
declare t text;
begin
  foreach t in array array['puestos_prubind','unidades_prubind','objetivos_prubind','productos_prubind','materias_primas_prubind',
    'proveedores_prubind','lotes_mp_prubind','equipos_prubind','equipo_parametros_prubind','recetas_prubind','receta_versiones_prubind',
    'metodos_prubind','especificaciones_prubind','plantilla_evaluacion_prubind','motivos_prubind','tipos_evidencia_prubind',
    'pruebas_prubind','prueba_materiales_prubind','batches_prubind','ejecucion_controles_prubind','resultados_prubind'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_touch', t);
    execute format('create trigger %I before update on public.%I for each row execute function public.prubind_touch_updated_at()', t || '_touch', t);
  end loop;
  foreach t in array array['puestos_prubind','unidades_prubind','objetivos_prubind','productos_prubind','materias_primas_prubind',
    'proveedores_prubind','lotes_mp_prubind','equipos_prubind','equipo_parametros_prubind','recetas_prubind','receta_versiones_prubind',
    'receta_ingredientes_prubind','metodos_prubind','especificaciones_prubind','plantilla_evaluacion_prubind','motivos_prubind',
    'tipos_evidencia_prubind','autoridades_prubind','pruebas_prubind','prueba_formulacion_prubind','prueba_materiales_prubind',
    'prueba_parametros_prubind','plan_evaluacion_prubind','puntos_muestreo_prubind','lotes_diarios_prubind','batches_prubind',
    'ejecucion_controles_prubind','muestras_prubind','resultados_prubind','dictamenes_prubind','autorizaciones_prubind','adjuntos_prubind'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_audit', t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.prubind_auditar()', t || '_audit', t);
  end loop;
end $$;
drop trigger if exists batch_lotes_mp_prubind_audit on public.batch_lotes_mp_prubind;
create trigger batch_lotes_mp_prubind_audit after insert or update or delete on public.batch_lotes_mp_prubind
  for each row execute function public.prubind_auditar('batch_id');
drop trigger if exists muestra_batches_prubind_audit on public.muestra_batches_prubind;
create trigger muestra_batches_prubind_audit after insert or delete on public.muestra_batches_prubind
  for each row execute function public.prubind_auditar('muestra_id');
drop trigger if exists seguimiento_prubind_validar on public.seguimiento_prubind;
create trigger seguimiento_prubind_validar before insert on public.seguimiento_prubind
  for each row execute function public.prubind_validar_seguimiento();

-- ---------- Recetas oficiales: nunca se modifican por una prueba --------
create or replace function public.prubind_validar_receta_version()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return new; end if;
  if tg_op = 'UPDATE' then
    if new.receta_id is distinct from old.receta_id then
      raise exception 'No se puede mover una versión a otra receta.' using errcode = 'P0001';
    end if;
    if old.estado <> 'borrador' and new.version is distinct from old.version then
      raise exception 'La versión vigente o histórica no puede renombrarse.' using errcode = 'P0001';
    end if;
    if old.estado in ('vigente', 'historica') and new.estado = 'borrador' then
      raise exception 'Una versión publicada no regresa a borrador; cree una versión nueva.' using errcode = 'P0001';
    end if;
  end if;
  if new.estado = 'vigente' and (tg_op = 'INSERT' or old.estado <> 'vigente') then
    if not exists (select 1 from public.receta_ingredientes_prubind i where i.version_id = new.id) and tg_op = 'UPDATE' then
      raise exception 'La versión no tiene ingredientes.' using errcode = 'P0001';
    end if;
    update public.receta_versiones_prubind set estado = 'historica'
     where receta_id = new.receta_id and estado = 'vigente' and id <> new.id;
    new.vigente_desde := coalesce(new.vigente_desde, public.prubind_hoy());
  end if;
  if tg_op = 'INSERT' then new.created_by := public.prubind_usuario_actual_id(); end if;
  return new;
end $$;
drop trigger if exists receta_versiones_prubind_validar on public.receta_versiones_prubind;
create trigger receta_versiones_prubind_validar before insert or update on public.receta_versiones_prubind
  for each row execute function public.prubind_validar_receta_version();

create or replace function public.prubind_validar_receta_ingrediente()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_estado text;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return coalesce(new, old); end if;
  if coalesce(current_setting('prubind.rpc', true), '') = '1' then return coalesce(new, old); end if;
  select estado into v_estado from public.receta_versiones_prubind
   where id = case when tg_op = 'DELETE' then old.version_id else new.version_id end;
  if v_estado is null then return coalesce(new, old); end if;  -- borrado en cascada de un borrador
  if v_estado <> 'borrador' then
    raise exception 'La receta oficial (versión vigente o histórica) no se modifica. Cree una versión nueva en borrador.' using errcode = 'P0001';
  end if;
  if tg_op = 'UPDATE' and new.version_id is distinct from old.version_id then
    raise exception 'No se puede mover un ingrediente a otra versión.' using errcode = 'P0001';
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists receta_ingredientes_prubind_validar on public.receta_ingredientes_prubind;
create trigger receta_ingredientes_prubind_validar before insert or update or delete on public.receta_ingredientes_prubind
  for each row execute function public.prubind_validar_receta_ingrediente();

-- Crea una versión en borrador copiando otra (solo administradores)
create or replace function public.prubind_clonar_version(p_version uuid, p_nueva text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v public.receta_versiones_prubind%rowtype; v_id uuid;
begin
  if not public.prubind_es_admin() then raise exception 'Solo administradores gestionan recetas.' using errcode = '42501'; end if;
  select * into v from public.receta_versiones_prubind where id = p_version;
  if not found then raise exception 'Versión no encontrada.' using errcode = 'P0001'; end if;
  if nullif(btrim(p_nueva), '') is null then raise exception 'Indique el nombre de la nueva versión.' using errcode = 'P0001'; end if;
  insert into public.receta_versiones_prubind (receta_id, version, estado, notas)
  values (v.receta_id, btrim(p_nueva), 'borrador', 'Copia de la versión ' || v.version) returning id into v_id;
  perform set_config('prubind.rpc', '1', true);
  insert into public.receta_ingredientes_prubind (version_id, materia_prima_id, cantidad, unidad_id, orden)
  select v_id, materia_prima_id, cantidad, unidad_id, orden from public.receta_ingredientes_prubind where version_id = p_version;
  perform set_config('prubind.rpc', '', true);
  return v_id;
end $$;

-- ---------- Etapa 1 · Registro (folio y validaciones) ------------------
create or replace function public.prubind_validar_prueba()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  uid   uuid := public.prubind_usuario_actual_id();
  v_rpc boolean := coalesce(current_setting('prubind.rpc', true), '') = '1';
  t     public.tipos_prueba_prubind%rowtype;
  v_n   integer;
  v_anio integer;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return coalesce(new, old); end if;
  if uid is null then raise exception 'Usuario no autorizado para Pruebas industriales.' using errcode = '42501'; end if;

  if tg_op = 'DELETE' then
    if old.estado <> 'registrada' then
      raise exception 'Solo se eliminan pruebas en estado "Registrada". Las demás se cancelan con motivo.' using errcode = 'P0001';
    end if;
    if not (uid = old.registrado_por or public.prubind_es_admin()) then
      raise exception 'Solo quien registró la prueba puede eliminarla.' using errcode = '42501';
    end if;
    if exists (select 1 from public.adjuntos_prubind a where a.prueba_id = old.id) then
      raise exception 'Elimine primero los archivos adjuntos.' using errcode = 'P0001';
    end if;
    return old;
  end if;

  select * into t from public.tipos_prueba_prubind where codigo = new.tipo;
  new.cambio := btrim(new.cambio);
  new.objetivo_desc := nullif(btrim(new.objetivo_desc), '');
  new.prioridad_just := case when new.prioridad = 'normal' then null else nullif(btrim(new.prioridad_just), '') end;
  new.proceso := nullif(btrim(new.proceso), '');
  new.empaque := nullif(btrim(new.empaque), '');
  new.plan_muestreo := nullif(btrim(new.plan_muestreo), '');
  -- Solo se conservan los campos que aplican al tipo de prueba
  if not ('producto' = any (t.campos_registro)) then new.producto_id := null; end if;
  if not ('receta' = any (t.campos_registro)) then new.receta_version_id := null; end if;
  if not ('materia_prima' = any (t.campos_registro)) then new.materia_prima_id := null; end if;
  if not ('proveedor' = any (t.campos_registro)) then new.proveedor_id := null; end if;
  if not ('equipo' = any (t.campos_registro)) then new.equipo_id := null; end if;
  if not ('proceso' = any (t.campos_registro)) then new.proceso := null; end if;
  if not ('empaque' = any (t.campos_registro)) then new.empaque := null; end if;
  if new.prioridad <> 'normal' and new.prioridad_just is null then
    raise exception 'Justifique la prioridad alta o urgente.' using errcode = 'P0001';
  end if;
  if new.objetivo_id is not null and not exists (select 1 from public.objetivos_prubind o where o.id = new.objetivo_id and (o.tipo is null or o.tipo = new.tipo)) then
    raise exception 'El objetivo no corresponde al tipo de prueba.' using errcode = 'P0001';
  end if;
  if new.receta_version_id is not null and (tg_op = 'INSERT' or new.receta_version_id is distinct from old.receta_version_id)
     and not exists (select 1 from public.receta_versiones_prubind r where r.id = new.receta_version_id and r.estado = 'vigente') then
    raise exception 'Seleccione la versión vigente de la receta.' using errcode = 'P0001';
  end if;

  if tg_op = 'INSERT' then
    if not public.prubind_puede_crear_tipo(new.tipo) then
      raise exception 'El tipo de prueba no está activo.' using errcode = 'P0001';
    end if;
    v_anio := extract(year from public.prubind_hoy())::integer;
    insert into public.folios_prubind as f (anio, ultimo) values (v_anio, 1)
      on conflict (anio) do update set ultimo = f.ultimo + 1 returning ultimo into v_n;
    new.anio := v_anio; new.consecutivo := v_n;
    new.folio := 'PI-' || v_anio || '-' || lpad(v_n::text, 3, '0');
    new.registrado_por := uid;
    new.estado := 'registrada'; new.ejecucion_actual := 1;
    new.plan_confirmado_at := null; new.plan_confirmado_por := null;
    new.motivo_cancelacion := null; new.cancelado_por := null; new.cancelado_at := null;
    new.disposicion_cierre := null; new.cerrada_por := null; new.cerrada_at := null;
    return new;
  end if;

  -- UPDATE
  if v_rpc then return new; end if;
  if (new.folio, new.anio, new.consecutivo, new.tipo, new.registrado_por, new.estado, new.ejecucion_actual,
      new.plan_confirmado_at, new.plan_confirmado_por, new.motivo_cancelacion, new.cancelado_por, new.cancelado_at,
      new.disposicion_cierre, new.cerrada_por, new.cerrada_at)
     is distinct from
     (old.folio, old.anio, old.consecutivo, old.tipo, old.registrado_por, old.estado, old.ejecucion_actual,
      old.plan_confirmado_at, old.plan_confirmado_por, old.motivo_cancelacion, old.cancelado_por, old.cancelado_at,
      old.disposicion_cierre, old.cerrada_por, old.cerrada_at) then
    raise exception 'El folio, el tipo y el estado solo cambian mediante las acciones de la prueba.' using errcode = 'P0001';
  end if;
  if old.estado not in ('registrada', 'en_preparacion') then
    raise exception 'Los datos de registro y preparación solo se modifican antes de marcar la prueba como preparada.' using errcode = 'P0001';
  end if;
  if not public.prubind_puede(old.id, 'preparar') then
    raise exception 'No tiene autoridad para modificar esta prueba.' using errcode = '42501';
  end if;
  if old.estado = 'registrada' and (new.fecha_planeada, new.batches_planeados, new.peso_objetivo_kg, new.responsable_ejecucion_id, new.plan_muestreo)
       is distinct from (old.fecha_planeada, old.batches_planeados, old.peso_objetivo_kg, old.responsable_ejecucion_id, old.plan_muestreo) then
    new.estado := 'en_preparacion';
  end if;
  return new;
end $$;
drop trigger if exists pruebas_prubind_validar on public.pruebas_prubind;
create trigger pruebas_prubind_validar before insert or update or delete on public.pruebas_prubind
  for each row execute function public.prubind_validar_prueba();

create or replace function public.prubind_despues_prueba()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    perform public.prubind_log(new.id, 'estado', 'Prueba registrada con folio ' || new.folio || '.');
  elsif new.estado = 'en_preparacion' and old.estado = 'registrada' then
    perform public.prubind_log(new.id, 'estado', 'Inició la preparación.');
  end if;
  return new;
end $$;
drop trigger if exists pruebas_prubind_despues on public.pruebas_prubind;
create trigger pruebas_prubind_despues after insert or update on public.pruebas_prubind
  for each row execute function public.prubind_despues_prueba();

-- ---------- Etapa 2 · Preparación (tablas hijas) ------------------------
create or replace function public.prubind_validar_prep()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v       public.pruebas_prubind%rowtype;
  v_pid   uuid;
  v_solo_abasto boolean := false;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return coalesce(new, old); end if;
  if coalesce(current_setting('prubind.rpc', true), '') = '1' then return coalesce(new, old); end if;
  v_pid := case when tg_op = 'DELETE' then old.prueba_id else new.prueba_id end;
  select * into v from public.pruebas_prubind where id = v_pid;
  if v.id is null then return coalesce(new, old); end if;  -- borrado en cascada
  if tg_op = 'UPDATE' and new.prueba_id is distinct from old.prueba_id then
    raise exception 'No se puede mover el registro a otra prueba.' using errcode = 'P0001';
  end if;

  -- Compras/Almacén actualizan compra y disponibilidad hasta la ejecución
  if tg_table_name = 'prueba_materiales_prubind' and tg_op = 'UPDATE'
     and (new.materia_prima_id, new.cantidad, new.unidad_id) is not distinct from (old.materia_prima_id, old.cantidad, old.unidad_id) then
    v_solo_abasto := true;
    perform public.prubind_req(v_pid, 'abastecer', array['registrada','en_preparacion','preparada','en_ejecucion']);
    new.actualizado_por := public.prubind_usuario_actual_id();
    new.observaciones := nullif(btrim(new.observaciones), '');
    return new;
  end if;

  perform public.prubind_req(v_pid, 'preparar', array['registrada','en_preparacion'],
    'La preparación solo se modifica antes de marcar la prueba como preparada.');

  if tg_table_name = 'plan_evaluacion_prubind' and v.plan_confirmado_at is not null then
    perform set_config('prubind.rpc', '1', true);
    update public.pruebas_prubind set plan_confirmado_at = null, plan_confirmado_por = null where id = v_pid;
    perform set_config('prubind.rpc', '', true);
  end if;
  if v.estado = 'registrada' then
    perform public.prubind_set_estado(v_pid, 'en_preparacion', null);  -- el trigger de pruebas registra el evento
  end if;
  if tg_op = 'DELETE' then return old; end if;

  if tg_table_name = 'prueba_formulacion_prubind' then
    if new.accion <> 'sustituir' then
      new.sustituye_a_id := null;
      new.accion := case
        when new.cantidad_original is null then 'agregar'
        when coalesce(new.cantidad_propuesta, 0) = 0 then 'retirar'
        when new.cantidad_propuesta <> new.cantidad_original then 'modificar'
        else 'sin_cambio' end;
    elsif new.sustituye_a_id is null then
      raise exception 'Indique qué materia prima se sustituye.' using errcode = 'P0001';
    end if;
  elsif tg_table_name = 'prueba_materiales_prubind' then
    new.actualizado_por := public.prubind_usuario_actual_id();
    new.observaciones := nullif(btrim(new.observaciones), '');
  elsif tg_table_name = 'prueba_parametros_prubind' then
    new.nombre := btrim(new.nombre);
    if new.parametro_id is not null then
      select p.nombre, p.unidad_id, p.minimo, p.maximo, p.referencia
        into new.nombre, new.unidad_id, new.minimo, new.maximo, new.referencia
        from public.equipo_parametros_prubind p where p.id = new.parametro_id and p.equipo_id = new.equipo_id;
      if not found then raise exception 'El parámetro no pertenece al equipo.' using errcode = 'P0001'; end if;
    end if;
  elsif tg_table_name = 'plan_evaluacion_prubind' then
    if tg_op = 'UPDATE' and new.metodo_id is distinct from old.metodo_id then
      raise exception 'No se puede cambiar el método de un renglón del plan.' using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;
do $$
declare t text;
begin
  foreach t in array array['prueba_formulacion_prubind','prueba_materiales_prubind','prueba_parametros_prubind',
                           'plan_evaluacion_prubind','puntos_muestreo_prubind'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_validar', t);
    execute format('create trigger %I before insert or update or delete on public.%I for each row execute function public.prubind_validar_prep()', t || '_validar', t);
  end loop;
end $$;

-- ¿Se puede registrar ejecución? (preparada con autorización, o en ejecución)
create or replace function public.prubind_ejecucion_abierta(p_prueba uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.pruebas_prubind p join public.tipos_prueba_prubind t on t.codigo = p.tipo
    where p.id = p_prueba and (p.estado = 'en_ejecucion' or (p.estado = 'preparada' and (not t.requiere_aut_ejecucion
      or exists (select 1 from public.autorizaciones_prubind a where a.prueba_id = p.id and a.ejecucion = p.ejecucion_actual and a.tipo = 'ejecucion')))))
$$;

-- ---------- Etapa 3 · Ejecución ----------------------------------------
create or replace function public.prubind_validar_ejecucion()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v     public.pruebas_prubind%rowtype;
  v_pid uuid;
  uid   uuid := public.prubind_usuario_actual_id();
  v_ok  boolean;
  v_res boolean := false;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return coalesce(new, old); end if;
  if tg_table_name = 'batch_lotes_mp_prubind' then
    select b.prueba_id into v_pid from public.batches_prubind b where b.id = case when tg_op = 'DELETE' then old.batch_id else new.batch_id end;
  else
    v_pid := case when tg_op = 'DELETE' then old.prueba_id else new.prueba_id end;
  end if;
  select * into v from public.pruebas_prubind where id = v_pid;
  if v.id is null then return coalesce(new, old); end if;

  -- Resolución de una no conformidad (en evaluación o dictamen)
  if tg_op = 'UPDATE' and tg_table_name in ('batches_prubind', 'ejecucion_controles_prubind')
     and new.resolucion is distinct from old.resolucion
     and (to_jsonb(new) - 'resolucion' - 'updated_at') = (to_jsonb(old) - 'resolucion' - 'updated_at') then
    if not (public.prubind_puede(v_pid, 'evaluar') or public.prubind_puede(v_pid, 'dictaminar')) then
      raise exception 'No tiene autoridad para resolver no conformidades.' using errcode = '42501';
    end if;
    if v.estado not in ('en_ejecucion', 'en_evaluacion', 'pendiente_resultados', 'pendiente_dictamen') then
      raise exception 'La no conformidad solo se resuelve antes del dictamen.' using errcode = 'P0001';
    end if;
    new.resolucion := nullif(btrim(new.resolucion), '');
    return new;
  end if;

  perform public.prubind_req(v_pid, 'ejecutar', null);
  if not public.prubind_ejecucion_abierta(v_pid) then
    raise exception 'La ejecución no está abierta: la prueba debe estar preparada%.',
      case when v.estado = 'preparada' then ' y con la autorización de ejecución' else '' end using errcode = 'P0001';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  if tg_table_name <> 'batch_lotes_mp_prubind' then
    if tg_op = 'UPDATE' and (new.prueba_id is distinct from old.prueba_id or new.ejecucion is distinct from old.ejecucion) then
      raise exception 'No se puede mover el registro a otra prueba o ejecución.' using errcode = 'P0001';
    end if;
    if tg_op = 'INSERT' then new.ejecucion := v.ejecucion_actual; end if;
  end if;

  if tg_table_name = 'lotes_diarios_prubind' then
    new.codigo := upper(btrim(new.codigo));
    if tg_op = 'INSERT' then new.created_by := uid; end if;
  elsif tg_table_name = 'batches_prubind' then
    if not exists (select 1 from public.lotes_diarios_prubind l where l.id = new.lote_diario_id and l.prueba_id = v_pid and l.ejecucion = new.ejecucion) then
      raise exception 'El batch debe pertenecer a un lote diario de esta prueba y ejecución.' using errcode = 'P0001';
    end if;
    if new.numero is null or new.numero = 0 then
      select coalesce(max(numero), 0) + 1 into new.numero from public.batches_prubind where prueba_id = v_pid and ejecucion = new.ejecucion;
    end if;
    if new.fecha_hora > now() + interval '15 minutes' then
      raise exception 'La fecha y hora de producción no puede ser futura.' using errcode = 'P0001';
    end if;
    new.identificador := nullif(upper(btrim(new.identificador)), '');
    new.incidencias := nullif(btrim(new.incidencias), '');
    if new.resultado_op = 'no_conforme' and new.incidencias is null then
      raise exception 'Describa la incidencia o desviación del batch no conforme.' using errcode = 'P0001';
    end if;
    if tg_op = 'INSERT' then new.capturado_por := uid; new.responsable_id := coalesce(new.responsable_id, uid); end if;
  elsif tg_table_name = 'ejecucion_controles_prubind' then
    new.nombre := btrim(new.nombre);
    new.valor := nullif(btrim(new.valor), '');
    new.observaciones := nullif(btrim(new.observaciones), '');
    if new.resultado = 'no_conforme' and new.observaciones is null then
      raise exception 'Justifique el resultado no conforme en observaciones.' using errcode = 'P0001';
    end if;
    if new.resultado <> 'pendiente' and new.fecha_hora is null then new.fecha_hora := now(); end if;
    if tg_op = 'INSERT' then new.responsable_id := coalesce(new.responsable_id, uid); end if;
  elsif tg_table_name = 'batch_lotes_mp_prubind' then
    if not exists (select 1 from public.lotes_mp_prubind l where l.id = new.lote_mp_id and l.activo) then
      raise exception 'El lote de materia prima no existe o está inactivo.' using errcode = 'P0001';
    end if;
  end if;

  if v.estado = 'preparada' then
    perform public.prubind_set_estado(v_pid, 'en_ejecucion', 'Inició la ejecución #' || v.ejecucion_actual || '.');
  end if;
  return new;
end $$;
do $$
declare t text;
begin
  foreach t in array array['lotes_diarios_prubind','batches_prubind','batch_lotes_mp_prubind','ejecucion_controles_prubind'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_validar', t);
    execute format('create trigger %I before insert or update or delete on public.%I for each row execute function public.prubind_validar_ejecucion()', t || '_validar', t);
  end loop;
end $$;

-- ---------- Etapa 4 · Muestras y resultados -----------------------------
create or replace function public.prubind_validar_muestra()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v     public.pruebas_prubind%rowtype;
  v_pid uuid;
  v_n   integer;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return coalesce(new, old); end if;
  if tg_table_name = 'muestra_batches_prubind' then
    select m.prueba_id into v_pid from public.muestras_prubind m where m.id = case when tg_op = 'DELETE' then old.muestra_id else new.muestra_id end;
  else
    v_pid := case when tg_op = 'DELETE' then old.prueba_id else new.prueba_id end;
  end if;
  select * into v from public.pruebas_prubind where id = v_pid;
  if v.id is null then return coalesce(new, old); end if;
  if not (public.prubind_puede(v_pid, 'ejecutar') or public.prubind_puede(v_pid, 'evaluar')) then
    raise exception 'No tiene autoridad para registrar muestras.' using errcode = '42501';
  end if;
  if v.estado not in ('en_ejecucion', 'en_evaluacion', 'pendiente_resultados') then
    raise exception 'Las muestras se registran durante la ejecución o la evaluación.' using errcode = 'P0001';
  end if;
  if tg_op = 'DELETE' then return old; end if;

  if tg_table_name = 'muestra_batches_prubind' then
    if not exists (select 1 from public.muestras_prubind m join public.batches_prubind b on b.prueba_id = m.prueba_id and b.ejecucion = m.ejecucion
                   where m.id = new.muestra_id and b.id = new.batch_id and m.nivel = 'compuesta') then
      raise exception 'Solo se componen muestras compuestas con batches de la misma prueba y ejecución.' using errcode = 'P0001';
    end if;
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.ejecucion := v.ejecucion_actual;
    new.tomada_por := coalesce(new.tomada_por, public.prubind_usuario_actual_id());
    if nullif(btrim(new.codigo), '') is null then
      select count(*) + 1 into v_n from public.muestras_prubind where prueba_id = v_pid and ejecucion = new.ejecucion;
      new.codigo := 'M' || new.ejecucion || '-' || lpad(v_n::text, 2, '0');
    end if;
  elsif new.prueba_id is distinct from old.prueba_id or new.ejecucion is distinct from old.ejecucion then
    raise exception 'No se puede mover la muestra.' using errcode = 'P0001';
  end if;
  new.codigo := upper(btrim(new.codigo));
  if new.batch_id is not null and not exists (select 1 from public.batches_prubind b where b.id = new.batch_id and b.prueba_id = v_pid and b.ejecucion = new.ejecucion) then
    raise exception 'El batch no pertenece a esta prueba y ejecución.' using errcode = 'P0001';
  end if;
  if new.lote_diario_id is not null and not exists (select 1 from public.lotes_diarios_prubind l where l.id = new.lote_diario_id and l.prueba_id = v_pid and l.ejecucion = new.ejecucion) then
    raise exception 'El lote diario no pertenece a esta prueba y ejecución.' using errcode = 'P0001';
  end if;
  if new.punto_id is not null and not exists (select 1 from public.puntos_muestreo_prubind p where p.id = new.punto_id and p.prueba_id = v_pid) then
    raise exception 'El punto de muestreo no pertenece a esta prueba.' using errcode = 'P0001';
  end if;
  if new.fecha_muestreo > public.prubind_hoy() then
    raise exception 'La fecha de muestreo no puede ser futura.' using errcode = 'P0001';
  end if;
  return new;
end $$;
do $$
declare t text;
begin
  foreach t in array array['muestras_prubind','muestra_batches_prubind'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_validar', t);
    execute format('create trigger %I before insert or update or delete on public.%I for each row execute function public.prubind_validar_muestra()', t || '_validar', t);
  end loop;
end $$;

create or replace function public.prubind_validar_resultado()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v     public.pruebas_prubind%rowtype;
  pl    public.plan_evaluacion_prubind%rowtype;
  m     public.metodos_prubind%rowtype;
  uid   uuid := public.prubind_usuario_actual_id();
  v_pid uuid;
  v_rpc boolean := coalesce(current_setting('prubind.rpc', true), '') = '1';
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return coalesce(new, old); end if;
  if v_rpc then return coalesce(new, old); end if;   -- revisión vía RPC
  v_pid := case when tg_op = 'DELETE' then old.prueba_id else new.prueba_id end;
  select * into v from public.pruebas_prubind where id = v_pid;
  if v.id is null then return coalesce(new, old); end if;

  -- Resolución de una no conformidad
  if tg_op = 'UPDATE' and new.resolucion is distinct from old.resolucion
     and (to_jsonb(new) - 'resolucion' - 'updated_at') = (to_jsonb(old) - 'resolucion' - 'updated_at') then
    if not (public.prubind_puede(v_pid, 'evaluar') or public.prubind_puede(v_pid, 'dictaminar')) then
      raise exception 'No tiene autoridad para resolver no conformidades.' using errcode = '42501';
    end if;
    if v.estado not in ('en_evaluacion', 'pendiente_resultados', 'pendiente_dictamen') then
      raise exception 'La no conformidad solo se resuelve antes del dictamen.' using errcode = 'P0001';
    end if;
    new.resolucion := nullif(btrim(new.resolucion), '');
    return new;
  end if;

  perform public.prubind_req(v_pid, 'evaluar', array['en_ejecucion','en_evaluacion','pendiente_resultados'],
    'Los resultados se capturan durante la ejecución o la evaluación.');
  if tg_op = 'DELETE' then return old; end if;

  select * into pl from public.plan_evaluacion_prubind where id = new.plan_id and prueba_id = v_pid;
  if not found or not pl.incluido then
    raise exception 'El análisis no está en el plan de evaluación de esta prueba.' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.muestras_prubind s where s.id = new.muestra_id and s.prueba_id = v_pid and s.ejecucion = v.ejecucion_actual) then
    raise exception 'La muestra no pertenece a la ejecución actual de esta prueba.' using errcode = 'P0001';
  end if;
  select * into m from public.metodos_prubind where id = pl.metodo_id;
  if tg_op = 'UPDATE' and (new.plan_id, new.muestra_id) is distinct from (old.plan_id, old.muestra_id) then
    raise exception 'No se puede mover el resultado a otro análisis o muestra.' using errcode = 'P0001';
  end if;
  new.ejecucion := v.ejecucion_actual;
  new.metodo_id := pl.metodo_id;
  new.unidad_id := coalesce(new.unidad_id, m.unidad_id);
  new.justificacion := nullif(btrim(new.justificacion), '');
  new.valor_opcion := nullif(btrim(new.valor_opcion), '');

  if m.tipo_resultado = 'diluciones' then
    if new.dilucion is null or not (new.dilucion = any (m.diluciones)) then
      raise exception 'Indique una dilución válida para %: %.', m.nombre, array_to_string(m.diluciones, ', ') using errcode = 'P0001';
    end if;
  else
    new.dilucion := null;
  end if;
  if m.tipo_resultado in ('numerico', 'diluciones') then
    new.valor_opcion := null;
    if new.valor_num is null and new.estado in ('conforme', 'no_conforme') then
      raise exception 'Capture el valor numérico de %.', m.nombre using errcode = 'P0001';
    end if;
    -- Conformidad automática contra el criterio copiado al plan
    if new.valor_num is not null and (pl.crit_minimo is not null or pl.crit_maximo is not null) then
      new.estado := case when (pl.crit_minimo is null or new.valor_num >= pl.crit_minimo)
                          and (pl.crit_maximo is null or new.valor_num <= pl.crit_maximo) then 'conforme' else 'no_conforme' end;
    end if;
  elsif m.tipo_resultado = 'presencia' then
    new.valor_num := null; new.unidad_id := null;
    if new.valor_opcion is not null and new.valor_opcion not in ('ausencia', 'presencia') then
      raise exception 'El resultado debe ser "ausencia" o "presencia".' using errcode = 'P0001';
    end if;
    if new.valor_opcion is not null and pl.crit_texto ilike '%ausencia%' then
      new.estado := case when new.valor_opcion = 'ausencia' then 'conforme' else 'no_conforme' end;
    end if;
  else -- opción
    new.valor_num := null;
    if new.valor_opcion is not null and cardinality(m.opciones) > 0 and not (new.valor_opcion = any (m.opciones)) then
      raise exception 'Opción no válida para %.', m.nombre using errcode = 'P0001';
    end if;
    if new.valor_opcion in ('conforme', 'no_conforme', 'no_aplica', 'pendiente') then new.estado := new.valor_opcion;
    elsif new.valor_opcion = 'no_evaluado' then new.estado := 'no_aplica'; end if;
  end if;
  if new.estado = 'no_conforme' and new.justificacion is null then
    raise exception '% no cumple el criterio: escriba una justificación breve.', m.nombre using errcode = 'P0001';
  end if;
  if new.estado <> 'pendiente' and new.fecha_lectura is null then new.fecha_lectura := now(); end if;
  if tg_op = 'INSERT' then
    new.capturado_por := uid; new.revisado_por := null; new.revisado_at := null; new.resolucion := null;
  else
    new.capturado_por := old.capturado_por; new.modificado_por := uid;
    -- Si cambia el valor, la revisión previa deja de ser válida
    if (new.valor_num, new.valor_opcion, new.estado, new.dilucion) is distinct from (old.valor_num, old.valor_opcion, old.estado, old.dilucion) then
      new.revisado_por := null; new.revisado_at := null;
    else
      new.revisado_por := old.revisado_por; new.revisado_at := old.revisado_at;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists resultados_prubind_validar on public.resultados_prubind;
create trigger resultados_prubind_validar before insert or update or delete on public.resultados_prubind
  for each row execute function public.prubind_validar_resultado();

-- Evidencia
create or replace function public.prubind_validar_adjunto()
returns trigger language plpgsql security definer set search_path = '' as $$
declare uid uuid := public.prubind_usuario_actual_id();
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return coalesce(new, old); end if;
  if uid is null then raise exception 'Usuario no autorizado.' using errcode = '42501'; end if;
  if tg_op = 'DELETE' then
    if not (old.subido_por = uid or public.prubind_es_admin()) then
      raise exception 'Solo quien subió el archivo o un administrador puede eliminarlo.' using errcode = '42501';
    end if;
    if exists (select 1 from public.pruebas_prubind p where p.id = old.prueba_id and p.estado in ('cerrada_aprobada','cerrada_rechazada')) then
      raise exception 'La evidencia de una prueba cerrada no se elimina.' using errcode = 'P0001';
    end if;
    return old;
  end if;
  if new.ruta !~ ('^' || new.prueba_id::text || '/[A-Za-z0-9._-]+$') then
    raise exception 'Ruta de archivo inválida.' using errcode = 'P0001';
  end if;
  if new.resultado_id is not null and not exists (select 1 from public.resultados_prubind r where r.id = new.resultado_id and r.prueba_id = new.prueba_id) then
    raise exception 'El resultado no pertenece a la prueba.' using errcode = 'P0001';
  end if;
  if new.batch_id is not null and not exists (select 1 from public.batches_prubind b where b.id = new.batch_id and b.prueba_id = new.prueba_id) then
    raise exception 'El batch no pertenece a la prueba.' using errcode = 'P0001';
  end if;
  new.subido_por := uid;
  new.nombre := btrim(new.nombre);
  new.descripcion := nullif(btrim(new.descripcion), '');
  return new;
end $$;
drop trigger if exists adjuntos_prubind_validar on public.adjuntos_prubind;
create trigger adjuntos_prubind_validar before insert or delete on public.adjuntos_prubind
  for each row execute function public.prubind_validar_adjunto();

-- ---------- Indicadores de completitud (uso interno y vistas) -----------
create or replace function public.prubind_eval_estado(p_prueba uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v public.pruebas_prubind%rowtype; r jsonb;
begin
  select * into v from public.pruebas_prubind where id = p_prueba;
  if not found then return null; end if;
  select jsonb_build_object(
    'plan_incluidos', (select count(*) from public.plan_evaluacion_prubind pl where pl.prueba_id = v.id and pl.incluido),
    'obligatorios', (select count(*) from public.plan_evaluacion_prubind pl where pl.prueba_id = v.id and pl.incluido and pl.obligatorio),
    'obligatorios_faltantes', (select count(*) from public.plan_evaluacion_prubind pl where pl.prueba_id = v.id and pl.incluido and pl.obligatorio
        and not exists (select 1 from public.resultados_prubind x where x.plan_id = pl.id and x.ejecucion = v.ejecucion_actual and x.estado <> 'pendiente')),
    'resultados', (select count(*) from public.resultados_prubind x where x.prueba_id = v.id and x.ejecucion = v.ejecucion_actual),
    'pendientes', (select count(*) from public.resultados_prubind x where x.prueba_id = v.id and x.ejecucion = v.ejecucion_actual and x.estado = 'pendiente'),
    'conformes', (select count(*) from public.resultados_prubind x where x.prueba_id = v.id and x.ejecucion = v.ejecucion_actual and x.estado = 'conforme'),
    'no_conformes', (select count(*) from public.resultados_prubind x where x.prueba_id = v.id and x.ejecucion = v.ejecucion_actual and x.estado = 'no_conforme'),
    'nc_sin_resolver',
        (select count(*) from public.resultados_prubind x where x.prueba_id = v.id and x.ejecucion = v.ejecucion_actual and x.estado = 'no_conforme' and x.resolucion is null)
      + (select count(*) from public.batches_prubind b where b.prueba_id = v.id and b.ejecucion = v.ejecucion_actual and b.resultado_op = 'no_conforme' and b.resolucion is null)
      + (select count(*) from public.ejecucion_controles_prubind c where c.prueba_id = v.id and c.ejecucion = v.ejecucion_actual and c.resultado = 'no_conforme' and c.resolucion is null),
    'revisiones_pendientes', (select count(*) from public.resultados_prubind x join public.metodos_prubind m on m.id = x.metodo_id
        where x.prueba_id = v.id and x.ejecucion = v.ejecucion_actual and m.revisa_puesto_id is not null and x.estado <> 'pendiente' and x.revisado_por is null),
    'batches', (select count(*) from public.batches_prubind b where b.prueba_id = v.id and b.ejecucion = v.ejecucion_actual),
    'batches_pendientes', (select count(*) from public.batches_prubind b where b.prueba_id = v.id and b.ejecucion = v.ejecucion_actual and b.resultado_op = 'pendiente'),
    'controles', (select count(*) from public.ejecucion_controles_prubind c where c.prueba_id = v.id and c.ejecucion = v.ejecucion_actual),
    'controles_pendientes', (select count(*) from public.ejecucion_controles_prubind c where c.prueba_id = v.id and c.ejecucion = v.ejecucion_actual and c.resultado = 'pendiente'),
    'aut_ejecucion', exists (select 1 from public.autorizaciones_prubind a where a.prueba_id = v.id and a.ejecucion = v.ejecucion_actual and a.tipo = 'ejecucion'),
    'impl_requeridas', (select count(*) from public.autoridades_prubind a where a.activo and a.accion = 'autorizar_implementacion' and (a.tipo is null or a.tipo = v.tipo)),
    'impl_obtenidas', (select count(*) from public.autoridades_prubind a where a.activo and a.accion = 'autorizar_implementacion' and (a.tipo is null or a.tipo = v.tipo)
        and exists (select 1 from public.autorizaciones_prubind z where z.prueba_id = v.id and z.tipo = 'implementacion'
                    and ((a.puesto_id is not null and z.puesto_id = a.puesto_id) or (a.usuario_id is not null and z.autorizado_por = a.usuario_id))))
  ) into r;
  return r;
end $$;

-- ---------- Acciones del flujo (una sola puerta de entrada) -------------
create or replace function public.prubind_accion(p_prueba uuid, p_accion text, p_datos jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid   uuid := public.prubind_usuario_actual_id();
  v     public.pruebas_prubind%rowtype;
  t     public.tipos_prueba_prubind%rowtype;
  e     jsonb;
  d     jsonb := coalesce(p_datos, '{}'::jsonb);
  v_txt text := nullif(btrim(d ->> 'texto'), '');
  v_dic text;
  v_mot uuid;
  v_ver uuid;
  v_n   integer;
begin
  if uid is null then raise exception 'Usuario no autorizado.' using errcode = '42501'; end if;
  if char_length(coalesce(v_txt, '')) > 1000 then raise exception 'El texto excede 1000 caracteres.' using errcode = 'P0001'; end if;
  select * into v from public.pruebas_prubind where id = p_prueba for update;
  if not found then raise exception 'La prueba no existe.' using errcode = 'P0001'; end if;
  select * into t from public.tipos_prueba_prubind where codigo = v.tipo;

  case p_accion
  -- ===== Preparación =====
  when 'generar_plan' then
    perform public.prubind_req(p_prueba, 'preparar', array['registrada','en_preparacion']);
    perform set_config('prubind.rpc', '1', true);
    delete from public.plan_evaluacion_prubind where prueba_id = p_prueba;
    insert into public.plan_evaluacion_prubind (prueba_id, metodo_id, incluido, obligatorio, nivel, especificacion_id,
                                                crit_minimo, crit_maximo, crit_texto, crit_referencia, orden)
    select p_prueba, pt.metodo_id, true, pt.obligatorio, pt.nivel, es.id, es.minimo, es.maximo, es.criterio_texto, es.referencia, pt.orden
      from public.plantilla_evaluacion_prubind pt
      join public.metodos_prubind m on m.id = pt.metodo_id and m.activo
      left join lateral (
        select s.* from public.especificaciones_prubind s
        where s.metodo_id = pt.metodo_id and s.activo and s.vigente
          and (s.producto_id is null or s.producto_id = v.producto_id)
          and (s.materia_prima_id is null or s.materia_prima_id = v.materia_prima_id)
        order by (s.producto_id is not null) desc, (s.materia_prima_id is not null) desc, s.updated_at desc limit 1) es on true
     where pt.tipo = v.tipo and pt.activo;
    get diagnostics v_n = row_count;
    update public.pruebas_prubind set plan_confirmado_at = null, plan_confirmado_por = null,
           estado = case when estado = 'registrada' then 'en_preparacion' else estado end where id = p_prueba;
    perform set_config('prubind.rpc', '', true);
    perform public.prubind_log(p_prueba, 'sistema', 'Plan de evaluación generado desde la plantilla del tipo (' || v_n || ' análisis o controles).');

  when 'confirmar_plan' then
    perform public.prubind_req(p_prueba, 'preparar', array['registrada','en_preparacion']);
    if not exists (select 1 from public.plan_evaluacion_prubind where prueba_id = p_prueba and incluido) then
      raise exception 'El plan de evaluación no tiene análisis incluidos.' using errcode = 'P0001';
    end if;
    perform set_config('prubind.rpc', '1', true);
    update public.pruebas_prubind set plan_confirmado_at = now(), plan_confirmado_por = uid,
           estado = case when estado = 'registrada' then 'en_preparacion' else estado end where id = p_prueba;
    perform set_config('prubind.rpc', '', true);
    perform public.prubind_log(p_prueba, 'estado', 'Plan de evaluación confirmado.');

  when 'copiar_receta' then
    perform public.prubind_req(p_prueba, 'preparar', array['registrada','en_preparacion']);
    if v.receta_version_id is null then raise exception 'La prueba no tiene receta seleccionada en el registro.' using errcode = 'P0001'; end if;
    perform set_config('prubind.rpc', '1', true);
    delete from public.prueba_formulacion_prubind where prueba_id = p_prueba;
    insert into public.prueba_formulacion_prubind (prueba_id, materia_prima_id, cantidad_original, cantidad_propuesta, unidad_id, accion, orden)
    select p_prueba, i.materia_prima_id, i.cantidad, i.cantidad, i.unidad_id, 'sin_cambio', i.orden
      from public.receta_ingredientes_prubind i where i.version_id = v.receta_version_id;
    get diagnostics v_n = row_count;
    update public.pruebas_prubind set estado = case when estado = 'registrada' then 'en_preparacion' else estado end where id = p_prueba;
    perform set_config('prubind.rpc', '', true);
    perform public.prubind_log(p_prueba, 'sistema', 'Se copió la receta original (' || v_n || ' ingredientes) para registrar la formulación propuesta. La receta oficial no se modifica.');

  when 'calcular_materiales' then
    perform public.prubind_req(p_prueba, 'preparar', array['registrada','en_preparacion']);
    if v.batches_planeados is null then raise exception 'Indique el número de batches planeados.' using errcode = 'P0001'; end if;
    perform set_config('prubind.rpc', '1', true);
    insert into public.prueba_materiales_prubind as pm (prueba_id, materia_prima_id, cantidad, unidad_id, actualizado_por)
    select p_prueba, f.materia_prima_id, round(f.cantidad_propuesta * v.batches_planeados, 3), f.unidad_id, uid
      from public.prueba_formulacion_prubind f where f.prueba_id = p_prueba and coalesce(f.cantidad_propuesta, 0) > 0
    on conflict (prueba_id, materia_prima_id) do update set cantidad = excluded.cantidad, unidad_id = excluded.unidad_id, actualizado_por = uid;
    get diagnostics v_n = row_count;
    perform set_config('prubind.rpc', '', true);
    perform public.prubind_log(p_prueba, 'sistema', 'Materiales calculados: formulación propuesta × ' || v.batches_planeados || ' batch(es) (' || v_n || ' renglones).');

  when 'marcar_preparada' then
    perform public.prubind_req(p_prueba, 'preparar', array['en_preparacion']);
    if v.plan_confirmado_at is null then raise exception 'Confirme el plan de evaluación.' using errcode = 'P0001'; end if;
    if v.responsable_ejecucion_id is null then raise exception 'Asigne el responsable de ejecución.' using errcode = 'P0001'; end if;
    if 'batches' = any (t.secciones_prep) and v.batches_planeados is null then
      raise exception 'Indique el número de batches planeados.' using errcode = 'P0001';
    end if;
    if 'formulacion' = any (t.secciones_prep) and not exists (select 1 from public.prueba_formulacion_prubind f where f.prueba_id = p_prueba) then
      raise exception 'Registre la formulación propuesta (copie la receta original y ajústela).' using errcode = 'P0001';
    end if;
    if 'vida_util' = any (t.secciones_prep) and not exists (select 1 from public.puntos_muestreo_prubind x where x.prueba_id = p_prueba) then
      raise exception 'Defina los puntos de muestreo de vida útil.' using errcode = 'P0001';
    end if;
    perform public.prubind_set_estado(p_prueba, 'preparada', 'Prueba preparada' ||
      case when t.requiere_aut_ejecucion then '; espera la autorización de ejecución.' else '.' end);

  when 'regresar_preparacion' then
    perform public.prubind_req(p_prueba, 'preparar', array['preparada']);
    perform set_config('prubind.rpc', '1', true);
    delete from public.autorizaciones_prubind where prueba_id = p_prueba and ejecucion = v.ejecucion_actual and tipo = 'ejecucion';
    perform set_config('prubind.rpc', '', true);
    perform public.prubind_set_estado(p_prueba, 'en_preparacion', 'Regresó a preparación' || coalesce(': ' || v_txt, '.'));

  when 'autorizar_ejecucion' then
    perform public.prubind_req(p_prueba, 'autorizar_ejecucion', array['preparada']);
    insert into public.autorizaciones_prubind (prueba_id, ejecucion, tipo, puesto_id, autorizado_por, comentario)
    values (p_prueba, v.ejecucion_actual, 'ejecucion', public.prubind_puesto_actual(), uid, v_txt)
    on conflict do nothing;
    perform public.prubind_log(p_prueba, 'estado', 'Ejecución #' || v.ejecucion_actual || ' autorizada' || coalesce(': ' || v_txt, '.'));

  -- ===== Ejecución → Evaluación =====
  when 'terminar_ejecucion' then
    perform public.prubind_req(p_prueba, 'ejecutar', array['en_ejecucion']);
    e := public.prubind_eval_estado(p_prueba);
    if t.ejecucion_form = 'fabricacion' then
      if (e ->> 'batches')::int = 0 then raise exception 'Registre al menos un batch.' using errcode = 'P0001'; end if;
      if (e ->> 'batches_pendientes')::int > 0 then
        raise exception 'Hay % batch(es) con resultado operativo pendiente.', e ->> 'batches_pendientes' using errcode = 'P0001';
      end if;
    else
      if (e ->> 'controles')::int = 0 then raise exception 'Registre al menos un control o parámetro de ejecución.' using errcode = 'P0001'; end if;
      if (e ->> 'controles_pendientes')::int > 0 then
        raise exception 'Hay % control(es) de ejecución pendientes.', e ->> 'controles_pendientes' using errcode = 'P0001';
      end if;
    end if;
    perform public.prubind_set_estado(p_prueba, 'en_evaluacion', 'Ejecución #' || v.ejecucion_actual || ' terminada; inicia la evaluación.');

  when 'enviar_dictamen' then
    perform public.prubind_req(p_prueba, 'evaluar', array['en_evaluacion','pendiente_resultados']);
    e := public.prubind_eval_estado(p_prueba);
    if (e ->> 'obligatorios_faltantes')::int > 0 then
      raise exception 'Faltan resultados de % análisis obligatorio(s) del plan.', e ->> 'obligatorios_faltantes' using errcode = 'P0001';
    end if;
    perform public.prubind_set_estado(p_prueba, 'pendiente_dictamen', 'Evaluación completa; pendiente de dictamen.');

  when 'revisar_resultado' then
    if not exists (select 1 from public.resultados_prubind x join public.metodos_prubind m on m.id = x.metodo_id
                   where x.id = (d ->> 'resultado_id')::uuid and x.prueba_id = p_prueba and m.revisa_puesto_id = public.prubind_puesto_actual()) then
      raise exception 'Este resultado no requiere su revisión o no existe.' using errcode = '42501';
    end if;
    if v.estado not in ('en_ejecucion','en_evaluacion','pendiente_resultados','pendiente_dictamen') then
      raise exception 'La revisión se registra antes del dictamen.' using errcode = 'P0001';
    end if;
    perform set_config('prubind.rpc', '1', true);
    update public.resultados_prubind set revisado_por = uid, revisado_at = now() where id = (d ->> 'resultado_id')::uuid;
    perform set_config('prubind.rpc', '', true);

  -- ===== Dictamen =====
  when 'dictaminar' then
    perform public.prubind_req(p_prueba, 'dictaminar', array['pendiente_dictamen']);
    v_dic := d ->> 'dictamen';
    v_mot := nullif(d ->> 'motivo_id', '')::uuid;
    e := public.prubind_eval_estado(p_prueba);
    if v_dic = 'aprobada' then
      if (e ->> 'obligatorios_faltantes')::int > 0 then
        raise exception 'No se puede aprobar: faltan % resultado(s) obligatorio(s).', e ->> 'obligatorios_faltantes' using errcode = 'P0001';
      end if;
      if (e ->> 'nc_sin_resolver')::int > 0 then
        raise exception 'No se puede aprobar: hay % incumplimiento(s) sin resolver.', e ->> 'nc_sin_resolver' using errcode = 'P0001';
      end if;
      if (e ->> 'revisiones_pendientes')::int > 0 then
        raise exception 'No se puede aprobar: % resultado(s) requieren revisión del puesto responsable.', e ->> 'revisiones_pendientes' using errcode = 'P0001';
      end if;
    elsif v_dic = 'rechazada' then
      if v_mot is null or not exists (select 1 from public.motivos_prubind where id = v_mot and tipo = 'rechazo') then
        raise exception 'Seleccione el motivo de rechazo.' using errcode = 'P0001';
      end if;
    elsif v_dic = 'requiere_repeticion' then
      if v_txt is null then raise exception 'Explique por qué se requiere repetir la prueba.' using errcode = 'P0001'; end if;
    elsif v_dic <> 'pendiente_resultados' then
      raise exception 'Dictamen no válido.' using errcode = 'P0001';
    end if;
    insert into public.dictamenes_prubind (prueba_id, ejecucion, dictamen, motivo_id, descripcion, emitido_por)
    values (p_prueba, v.ejecucion_actual, v_dic, case when v_dic = 'rechazada' then v_mot end, v_txt, uid);
    perform public.prubind_set_estado(p_prueba, v_dic,
      'Dictamen: ' || case v_dic when 'aprobada' then 'APROBADA' when 'rechazada' then 'RECHAZADA' when 'requiere_repeticion' then 'REQUIERE REPETICIÓN'
      else 'PENDIENTE DE RESULTADOS' end || coalesce('. ' || v_txt, '.'));

  when 'nueva_ejecucion' then
    if not (public.prubind_puede(p_prueba, 'preparar') or public.prubind_puede(p_prueba, 'dictaminar')) then
      raise exception 'No tiene autoridad para iniciar una nueva ejecución.' using errcode = '42501';
    end if;
    if v.estado <> 'requiere_repeticion' then raise exception 'Solo una prueba que requiere repetición inicia una nueva ejecución.' using errcode = 'P0001'; end if;
    perform set_config('prubind.rpc', '1', true);
    update public.pruebas_prubind set ejecucion_actual = ejecucion_actual + 1, estado = 'en_preparacion' where id = p_prueba;
    perform set_config('prubind.rpc', '', true);
    perform public.prubind_log(p_prueba, 'estado', 'Se abrió la ejecución #' || (v.ejecucion_actual + 1) || ' vinculada al registro original. El historial anterior se conserva.');

  -- ===== Cierre =====
  when 'cerrar' then
    perform public.prubind_req(p_prueba, 'cerrar', array['aprobada','rechazada']);
    e := public.prubind_eval_estado(p_prueba);
    if v.estado = 'rechazada' and (e ->> 'obligatorios_faltantes')::int > 0 and v_txt is null then
      raise exception 'Hay resultados obligatorios pendientes: registre la disposición formal para cerrar.' using errcode = 'P0001';
    end if;
    perform set_config('prubind.rpc', '1', true);
    update public.pruebas_prubind set estado = case when v.estado = 'aprobada' then 'cerrada_aprobada' else 'cerrada_rechazada' end,
           cerrada_por = uid, cerrada_at = now(), disposicion_cierre = v_txt where id = p_prueba;
    perform set_config('prubind.rpc', '', true);
    perform public.prubind_log(p_prueba, 'estado', 'Prueba cerrada (' || case when v.estado = 'aprobada' then 'aprobada' else 'rechazada' end || ').'
      || case when v.estado = 'aprobada' then ' La aprobación no libera producto ni autoriza por sí misma el cambio en producción.' else '' end);

  when 'autorizar_implementacion' then
    perform public.prubind_req(p_prueba, 'autorizar_implementacion', array['cerrada_aprobada']);
    insert into public.autorizaciones_prubind (prueba_id, ejecucion, tipo, puesto_id, autorizado_por, comentario)
    values (p_prueba, v.ejecucion_actual, 'implementacion', public.prubind_puesto_actual(), uid, v_txt)
    on conflict do nothing;
    perform public.prubind_log(p_prueba, 'estado', 'Autorización de implementación registrada' || coalesce(': ' || v_txt, '.'));

  when 'publicar_formulacion' then
    if not public.prubind_es_admin() then raise exception 'Solo los administradores publican versiones de receta.' using errcode = '42501'; end if;
    if v.estado <> 'cerrada_aprobada' then raise exception 'La prueba debe estar cerrada y aprobada.' using errcode = 'P0001'; end if;
    e := public.prubind_eval_estado(p_prueba);
    if (e ->> 'impl_requeridas')::int = 0 or (e ->> 'impl_obtenidas')::int < (e ->> 'impl_requeridas')::int then
      raise exception 'Faltan autorizaciones de implementación (% de %).', e ->> 'impl_obtenidas', e ->> 'impl_requeridas' using errcode = 'P0001';
    end if;
    if v.receta_version_id is null or not exists (select 1 from public.prueba_formulacion_prubind where prueba_id = p_prueba) then
      raise exception 'La prueba no tiene una formulación propuesta.' using errcode = 'P0001';
    end if;
    if nullif(btrim(d ->> 'version'), '') is null then raise exception 'Indique el nombre de la nueva versión.' using errcode = 'P0001'; end if;
    insert into public.receta_versiones_prubind (receta_id, version, estado, notas, origen_prueba_id)
    select r.receta_id, btrim(d ->> 'version'), 'borrador', 'Generada desde la prueba ' || v.folio, p_prueba
      from public.receta_versiones_prubind r where r.id = v.receta_version_id returning id into v_ver;
    perform set_config('prubind.rpc', '1', true);
    insert into public.receta_ingredientes_prubind (version_id, materia_prima_id, cantidad, unidad_id, orden)
    select v_ver, f.materia_prima_id, f.cantidad_propuesta, f.unidad_id, f.orden
      from public.prueba_formulacion_prubind f where f.prueba_id = p_prueba and coalesce(f.cantidad_propuesta, 0) > 0;
    perform set_config('prubind.rpc', '', true);
    update public.receta_versiones_prubind set estado = 'vigente' where id = v_ver;
    perform public.prubind_log(p_prueba, 'estado', 'Nueva versión de receta publicada: ' || btrim(d ->> 'version') || '. La versión anterior queda como histórica.');

  when 'cancelar' then
    perform public.prubind_req(p_prueba, 'cancelar', array['registrada','en_preparacion','preparada','en_ejecucion','en_evaluacion',
      'pendiente_resultados','pendiente_dictamen','requiere_repeticion']);
    if v_txt is null then raise exception 'Indique el motivo de la cancelación.' using errcode = 'P0001'; end if;
    perform set_config('prubind.rpc', '1', true);
    update public.pruebas_prubind set estado = 'cancelada', motivo_cancelacion = left(v_txt, 500), cancelado_por = uid, cancelado_at = now() where id = p_prueba;
    perform set_config('prubind.rpc', '', true);
    perform public.prubind_log(p_prueba, 'estado', 'Prueba cancelada: ' || v_txt);

  else
    raise exception 'Acción no válida.' using errcode = 'P0001';
  end case;

  select estado into v_dic from public.pruebas_prubind where id = p_prueba;
  return jsonb_build_object('estado', v_dic);
end $$;

-- ---------- Vistas (security_invoker) ----------------------------------
create or replace view public.v_pruebas_prubind with (security_invoker = true) as
select p.*, t.nombre as tipo_nombre, t.campos_registro, t.secciones_prep, t.ejecucion_form, t.requiere_aut_ejecucion,
       o.nombre as objetivo_nombre, ar.nombre as area_nombre, pr.nombre as producto_nombre,
       rc.nombre as receta_nombre, rv.version as receta_version, mp.nombre as materia_prima_nombre, pv.nombre as proveedor_nombre,
       eq.nombre as equipo_nombre,
       ur.nombre as registrado_por_nombre, ur.foto_url as registrado_por_foto,
       ui.nombre as responsable_inicial_nombre, ue.nombre as responsable_ejecucion_nombre,
       uc.nombre as cerrada_por_nombre, ux.nombre as cancelado_por_nombre,
       (select jsonb_build_object('dictamen', d.dictamen, 'fecha', d.created_at, 'por', du.nombre, 'descripcion', d.descripcion, 'motivo', mo.nombre)
          from public.dictamenes_prubind d join public.usuarios_prubind du on du.id = d.emitido_por
          left join public.motivos_prubind mo on mo.id = d.motivo_id
         where d.prueba_id = p.id order by d.created_at desc limit 1) as ultimo_dictamen
from public.pruebas_prubind p
join public.tipos_prueba_prubind t on t.codigo = p.tipo
join public.usuarios_prubind ur on ur.id = p.registrado_por
left join public.objetivos_prubind o on o.id = p.objetivo_id
left join public.areas_prubind ar on ar.id = p.area_id
left join public.productos_prubind pr on pr.id = p.producto_id
left join public.receta_versiones_prubind rv on rv.id = p.receta_version_id
left join public.recetas_prubind rc on rc.id = rv.receta_id
left join public.materias_primas_prubind mp on mp.id = p.materia_prima_id
left join public.proveedores_prubind pv on pv.id = p.proveedor_id
left join public.equipos_prubind eq on eq.id = p.equipo_id
left join public.usuarios_prubind ui on ui.id = p.responsable_inicial_id
left join public.usuarios_prubind ue on ue.id = p.responsable_ejecucion_id
left join public.usuarios_prubind uc on uc.id = p.cerrada_por
left join public.usuarios_prubind ux on ux.id = p.cancelado_por;

create or replace view public.v_batches_prubind with (security_invoker = true) as
select b.*, l.codigo as lote_codigo, l.fecha as lote_fecha, p.folio, p.tipo, t.nombre as tipo_nombre, p.estado as prueba_estado,
       p.ejecucion_actual, rc.nombre as receta_nombre, rv.version as receta_version, u.nombre as responsable_nombre,
       mo.nombre as motivo_nombre,
       (select coalesce(jsonb_agg(jsonb_build_object('lote_mp_id', x.lote_mp_id, 'lote', lm.lote, 'materia_prima', m.nombre, 'cantidad', x.cantidad)), '[]'::jsonb)
          from public.batch_lotes_mp_prubind x join public.lotes_mp_prubind lm on lm.id = x.lote_mp_id
          join public.materias_primas_prubind m on m.id = lm.materia_prima_id where x.batch_id = b.id) as lotes_mp
from public.batches_prubind b
join public.lotes_diarios_prubind l on l.id = b.lote_diario_id
join public.pruebas_prubind p on p.id = b.prueba_id
join public.tipos_prueba_prubind t on t.codigo = p.tipo
left join public.receta_versiones_prubind rv on rv.id = b.receta_version_id
left join public.recetas_prubind rc on rc.id = rv.receta_id
left join public.usuarios_prubind u on u.id = b.responsable_id
left join public.motivos_prubind mo on mo.id = b.motivo_desviacion_id;

create or replace view public.v_resultados_prubind with (security_invoker = true) as
select r.*, m.codigo as metodo_codigo, m.nombre as metodo_nombre, m.categoria, m.tipo_resultado, m.tecnica, m.horas_lectura,
       m.base_expresion, m.procedimiento_ref, m.revisa_puesto_id, un.simbolo as unidad,
       s.codigo as muestra_codigo, s.nivel as muestra_nivel, s.fecha_muestreo, b.numero as batch_numero, l.codigo as lote_codigo,
       pl.obligatorio, pl.crit_minimo, pl.crit_maximo, pl.crit_texto, pl.crit_referencia,
       uc.nombre as capturado_por_nombre, um.nombre as modificado_por_nombre, uv.nombre as revisado_por_nombre, mo.nombre as motivo_nombre
from public.resultados_prubind r
join public.metodos_prubind m on m.id = r.metodo_id
join public.muestras_prubind s on s.id = r.muestra_id
join public.plan_evaluacion_prubind pl on pl.id = r.plan_id
left join public.batches_prubind b on b.id = s.batch_id
left join public.lotes_diarios_prubind l on l.id = s.lote_diario_id
left join public.unidades_prubind un on un.id = r.unidad_id
join public.usuarios_prubind uc on uc.id = r.capturado_por
left join public.usuarios_prubind um on um.id = r.modificado_por
left join public.usuarios_prubind uv on uv.id = r.revisado_por
left join public.motivos_prubind mo on mo.id = r.motivo_desviacion_id;

create or replace view public.v_seguimiento_prubind with (security_invoker = true) as
select s.id, s.prueba_id, s.tipo, s.texto, s.created_at, s.usuario_id, u.nombre as usuario, u.foto_url, p.folio, p.cambio
from public.seguimiento_prubind s
join public.pruebas_prubind p on p.id = s.prueba_id
left join public.usuarios_prubind u on u.id = s.usuario_id;

-- ---------- Pendientes del usuario y tablero ----------------------------
create or replace function public.prubind_mis_pendientes()
returns table (prueba_id uuid, folio text, cambio text, tipo_nombre text, estado text, accion text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare uid uuid := public.prubind_usuario_actual_id();
begin
  if uid is null then raise exception 'Usuario no autorizado.' using errcode = '42501'; end if;
  return query
  with p as (
    select x.*, t.nombre as tnom, t.requiere_aut_ejecucion as req_aut, public.prubind_eval_estado(x.id) as e
    from public.pruebas_prubind x join public.tipos_prueba_prubind t on t.codigo = x.tipo
    where x.estado not in ('cerrada_rechazada', 'cancelada')
  )
  select p.id, p.folio, p.cambio, p.tnom, p.estado, a.accion
  from p cross join lateral (values
    ('preparar'), ('abastecer'), ('autorizar_ejecucion'), ('ejecutar'), ('evaluar'), ('revisar'), ('dictaminar'), ('cerrar'), ('autorizar_implementacion')) a(accion)
  where case a.accion
    when 'preparar' then p.estado in ('registrada', 'en_preparacion', 'requiere_repeticion') and public.prubind_puede(p.id, 'preparar')
    when 'abastecer' then p.estado in ('en_preparacion', 'preparada') and public.prubind_tiene_autoridad(p.tipo, 'abastecer')
         and exists (select 1 from public.prueba_materiales_prubind m where m.prueba_id = p.id and m.disponibilidad in ('pendiente', 'en_compra'))
    when 'autorizar_ejecucion' then p.estado = 'preparada' and p.req_aut and not (p.e ->> 'aut_ejecucion')::boolean
         and public.prubind_puede(p.id, 'autorizar_ejecucion')
    when 'ejecutar' then (p.estado = 'en_ejecucion' or (p.estado = 'preparada' and public.prubind_ejecucion_abierta(p.id))) and public.prubind_puede(p.id, 'ejecutar')
    when 'evaluar' then p.estado in ('en_evaluacion', 'pendiente_resultados') and public.prubind_puede(p.id, 'evaluar')
    when 'revisar' then p.estado in ('en_ejecucion', 'en_evaluacion', 'pendiente_resultados', 'pendiente_dictamen')
         and exists (select 1 from public.resultados_prubind r join public.metodos_prubind m on m.id = r.metodo_id
                     where r.prueba_id = p.id and r.ejecucion = p.ejecucion_actual and r.estado <> 'pendiente' and r.revisado_por is null
                       and m.revisa_puesto_id = public.prubind_puesto_actual())
    when 'dictaminar' then p.estado = 'pendiente_dictamen' and public.prubind_puede(p.id, 'dictaminar')
    when 'cerrar' then p.estado in ('aprobada', 'rechazada') and public.prubind_puede(p.id, 'cerrar')
    when 'autorizar_implementacion' then p.estado = 'cerrada_aprobada' and public.prubind_puede(p.id, 'autorizar_implementacion')
         and not exists (select 1 from public.autorizaciones_prubind z where z.prueba_id = p.id and z.tipo = 'implementacion'
                         and (z.autorizado_por = uid or (z.puesto_id is not null and z.puesto_id = public.prubind_puesto_actual())))
    else false end
  order by p.created_at;
end $$;

create or replace function public.prubind_dashboard(p_desde date, p_hasta date)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare v_res jsonb; v_por_mes boolean;
begin
  if not public.prubind_es_miembro() then raise exception 'Usuario no autorizado.' using errcode = '42501'; end if;
  if p_desde is null or p_hasta is null or p_hasta < p_desde or p_hasta - p_desde > 1100 then
    raise exception 'Periodo inválido (máximo 3 años).' using errcode = 'P0001';
  end if;
  v_por_mes := (p_hasta - p_desde) > 62;
  with reg as (
    select * from public.pruebas_prubind where (created_at at time zone 'America/Mexico_City')::date between p_desde and p_hasta
  ), cer as (
    select * from public.pruebas_prubind where estado in ('cerrada_aprobada', 'cerrada_rechazada')
      and (cerrada_at at time zone 'America/Mexico_City')::date between p_desde and p_hasta
  ), res as (
    select r.estado, m.categoria from public.resultados_prubind r join public.metodos_prubind m on m.id = r.metodo_id
    where (r.created_at at time zone 'America/Mexico_City')::date between p_desde and p_hasta
  )
  select jsonb_build_object(
    'por_mes', v_por_mes,
    'actual', (select coalesce(jsonb_object_agg(estado, n), '{}'::jsonb) from (select estado, count(*) n from public.pruebas_prubind group by estado) s),
    'registradas', (select count(*) from reg),
    'cerradas_aprobadas', (select count(*) from cer where estado = 'cerrada_aprobada'),
    'cerradas_rechazadas', (select count(*) from cer where estado = 'cerrada_rechazada'),
    'urgentes_abiertas', (select count(*) from public.pruebas_prubind where prioridad = 'urgente'
                          and estado not in ('cerrada_aprobada','cerrada_rechazada','cancelada')),
    'por_tipo', coalesce((select jsonb_agg(jsonb_build_object('tipo', t.nombre, 'n', coalesce(x.n, 0)) order by t.orden)
                 from public.tipos_prueba_prubind t left join (select tipo, count(*) n from reg group by tipo) x on x.tipo = t.codigo
                 where t.activo or x.n > 0), '[]'::jsonb),
    'resultados_por_categoria', coalesce((select jsonb_agg(jsonb_build_object('categoria', categoria, 'conforme', c, 'no_conforme', nc, 'pendiente', pe, 'no_aplica', na))
                 from (select categoria, count(*) filter (where estado = 'conforme') c, count(*) filter (where estado = 'no_conforme') nc,
                       count(*) filter (where estado = 'pendiente') pe, count(*) filter (where estado = 'no_aplica') na from res group by categoria) s), '[]'::jsonb),
    'serie', coalesce((select jsonb_agg(jsonb_build_object('periodo', periodo, 'registradas', a, 'cerradas', b) order by periodo) from (
       select periodo, sum(a)::int a, sum(b)::int b from (
         select to_char(created_at at time zone 'America/Mexico_City', case when v_por_mes then 'YYYY-MM' else 'YYYY-MM-DD' end) periodo, 1 a, 0 b from reg
         union all
         select to_char(cerrada_at at time zone 'America/Mexico_City', case when v_por_mes then 'YYYY-MM' else 'YYYY-MM-DD' end), 0, 1 from cer) u
       group by periodo) s), '[]'::jsonb)
  ) into v_res;
  return v_res;
end $$;

-- ---------- RLS --------------------------------------------------------
do $$
declare t text;
begin
  -- Lectura para todos los miembros
  foreach t in array array['puestos_prubind','unidades_prubind','objetivos_prubind','productos_prubind','materias_primas_prubind',
    'proveedores_prubind','lotes_mp_prubind','equipos_prubind','equipo_parametros_prubind','recetas_prubind','receta_versiones_prubind',
    'receta_ingredientes_prubind','metodos_prubind','especificaciones_prubind','plantilla_evaluacion_prubind','motivos_prubind',
    'tipos_evidencia_prubind','autoridades_prubind','pruebas_prubind','prueba_formulacion_prubind','prueba_materiales_prubind',
    'prueba_parametros_prubind','plan_evaluacion_prubind','puntos_muestreo_prubind','lotes_diarios_prubind','batches_prubind',
    'batch_lotes_mp_prubind','ejecucion_controles_prubind','muestras_prubind','muestra_batches_prubind','resultados_prubind',
    'dictamenes_prubind','autorizaciones_prubind','seguimiento_prubind','adjuntos_prubind'] loop
    execute format('drop policy if exists %I on public.%I', t || '_sel', t);
    execute format('create policy %I on public.%I for select to authenticated using ((select public.prubind_es_miembro()))', t || '_sel', t);
  end loop;
  -- Catálogos: escritura solo administradores
  foreach t in array array['puestos_prubind','unidades_prubind','objetivos_prubind','productos_prubind','materias_primas_prubind',
    'proveedores_prubind','equipos_prubind','equipo_parametros_prubind','recetas_prubind','receta_versiones_prubind',
    'receta_ingredientes_prubind','metodos_prubind','especificaciones_prubind','plantilla_evaluacion_prubind','motivos_prubind',
    'tipos_evidencia_prubind','autoridades_prubind'] loop
    execute format('drop policy if exists %I on public.%I', t || '_adm', t);
    execute format('create policy %I on public.%I for all to authenticated using ((select public.prubind_es_admin())) with check ((select public.prubind_es_admin()))', t || '_adm', t);
  end loop;
  -- Registros: los miembros pasan la política; los triggers aplican la autoridad fina
  foreach t in array array['pruebas_prubind','prueba_formulacion_prubind','prueba_materiales_prubind','prueba_parametros_prubind',
    'plan_evaluacion_prubind','puntos_muestreo_prubind','lotes_diarios_prubind','batches_prubind','batch_lotes_mp_prubind',
    'ejecucion_controles_prubind','muestras_prubind','muestra_batches_prubind','resultados_prubind'] loop
    execute format('drop policy if exists %I on public.%I', t || '_ins', t);
    execute format('create policy %I on public.%I for insert to authenticated with check ((select public.prubind_es_miembro()))', t || '_ins', t);
    execute format('drop policy if exists %I on public.%I', t || '_upd', t);
    execute format('create policy %I on public.%I for update to authenticated using ((select public.prubind_es_miembro())) with check ((select public.prubind_es_miembro()))', t || '_upd', t);
    execute format('drop policy if exists %I on public.%I', t || '_del', t);
    execute format('create policy %I on public.%I for delete to authenticated using ((select public.prubind_es_miembro()))', t || '_del', t);
  end loop;
end $$;
-- Lotes de materia prima: administradores y quien tenga la autoridad "abastecer" (Almacén / Compras)
drop policy if exists lotes_mp_prubind_ins on public.lotes_mp_prubind;
create policy lotes_mp_prubind_ins on public.lotes_mp_prubind for insert to authenticated
  with check ((select public.prubind_es_admin()) or (select public.prubind_tiene_autoridad_alguna('abastecer')));
drop policy if exists lotes_mp_prubind_upd on public.lotes_mp_prubind;
create policy lotes_mp_prubind_upd on public.lotes_mp_prubind for update to authenticated
  using ((select public.prubind_es_admin()) or (select public.prubind_tiene_autoridad_alguna('abastecer')))
  with check ((select public.prubind_es_admin()) or (select public.prubind_tiene_autoridad_alguna('abastecer')));
drop policy if exists tipos_prueba_prubind_ins on public.tipos_prueba_prubind;
create policy tipos_prueba_prubind_ins on public.tipos_prueba_prubind for insert to authenticated with check ((select public.prubind_es_admin()));
grant insert on public.tipos_prueba_prubind to authenticated;
drop policy if exists seguimiento_prubind_ins on public.seguimiento_prubind;
create policy seguimiento_prubind_ins on public.seguimiento_prubind for insert to authenticated with check ((select public.prubind_es_miembro()));
drop policy if exists adjuntos_prubind_ins on public.adjuntos_prubind;
create policy adjuntos_prubind_ins on public.adjuntos_prubind for insert to authenticated with check ((select public.prubind_es_miembro()));
drop policy if exists adjuntos_prubind_del on public.adjuntos_prubind;
create policy adjuntos_prubind_del on public.adjuntos_prubind for delete to authenticated
  using ((select public.prubind_es_admin()) or subido_por = (select public.prubind_usuario_actual_id()));

-- ---------- Privilegios ------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['puestos_prubind','unidades_prubind','objetivos_prubind','productos_prubind','materias_primas_prubind',
    'proveedores_prubind','lotes_mp_prubind','equipos_prubind','equipo_parametros_prubind','recetas_prubind','receta_versiones_prubind',
    'receta_ingredientes_prubind','metodos_prubind','especificaciones_prubind','plantilla_evaluacion_prubind','motivos_prubind',
    'tipos_evidencia_prubind','autoridades_prubind','pruebas_prubind','prueba_formulacion_prubind','prueba_materiales_prubind',
    'prueba_parametros_prubind','plan_evaluacion_prubind','puntos_muestreo_prubind','lotes_diarios_prubind','batches_prubind',
    'batch_lotes_mp_prubind','ejecucion_controles_prubind','muestras_prubind','muestra_batches_prubind','resultados_prubind'] loop
    execute format('revoke all on public.%I from anon, public', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
  foreach t in array array['dictamenes_prubind','autorizaciones_prubind','folios_prubind'] loop
    execute format('revoke all on public.%I from anon, public, authenticated', t);
  end loop;
end $$;
grant select on public.dictamenes_prubind, public.autorizaciones_prubind to authenticated;   -- se escriben solo por RPC
revoke all on public.seguimiento_prubind, public.adjuntos_prubind from anon, public, authenticated;
grant select, insert on public.seguimiento_prubind to authenticated;
grant select, insert, delete on public.adjuntos_prubind to authenticated;
revoke all on public.v_pruebas_prubind, public.v_batches_prubind, public.v_resultados_prubind, public.v_seguimiento_prubind from anon, public;
grant select on public.v_pruebas_prubind, public.v_batches_prubind, public.v_resultados_prubind, public.v_seguimiento_prubind to authenticated;

do $$
declare f text;
begin
  foreach f in array array['prubind_puesto_actual()', 'prubind_tiene_autoridad(text,text)', 'prubind_tiene_autoridad_alguna(text)',
    'prubind_puede(uuid,text)', 'prubind_puede_crear_tipo(text)', 'prubind_mi_perfil()', 'prubind_eval_estado(uuid)',
    'prubind_accion(uuid,text,jsonb)', 'prubind_mis_pendientes()', 'prubind_dashboard(date,date)', 'prubind_clonar_version(uuid,text)',
    'prubind_ejecucion_abierta(uuid)', 'prubind_estado_txt(text)', 'prubind_accion_txt(text)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
  foreach f in array array['prubind_req(uuid,text,text[],text)', 'prubind_set_estado(uuid,text,text)', 'prubind_validar_prueba()',
    'prubind_despues_prueba()', 'prubind_validar_prep()', 'prubind_validar_ejecucion()', 'prubind_validar_muestra()',
    'prubind_validar_resultado()', 'prubind_validar_adjunto()', 'prubind_validar_receta_version()', 'prubind_validar_receta_ingrediente()'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

-- ---------- Storage: adjuntos (la política de inserción dependía de la tabla v1)
drop policy if exists adjuntos_prubind_insert on storage.objects;
create policy adjuntos_prubind_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'adjuntos_prubind' and (select public.prubind_es_miembro())
              and exists (select 1 from public.pruebas_prubind p where p.id::text = (storage.foldername(name))[1]));
