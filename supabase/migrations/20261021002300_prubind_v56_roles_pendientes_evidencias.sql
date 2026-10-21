-- =====================================================================
-- Pruebas industriales v5.6
--  · Permisos por puesto: el Ingeniero de Seguridad registra Seguridad (no
--    Calidad); nuevo puesto Técnico de Mantenimiento que registra
--    Mantenimiento. Solo los responsables de área crean parámetros nuevos.
--  · Valores "Pendiente": un resultado sin valor con estado 'pendiente'.
--    El responsable lo completa al evaluar y quien dictamina puede
--    completarlo y evaluarlo con la prueba pendiente de dictamen.
--  · Ya no hay atajo de captura para el responsable de ejecución.
--  · Fecha de ejecución de un día o de un rango (fecha_fin) y terminado
--    automático al concluir la fecha (pg_cron, 00:05 hora de México).
--  · Evidencia ligada al parámetro (adjuntos_prubind.plan_id).
--  · Pendientes: los responsables ven "Evaluar" desde que la prueba está en
--    proceso y quien la registró ve "Terminar la prueba" al llegar la fecha.
--  · Depuración del catálogo de parámetros (se desactivan, no se borran).
-- No destructiva: solo agrega columnas, funciones y datos propios (_prubind).
-- =====================================================================

-- ---------- 1. Permisos por puesto ----------
update public.autoridades_prubind a set activo = false
 where a.activo and a.accion in ('capturar_calidad', 'evaluar_calidad')
   and a.puesto_id = (select id from public.puestos_prubind where nombre = 'Ingeniero de Seguridad Industrial');

insert into public.autoridades_prubind (accion, puesto_id, activo)
select 'capturar_seguridad', p.id, true from public.puestos_prubind p
 where p.nombre = 'Ingeniero de Seguridad Industrial'
   and not exists (select 1 from public.autoridades_prubind a where a.puesto_id = p.id and a.accion = 'capturar_seguridad' and a.activo);

insert into public.puestos_prubind (nombre, activo)
select 'Técnico de Mantenimiento', true
 where not exists (select 1 from public.puestos_prubind where nombre = 'Técnico de Mantenimiento');

insert into public.autoridades_prubind (accion, puesto_id, activo)
select 'capturar_mantenimiento', p.id, true from public.puestos_prubind p
 where p.nombre = 'Técnico de Mantenimiento'
   and not exists (select 1 from public.autoridades_prubind a where a.puesto_id = p.id and a.accion = 'capturar_mantenimiento' and a.activo);

-- ---------- 2. Fecha de ejecución: un día o un rango ----------
alter table public.pruebas_prubind add column if not exists fecha_fin date;

create or replace function public.prubind_validar_fechas()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.fecha_planeada is null then new.fecha_fin := null; end if;
  if new.fecha_fin is not null and new.fecha_fin = new.fecha_planeada then new.fecha_fin := null; end if;
  if new.fecha_fin is not null and new.fecha_fin < new.fecha_planeada then
    raise exception 'La fecha final no puede ser anterior a la fecha de inicio.' using errcode = 'P0001';
  end if;
  return new;
end $$;

drop trigger if exists prubind_fechas_prueba on public.pruebas_prubind;
create trigger prubind_fechas_prueba before insert or update of fecha_planeada, fecha_fin on public.pruebas_prubind
  for each row execute function public.prubind_validar_fechas();

