-- =====================================================================
-- Pruebas industriales v5.7: la evaluación (y el veredicto de cada área)
-- solo se registra con la prueba TERMINADA. La etapa se llama Evaluación.
-- No destructiva: solo reemplaza funciones propias (_prubind).
-- =====================================================================

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
  if v.estado not in ('en_evaluacion', 'pendiente_resultados') and not v_dic then
    raise exception 'Los resultados se evalúan cuando la prueba se termina.' using errcode = 'P0001';
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

create or replace function public.prubind_validar_recomendacion()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v     public.pruebas_prubind%rowtype;
  v_pid uuid;
  v_area text;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return coalesce(new, old); end if;
  if coalesce(current_setting('prubind.rpc', true), '') = '1' then return coalesce(new, old); end if;
  v_pid := case when tg_op = 'DELETE' then old.prueba_id else new.prueba_id end;
  v_area := case when tg_op = 'DELETE' then old.area else new.area end;
  select * into v from public.pruebas_prubind where id = v_pid;
  if v.id is null then return coalesce(new, old); end if;
  if v.estado not in ('en_evaluacion', 'pendiente_resultados') then
    raise exception 'El veredicto del área se registra cuando la prueba se termina, antes del dictamen.' using errcode = 'P0001';
  end if;
  if not public.prubind_puede_area(v_pid, 'evaluar', v_area) then
    raise exception 'El veredicto de % lo registra el responsable de esa área.', initcap(v_area) using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  if tg_op = 'UPDATE' and (new.prueba_id, new.ejecucion, new.area) is distinct from (old.prueba_id, old.ejecucion, old.area) then
    raise exception 'No se puede mover la recomendación.' using errcode = 'P0001';
  end if;
  if not (new.area = any (public.prubind_areas_participantes(v_pid))) then
    raise exception 'El área aún no tiene datos registrados en esta prueba.' using errcode = 'P0001';
  end if;
  if public.prubind_sin_evaluar(v_pid, new.area) > 0 then
    raise exception 'Evalúe primero todos los parámetros registrados del área.' using errcode = 'P0001';
  end if;
  new.ejecucion := v.ejecucion_actual;
  new.recomendacion := btrim(new.recomendacion);
  new.emitido_por := public.prubind_usuario_actual_id();
  return new;
end $$;

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
    from pa where pa.estado in ('en_evaluacion', 'pendiente_resultados') and public.prubind_tiene_autoridad(pa.tipo, 'evaluar_' || pa.a)
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
