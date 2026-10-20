-- =====================================================================
-- Pruebas industriales · Migración 2/3
-- Identidad y roles, reglas de negocio (triggers), auditoría, RPC
-- transaccionales, vistas, tablero, RLS, privilegios y Storage.
-- =====================================================================

-- ---------- Identidad, rol y funciones ---------------------------------
create or replace function public.prubind_usuario_actual_id()
returns uuid language sql stable security definer set search_path = '' as $$
  select u.id from public.usuarios_prubind u
  where lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', '')) and u.activo
  limit 1
$$;

create or replace function public.prubind_es_miembro()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.usuarios_prubind u
                 where lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', '')) and u.activo)
$$;

create or replace function public.prubind_es_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.usuarios_prubind u
                 where lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
                   and u.activo and u.rol = 'admin')
$$;

-- ¿El usuario actual tiene la función indicada? (los administradores tienen todas)
create or replace function public.prubind_tiene_funcion(p_funcion text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.usuarios_prubind u
                 where lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
                   and u.activo and (u.rol = 'admin' or p_funcion = any (u.funciones)))
$$;

create or replace function public.prubind_puede_crear_tipo(p_tipo text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.tipos_prueba_prubind t where t.codigo = p_tipo and t.activo)
     and (public.prubind_es_admin() or exists (
          select 1 from public.tipo_responsables_prubind r
          where r.tipo = p_tipo and r.usuario_id = public.prubind_usuario_actual_id()))
$$;

create or replace function public.prubind_hoy()
returns date language sql stable set search_path = '' as $$
  select (now() at time zone 'America/Mexico_City')::date
$$;

-- Perfil de la sesión (lo usa el frontend al iniciar sesión)
create or replace function public.prubind_mi_perfil()
returns table (id uuid, email text, nombre text, rol text, area_id uuid, area text, puesto text,
               foto_url text, funciones text[], tipos_responsable text[])
language sql stable security definer set search_path = '' as $$
  select u.id, u.email, u.nombre, u.rol, u.area_id, a.nombre, u.puesto, u.foto_url, u.funciones,
         coalesce((select array_agg(r.tipo order by r.tipo) from public.tipo_responsables_prubind r where r.usuario_id = u.id), '{}')
  from public.usuarios_prubind u left join public.areas_prubind a on a.id = u.area_id
  where lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', '')) and u.activo
$$;