-- Quien registró la prueba puede cambiar la fecha final mientras está en proceso
create or replace function public.prubind_cambiar_fecha_fin(p_prueba uuid, p_fecha_fin date)
returns void language plpgsql security definer set search_path = '' as $$
declare v public.pruebas_prubind%rowtype;
begin
  select * into v from public.pruebas_prubind where id = p_prueba for update;
  if not found then raise exception 'La prueba no existe.' using errcode = 'P0001'; end if;
  if not public.prubind_puede(p_prueba, 'preparar') then
    raise exception 'Solo quien registró la prueba cambia la fecha de ejecución.' using errcode = '42501';
  end if;
  if v.estado not in ('registrada', 'en_preparacion', 'preparada', 'en_ejecucion') then
    raise exception 'La fecha de ejecución solo cambia mientras la prueba no termina.' using errcode = 'P0001';
  end if;
  if v.fecha_planeada is null then raise exception 'La prueba no tiene fecha de inicio.' using errcode = 'P0001'; end if;
  if p_fecha_fin is not null and p_fecha_fin < public.prubind_hoy() and v.estado = 'en_ejecucion' then
    raise exception 'La fecha final no puede ser anterior a hoy.' using errcode = 'P0001';
  end if;
  perform set_config('prubind.rpc', '1', true);
  update public.pruebas_prubind set fecha_fin = p_fecha_fin where id = p_prueba;
  perform set_config('prubind.rpc', '', true);
  perform public.prubind_log(p_prueba, 'sistema', 'Fecha de ejecución: ' || to_char(v.fecha_planeada, 'DD/MM/YYYY')
    || coalesce(' al ' || to_char(nullif(p_fecha_fin, v.fecha_planeada), 'DD/MM/YYYY'), '') || '.');
end $$;
revoke all on function public.prubind_cambiar_fecha_fin(uuid, date) from public, anon;
grant execute on function public.prubind_cambiar_fecha_fin(uuid, date) to authenticated;

-- La vista agrega fecha_fin al final (mismas columnas y opciones que antes)
create or replace view public.v_pruebas_prubind with (security_invoker = true) as
 SELECT p.id, p.folio, p.anio, p.consecutivo, p.tipo, p.objetivo_id, p.objetivo_desc, p.cambio, p.area_id, p.prioridad, p.prioridad_just,
    p.producto_id, p.receta_version_id, p.materia_prima_id, p.proveedor_id, p.equipo_id, p.proceso, p.empaque, p.registrado_por,
    p.responsable_inicial_id, p.fecha_planeada, p.batches_planeados, p.peso_objetivo_kg, p.responsable_ejecucion_id, p.plan_muestreo,
    p.plan_confirmado_at, p.plan_confirmado_por, p.estado, p.ejecucion_actual, p.motivo_cancelacion, p.cancelado_por, p.cancelado_at,
    p.disposicion_cierre, p.cerrada_por, p.cerrada_at, p.created_at, p.updated_at, p.cantidad_evaluar, p.cantidad_unidad_id, p.areas_involucradas,
    t.nombre AS tipo_nombre, t.campos_registro, t.secciones_prep, t.ejecucion_form, t.requiere_aut_ejecucion,
    o.nombre AS objetivo_nombre, ar.nombre AS area_nombre, pr.nombre AS producto_nombre, rc.nombre AS receta_nombre, rv.version AS receta_version,
    mp.nombre AS materia_prima_nombre, pv.nombre AS proveedor_nombre, eq.nombre AS equipo_nombre,
    ur.nombre AS registrado_por_nombre, ur.foto_url AS registrado_por_foto, ui.nombre AS responsable_inicial_nombre,
    ue.nombre AS responsable_ejecucion_nombre, uc.nombre AS cerrada_por_nombre, ux.nombre AS cancelado_por_nombre,
    ( SELECT jsonb_build_object('dictamen', d.dictamen, 'fecha', d.created_at, 'por', du.nombre, 'descripcion', d.descripcion, 'motivo', mo.nombre) AS jsonb_build_object
           FROM public.dictamenes_prubind d
             JOIN public.usuarios_prubind du ON du.id = d.emitido_por
             LEFT JOIN public.motivos_prubind mo ON mo.id = d.motivo_id
          WHERE d.prueba_id = p.id
          ORDER BY d.created_at DESC
         LIMIT 1) AS ultimo_dictamen,
    cu.simbolo AS cantidad_unidad,
    p.fecha_fin
   FROM public.pruebas_prubind p
     JOIN public.tipos_prueba_prubind t ON t.codigo = p.tipo
     JOIN public.usuarios_prubind ur ON ur.id = p.registrado_por
     LEFT JOIN public.objetivos_prubind o ON o.id = p.objetivo_id
     LEFT JOIN public.areas_prubind ar ON ar.id = p.area_id
     LEFT JOIN public.productos_prubind pr ON pr.id = p.producto_id
     LEFT JOIN public.receta_versiones_prubind rv ON rv.id = p.receta_version_id
     LEFT JOIN public.recetas_prubind rc ON rc.id = rv.receta_id
     LEFT JOIN public.materias_primas_prubind mp ON mp.id = p.materia_prima_id
     LEFT JOIN public.proveedores_prubind pv ON pv.id = p.proveedor_id
     LEFT JOIN public.equipos_prubind eq ON eq.id = p.equipo_id
     LEFT JOIN public.usuarios_prubind ui ON ui.id = p.responsable_inicial_id
     LEFT JOIN public.usuarios_prubind ue ON ue.id = p.responsable_ejecucion_id
     LEFT JOIN public.usuarios_prubind uc ON uc.id = p.cerrada_por
     LEFT JOIN public.usuarios_prubind ux ON ux.id = p.cancelado_por
     LEFT JOIN public.unidades_prubind cu ON cu.id = p.cantidad_unidad_id;

-- ---------- 3. Terminado automático al concluir la fecha de ejecución ----------
create or replace function public.prubind_autoterminar()
returns integer language plpgsql security definer set search_path = '' as $$
declare r record; e jsonb; n integer := 0;
begin
  for r in select id, ejecucion_actual from public.pruebas_prubind
            where estado = 'en_ejecucion' and coalesce(fecha_fin, fecha_planeada) < public.prubind_hoy() loop
    perform public.prubind_set_estado(r.id, 'en_evaluacion', 'La prueba se terminó automáticamente al concluir su fecha de ejecución (ejecución #'
      || r.ejecucion_actual || '); continúa la evaluación por área.');
    e := public.prubind_eval_estado(r.id);
    if (e ->> 'eval_faltantes')::int = 0 and (e ->> 'recom_faltantes')::int = 0 and jsonb_array_length(e -> 'participantes') > 0 then
      perform public.prubind_set_estado(r.id, 'pendiente_dictamen', 'Las áreas que participaron ya registraron su evaluación; pendiente del dictamen de Alta Dirección.');
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.prubind_autoterminar() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'prubind_autoterminar') then
    perform cron.unschedule('prubind_autoterminar');
  end if;
  perform cron.schedule('prubind_autoterminar', '5 6 * * *', 'select public.prubind_autoterminar()');
end $$;

-- ---------- 4. Evidencia ligada al parámetro ----------
alter table public.adjuntos_prubind add column if not exists plan_id uuid
  references public.plan_evaluacion_prubind(id) on delete set null;
create index if not exists adjuntos_prubind_plan_idx on public.adjuntos_prubind (plan_id);

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
  if new.plan_id is not null and not exists (select 1 from public.plan_evaluacion_prubind pl where pl.id = new.plan_id and pl.prueba_id = new.prueba_id) then
    raise exception 'El parámetro no pertenece a la prueba.' using errcode = 'P0001';
  end if;
  new.subido_por := uid;
  new.nombre := btrim(new.nombre);
  new.descripcion := nullif(btrim(new.descripcion), '');
  return new;
end $$;