-- ---------- updated_at -------------------------------------------------
create or replace function public.prubind_touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['areas_prubind','usuarios_prubind','tipos_prueba_prubind','pruebas_prubind','batches_prubind',
                           'insumos_prubind','resultados_prubind','envasadora_prubind'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_touch', t);
    execute format('create trigger %I before update on public.%I for each row execute function public.prubind_touch_updated_at()', t || '_touch', t);
  end loop;
end $$;

-- ---------- Auditoría --------------------------------------------------
create or replace function public.prubind_auditar()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_cambios jsonb;
  v_id text;
  v_key text := coalesce(tg_argv[0], 'id');
begin
  if tg_op = 'DELETE' then
    v_id := to_jsonb(old) ->> v_key; v_cambios := to_jsonb(old);
  elsif tg_op = 'INSERT' then
    v_id := to_jsonb(new) ->> v_key; v_cambios := to_jsonb(new);
  else
    v_id := to_jsonb(new) ->> v_key;
    select jsonb_object_agg(n.key, jsonb_build_array(o.value, n.value)) into v_cambios
      from jsonb_each(to_jsonb(new)) n join jsonb_each(to_jsonb(old)) o using (key)
     where n.value is distinct from o.value and n.key <> 'updated_at';
    if v_cambios is null then return new; end if;
  end if;
  insert into public.bitacora_prubind (tabla, registro_id, accion, cambios, usuario_email)
  values (tg_table_name, coalesce(v_id, '?'), tg_op, v_cambios, auth.jwt() ->> 'email');
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array['areas_prubind','usuarios_prubind','tipos_prueba_prubind','pruebas_prubind','batches_prubind',
                           'insumos_prubind','resultados_prubind','envasadora_prubind','adjuntos_prubind'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_audit', t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.prubind_auditar()', t || '_audit', t);
  end loop;
end $$;
drop trigger if exists tipo_responsables_prubind_audit on public.tipo_responsables_prubind;
create trigger tipo_responsables_prubind_audit after insert or delete on public.tipo_responsables_prubind
  for each row execute function public.prubind_auditar('tipo');

-- ---------- Seguimiento automático ------------------------------------
-- Inserta un evento en el seguimiento de la prueba (solo desde funciones del servidor)
create or replace function public.prubind_log(p_prueba uuid, p_tipo text, p_texto text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform set_config('prubind.sys', '1', true);
  insert into public.seguimiento_prubind (prueba_id, tipo, texto, usuario_id)
  values (p_prueba, p_tipo, left(p_texto, 2000), public.prubind_usuario_actual_id());
  perform set_config('prubind.sys', '', true);
end $$;

create or replace function public.prubind_validar_seguimiento()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return new; end if;
  if coalesce(current_setting('prubind.sys', true), '') <> '1' then
    if public.prubind_usuario_actual_id() is null then
      raise exception 'Usuario no autorizado.' using errcode = '42501';
    end if;
    new.tipo := 'nota';
    new.usuario_id := public.prubind_usuario_actual_id();
  end if;
  new.texto := btrim(new.texto);
  return new;
end $$;
drop trigger if exists seguimiento_prubind_validar on public.seguimiento_prubind;
create trigger seguimiento_prubind_validar before insert on public.seguimiento_prubind
  for each row execute function public.prubind_validar_seguimiento();

-- ---------- Usuarios: nunca quedarse sin administrador ----------------
create or replace function public.prubind_validar_usuario()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.email := lower(btrim(new.email));
  new.nombre := btrim(regexp_replace(new.nombre, '\s+', ' ', 'g'));
  new.puesto := nullif(btrim(new.puesto), '');
  new.funciones := coalesce((select array_agg(distinct f order by f) from unnest(new.funciones) f), '{}');
  if tg_op = 'UPDATE' then
    if lower(old.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
       and (new.activo is distinct from old.activo or new.rol is distinct from old.rol or new.email is distinct from old.email) then
      raise exception 'No puede cambiar su propio rol, correo ni estado.' using errcode = 'P0001';
    end if;
    if old.rol = 'admin' and old.activo and (new.rol <> 'admin' or not new.activo)
       and (select count(*) from public.usuarios_prubind where rol = 'admin' and activo and id <> old.id) = 0 then
      raise exception 'Debe existir al menos un administrador activo.' using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists usuarios_prubind_validar on public.usuarios_prubind;
create trigger usuarios_prubind_validar before insert or update on public.usuarios_prubind
  for each row execute function public.prubind_validar_usuario();

-- ---------- Batches: sincronización con num_batches ---------------------
create or replace function public.prubind_sincronizar_batches(p_prueba uuid, p_n integer, p_fecha date)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.batches_prubind b
             where b.prueba_id = p_prueba and b.numero > p_n
               and (b.estado <> 'programado' or exists (select 1 from public.resultados_prubind r where r.batch_id = b.id))) then
    raise exception 'No se puede reducir el número de batches: hay batches producidos, cancelados o con resultados por encima del nuevo total.' using errcode = 'P0001';
  end if;
  perform set_config('prubind.sync', '1', true);
  delete from public.batches_prubind where prueba_id = p_prueba and numero > p_n;
  insert into public.batches_prubind (prueba_id, numero, fecha_programada)
  select p_prueba, g, p_fecha from generate_series(1, p_n) g
  where not exists (select 1 from public.batches_prubind b where b.prueba_id = p_prueba and b.numero = g);
  perform set_config('prubind.sync', '', true);
end $$;

-- ---------- Reglas de negocio: pruebas ---------------------------------
create or replace function public.prubind_validar_prueba()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_uid   uuid := public.prubind_usuario_actual_id();
  v_admin boolean := public.prubind_es_admin();
  v_rpc   boolean := coalesce(current_setting('prubind.rpc', true), '') = '1';
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return coalesce(new, old); end if;
  if v_uid is null then
    raise exception 'Usuario no autorizado para Pruebas industriales.' using errcode = '42501';
  end if;

  if tg_op = 'DELETE' then
    if old.estado <> 'borrador' then
      raise exception 'Solo se eliminan pruebas en borrador. Para las demás use "Cancelar".' using errcode = 'P0001';
    end if;
    if not (v_admin or old.creado_por = v_uid) then
      raise exception 'Solo el responsable de la prueba o un administrador puede eliminarla.' using errcode = '42501';
    end if;
    if exists (select 1 from public.adjuntos_prubind a where a.prueba_id = old.id) then
      raise exception 'Elimine primero los archivos adjuntos de la prueba.' using errcode = 'P0001';
    end if;
    return old;
  end if;

  new.titulo := btrim(regexp_replace(new.titulo, '\s+', ' ', 'g'));
  new.objetivo := btrim(new.objetivo);
  new.producto := nullif(btrim(new.producto), '');
  new.descripcion := nullif(btrim(new.descripcion), '');
  new.insumo_cambio := nullif(btrim(new.insumo_cambio), '');
  new.proveedor_actual := nullif(btrim(new.proveedor_actual), '');
  new.proveedor_nuevo := nullif(btrim(new.proveedor_nuevo), '');
  new.material_actual := nullif(btrim(new.material_actual), '');
  new.material_nuevo := nullif(btrim(new.material_nuevo), '');

  if tg_op = 'INSERT' then
    if not public.prubind_puede_crear_tipo(new.tipo) then
      raise exception 'No está autorizado para registrar pruebas de este tipo.' using errcode = '42501';
    end if;
    new.creado_por := v_uid;
    new.estado := 'borrador';
    new.dictamen_calidad := null; new.dictamen_calidad_obs := null; new.dictamen_calidad_por := null; new.dictamen_calidad_at := null;
    new.dictamen_final := null; new.dictamen_final_obs := null; new.dictamen_final_por := null; new.dictamen_final_at := null;
    new.motivo_cancelacion := null; new.cancelado_por := null; new.cancelado_at := null;
    return new;
  end if;

  -- UPDATE
  if new.tipo is distinct from old.tipo or new.creado_por is distinct from old.creado_por then
    raise exception 'No se puede cambiar el tipo ni el responsable de una prueba.' using errcode = 'P0001';
  end if;
  if old.estado in ('aprobada', 'rechazada', 'cancelada') then
    raise exception 'La prueba ya está cerrada y no puede modificarse.' using errcode = 'P0001';
  end if;
  if not v_rpc and (new.estado, new.dictamen_calidad, new.dictamen_calidad_obs, new.dictamen_calidad_por, new.dictamen_calidad_at,
                    new.dictamen_final, new.dictamen_final_obs, new.dictamen_final_por, new.dictamen_final_at,
                    new.motivo_cancelacion, new.cancelado_por, new.cancelado_at)
                is distinct from
                   (old.estado, old.dictamen_calidad, old.dictamen_calidad_obs, old.dictamen_calidad_por, old.dictamen_calidad_at,
                    old.dictamen_final, old.dictamen_final_obs, old.dictamen_final_por, old.dictamen_final_at,
                    old.motivo_cancelacion, old.cancelado_por, old.cancelado_at) then
    raise exception 'Use las acciones de la prueba para cambiar su estado o registrar un dictamen.' using errcode = 'P0001';
  end if;
  if (new.titulo, new.producto, new.objetivo, new.descripcion, new.num_batches, new.fecha_inicio, new.fecha_fin,
      new.insumo_cambio, new.proveedor_actual, new.proveedor_nuevo, new.material_actual, new.material_nuevo)
     is distinct from
     (old.titulo, old.producto, old.objetivo, old.descripcion, old.num_batches, old.fecha_inicio, old.fecha_fin,
      old.insumo_cambio, old.proveedor_actual, old.proveedor_nuevo, old.material_actual, old.material_nuevo) then
    if not (v_admin or old.creado_por = v_uid) then
      raise exception 'Solo el responsable de la prueba o un administrador puede editar sus datos.' using errcode = '42501';
    end if;
    if old.estado not in ('borrador', 'planeada') and not v_admin then
      raise exception 'La prueba ya está en ejecución: solo un administrador puede modificar sus datos generales.' using errcode = 'P0001';
    end if;
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
    perform public.prubind_sincronizar_batches(new.id, new.num_batches, new.fecha_inicio);
    perform public.prubind_log(new.id, 'sistema', format('Prueba registrada con %s batch(es) planeado(s).', new.num_batches));
  elsif new.num_batches is distinct from old.num_batches then
    perform public.prubind_sincronizar_batches(new.id, new.num_batches, new.fecha_inicio);
    perform public.prubind_log(new.id, 'sistema', format('Número de batches cambiado de %s a %s.', old.num_batches, new.num_batches));
  end if;
  return new;
end $$;
drop trigger if exists pruebas_prubind_despues on public.pruebas_prubind;
create trigger pruebas_prubind_despues after insert or update on public.pruebas_prubind
  for each row execute function public.prubind_despues_prueba();

-- ---------- Reglas de negocio: batches ---------------------------------
create or replace function public.prubind_validar_batch()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.prubind_usuario_actual_id();
  v_p   public.pruebas_prubind%rowtype;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return new; end if;
  if tg_op = 'INSERT' then
    if coalesce(current_setting('prubind.sync', true), '') <> '1' then
      raise exception 'Los batches se generan a partir del número de batches de la prueba.' using errcode = 'P0001';
    end if;
    return new;
  end if;

  select * into v_p from public.pruebas_prubind where id = old.prueba_id;
  if new.prueba_id is distinct from old.prueba_id or new.numero is distinct from old.numero then
    raise exception 'No se puede cambiar la prueba ni el número del batch.' using errcode = 'P0001';
  end if;
  if v_p.estado in ('aprobada', 'rechazada', 'cancelada') then
    raise exception 'La prueba está cerrada; sus batches no pueden modificarse.' using errcode = 'P0001';
  end if;
  if not (public.prubind_tiene_funcion('produccion') or v_p.creado_por = v_uid) then
    raise exception 'Solo Producción, el responsable de la prueba o un administrador pueden actualizar batches.' using errcode = '42501';
  end if;

  new.lote := nullif(upper(btrim(new.lote)), '');
  new.unidad := nullif(btrim(new.unidad), '');
  new.observaciones := nullif(btrim(new.observaciones), '');
  new.motivo_cancelacion := nullif(btrim(new.motivo_cancelacion), '');
  new.registrado_por := old.registrado_por;

  if new.estado is distinct from old.estado then
    if v_p.estado <> 'en_ejecucion' then
      raise exception 'La producción de batches solo se registra cuando la prueba está en ejecución.' using errcode = 'P0001';
    end if;
    if new.estado = 'producido' then
      if old.estado <> 'programado' then
        raise exception 'Solo un batch programado puede marcarse como producido.' using errcode = 'P0001';
      end if;
      if new.fecha_real is null then
        raise exception 'Indique la fecha real de producción.' using errcode = 'P0001';
      end if;
      new.registrado_por := v_uid;
      new.motivo_cancelacion := null;
    elsif new.estado = 'cancelado' then
      if old.estado <> 'programado' then
        raise exception 'Solo se cancelan batches programados.' using errcode = 'P0001';
      end if;
      if new.motivo_cancelacion is null then
        raise exception 'Indique el motivo de la cancelación del batch.' using errcode = 'P0001';
      end if;
      new.fecha_real := null;
    else -- regresar a programado
      if exists (select 1 from public.resultados_prubind r where r.batch_id = old.id) then
        raise exception 'El batch tiene resultados de calidad; elimínelos antes de revertirlo.' using errcode = 'P0001';
      end if;
      new.fecha_real := null; new.registrado_por := null; new.motivo_cancelacion := null;
    end if;
  elsif new.estado = 'programado' then
    new.fecha_real := null;
  end if;

  if new.fecha_real is not null and new.fecha_real > public.prubind_hoy() then
    raise exception 'La fecha real de producción no puede ser futura.' using errcode = 'P0001';
  end if;
  if new.fecha_programada is distinct from old.fecha_programada and new.estado <> 'programado' then
    raise exception 'Solo se reprograma un batch que sigue programado.' using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists batches_prubind_validar on public.batches_prubind;
create trigger batches_prubind_validar before insert or update on public.batches_prubind
  for each row execute function public.prubind_validar_batch();

create or replace function public.prubind_despues_batch()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.estado is distinct from old.estado then
    perform public.prubind_log(new.prueba_id, 'sistema', case new.estado
      when 'producido' then format('Batch %s producido el %s%s.', new.numero, to_char(new.fecha_real, 'DD/MM/YYYY'), coalesce(' · lote ' || new.lote, ''))
      when 'cancelado' then format('Batch %s cancelado: %s', new.numero, new.motivo_cancelacion)
      else format('Batch %s regresado a programado.', new.numero) end);
  end if;
  return new;
end $$;
drop trigger if exists batches_prubind_despues on public.batches_prubind;
create trigger batches_prubind_despues after update on public.batches_prubind
  for each row execute function public.prubind_despues_batch();

-- ---------- Reglas de negocio: insumos ---------------------------------
-- solicitado → validado (Producción) → en_compra → recibido (Compras); cancelado en cualquier punto abierto
create or replace function public.prubind_validar_insumo()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_uid   uuid := public.prubind_usuario_actual_id();
  v_p     public.pruebas_prubind%rowtype;
  v_resp  boolean;
  v_prod  boolean := public.prubind_tiene_funcion('produccion');
  v_comp  boolean := public.prubind_tiene_funcion('compras');
  v_pid   uuid;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if v_uid is null then
    raise exception 'Usuario no autorizado.' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then v_pid := old.prueba_id; else v_pid := new.prueba_id; end if;
  select * into v_p from public.pruebas_prubind where id = v_pid;
  v_resp := public.prubind_es_admin() or v_p.creado_por = v_uid;

  if tg_op = 'DELETE' then
    if old.estado <> 'solicitado' then
      raise exception 'Solo se eliminan solicitudes que no han sido validadas. Use "Cancelar".' using errcode = 'P0001';
    end if;
    if not (v_resp or v_prod or old.solicitado_por = v_uid) then
      raise exception 'No tiene permiso para eliminar esta solicitud.' using errcode = '42501';
    end if;
    return old;
  end if;

  new.insumo := btrim(regexp_replace(new.insumo, '\s+', ' ', 'g'));
  new.unidad := btrim(new.unidad);
  new.especificacion := nullif(btrim(new.especificacion), '');
  new.proveedor := nullif(btrim(new.proveedor), '');
  new.obs_validacion := nullif(btrim(new.obs_validacion), '');
  new.orden_compra := nullif(btrim(new.orden_compra), '');
  new.obs_compras := nullif(btrim(new.obs_compras), '');
  new.motivo_cancelacion := nullif(btrim(new.motivo_cancelacion), '');

  if tg_op = 'INSERT' then
    if v_p.estado not in ('borrador', 'planeada', 'en_ejecucion') then
      raise exception 'Solo se solicitan insumos para pruebas en borrador, planeadas o en ejecución.' using errcode = 'P0001';
    end if;
    if not (v_resp or v_prod) then
      raise exception 'Solo Producción, el responsable de la prueba o un administrador pueden solicitar insumos.' using errcode = '42501';
    end if;
    new.estado := 'solicitado'; new.solicitado_por := v_uid;
    new.cantidad_validada := null; new.obs_validacion := null; new.validado_por := null; new.validado_at := null;
    new.orden_compra := null; new.obs_compras := null; new.cantidad_recibida := null; new.fecha_recepcion := null;
    new.compras_por := null; new.motivo_cancelacion := null;
    return new;
  end if;

  -- UPDATE
  if new.prueba_id is distinct from old.prueba_id or new.solicitado_por is distinct from old.solicitado_por then
    raise exception 'No se puede cambiar la prueba ni el solicitante del insumo.' using errcode = 'P0001';
  end if;
  if old.estado in ('recibido', 'cancelado') then
    raise exception 'La solicitud del insumo ya está cerrada.' using errcode = 'P0001';
  end if;
  if v_p.estado in ('aprobada', 'rechazada', 'cancelada') and new.estado <> 'cancelado' then
    raise exception 'La prueba está cerrada; solo puede cancelar la solicitud.' using errcode = 'P0001';
  end if;

  -- Datos de la solicitud: editables solo mientras está "solicitado"
  if (new.insumo, new.especificacion, new.proveedor, new.unidad, new.cantidad_por_batch, new.cantidad_solicitada, new.fecha_requerida)
     is distinct from (old.insumo, old.especificacion, old.proveedor, old.unidad, old.cantidad_por_batch, old.cantidad_solicitada, old.fecha_requerida) then
    if old.estado <> 'solicitado' then
      raise exception 'El insumo ya fue validado; sus datos de solicitud no pueden cambiar.' using errcode = 'P0001';
    end if;
    if not (v_resp or v_prod or old.solicitado_por = v_uid) then
      raise exception 'No tiene permiso para editar esta solicitud.' using errcode = '42501';
    end if;
  end if;

  -- Los autores de cada etapa los asigna el servidor; nunca el cliente
  new.validado_por := old.validado_por; new.validado_at := old.validado_at; new.compras_por := old.compras_por;

  if new.estado is distinct from old.estado then
    -- Al avanzar a compra/recepción/cancelación la validación queda congelada
    if new.estado in ('en_compra', 'recibido', 'cancelado') then
      new.cantidad_validada := old.cantidad_validada; new.obs_validacion := old.obs_validacion;
    end if;
    if new.estado = 'validado' and old.estado = 'solicitado' then
      if not v_prod then raise exception 'Solo Producción valida las cantidades de insumos.' using errcode = '42501'; end if;
      if new.cantidad_validada is null then raise exception 'Indique la cantidad validada.' using errcode = 'P0001'; end if;
      new.validado_por := v_uid; new.validado_at := now();
    elsif new.estado = 'solicitado' and old.estado = 'validado' then
      if not v_prod then raise exception 'Solo Producción puede retirar su validación.' using errcode = '42501'; end if;
      new.cantidad_validada := null; new.validado_por := null; new.validado_at := null;
    elsif new.estado = 'en_compra' and old.estado = 'validado' then
      if not v_comp then raise exception 'Solo Compras registra la compra de insumos.' using errcode = '42501'; end if;
      new.compras_por := v_uid;
    elsif new.estado = 'recibido' and old.estado in ('validado', 'en_compra') then
      if not v_comp then raise exception 'Solo Compras registra la recepción de insumos.' using errcode = '42501'; end if;
      if new.cantidad_recibida is null or new.fecha_recepcion is null then
        raise exception 'Indique la cantidad recibida y la fecha de recepción.' using errcode = 'P0001';
      end if;
      if new.fecha_recepcion > public.prubind_hoy() then
        raise exception 'La fecha de recepción no puede ser futura.' using errcode = 'P0001';
      end if;
      new.compras_por := v_uid;
    elsif new.estado = 'cancelado' then
      if not (v_resp or v_prod or v_comp or old.solicitado_por = v_uid) then
        raise exception 'No tiene permiso para cancelar esta solicitud.' using errcode = '42501';
      end if;
      if new.motivo_cancelacion is null then raise exception 'Indique el motivo de la cancelación.' using errcode = 'P0001'; end if;
    else
      raise exception 'Cambio de estado de insumo no permitido (% → %).', old.estado, new.estado using errcode = 'P0001';
    end if;
  else
    -- Sin cambio de estado: validar quién toca los campos de cada etapa
    if (new.cantidad_validada, new.obs_validacion) is distinct from (old.cantidad_validada, old.obs_validacion) then
      if not v_prod then raise exception 'Solo Producción modifica la validación.' using errcode = '42501'; end if;
      if old.estado not in ('solicitado', 'validado') then
        raise exception 'El insumo ya está en compra; la validación no puede cambiar.' using errcode = 'P0001';
      end if;
    end if;
    if (new.orden_compra, new.obs_compras, new.cantidad_recibida, new.fecha_recepcion) is distinct from
       (old.orden_compra, old.obs_compras, old.cantidad_recibida, old.fecha_recepcion) and not v_comp then
      raise exception 'Solo Compras modifica los datos de compra.' using errcode = '42501';
    end if;
  end if;
  if new.estado <> 'cancelado' then new.motivo_cancelacion := null; end if;
  return new;
end $$;
drop trigger if exists insumos_prubind_validar on public.insumos_prubind;
create trigger insumos_prubind_validar before insert or update or delete on public.insumos_prubind
  for each row execute function public.prubind_validar_insumo();

create or replace function public.prubind_despues_insumo()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_cant text;
begin
  if tg_op = 'INSERT' then
    perform public.prubind_log(new.prueba_id, 'sistema', format('Insumo solicitado: %s (%s %s).', new.insumo, trim(to_char(new.cantidad_solicitada, 'FM999999990.###')), new.unidad));
  elsif new.estado is distinct from old.estado then
    v_cant := trim(to_char(coalesce(new.cantidad_recibida, new.cantidad_validada, new.cantidad_solicitada), 'FM999999990.###'));
    perform public.prubind_log(new.prueba_id, 'sistema', case new.estado
      when 'validado'  then format('Producción validó %s %s de %s.', v_cant, new.unidad, new.insumo)
      when 'en_compra' then format('Compras inició la compra de %s%s.', new.insumo, coalesce(' (OC ' || new.orden_compra || ')', ''))
      when 'recibido'  then format('Se recibieron %s %s de %s.', v_cant, new.unidad, new.insumo)
      when 'cancelado' then format('Solicitud de %s cancelada: %s', new.insumo, new.motivo_cancelacion)
      else format('Validación de %s retirada.', new.insumo) end);
  end if;
  return new;
end $$;
drop trigger if exists insumos_prubind_despues on public.insumos_prubind;
create trigger insumos_prubind_despues after insert or update on public.insumos_prubind
  for each row execute function public.prubind_despues_insumo();

-- ---------- Reglas de negocio: resultados de calidad -------------------
create or replace function public.prubind_validar_resultado()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_b public.batches_prubind%rowtype;
  v_estado text;
  v_bid uuid;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if not public.prubind_tiene_funcion('calidad') then
    raise exception 'Solo Calidad (o un administrador) registra resultados de análisis.' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then v_bid := old.batch_id; else v_bid := new.batch_id; end if;
  select * into v_b from public.batches_prubind where id = v_bid;
  if not found then raise exception 'El batch no existe.' using errcode = 'P0001'; end if;
  select estado into v_estado from public.pruebas_prubind where id = v_b.prueba_id;
  if v_estado not in ('en_ejecucion', 'en_evaluacion') then
    raise exception 'Los resultados se registran cuando la prueba está en ejecución o en evaluación.' using errcode = 'P0001';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  if v_b.estado = 'cancelado' then
    raise exception 'El batch está cancelado.' using errcode = 'P0001';
  end if;
  if tg_op = 'UPDATE' and new.batch_id is distinct from old.batch_id then
    raise exception 'No se puede mover un resultado a otro batch.' using errcode = 'P0001';
  end if;
  new.prueba_id := v_b.prueba_id;
  new.parametro := btrim(regexp_replace(new.parametro, '\s+', ' ', 'g'));
  new.valor := btrim(new.valor);
  new.unidad := nullif(btrim(new.unidad), '');
  new.especificacion := nullif(btrim(new.especificacion), '');
  new.observaciones := nullif(btrim(new.observaciones), '');
  if new.fecha_analisis > public.prubind_hoy() then
    raise exception 'La fecha de análisis no puede ser futura.' using errcode = 'P0001';
  end if;
  if tg_op = 'INSERT' then new.capturado_por := public.prubind_usuario_actual_id();
  else new.capturado_por := old.capturado_por; end if;
  return new;
end $$;
drop trigger if exists resultados_prubind_validar on public.resultados_prubind;
create trigger resultados_prubind_validar before insert or update or delete on public.resultados_prubind
  for each row execute function public.prubind_validar_resultado();

-- ---------- Reglas de negocio: parámetros de envasadora ----------------
create or replace function public.prubind_validar_envasadora()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.prubind_usuario_actual_id();
  v_p   public.pruebas_prubind%rowtype;
  v_usa boolean;
  v_pid uuid;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if tg_op = 'DELETE' then v_pid := old.prueba_id; else v_pid := new.prueba_id; end if;
  select * into v_p from public.pruebas_prubind where id = v_pid;
  if not (public.prubind_tiene_funcion('produccion') or v_p.creado_por = v_uid) then
    raise exception 'Solo Producción, el responsable de la prueba o un administrador registran parámetros de envasadora.' using errcode = '42501';
  end if;
  if v_p.estado not in ('planeada', 'en_ejecucion', 'en_evaluacion') then
    raise exception 'Los parámetros se registran con la prueba planeada, en ejecución o en evaluación.' using errcode = 'P0001';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  select usa_envasadora into v_usa from public.tipos_prueba_prubind where codigo = v_p.tipo;
  if not coalesce(v_usa, false) then
    raise exception 'Este tipo de prueba no registra parámetros de envasadora.' using errcode = 'P0001';
  end if;
  if tg_op = 'UPDATE' and new.prueba_id is distinct from old.prueba_id then
    raise exception 'No se puede mover el parámetro a otra prueba.' using errcode = 'P0001';
  end if;
  if new.batch_id is not null and not exists (select 1 from public.batches_prubind b where b.id = new.batch_id and b.prueba_id = new.prueba_id) then
    raise exception 'El batch no pertenece a esta prueba.' using errcode = 'P0001';
  end if;
  new.maquina := nullif(btrim(new.maquina), '');
  new.parametro := btrim(regexp_replace(new.parametro, '\s+', ' ', 'g'));
  new.valor := btrim(new.valor);
  new.unidad := nullif(btrim(new.unidad), '');
  new.observaciones := nullif(btrim(new.observaciones), '');
  if tg_op = 'INSERT' then new.capturado_por := v_uid; else new.capturado_por := old.capturado_por; end if;
  return new;
end $$;
drop trigger if exists envasadora_prubind_validar on public.envasadora_prubind;
create trigger envasadora_prubind_validar before insert or update or delete on public.envasadora_prubind
  for each row execute function public.prubind_validar_envasadora();

-- ---------- Adjuntos ---------------------------------------------------
create or replace function public.prubind_validar_adjunto()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := public.prubind_usuario_actual_id();
begin
  if coalesce(auth.role(), '') <> 'authenticated' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if v_uid is null then raise exception 'Usuario no autorizado.' using errcode = '42501'; end if;
  if tg_op = 'DELETE' then
    if not (public.prubind_es_admin() or old.subido_por = v_uid) then
      raise exception 'Solo quien subió el archivo o un administrador puede eliminarlo.' using errcode = '42501';
    end if;
    return old;
  end if;
  if new.ruta !~ ('^' || new.prueba_id::text || '/[A-Za-z0-9._-]+$') then
    raise exception 'Ruta de archivo inválida.' using errcode = 'P0001';
  end if;
  new.subido_por := v_uid;
  new.nombre := btrim(new.nombre);
  new.descripcion := nullif(btrim(new.descripcion), '');
  return new;
end $$;
drop trigger if exists adjuntos_prubind_validar on public.adjuntos_prubind;
create trigger adjuntos_prubind_validar before insert or delete on public.adjuntos_prubind
  for each row execute function public.prubind_validar_adjunto();

-- ---------- RPC: cambio de estado de la prueba -------------------------
-- p_accion: planear | regresar_borrador | iniciar | evaluar | reabrir | cancelar
create or replace function public.prubind_cambiar_estado(p_prueba uuid, p_accion text, p_obs text default null)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_uid  uuid := public.prubind_usuario_actual_id();
  v_p    public.pruebas_prubind%rowtype;
  v_resp boolean;
  v_obs  text := nullif(btrim(p_obs), '');
  v_nuevo text;
  v_txt  text;
begin
  if v_uid is null then raise exception 'Usuario no autorizado.' using errcode = '42501'; end if;
  if char_length(coalesce(v_obs, '')) > 500 then raise exception 'El comentario excede 500 caracteres.' using errcode = 'P0001'; end if;
  select * into v_p from public.pruebas_prubind where id = p_prueba for update;
  if not found then raise exception 'La prueba no existe.' using errcode = 'P0001'; end if;
  v_resp := public.prubind_es_admin() or v_p.creado_por = v_uid;

  case p_accion
  when 'planear' then
    if v_p.estado <> 'borrador' then raise exception 'Solo una prueba en borrador puede pasar a planeada.' using errcode = 'P0001'; end if;
    if not v_resp then raise exception 'Solo el responsable de la prueba o un administrador puede planearla.' using errcode = '42501'; end if;
    if v_p.fecha_inicio is null then raise exception 'Indique la fecha de inicio planeada antes de planear la prueba.' using errcode = 'P0001'; end if;
    v_nuevo := 'planeada'; v_txt := 'Prueba planeada.';
  when 'regresar_borrador' then
    if v_p.estado <> 'planeada' then raise exception 'Solo una prueba planeada puede regresar a borrador.' using errcode = 'P0001'; end if;
    if not v_resp then raise exception 'Solo el responsable de la prueba o un administrador puede hacerlo.' using errcode = '42501'; end if;
    v_nuevo := 'borrador'; v_txt := 'Prueba regresada a borrador.';
  when 'iniciar' then
    if v_p.estado <> 'planeada' then raise exception 'Solo una prueba planeada puede iniciar su ejecución.' using errcode = 'P0001'; end if;
    if not (v_resp or public.prubind_tiene_funcion('produccion')) then
      raise exception 'Solo Producción, el responsable o un administrador inician la ejecución.' using errcode = '42501';
    end if;
    v_nuevo := 'en_ejecucion'; v_txt := 'Inició la ejecución de la prueba.';
  when 'evaluar' then
    if v_p.estado <> 'en_ejecucion' then raise exception 'Solo una prueba en ejecución puede pasar a evaluación.' using errcode = 'P0001'; end if;
    if not (v_resp or public.prubind_tiene_funcion('produccion') or public.prubind_tiene_funcion('calidad')) then
      raise exception 'No tiene permiso para enviar la prueba a evaluación.' using errcode = '42501';
    end if;
    if exists (select 1 from public.batches_prubind where prueba_id = p_prueba and estado = 'programado') then
      raise exception 'Aún hay batches programados: márquelos como producidos o cancelados.' using errcode = 'P0001';
    end if;
    if not exists (select 1 from public.batches_prubind where prueba_id = p_prueba and estado = 'producido') then
      raise exception 'La prueba no tiene ningún batch producido.' using errcode = 'P0001';
    end if;
    v_nuevo := 'en_evaluacion'; v_txt := 'Prueba enviada a evaluación.';
  when 'reabrir' then
    if v_p.estado <> 'en_evaluacion' then raise exception 'Solo una prueba en evaluación puede reabrirse.' using errcode = 'P0001'; end if;
    if not public.prubind_es_admin() then raise exception 'Solo un administrador puede reabrir una prueba.' using errcode = '42501'; end if;
    if v_obs is null then raise exception 'Indique el motivo para reabrir la prueba.' using errcode = 'P0001'; end if;
    v_nuevo := 'en_ejecucion'; v_txt := 'Prueba reabierta a ejecución (se retiró el dictamen de Calidad).';
  when 'cancelar' then
    if v_p.estado in ('aprobada', 'rechazada', 'cancelada') then raise exception 'La prueba ya está cerrada.' using errcode = 'P0001'; end if;
    if not v_resp then raise exception 'Solo el responsable de la prueba o un administrador puede cancelarla.' using errcode = '42501'; end if;
    if v_obs is null then raise exception 'Indique el motivo de la cancelación.' using errcode = 'P0001'; end if;
    v_nuevo := 'cancelada'; v_txt := 'Prueba cancelada.';
  else
    raise exception 'Acción no válida.' using errcode = 'P0001';
  end case;

  perform set_config('prubind.rpc', '1', true);
  update public.pruebas_prubind set
    estado = v_nuevo,
    dictamen_calidad     = case when p_accion = 'reabrir' then null else dictamen_calidad end,
    dictamen_calidad_obs = case when p_accion = 'reabrir' then null else dictamen_calidad_obs end,
    dictamen_calidad_por = case when p_accion = 'reabrir' then null else dictamen_calidad_por end,
    dictamen_calidad_at  = case when p_accion = 'reabrir' then null else dictamen_calidad_at end,
    motivo_cancelacion   = case when p_accion = 'cancelar' then v_obs else null end,
    cancelado_por        = case when p_accion = 'cancelar' then v_uid else null end,
    cancelado_at         = case when p_accion = 'cancelar' then now() else null end
  where id = p_prueba;
  perform set_config('prubind.rpc', '', true);
  perform public.prubind_log(p_prueba, 'estado', v_txt || coalesce(' ' || v_obs, ''));
  return v_nuevo;
end $$;

-- ---------- RPC: dictamen técnico de Calidad ---------------------------
create or replace function public.prubind_dictamen_calidad(p_prueba uuid, p_dictamen text, p_obs text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_p   public.pruebas_prubind%rowtype;
  v_obs text := nullif(btrim(p_obs), '');
begin
  if not public.prubind_tiene_funcion('calidad') then
    raise exception 'Solo Calidad (o un administrador) emite el dictamen técnico.' using errcode = '42501';
  end if;
  if p_dictamen not in ('conforme', 'no_conforme') then raise exception 'Dictamen no válido.' using errcode = 'P0001'; end if;
  if v_obs is null or char_length(v_obs) > 2000 then
    raise exception 'Escriba la conclusión del dictamen (máx. 2000 caracteres).' using errcode = 'P0001';
  end if;
  select * into v_p from public.pruebas_prubind where id = p_prueba for update;
  if not found then raise exception 'La prueba no existe.' using errcode = 'P0001'; end if;
  if v_p.estado <> 'en_evaluacion' then
    raise exception 'El dictamen de Calidad se emite cuando la prueba está en evaluación.' using errcode = 'P0001';
  end if;
  perform set_config('prubind.rpc', '1', true);
  update public.pruebas_prubind set dictamen_calidad = p_dictamen, dictamen_calidad_obs = v_obs,
         dictamen_calidad_por = public.prubind_usuario_actual_id(), dictamen_calidad_at = now()
   where id = p_prueba;
  perform set_config('prubind.rpc', '', true);
  perform public.prubind_log(p_prueba, 'estado', format('Dictamen de Calidad: %s. %s',
          case p_dictamen when 'conforme' then 'CONFORME' else 'NO CONFORME' end, v_obs));
end $$;

-- ---------- RPC: dictamen final de Dirección ---------------------------
create or replace function public.prubind_dictamen_final(p_prueba uuid, p_dictamen text, p_obs text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_p   public.pruebas_prubind%rowtype;
  v_obs text := nullif(btrim(p_obs), '');
begin
  if not public.prubind_tiene_funcion('direccion') then
    raise exception 'Solo Dirección (o un administrador) emite el dictamen final.' using errcode = '42501';
  end if;
  if p_dictamen not in ('aprobada', 'rechazada') then raise exception 'Dictamen no válido.' using errcode = 'P0001'; end if;
  if p_dictamen = 'rechazada' and v_obs is null then
    raise exception 'Indique el motivo del rechazo.' using errcode = 'P0001';
  end if;
  if char_length(coalesce(v_obs, '')) > 2000 then raise exception 'El comentario excede 2000 caracteres.' using errcode = 'P0001'; end if;
  select * into v_p from public.pruebas_prubind where id = p_prueba for update;
  if not found then raise exception 'La prueba no existe.' using errcode = 'P0001'; end if;
  if v_p.estado <> 'en_evaluacion' then
    raise exception 'El dictamen final se emite cuando la prueba está en evaluación.' using errcode = 'P0001';
  end if;
  if v_p.dictamen_calidad is null then
    raise exception 'Primero Calidad debe emitir su dictamen técnico.' using errcode = 'P0001';
  end if;
  perform set_config('prubind.rpc', '1', true);
  update public.pruebas_prubind set estado = p_dictamen, dictamen_final = p_dictamen, dictamen_final_obs = v_obs,
         dictamen_final_por = public.prubind_usuario_actual_id(), dictamen_final_at = now()
   where id = p_prueba;
  perform set_config('prubind.rpc', '', true);
  perform public.prubind_log(p_prueba, 'estado', format('Dictamen final: prueba %s.%s',
          upper(p_dictamen), coalesce(' ' || v_obs, '')));
end $$;

-- ---------- Vistas (security_invoker: respetan RLS) --------------------
create or replace view public.v_pruebas_prubind with (security_invoker = true) as
select p.id, p.folio, t.prefijo || '-' || lpad(p.folio::text, 4, '0') as folio_txt,
       p.tipo, t.nombre as tipo_nombre, t.usa_proveedor, t.usa_empaque, t.usa_envasadora,
       p.titulo, p.producto, p.objetivo, p.descripcion, p.num_batches, p.fecha_inicio, p.fecha_fin,
       p.insumo_cambio, p.proveedor_actual, p.proveedor_nuevo, p.material_actual, p.material_nuevo,
       p.estado, p.creado_por, cu.nombre as creado_por_nombre, cu.foto_url as creado_por_foto,
       p.dictamen_calidad, p.dictamen_calidad_obs, p.dictamen_calidad_at, dc.nombre as dictamen_calidad_por_nombre,
       p.dictamen_final, p.dictamen_final_obs, p.dictamen_final_at, df.nombre as dictamen_final_por_nombre,
       p.motivo_cancelacion, p.cancelado_at, ca.nombre as cancelado_por_nombre,
       p.created_at, p.updated_at,
       (select count(*) from public.batches_prubind b where b.prueba_id = p.id and b.estado = 'producido')::int as batches_producidos,
       (select count(*) from public.batches_prubind b where b.prueba_id = p.id and b.estado = 'cancelado')::int as batches_cancelados,
       (select min(b.fecha_programada) from public.batches_prubind b where b.prueba_id = p.id and b.estado = 'programado') as proximo_batch,
       (select count(*) from public.insumos_prubind i where i.prueba_id = p.id and i.estado in ('solicitado','validado','en_compra'))::int as insumos_pendientes,
       (select count(*) from public.insumos_prubind i where i.prueba_id = p.id and i.estado <> 'cancelado')::int as insumos_total,
       (select count(*) from public.resultados_prubind r where r.prueba_id = p.id)::int as resultados_total,
       (select count(*) from public.resultados_prubind r where r.prueba_id = p.id and r.resultado = 'no_cumple')::int as resultados_no_cumple
from public.pruebas_prubind p
join public.tipos_prueba_prubind t on t.codigo = p.tipo
join public.usuarios_prubind cu on cu.id = p.creado_por
left join public.usuarios_prubind dc on dc.id = p.dictamen_calidad_por
left join public.usuarios_prubind df on df.id = p.dictamen_final_por
left join public.usuarios_prubind ca on ca.id = p.cancelado_por;

create or replace view public.v_batches_prubind with (security_invoker = true) as
select b.id, b.prueba_id, b.numero, b.fecha_programada, b.fecha_real, b.lote, b.cantidad, b.unidad, b.estado,
       b.observaciones, b.motivo_cancelacion, b.registrado_por, u.nombre as registrado_por_nombre, b.updated_at,
       t.prefijo || '-' || lpad(p.folio::text, 4, '0') as folio_txt, p.titulo, p.tipo, t.nombre as tipo_nombre,
       p.estado as prueba_estado, p.producto, p.num_batches,
       (select count(*) from public.resultados_prubind r where r.batch_id = b.id)::int as resultados_total,
       (select count(*) from public.resultados_prubind r where r.batch_id = b.id and r.resultado = 'no_cumple')::int as resultados_no_cumple
from public.batches_prubind b
join public.pruebas_prubind p on p.id = b.prueba_id
join public.tipos_prueba_prubind t on t.codigo = p.tipo
left join public.usuarios_prubind u on u.id = b.registrado_por;

create or replace view public.v_insumos_prubind with (security_invoker = true) as
select i.*, t.prefijo || '-' || lpad(p.folio::text, 4, '0') as folio_txt, p.titulo, p.tipo, t.nombre as tipo_nombre,
       p.estado as prueba_estado, p.num_batches,
       s.nombre as solicitado_por_nombre, v.nombre as validado_por_nombre, c.nombre as compras_por_nombre
from public.insumos_prubind i
join public.pruebas_prubind p on p.id = i.prueba_id
join public.tipos_prueba_prubind t on t.codigo = p.tipo
join public.usuarios_prubind s on s.id = i.solicitado_por
left join public.usuarios_prubind v on v.id = i.validado_por
left join public.usuarios_prubind c on c.id = i.compras_por;

create or replace view public.v_seguimiento_prubind with (security_invoker = true) as
select s.id, s.prueba_id, s.tipo, s.texto, s.created_at, s.usuario_id, u.nombre as usuario, u.foto_url,
       t.prefijo || '-' || lpad(p.folio::text, 4, '0') as folio_txt, p.titulo
from public.seguimiento_prubind s
join public.pruebas_prubind p on p.id = s.prueba_id
join public.tipos_prueba_prubind t on t.codigo = p.tipo
left join public.usuarios_prubind u on u.id = s.usuario_id;

-- ---------- RPC: tablero ----------------------------------------------
-- Criterios: los indicadores "actuales" usan el estado presente de todas las pruebas;
-- las distribuciones y series usan las pruebas REGISTRADAS en el periodo (created_at, hora CDMX);
-- los cierres usan la fecha del dictamen final; los resultados usan la fecha de análisis.
create or replace function public.prubind_dashboard(p_desde date, p_hasta date)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare
  v_hoy date := public.prubind_hoy();
  v_uid uuid := public.prubind_usuario_actual_id();
  v_por_mes boolean;
  v_res jsonb;
begin
  if v_uid is null then raise exception 'Usuario no autorizado.' using errcode = '42501'; end if;
  if p_desde is null or p_hasta is null or p_hasta < p_desde or p_hasta - p_desde > 1100 then
    raise exception 'Periodo inválido (máximo 3 años).' using errcode = 'P0001';
  end if;
  v_por_mes := (p_hasta - p_desde) > 62;

  with reg as (
    select p.* from public.pruebas_prubind p
    where (p.created_at at time zone 'America/Mexico_City')::date between p_desde and p_hasta
  ), cierres as (
    select p.* from public.pruebas_prubind p
    where p.estado in ('aprobada','rechazada')
      and (p.dictamen_final_at at time zone 'America/Mexico_City')::date between p_desde and p_hasta
  ), res as (
    select r.* from public.resultados_prubind r where r.fecha_analisis between p_desde and p_hasta
  )
  select jsonb_build_object(
    'hoy', v_hoy,
    'por_mes', v_por_mes,
    'actual', (select jsonb_build_object(
        'borrador', count(*) filter (where estado = 'borrador'),
        'planeada', count(*) filter (where estado = 'planeada'),
        'en_ejecucion', count(*) filter (where estado = 'en_ejecucion'),
        'en_evaluacion', count(*) filter (where estado = 'en_evaluacion'),
        'activas', count(*) filter (where estado in ('planeada','en_ejecucion','en_evaluacion')))
      from public.pruebas_prubind),
    'registradas', (select count(*) from reg),
    'aprobadas', (select count(*) from cierres where estado = 'aprobada'),
    'rechazadas', (select count(*) from cierres where estado = 'rechazada'),
    'batches_semana', (select count(*) from public.batches_prubind b join public.pruebas_prubind p on p.id = b.prueba_id
                       where b.estado = 'programado' and p.estado in ('planeada','en_ejecucion')
                         and b.fecha_programada between v_hoy and v_hoy + 7),
    'batches_atrasados', (select count(*) from public.batches_prubind b join public.pruebas_prubind p on p.id = b.prueba_id
                          where b.estado = 'programado' and p.estado in ('planeada','en_ejecucion') and b.fecha_programada < v_hoy),
    'insumos_por_validar', (select count(*) from public.insumos_prubind i join public.pruebas_prubind p on p.id = i.prueba_id
                            where i.estado = 'solicitado' and p.estado not in ('aprobada','rechazada','cancelada')),
    'insumos_por_comprar', (select count(*) from public.insumos_prubind i join public.pruebas_prubind p on p.id = i.prueba_id
                            where i.estado in ('validado','en_compra') and p.estado not in ('aprobada','rechazada','cancelada')),
    'batches_sin_resultados', (select count(*) from public.batches_prubind b join public.pruebas_prubind p on p.id = b.prueba_id
                               where b.estado = 'producido' and p.estado in ('en_ejecucion','en_evaluacion')
                                 and not exists (select 1 from public.resultados_prubind r where r.batch_id = b.id)),
    'por_dictamen_calidad', (select count(*) from public.pruebas_prubind where estado = 'en_evaluacion' and dictamen_calidad is null),
    'por_dictamen_final', (select count(*) from public.pruebas_prubind where estado = 'en_evaluacion' and dictamen_calidad is not null),
    'mis_borradores', (select count(*) from public.pruebas_prubind where estado = 'borrador' and creado_por = v_uid),
    'resultados', (select jsonb_build_object('total', count(*), 'cumple', count(*) filter (where resultado = 'cumple'),
                     'no_cumple', count(*) filter (where resultado = 'no_cumple'), 'informativo', count(*) filter (where resultado = 'informativo')) from res),
    'por_tipo', coalesce((select jsonb_agg(jsonb_build_object('tipo', t.nombre, 'codigo', t.codigo, 'n', coalesce(x.n, 0)) order by t.orden)
                 from public.tipos_prueba_prubind t
                 left join (select tipo, count(*) n from reg group by tipo) x on x.tipo = t.codigo
                 where t.activo or x.n > 0), '[]'::jsonb),
    'por_estado', coalesce((select jsonb_object_agg(estado, n) from (select estado, count(*) n from reg group by estado) s), '{}'::jsonb),
    'resultados_por_analisis', coalesce((select jsonb_agg(jsonb_build_object('tipo', tipo_analisis, 'cumple', c, 'no_cumple', nc, 'informativo', i))
                 from (select tipo_analisis, count(*) filter (where resultado = 'cumple') c, count(*) filter (where resultado = 'no_cumple') nc,
                              count(*) filter (where resultado = 'informativo') i from res group by tipo_analisis) s), '[]'::jsonb),
    'serie', coalesce((
      select jsonb_agg(jsonb_build_object('periodo', periodo, 'registradas', registradas, 'cerradas', cerradas) order by periodo)
      from (
        select periodo, sum(registradas)::int registradas, sum(cerradas)::int cerradas from (
          select case when v_por_mes then to_char((created_at at time zone 'America/Mexico_City'), 'YYYY-MM')
                      else to_char((created_at at time zone 'America/Mexico_City'), 'YYYY-MM-DD') end periodo, 1 registradas, 0 cerradas from reg
          union all
          select case when v_por_mes then to_char((dictamen_final_at at time zone 'America/Mexico_City'), 'YYYY-MM')
                      else to_char((dictamen_final_at at time zone 'America/Mexico_City'), 'YYYY-MM-DD') end, 0, 1 from cierres
        ) u group by periodo) s), '[]'::jsonb)
  ) into v_res;
  return v_res;
end $$;

-- ---------- Cuentas de acceso (Supabase Auth compartido) ----------------
create or replace function public.prubind_estado_cuentas()
returns table (email text, tiene_cuenta boolean, confirmada boolean, ultimo_acceso timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.prubind_es_admin() then raise exception 'Solo administradores.' using errcode = '42501'; end if;
  return query
  select u.email, (au.id is not null), (au.email_confirmed_at is not null), au.last_sign_in_at
  from public.usuarios_prubind u left join auth.users au on lower(au.email) = lower(u.email);
end $$;

create or replace function public.prubind_correo_tiene_cuenta(p_email text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.prubind_es_admin() then raise exception 'Solo administradores.' using errcode = '42501'; end if;
  if p_email !~* '^[a-z0-9._%+-]+@petstable\.mx$' then raise exception 'Correo inválido.' using errcode = 'P0001'; end if;
  return exists (select 1 from auth.users where lower(email) = lower(btrim(p_email)));
end $$;

-- Busca cuentas existentes de Auth (@petstable.mx) y sugiere foto del bucket "avatares" (solo lectura)
create or replace function public.prubind_buscar_cuentas(p_q text)
returns table (email text, nombre text, ultimo_acceso timestamptz, ya_registrado boolean, foto_sugerida text)
language plpgsql stable security definer set search_path = '' as $$
declare v_q text := lower(btrim(coalesce(p_q, '')));
begin
  if not public.prubind_es_admin() then raise exception 'Solo administradores.' using errcode = '42501'; end if;
  if char_length(v_q) < 2 then return; end if;
  return query
  with cuentas as (
    select lower(au.email)::text as email,
           coalesce(nullif(btrim(au.raw_user_meta_data ->> 'full_name'), ''), nullif(btrim(au.raw_user_meta_data ->> 'nombre'), ''),
                    nullif(btrim(au.raw_user_meta_data ->> 'name'), ''),
                    initcap(replace(split_part(split_part(au.email, '@', 1), '.', 1), '_', ' ')) || ' ' ||
                    initcap(replace(split_part(split_part(au.email, '@', 1), '.', 2), '_', ' '))) as nombre,
           au.last_sign_in_at
    from auth.users au
    where au.email ilike '%@petstable.mx'
      and (au.email ilike '%' || v_q || '%' or coalesce(au.raw_user_meta_data ->> 'full_name', '') ilike '%' || v_q || '%')
    order by au.email
    limit 12
  )
  select c.email, btrim(c.nombre), c.last_sign_in_at,
         exists (select 1 from public.usuarios_prubind u where lower(u.email) = c.email),
         (select 'https://domumnsezocubigfqwry.supabase.co/storage/v1/object/public/avatares/' || o.name
            from storage.objects o
           where o.bucket_id = 'avatares'
             and translate(lower(split_part(split_part(o.name, '.', 1), ' ', 1)), 'áéíóúñ', 'aeioun')
                 = translate(lower(split_part(split_part(c.email, '@', 1), '.', 1)), 'áéíóúñ', 'aeioun')
           order by char_length(o.name), o.name limit 1)
  from cuentas c;
end $$;

-- ---------- Row Level Security -----------------------------------------
-- Lectura: todos los miembros activos (la información es de trabajo colaborativo).
-- Escritura: políticas por rol + validaciones detalladas en los triggers.
do $$
declare t text;
begin
  foreach t in array array['areas_prubind','usuarios_prubind','tipos_prueba_prubind','tipo_responsables_prubind','pruebas_prubind',
                           'batches_prubind','insumos_prubind','resultados_prubind','envasadora_prubind','seguimiento_prubind','adjuntos_prubind'] loop
    execute format('drop policy if exists %I on public.%I', t || '_sel', t);
    execute format('create policy %I on public.%I for select to authenticated using ((select public.prubind_es_miembro()))', t || '_sel', t);
  end loop;
end $$;

-- Catálogos administrados
drop policy if exists areas_prubind_ins on public.areas_prubind;
create policy areas_prubind_ins on public.areas_prubind for insert to authenticated with check ((select public.prubind_es_admin()));
drop policy if exists areas_prubind_upd on public.areas_prubind;
create policy areas_prubind_upd on public.areas_prubind for update to authenticated using ((select public.prubind_es_admin())) with check ((select public.prubind_es_admin()));
drop policy if exists areas_prubind_del on public.areas_prubind;
create policy areas_prubind_del on public.areas_prubind for delete to authenticated using ((select public.prubind_es_admin()));

drop policy if exists usuarios_prubind_ins on public.usuarios_prubind;
create policy usuarios_prubind_ins on public.usuarios_prubind for insert to authenticated with check ((select public.prubind_es_admin()));
drop policy if exists usuarios_prubind_upd on public.usuarios_prubind;
create policy usuarios_prubind_upd on public.usuarios_prubind for update to authenticated using ((select public.prubind_es_admin())) with check ((select public.prubind_es_admin()));

drop policy if exists tipos_prueba_prubind_upd on public.tipos_prueba_prubind;
create policy tipos_prueba_prubind_upd on public.tipos_prueba_prubind for update to authenticated using ((select public.prubind_es_admin())) with check ((select public.prubind_es_admin()));

drop policy if exists tipo_responsables_prubind_ins on public.tipo_responsables_prubind;
create policy tipo_responsables_prubind_ins on public.tipo_responsables_prubind for insert to authenticated with check ((select public.prubind_es_admin()));
drop policy if exists tipo_responsables_prubind_del on public.tipo_responsables_prubind;
create policy tipo_responsables_prubind_del on public.tipo_responsables_prubind for delete to authenticated using ((select public.prubind_es_admin()));

-- Pruebas
drop policy if exists pruebas_prubind_ins on public.pruebas_prubind;
create policy pruebas_prubind_ins on public.pruebas_prubind for insert to authenticated
  with check ((select public.prubind_puede_crear_tipo(tipo)));
drop policy if exists pruebas_prubind_upd on public.pruebas_prubind;
create policy pruebas_prubind_upd on public.pruebas_prubind for update to authenticated
  using ((select public.prubind_es_admin()) or creado_por = (select public.prubind_usuario_actual_id()))
  with check ((select public.prubind_es_admin()) or creado_por = (select public.prubind_usuario_actual_id()));
drop policy if exists pruebas_prubind_del on public.pruebas_prubind;
create policy pruebas_prubind_del on public.pruebas_prubind for delete to authenticated
  using (estado = 'borrador' and ((select public.prubind_es_admin()) or creado_por = (select public.prubind_usuario_actual_id())));

-- Detalle: los miembros pasan la política; el trigger aplica el permiso fino por función
drop policy if exists batches_prubind_upd on public.batches_prubind;
create policy batches_prubind_upd on public.batches_prubind for update to authenticated
  using ((select public.prubind_es_miembro())) with check ((select public.prubind_es_miembro()));

drop policy if exists insumos_prubind_ins on public.insumos_prubind;
create policy insumos_prubind_ins on public.insumos_prubind for insert to authenticated with check ((select public.prubind_es_miembro()));
drop policy if exists insumos_prubind_upd on public.insumos_prubind;
create policy insumos_prubind_upd on public.insumos_prubind for update to authenticated
  using ((select public.prubind_es_miembro())) with check ((select public.prubind_es_miembro()));
drop policy if exists insumos_prubind_del on public.insumos_prubind;
create policy insumos_prubind_del on public.insumos_prubind for delete to authenticated using ((select public.prubind_es_miembro()));

drop policy if exists resultados_prubind_ins on public.resultados_prubind;
create policy resultados_prubind_ins on public.resultados_prubind for insert to authenticated with check ((select public.prubind_tiene_funcion('calidad')));
drop policy if exists resultados_prubind_upd on public.resultados_prubind;
create policy resultados_prubind_upd on public.resultados_prubind for update to authenticated
  using ((select public.prubind_tiene_funcion('calidad'))) with check ((select public.prubind_tiene_funcion('calidad')));
drop policy if exists resultados_prubind_del on public.resultados_prubind;
create policy resultados_prubind_del on public.resultados_prubind for delete to authenticated using ((select public.prubind_tiene_funcion('calidad')));

drop policy if exists envasadora_prubind_ins on public.envasadora_prubind;
create policy envasadora_prubind_ins on public.envasadora_prubind for insert to authenticated with check ((select public.prubind_es_miembro()));
drop policy if exists envasadora_prubind_upd on public.envasadora_prubind;
create policy envasadora_prubind_upd on public.envasadora_prubind for update to authenticated
  using ((select public.prubind_es_miembro())) with check ((select public.prubind_es_miembro()));
drop policy if exists envasadora_prubind_del on public.envasadora_prubind;
create policy envasadora_prubind_del on public.envasadora_prubind for delete to authenticated using ((select public.prubind_es_miembro()));

drop policy if exists seguimiento_prubind_ins on public.seguimiento_prubind;
create policy seguimiento_prubind_ins on public.seguimiento_prubind for insert to authenticated with check ((select public.prubind_es_miembro()));

drop policy if exists adjuntos_prubind_ins on public.adjuntos_prubind;
create policy adjuntos_prubind_ins on public.adjuntos_prubind for insert to authenticated with check ((select public.prubind_es_miembro()));
drop policy if exists adjuntos_prubind_del on public.adjuntos_prubind;
create policy adjuntos_prubind_del on public.adjuntos_prubind for delete to authenticated
  using ((select public.prubind_es_admin()) or subido_por = (select public.prubind_usuario_actual_id()));

drop policy if exists bitacora_prubind_sel on public.bitacora_prubind;
create policy bitacora_prubind_sel on public.bitacora_prubind for select to authenticated using ((select public.prubind_es_admin()));

-- ---------- Privilegios ------------------------------------------------
revoke all on public.areas_prubind, public.usuarios_prubind, public.tipos_prueba_prubind, public.tipo_responsables_prubind,
              public.pruebas_prubind, public.batches_prubind, public.insumos_prubind, public.resultados_prubind,
              public.envasadora_prubind, public.seguimiento_prubind, public.adjuntos_prubind, public.bitacora_prubind,
              public.v_pruebas_prubind, public.v_batches_prubind, public.v_insumos_prubind, public.v_seguimiento_prubind
  from anon, public, authenticated;
grant select, insert, update, delete on public.areas_prubind, public.pruebas_prubind, public.insumos_prubind,
                                         public.resultados_prubind, public.envasadora_prubind to authenticated;
grant select, insert, update on public.usuarios_prubind to authenticated;
grant select, update on public.tipos_prueba_prubind, public.batches_prubind to authenticated;
grant select, insert, delete on public.tipo_responsables_prubind, public.adjuntos_prubind to authenticated;
grant select, insert on public.seguimiento_prubind to authenticated;
grant select on public.bitacora_prubind, public.v_pruebas_prubind, public.v_batches_prubind,
                public.v_insumos_prubind, public.v_seguimiento_prubind to authenticated;

do $$
declare f text;
begin
  foreach f in array array[
    'prubind_usuario_actual_id()', 'prubind_es_miembro()', 'prubind_es_admin()', 'prubind_tiene_funcion(text)',
    'prubind_puede_crear_tipo(text)', 'prubind_hoy()', 'prubind_mi_perfil()',
    'prubind_cambiar_estado(uuid,text,text)', 'prubind_dictamen_calidad(uuid,text,text)', 'prubind_dictamen_final(uuid,text,text)',
    'prubind_dashboard(date,date)', 'prubind_estado_cuentas()', 'prubind_correo_tiene_cuenta(text)', 'prubind_buscar_cuentas(text)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
  -- Internas y de trigger: no invocables vía API
  foreach f in array array['prubind_touch_updated_at()', 'prubind_auditar()', 'prubind_log(uuid,text,text)',
                           'prubind_validar_seguimiento()', 'prubind_validar_usuario()', 'prubind_sincronizar_batches(uuid,integer,date)',
                           'prubind_validar_prueba()', 'prubind_despues_prueba()', 'prubind_validar_batch()', 'prubind_despues_batch()',
                           'prubind_validar_insumo()', 'prubind_despues_insumo()', 'prubind_validar_resultado()',
                           'prubind_validar_envasadora()', 'prubind_validar_adjunto()'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

-- ---------- Storage ----------------------------------------------------
-- Fotos de usuario: lectura pública (se muestran con <img>), escritura solo administradores
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatares_prubind', 'avatares_prubind', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;
-- Adjuntos de pruebas: privado (URL firmada), 10 MB
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('adjuntos_prubind', 'adjuntos_prubind', false, 10485760, array[
  'application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'text/csv', 'text/plain',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/msword'])
on conflict (id) do nothing;

drop policy if exists avatares_prubind_select on storage.objects;
create policy avatares_prubind_select on storage.objects for select to authenticated
  using (bucket_id = 'avatares_prubind' and (select public.prubind_es_admin()));
drop policy if exists avatares_prubind_insert on storage.objects;
create policy avatares_prubind_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'avatares_prubind' and (select public.prubind_es_admin()));
drop policy if exists avatares_prubind_delete on storage.objects;
create policy avatares_prubind_delete on storage.objects for delete to authenticated
  using (bucket_id = 'avatares_prubind' and (select public.prubind_es_admin()));

drop policy if exists adjuntos_prubind_select on storage.objects;
create policy adjuntos_prubind_select on storage.objects for select to authenticated
  using (bucket_id = 'adjuntos_prubind' and (select public.prubind_es_miembro()));
drop policy if exists adjuntos_prubind_insert on storage.objects;
create policy adjuntos_prubind_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'adjuntos_prubind' and (select public.prubind_es_miembro())
              and exists (select 1 from public.pruebas_prubind p where p.id::text = (storage.foldername(name))[1]));
drop policy if exists adjuntos_prubind_delete on storage.objects;
create policy adjuntos_prubind_delete on storage.objects for delete to authenticated
  using (bucket_id = 'adjuntos_prubind' and ((select public.prubind_es_admin()) or owner_id = (select auth.uid())::text));