-- ---------- 5. Resultados: permisos por área, valores pendientes y dictamen ----------
create or replace function public.prubind_validar_resultado()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v     public.pruebas_prubind%rowtype;
  pl    public.plan_evaluacion_prubind%rowtype;
  m     public.metodos_prubind%rowtype;
  uid   uuid := public.prubind_usuario_actual_id();
  v_pid uuid;
  v_rpc boolean := coalesce(current_setting('prubind.rpc', true), '') = '1';
  v_dic boolean;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return coalesce(new, old); end if;
  if v_rpc then return coalesce(new, old); end if;
  v_pid := case when tg_op = 'DELETE' then old.prueba_id else new.prueba_id end;
  select * into v from public.pruebas_prubind where id = v_pid;
  if v.id is null then return coalesce(new, old); end if;
  -- Quien dictamina puede completar valores pendientes antes de emitir el dictamen
  v_dic := v.estado = 'pendiente_dictamen' and public.prubind_puede(v_pid, 'dictaminar');

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

  select * into pl from public.plan_evaluacion_prubind where id = case when tg_op = 'DELETE' then old.plan_id else new.plan_id end and prueba_id = v_pid;
  if not found or not pl.incluido then
    raise exception 'El parámetro no está en la lista de parámetros a evaluar de esta prueba.' using errcode = 'P0001';
  end if;
  select * into m from public.metodos_prubind where id = pl.metodo_id;
  if not (public.prubind_puede_area(v_pid, 'capturar', m.area) or public.prubind_puede_area(v_pid, 'evaluar', m.area) or v_dic) then
    raise exception 'No tiene autoridad para registrar parámetros de %.', initcap(m.area) using errcode = '42501';
  end if;
  if not (public.prubind_ejecucion_abierta(v_pid) or v.estado in ('en_evaluacion', 'pendiente_resultados') or v_dic) then
    raise exception 'Los resultados se registran durante el proceso o mientras se completan resultados.' using errcode = 'P0001';
  end if;

  if tg_op = 'DELETE' or (new.valor_num, new.valor_opcion, new.dilucion) is distinct from (old.valor_num, old.valor_opcion, old.dilucion) then
    perform set_config('prubind.rpc', '1', true);
    delete from public.evaluaciones_prubind e where e.plan_id = pl.id and e.ejecucion = v.ejecucion_actual;
    perform set_config('prubind.rpc', '', true);
  end if;
  if tg_op = 'DELETE' then return old; end if;

  if not exists (select 1 from public.muestras_prubind s where s.id = new.muestra_id and s.prueba_id = v_pid and s.ejecucion = v.ejecucion_actual) then
    raise exception 'La muestra no pertenece a la ejecución actual de esta prueba.' using errcode = 'P0001';
  end if;
  if tg_op = 'UPDATE' and (new.plan_id, new.muestra_id) is distinct from (old.plan_id, old.muestra_id) then
    raise exception 'No se puede mover el resultado a otro parámetro o muestra.' using errcode = 'P0001';
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
    if new.valor_num is not null and (pl.crit_minimo is not null or pl.crit_maximo is not null) then
      new.estado := case when (pl.crit_minimo is null or new.valor_num >= pl.crit_minimo)
                          and (pl.crit_maximo is null or new.valor_num <= pl.crit_maximo) then 'conforme' else 'no_conforme' end;
    elsif new.estado = 'no_conforme' then new.estado := 'pendiente';
    end if;
  elsif m.tipo_resultado = 'presencia' then
    new.valor_num := null; new.unidad_id := null;
    if new.valor_opcion is not null and new.valor_opcion not in ('ausencia', 'presencia') then
      raise exception 'El resultado debe ser "ausencia" o "presencia".' using errcode = 'P0001';
    end if;
    if new.valor_opcion is not null and pl.crit_texto ilike '%ausencia%' then
      new.estado := case when new.valor_opcion = 'ausencia' then 'conforme' else 'no_conforme' end;
    end if;
  else
    new.valor_num := null;
    if new.valor_opcion is not null and cardinality(m.opciones) > 0 and not (new.valor_opcion = any (m.opciones)) then
      raise exception 'Opción no válida para %.', m.nombre using errcode = 'P0001';
    end if;
    if new.valor_opcion in ('conforme', 'no_conforme', 'no_aplica', 'pendiente') then new.estado := new.valor_opcion;
    elsif new.valor_opcion = 'no_evaluado' then new.estado := 'no_aplica'; end if;
  end if;
  -- Sin valor = marcado como "Pendiente" (se completa después)
  if new.valor_num is null and new.valor_opcion is null then new.estado := 'pendiente'; new.fecha_lectura := null; end if;
  if new.estado = 'no_conforme' and new.justificacion is null then
    raise exception '% no cumple: escriba una explicación breve.', m.nombre using errcode = 'P0001';
  end if;
  if new.estado <> 'pendiente' and new.fecha_lectura is null then new.fecha_lectura := now(); end if;
  if tg_op = 'INSERT' then
    new.capturado_por := uid; new.revisado_por := null; new.revisado_at := null; new.resolucion := null;
  else
    new.capturado_por := old.capturado_por; new.modificado_por := uid;
    new.revisado_por := old.revisado_por; new.revisado_at := old.revisado_at;
  end if;
  perform public.prubind_iniciar_captura(v_pid);
  return new;
end $$;

-- ---------- 6. Evaluaciones: también quien dictamina, con la prueba pendiente de dictamen ----------
create or replace function public.prubind_validar_evaluacion()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v     public.pruebas_prubind%rowtype;
  uid   uuid := public.prubind_usuario_actual_id();
  v_pid uuid;
  v_area text;
  v_con boolean;
  v_dic boolean;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return coalesce(new, old); end if;
  if coalesce(current_setting('prubind.rpc', true), '') = '1' then return coalesce(new, old); end if;
  v_pid := case when tg_op = 'DELETE' then old.prueba_id else new.prueba_id end;
  select * into v from public.pruebas_prubind where id = v_pid;
  if v.id is null then return coalesce(new, old); end if;
  v_dic := v.estado = 'pendiente_dictamen' and public.prubind_puede(v_pid, 'dictaminar');
  if v.estado not in ('en_ejecucion', 'en_evaluacion', 'pendiente_resultados') and not v_dic then
    raise exception 'Los resultados se evalúan con la prueba en proceso o en evaluación, antes del dictamen.' using errcode = 'P0001';
  end if;
  if tg_op = 'DELETE' then
    if not (public.prubind_puede_area(v_pid, 'evaluar', old.area) or v_dic) then
      raise exception 'No tiene autoridad para %.', public.prubind_accion_txt('evaluar_' || old.area) using errcode = '42501';
    end if;
    return old;
  end if;
  if tg_op = 'UPDATE' and (new.prueba_id, new.plan_id, new.prueba_parametro_id, new.ejecucion)
                          is distinct from (old.prueba_id, old.plan_id, old.prueba_parametro_id, old.ejecucion) then
    raise exception 'No se puede mover la evaluación a otro parámetro.' using errcode = 'P0001';
  end if;

  if new.plan_id is not null then
    select m.area into v_area from public.plan_evaluacion_prubind pl join public.metodos_prubind m on m.id = pl.metodo_id
     where pl.id = new.plan_id and pl.prueba_id = v_pid and pl.incluido;
    if v_area is null then raise exception 'El parámetro no pertenece a esta prueba.' using errcode = 'P0001'; end if;
    v_con := exists (select 1 from public.resultados_prubind r where r.plan_id = new.plan_id and r.ejecucion = v.ejecucion_actual
                     and (r.valor_num is not null or r.valor_opcion is not null));
  else
    if not exists (select 1 from public.prueba_parametros_prubind x where x.id = new.prueba_parametro_id and x.prueba_id = v_pid) then
      raise exception 'El parámetro no pertenece a esta prueba.' using errcode = 'P0001';
    end if;
    v_area := 'produccion';
    v_con := exists (select 1 from public.ejecucion_controles_prubind c where c.prueba_parametro_id = new.prueba_parametro_id
                     and c.ejecucion = v.ejecucion_actual and c.valor is not null);
  end if;
  if not v_con and new.evaluacion <> 'no_determinado' then
    raise exception 'El parámetro aún no tiene resultado registrado: solo puede marcarse "No se pudo determinar".' using errcode = 'P0001';
  end if;
  if not (public.prubind_puede_area(v_pid, 'evaluar', v_area) or v_dic) then
    raise exception 'No tiene autoridad para %.', public.prubind_accion_txt('evaluar_' || v_area) using errcode = '42501';
  end if;
  new.area := v_area;
  new.ejecucion := v.ejecucion_actual;
  new.observaciones := nullif(btrim(new.observaciones), '');
  if new.evaluacion = 'no_cumple' and (new.observaciones is null or lower(new.observaciones) = 'sin observaciones') then
    raise exception 'Explique por qué el parámetro no cumple.' using errcode = 'P0001';
  end if;
  if new.evaluacion = 'no_determinado' and (new.observaciones is null or lower(new.observaciones) = 'sin observaciones') then
    raise exception 'Explique por qué no se pudo determinar.' using errcode = 'P0001';
  end if;
  new.observaciones := coalesce(new.observaciones, 'Sin observaciones');
  new.evaluado_por := uid;
  return new;
end $$;

-- ---------- 7. Parámetros nuevos: solo el responsable del área ----------
create or replace function public.prubind_nuevo_parametro(p_nombre text, p_area text, p_tipo_resultado text, p_unidad uuid default null, p_tipo_prueba text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_nom text := btrim(coalesce(p_nombre, ''));
  v_id  uuid;
  v_cod text;
  v_n   integer := 0;
  v_fab boolean;
begin
  if not public.prubind_es_miembro() then raise exception 'Usuario no autorizado.' using errcode = '42501'; end if;
  if p_area not in ('calidad', 'produccion', 'seguridad', 'mantenimiento') then raise exception 'Área no válida.' using errcode = 'P0001'; end if;
  if not public.prubind_tiene_autoridad_alguna('evaluar_' || p_area) then
    raise exception 'Los parámetros de % los agrega el responsable de esa área.', initcap(p_area) using errcode = '42501';
  end if;
  if char_length(v_nom) not between 2 and 150 then raise exception 'Escriba el nombre del parámetro (2 a 150 caracteres).' using errcode = 'P0001'; end if;
  if p_tipo_resultado not in ('numerico', 'opcion') then raise exception 'Indique si el parámetro es cuantitativo o cualitativo.' using errcode = 'P0001'; end if;
  if p_unidad is not null and not exists (select 1 from public.unidades_prubind u where u.id = p_unidad and u.activo) then
    raise exception 'Unidad no válida.' using errcode = 'P0001';
  end if;
  select id into v_id from public.metodos_prubind where lower(btrim(nombre)) = lower(v_nom) and area = p_area order by activo desc limit 1;
  if v_id is not null then
    update public.metodos_prubind set activo = true where id = v_id and not activo;
  else
    loop
      v_n := v_n + 1;
      v_cod := case p_area when 'calidad' then 'CAL' when 'produccion' then 'PROD' when 'seguridad' then 'SEG' else 'MANT' end
               || '-U' || lpad(((select count(*) from public.metodos_prubind where area = p_area) + v_n)::text, 2, '0');
      exit when not exists (select 1 from public.metodos_prubind where codigo = v_cod);
    end loop;
    insert into public.metodos_prubind (codigo, nombre, categoria, area, tipo_resultado, unidad_id, opciones)
    values (v_cod, v_nom, case p_area when 'calidad' then 'general' when 'produccion' then 'proceso' when 'seguridad' then 'seguridad' else 'equipo' end,
            p_area, p_tipo_resultado, case when p_tipo_resultado = 'numerico' then p_unidad end,
            case when p_tipo_resultado = 'opcion' then '{conforme,no_conforme,no_aplica}'::text[] else '{}'::text[] end)
    returning id into v_id;
  end if;
  if p_tipo_prueba is not null then
    select ejecucion_form = 'fabricacion' into v_fab from public.tipos_prueba_prubind where codigo = p_tipo_prueba;
    insert into public.plantilla_evaluacion_prubind (tipo, metodo_id, obligatorio, nivel, orden)
    values (p_tipo_prueba, v_id, true, case when coalesce(v_fab, false) and p_area in ('calidad', 'produccion') then 'batch' else 'corrida' end, 900)
    on conflict (tipo, metodo_id) do update set activo = true;
  end if;
  return v_id;
end $$;

-- ---------- 8. Pendientes: evaluar durante el proceso y terminar la prueba ----------
create or replace function public.prubind_mis_pendientes_todos()
returns table(prueba_id uuid, folio text, cambio text, tipo_nombre text, estado text, accion text, area text, prioridad text, fecha_planeada date, tipo text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare uid uuid := public.prubind_usuario_actual_id();
begin
  if uid is null then raise exception 'Usuario no autorizado.' using errcode = '42501'; end if;
  return query
  with p as (
    select x.*, t.nombre as tnom, public.prubind_areas_prueba(x.id) as areas, public.prubind_areas_participantes(x.id) as part,
           coalesce((select array_agg(s.area) from public.areas_sin_parametros_prubind s where s.prueba_id = x.id), '{}') as sinp
    from public.pruebas_prubind x join public.tipos_prueba_prubind t on t.codigo = x.tipo
    where x.estado not in ('cerrada_rechazada', 'cancelada')
  ), pa as (
    select p.*, ar.a from p cross join unnest(array['calidad','produccion','seguridad','mantenimiento']) ar(a)
  )
  select p.id, p.folio, p.cambio, p.tnom, p.estado, 'iniciar'::text, null::text, p.prioridad, p.fecha_planeada, p.tipo
    from p where p.estado in ('registrada', 'en_preparacion', 'preparada') and public.prubind_puede(p.id, 'preparar')
  union all
  select pa.id, pa.folio, pa.cambio, pa.tnom, pa.estado, 'definir', pa.a, pa.prioridad, pa.fecha_planeada, pa.tipo
    from pa where pa.estado in ('registrada', 'en_preparacion', 'preparada')
     and public.prubind_tiene_autoridad(pa.tipo, 'evaluar_' || pa.a) and not (pa.a = any (pa.areas)) and not (pa.a = any (pa.sinp))
  union all
  select pa.id, pa.folio, pa.cambio, pa.tnom, pa.estado, 'capturar', pa.a, pa.prioridad, pa.fecha_planeada, pa.tipo
    from pa where pa.estado = 'en_ejecucion' and pa.a = any (pa.areas) and public.prubind_tiene_autoridad(pa.tipo, 'capturar_' || pa.a)
  union all
  select p.id, p.folio, p.cambio, p.tnom, p.estado, 'terminar', null, p.prioridad, p.fecha_planeada, p.tipo
    from p where p.estado = 'en_ejecucion' and public.prubind_puede(p.id, 'preparar')
     and coalesce(p.fecha_fin, p.fecha_planeada, public.prubind_hoy()) <= public.prubind_hoy()
  union all
  select pa.id, pa.folio, pa.cambio, pa.tnom, pa.estado, 'evaluar', pa.a, pa.prioridad, pa.fecha_planeada, pa.tipo
    from pa where pa.estado in ('en_ejecucion', 'en_evaluacion', 'pendiente_resultados') and public.prubind_tiene_autoridad(pa.tipo, 'evaluar_' || pa.a)
     and public.prubind_sin_evaluar(pa.id, pa.a) > 0
  union all
  select pa.id, pa.folio, pa.cambio, pa.tnom, pa.estado, 'recomendar', pa.a, pa.prioridad, pa.fecha_planeada, pa.tipo
    from pa where pa.estado in ('en_evaluacion', 'pendiente_resultados') and pa.a = any (pa.part)
     and public.prubind_tiene_autoridad(pa.tipo, 'evaluar_' || pa.a) and public.prubind_sin_evaluar(pa.id, pa.a) = 0
     and not exists (select 1 from public.recomendaciones_prubind r where r.prueba_id = pa.id and r.ejecucion = pa.ejecucion_actual and r.area = pa.a)
  union all
  select p.id, p.folio, p.cambio, p.tnom, p.estado, 'dictaminar', null, p.prioridad, p.fecha_planeada, p.tipo
    from p where p.estado = 'pendiente_dictamen' and public.prubind_puede(p.id, 'dictaminar')
  union all
  select p.id, p.folio, p.cambio, p.tnom, p.estado, 'cerrar', null, p.prioridad, p.fecha_planeada, p.tipo
    from p where p.estado in ('aprobada', 'rechazada') and public.prubind_puede(p.id, 'cerrar');
end $$;

-- ---------- 9. Depuración del catálogo de parámetros ----------
-- Se desactivan (no se borran) parámetros vagos o duplicados de otra área, sin uso en pruebas:
--   EP-PARAM  "Parámetros de operación utilizados" (Calidad; vago)
--   EP-TSELL  "Temperatura de sellado" (Calidad; duplica la temperatura de termosellado de Mantenimiento)
--   EQ-PARAM  "Parámetros de operación del equipo" (Mantenimiento; vago)
--   EQ-INST   "Condición de instalación y seguridad" (Mantenimiento; duplica Seguridad)
--   PR-PARAM  "Parámetros de proceso conforme a lo planeado" (Producción; vago)
update public.metodos_prubind set activo = false
 where codigo in ('EP-PARAM', 'EP-TSELL', 'EQ-PARAM', 'EQ-INST', 'PR-PARAM')
   and not exists (select 1 from public.plan_evaluacion_prubind pl where pl.metodo_id = metodos_prubind.id);
update public.plantilla_evaluacion_prubind set activo = false
 where metodo_id in (select id from public.metodos_prubind where codigo in ('EP-PARAM', 'EP-TSELL', 'EQ-PARAM', 'EQ-INST', 'PR-PARAM') and not activo);

-- La función de trigger no se expone por la API
revoke all on function public.prubind_validar_fechas() from public, anon, authenticated;
