-- =====================================================================
-- Pruebas industriales · v5.0
--  1. La prueba se INICIA con un botón (quien la registró). Antes de
--     iniciar no se registran datos; las áreas definen sus parámetros y
--     pueden seguir agregándolos durante la prueba.
--  2. Cada área puede indicar que "no tiene nada que evaluar" en la prueba.
--  3. Áreas independientes: participa el área que registró datos. Cada una
--     evalúa lo suyo (Cumple / No cumple / No se pudo determinar), registra
--     su recomendación y su veredicto (satisfactoria / no satisfactoria),
--     incluso mientras la prueba sigue en proceso. El dictamen espera solo a
--     las áreas que participaron.
--  4. Los parámetros sin resultado (p. ej. bromatológicos que tarda el
--     laboratorio) no detienen la evaluación.
--  5. Notificaciones push (como Servicio Médico): suscripciones, registro de
--     avisos y claves VAPID en un esquema privado.
-- Solo objetos *_prubind. No destructiva: los datos existentes se conservan.
-- =====================================================================

-- ---------- 1. Inicio explícito de la prueba ----------
-- Solo se registra durante el proceso cuando la prueba está "En proceso"
create or replace function public.prubind_ejecucion_abierta(p_prueba uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.pruebas_prubind p where p.id = p_prueba and p.estado = 'en_ejecucion')
$$;

create or replace function public.prubind_estado_txt(p text)
returns text language sql immutable set search_path = '' as $$
  select case p when 'registrada' then 'Registrada' when 'en_preparacion' then 'Registrada' when 'preparada' then 'Registrada'
    when 'en_ejecucion' then 'En proceso' when 'en_evaluacion' then 'En evaluación' when 'pendiente_resultados' then 'Pendiente de resultados'
    when 'pendiente_dictamen' then 'Pendiente de dictamen' when 'aprobada' then 'Aprobada (por cerrar)' when 'rechazada' then 'Rechazada (por cerrar)'
    when 'requiere_repeticion' then 'Requiere repetición' when 'cerrada_aprobada' then 'Cerrada y aprobada'
    when 'cerrada_rechazada' then 'Cerrada y rechazada' when 'cancelada' then 'Cancelada' else p end
$$;

-- ---------- 2. Áreas sin parámetros que evaluar ----------
create table if not exists public.areas_sin_parametros_prubind (
  id            uuid primary key default gen_random_uuid(),
  prueba_id     uuid not null references public.pruebas_prubind(id) on delete cascade,
  area          text not null check (area in ('calidad', 'produccion', 'seguridad', 'mantenimiento')),
  motivo        text check (motivo is null or char_length(motivo) <= 300),
  declarado_por uuid references public.usuarios_prubind(id) on delete set null,
  created_at    timestamptz not null default now(),
  unique (prueba_id, area)
);
create index if not exists areas_sin_parametros_prubind_por_idx on public.areas_sin_parametros_prubind (declarado_por);
alter table public.areas_sin_parametros_prubind enable row level security;
drop policy if exists areas_sin_parametros_prubind_sel on public.areas_sin_parametros_prubind;
create policy areas_sin_parametros_prubind_sel on public.areas_sin_parametros_prubind for select to authenticated using ((select public.prubind_es_miembro()));
revoke all on public.areas_sin_parametros_prubind from anon, public;
grant select on public.areas_sin_parametros_prubind to authenticated;

-- Si el área agrega parámetros, deja de estar marcada "sin parámetros"
create or replace function public.prubind_area_con_parametros()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from public.areas_sin_parametros_prubind s
   using public.metodos_prubind m
   where m.id = new.metodo_id and s.prueba_id = new.prueba_id and s.area = m.area;
  return new;
end $$;
revoke all on function public.prubind_area_con_parametros() from public, anon, authenticated;
drop trigger if exists plan_evaluacion_prubind_area_con_parametros on public.plan_evaluacion_prubind;
create trigger plan_evaluacion_prubind_area_con_parametros after insert on public.plan_evaluacion_prubind
  for each row execute function public.prubind_area_con_parametros();

create or replace function public.prubind_area_sin_parametros(p_prueba uuid, p_area text, p_motivo text default null, p_quitar boolean default false)
returns void language plpgsql security definer set search_path = '' as $$
declare v public.pruebas_prubind%rowtype; n int;
begin
  if public.prubind_usuario_actual_id() is null then raise exception 'Usuario no autorizado.' using errcode = '42501'; end if;
  if p_area not in ('calidad', 'produccion', 'seguridad', 'mantenimiento') then raise exception 'Área no válida.' using errcode = 'P0001'; end if;
  select * into v from public.pruebas_prubind where id = p_prueba for update;
  if not found then raise exception 'La prueba no existe.' using errcode = 'P0001'; end if;
  if v.estado not in ('registrada', 'en_preparacion', 'preparada', 'en_ejecucion') then
    raise exception 'Esto se indica antes de terminar la prueba.' using errcode = 'P0001';
  end if;
  if not public.prubind_puede_area(p_prueba, 'evaluar', p_area) then
    raise exception 'Solo el responsable de % lo indica.', initcap(p_area) using errcode = '42501';
  end if;
  if p_quitar then
    delete from public.areas_sin_parametros_prubind where prueba_id = p_prueba and area = p_area;
    get diagnostics n = row_count;
    if n > 0 then perform public.prubind_log(p_prueba, 'sistema', initcap(p_area) || ' retomó su participación en la prueba.'); end if;
    return;
  end if;
  if exists (select 1 from public.resultados_prubind r join public.plan_evaluacion_prubind pl on pl.id = r.plan_id
               join public.metodos_prubind m on m.id = pl.metodo_id
              where r.prueba_id = p_prueba and m.area = p_area)
     or (p_area = 'produccion' and exists (select 1 from public.ejecucion_controles_prubind c where c.prueba_id = p_prueba and c.valor is not null)) then
    raise exception 'El área ya tiene datos registrados en esta prueba.' using errcode = 'P0001';
  end if;
  perform set_config('prubind.rpc', '1', true);
  delete from public.plan_evaluacion_prubind pl using public.metodos_prubind m
   where m.id = pl.metodo_id and pl.prueba_id = p_prueba and m.area = p_area;
  perform set_config('prubind.rpc', '', true);
  insert into public.areas_sin_parametros_prubind (prueba_id, area, motivo, declarado_por)
  values (p_prueba, p_area, nullif(btrim(p_motivo), ''), public.prubind_usuario_actual_id())
  on conflict (prueba_id, area) do update set motivo = excluded.motivo, declarado_por = excluded.declarado_por, created_at = now();
  perform public.prubind_log(p_prueba, 'sistema', initcap(p_area) || ' indicó que no tiene parámetros que evaluar en esta prueba'
    || coalesce(': ' || nullif(btrim(p_motivo), ''), '.'));
end $$;
revoke all on function public.prubind_area_sin_parametros(uuid, text, text, boolean) from public, anon;
grant execute on function public.prubind_area_sin_parametros(uuid, text, text, boolean) to authenticated;

-- ---------- 3. Áreas independientes ----------
-- Participa el área que registró algún dato (o que ya evaluó algo) en la ejecución actual
create or replace function public.prubind_areas_participantes(p_prueba uuid)
returns text[] language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(a order by array_position(array['calidad','produccion','seguridad','mantenimiento'], a)), '{}')
  from (
    select distinct m.area a
      from public.resultados_prubind r join public.pruebas_prubind p on p.id = r.prueba_id
      join public.plan_evaluacion_prubind pl on pl.id = r.plan_id and pl.incluido
      join public.metodos_prubind m on m.id = pl.metodo_id
     where r.prueba_id = p_prueba and r.ejecucion = p.ejecucion_actual and (r.valor_num is not null or r.valor_opcion is not null)
    union
    select 'produccion' from public.ejecucion_controles_prubind c join public.pruebas_prubind p on p.id = c.prueba_id
     where c.prueba_id = p_prueba and c.ejecucion = p.ejecucion_actual and c.valor is not null
    union
    select e.area from public.evaluaciones_prubind e join public.pruebas_prubind p on p.id = e.prueba_id
     where e.prueba_id = p_prueba and e.ejecucion = p.ejecucion_actual
  ) s
$$;
revoke all on function public.prubind_areas_participantes(uuid) from public, anon;
grant execute on function public.prubind_areas_participantes(uuid) to authenticated;

-- Por evaluar: solo lo que tiene resultado registrado (lo pendiente de laboratorio no detiene)
create or replace function public.prubind_sin_evaluar(p_prueba uuid, p_area text default null)
returns integer language sql stable security definer set search_path = '' as $$
  select (select count(*) from public.plan_evaluacion_prubind pl join public.metodos_prubind m on m.id = pl.metodo_id
           join public.pruebas_prubind p on p.id = pl.prueba_id
          where pl.prueba_id = p_prueba and pl.incluido and (p_area is null or m.area = p_area)
            and exists (select 1 from public.resultados_prubind r where r.plan_id = pl.id and r.ejecucion = p.ejecucion_actual
                        and (r.valor_num is not null or r.valor_opcion is not null))
            and not exists (select 1 from public.evaluaciones_prubind e where e.plan_id = pl.id and e.ejecucion = p.ejecucion_actual))::int
       + (select count(*) from public.prueba_parametros_prubind x join public.pruebas_prubind p on p.id = x.prueba_id
          where x.prueba_id = p_prueba and (p_area is null or p_area = 'produccion')
            and exists (select 1 from public.ejecucion_controles_prubind c where c.prueba_parametro_id = x.id and c.ejecucion = p.ejecucion_actual and c.valor is not null)
            and not exists (select 1 from public.evaluaciones_prubind e where e.prueba_parametro_id = x.id and e.ejecucion = p.ejecucion_actual))::int
$$;

create or replace function public.prubind_eval_estado(p_prueba uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v public.pruebas_prubind%rowtype; r jsonb; v_areas text[]; v_part text[];
begin
  select * into v from public.pruebas_prubind where id = p_prueba;
  if not found then return null; end if;
  v_areas := public.prubind_areas_prueba(v.id);
  v_part := public.prubind_areas_participantes(v.id);
  select jsonb_build_object(
    'plan_incluidos', (select count(*) from public.plan_evaluacion_prubind pl where pl.prueba_id = v.id and pl.incluido),
    'obligatorios', (select count(*) from public.plan_evaluacion_prubind pl where pl.prueba_id = v.id and pl.incluido and pl.obligatorio),
    'obligatorios_faltantes', (select count(*) from public.plan_evaluacion_prubind pl where pl.prueba_id = v.id and pl.incluido and pl.obligatorio
        and not exists (select 1 from public.resultados_prubind x where x.plan_id = pl.id and x.ejecucion = v.ejecucion_actual
                        and (x.valor_num is not null or x.valor_opcion is not null))),
    'resultados', (select count(*) from public.resultados_prubind x where x.prueba_id = v.id and x.ejecucion = v.ejecucion_actual),
    'pendientes', (select count(*) from public.resultados_prubind x where x.prueba_id = v.id and x.ejecucion = v.ejecucion_actual and x.estado = 'pendiente'),
    'conformes', (select count(*) from public.resultados_prubind x where x.prueba_id = v.id and x.ejecucion = v.ejecucion_actual and x.estado = 'conforme'),
    'no_conformes', (select count(*) from public.resultados_prubind x where x.prueba_id = v.id and x.ejecucion = v.ejecucion_actual and x.estado = 'no_conforme'),
    'nc_sin_resolver', 0,
    'revisiones_pendientes', 0,
    'batches', (select count(*) from public.batches_prubind b where b.prueba_id = v.id and b.ejecucion = v.ejecucion_actual),
    'batches_pendientes', (select count(*) from public.batches_prubind b where b.prueba_id = v.id and b.ejecucion = v.ejecucion_actual and b.resultado_op = 'pendiente'),
    'controles', (select count(*) from public.ejecucion_controles_prubind c where c.prueba_id = v.id and c.ejecucion = v.ejecucion_actual),
    'controles_pendientes', (select count(*) from public.ejecucion_controles_prubind c where c.prueba_id = v.id and c.ejecucion = v.ejecucion_actual and c.resultado = 'pendiente'),
    'aut_ejecucion', exists (select 1 from public.autorizaciones_prubind a where a.prueba_id = v.id and a.ejecucion = v.ejecucion_actual and a.tipo = 'ejecucion'),
    'areas', to_jsonb(v_areas),
    'areas_involucradas', to_jsonb(v.areas_involucradas),
    'participantes', to_jsonb(v_part),
    'sin_parametros', coalesce((select jsonb_agg(s.area) from public.areas_sin_parametros_prubind s where s.prueba_id = v.id), '[]'::jsonb),
    'eval_total', (select count(*) from public.plan_evaluacion_prubind pl where pl.prueba_id = v.id and pl.incluido)
                  + (select count(*) from public.prueba_parametros_prubind x where x.prueba_id = v.id),
    'eval_faltantes', public.prubind_sin_evaluar(v.id),
    'no_cumple', (select count(*) from public.evaluaciones_prubind e where e.prueba_id = v.id and e.ejecucion = v.ejecucion_actual and e.evaluacion = 'no_cumple'),
    'no_determinado', (select count(*) from public.evaluaciones_prubind e where e.prueba_id = v.id and e.ejecucion = v.ejecucion_actual and e.evaluacion = 'no_determinado'),
    'sin_resultado', (select count(*) from public.plan_evaluacion_prubind pl where pl.prueba_id = v.id and pl.incluido
        and not exists (select 1 from public.resultados_prubind x where x.plan_id = pl.id and x.ejecucion = v.ejecucion_actual
                        and (x.valor_num is not null or x.valor_opcion is not null))
        and not exists (select 1 from public.evaluaciones_prubind e where e.plan_id = pl.id and e.ejecucion = v.ejecucion_actual)),
    'recom_faltantes', (select count(*) from unnest(v_part) a
                        where not exists (select 1 from public.recomendaciones_prubind x where x.prueba_id = v.id and x.ejecucion = v.ejecucion_actual and x.area = a)),
    'opcionales_pendientes', 0,
    'impl_requeridas', (select count(*) from public.autoridades_prubind a where a.activo and a.accion = 'autorizar_implementacion' and (a.tipo is null or a.tipo = v.tipo)),
    'impl_obtenidas', (select count(*) from public.autoridades_prubind a where a.activo and a.accion = 'autorizar_implementacion' and (a.tipo is null or a.tipo = v.tipo)
        and exists (select 1 from public.autorizaciones_prubind z where z.prueba_id = v.id and z.tipo = 'implementacion'
                    and ((a.puesto_id is not null and z.puesto_id = a.puesto_id) or (a.usuario_id is not null and z.autorizado_por = a.usuario_id))))
  ) into r;
  return r;
end $$;

-- "No se pudo determinar" como tercera opción de evaluación
do $$
declare c text;
begin
  for c in select conname from pg_constraint where conrelid = 'public.evaluaciones_prubind'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) like '%no_cumple%' loop
    execute format('alter table public.evaluaciones_prubind drop constraint %I', c);
  end loop;
end $$;
alter table public.evaluaciones_prubind add constraint evaluaciones_prubind_evaluacion_check
  check (evaluacion in ('cumple', 'no_cumple', 'no_determinado'));

create or replace function public.prubind_validar_evaluacion()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v     public.pruebas_prubind%rowtype;
  uid   uuid := public.prubind_usuario_actual_id();
  v_pid uuid;
  v_area text;
  v_con boolean;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return coalesce(new, old); end if;
  if coalesce(current_setting('prubind.rpc', true), '') = '1' then return coalesce(new, old); end if;
  v_pid := case when tg_op = 'DELETE' then old.prueba_id else new.prueba_id end;
  select * into v from public.pruebas_prubind where id = v_pid;
  if v.id is null then return coalesce(new, old); end if;
  if v.estado not in ('en_ejecucion', 'en_evaluacion', 'pendiente_resultados') then
    raise exception 'Los resultados se evalúan con la prueba en proceso o en evaluación, antes del dictamen.' using errcode = 'P0001';
  end if;
  if tg_op = 'DELETE' then
    if not public.prubind_puede_area(v_pid, 'evaluar', old.area) then
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
  -- Sin resultado solo se puede marcar "No se pudo determinar"
  if not v_con and new.evaluacion <> 'no_determinado' then
    raise exception 'El parámetro aún no tiene resultado registrado: solo puede marcarse "No se pudo determinar".' using errcode = 'P0001';
  end if;
  if not public.prubind_puede_area(v_pid, 'evaluar', v_area) then
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
  if v.estado not in ('en_ejecucion', 'en_evaluacion', 'pendiente_resultados') then
    raise exception 'El veredicto del área se registra con la prueba en proceso o en evaluación, antes del dictamen.' using errcode = 'P0001';
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

-- ---------- 4. Acciones: iniciar, terminar (con paso automático) y enviar a dictamen ----------
do $$
declare d text; o text;
begin
  d := pg_get_functiondef('public.prubind_accion(uuid,text,jsonb)'::regprocedure);
  o := d;
  d := replace(d, $q$  when 'agregar_parametros' then$q$, $q$  when 'iniciar' then
    perform public.prubind_req(p_prueba, 'preparar', array['registrada','en_preparacion','preparada'], 'La prueba ya se inició.');
    perform public.prubind_set_estado(p_prueba, 'en_ejecucion', 'Prueba iniciada (ejecución #' || v.ejecucion_actual || '): cada área registra sus parámetros.');

  when 'agregar_parametros' then$q$);
  if d = o then raise exception 'No se pudo agregar la acción iniciar'; end if;
  o := d;
  d := replace(d, $q$'Terminó el registro durante el proceso (ejecución #' || v.ejecucion_actual || '); inicia la evaluación de resultados.');$q$,
    $q$'Terminó la prueba (ejecución #' || v.ejecucion_actual || '); continúa la evaluación por área.');
    e := public.prubind_eval_estado(p_prueba);
    if (e ->> 'eval_faltantes')::int = 0 and (e ->> 'recom_faltantes')::int = 0 and jsonb_array_length(e -> 'participantes') > 0 then
      perform public.prubind_set_estado(p_prueba, 'pendiente_dictamen', 'Las áreas que participaron ya registraron su evaluación; pendiente del dictamen de Alta Dirección.');
    end if;$q$);
  if d = o then raise exception 'No se pudo ajustar terminar_ejecucion'; end if;
  o := d;
  d := replace(d, $q$    perform public.prubind_set_estado(p_prueba, 'pendiente_dictamen', 'Resultados evaluados y recomendaciones registradas;$q$,
    $q$    if jsonb_array_length(e -> 'participantes') = 0 then
      raise exception 'Ninguna área ha registrado datos en la prueba.' using errcode = 'P0001';
    end if;
    perform public.prubind_set_estado(p_prueba, 'pendiente_dictamen', 'Resultados evaluados y recomendaciones registradas;$q$);
  if d = o then raise exception 'No se pudo ajustar enviar_dictamen'; end if;
  d := replace(d, $q$'Faltan las recomendaciones de % área(s).'$q$, $q$'Faltan el veredicto y las recomendaciones de % área(s).'$q$);
  execute d;
end $$;

-- ---------- 5. Pendientes por persona (con área, prioridad y fecha) ----------
drop function if exists public.prubind_mis_pendientes();
create function public.prubind_mis_pendientes()
returns table (prueba_id uuid, folio text, cambio text, tipo_nombre text, estado text, accion text, area text,
               prioridad text, fecha_planeada date, tipo text)
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
    from p where p.estado in ('aprobada', 'rechazada') and public.prubind_puede(p.id, 'cerrar')
  union all
  select p.id, p.folio, p.cambio, p.tnom, p.estado, 'autorizar_implementacion', null, p.prioridad, p.fecha_planeada, p.tipo
    from p where p.estado = 'cerrada_aprobada' and public.prubind_puede(p.id, 'autorizar_implementacion')
     and not exists (select 1 from public.autorizaciones_prubind z where z.prueba_id = p.id and z.tipo = 'implementacion'
                     and (z.autorizado_por = uid or (z.puesto_id is not null and z.puesto_id = public.prubind_puesto_actual())));
end $$;
revoke all on function public.prubind_mis_pendientes() from public, anon;
grant execute on function public.prubind_mis_pendientes() to authenticated;

-- Panel: evaluaciones "No se pudo determinar" por área
do $$
declare d text; o text;
begin
  d := pg_get_functiondef('public.prubind_dashboard(date,date)'::regprocedure);
  o := d;
  d := replace(d, $q$count(*) filter (where e.evaluacion = 'no_cumple') nc$q$,
                  $q$count(*) filter (where e.evaluacion = 'no_cumple') nc, count(*) filter (where e.evaluacion = 'no_determinado') nd$q$);
  d := replace(d, $q$'no_cumple', nc) order by$q$, $q$'no_cumple', nc, 'no_determinado', nd) order by$q$);
  if d = o then raise exception 'No se pudo ajustar prubind_dashboard'; end if;
  execute d;
end $$;

-- ---------- 6. Notificaciones push ----------
create table if not exists public.push_subs_prubind (
  id          uuid primary key default gen_random_uuid(),
  usuario_id  uuid not null references public.usuarios_prubind(id) on delete cascade,
  endpoint    text not null check (endpoint ~ '^https://' and char_length(endpoint) <= 1000),
  p256dh      text not null check (char_length(p256dh) <= 200),
  auth        text not null check (char_length(auth) <= 100),
  dispositivo text check (dispositivo is null or char_length(dispositivo) <= 200),
  created_at  timestamptz not null default now()
);
create unique index if not exists push_subs_prubind_endpoint_uk on public.push_subs_prubind (endpoint);
create index if not exists push_subs_prubind_usuario_idx on public.push_subs_prubind (usuario_id);
alter table public.push_subs_prubind enable row level security;
drop policy if exists push_subs_prubind_sel on public.push_subs_prubind;
create policy push_subs_prubind_sel on public.push_subs_prubind for select to authenticated using (usuario_id = (select public.prubind_usuario_actual_id()));
drop policy if exists push_subs_prubind_ins on public.push_subs_prubind;
create policy push_subs_prubind_ins on public.push_subs_prubind for insert to authenticated with check (usuario_id = (select public.prubind_usuario_actual_id()));
drop policy if exists push_subs_prubind_del on public.push_subs_prubind;
create policy push_subs_prubind_del on public.push_subs_prubind for delete to authenticated using (usuario_id = (select public.prubind_usuario_actual_id()));
revoke all on public.push_subs_prubind from anon, public;
grant select, insert, delete on public.push_subs_prubind to authenticated;

-- Registro de avisos enviados (evita duplicados por prueba, evento y ejecución)
create table if not exists public.avisos_prubind (
  id              bigint generated always as identity primary key,
  prueba_id       uuid not null references public.pruebas_prubind(id) on delete cascade,
  evento          text not null check (evento in ('nueva_prueba', 'iniciada', 'lista_dictamen', 'dictamen')),
  clave           text not null,
  enviados_push   integer not null default 0,
  created_at      timestamptz not null default now()
);
create unique index if not exists avisos_prubind_uk on public.avisos_prubind (prueba_id, evento, clave);
alter table public.avisos_prubind enable row level security;
revoke all on public.avisos_prubind from anon, public, authenticated;

-- Claves VAPID en un esquema privado (no expuesto por la API); las genera la Edge Function
create schema if not exists prubind_private;
revoke all on schema prubind_private from public, anon, authenticated;
create table if not exists prubind_private.config_push (
  id smallint primary key default 1 check (id = 1),
  vapid_publica text not null,
  vapid_privada text not null,
  contacto text not null default 'mailto:javier.martinez@petstable.mx'
);
revoke all on prubind_private.config_push from public, anon, authenticated;

create or replace function public.prubind_vapid_publica()
returns text language sql stable security definer set search_path = '' as $$
  select vapid_publica from prubind_private.config_push where id = 1 and public.prubind_es_miembro()
$$;
revoke all on function public.prubind_vapid_publica() from public, anon;
grant execute on function public.prubind_vapid_publica() to authenticated;

create or replace function public.prubind_vapid_claves()
returns table (vapid_publica text, vapid_privada text, contacto text)
language sql stable security definer set search_path = '' as $$
  select vapid_publica, vapid_privada, contacto from prubind_private.config_push where id = 1
$$;
revoke all on function public.prubind_vapid_claves() from public, anon, authenticated;
grant execute on function public.prubind_vapid_claves() to service_role;

create or replace function public.prubind_vapid_guardar(p_publica text, p_privada text)
returns void language sql security definer set search_path = '' as $$
  insert into prubind_private.config_push (id, vapid_publica, vapid_privada) values (1, p_publica, p_privada)
  on conflict (id) do nothing
$$;
revoke all on function public.prubind_vapid_guardar(text, text) from public, anon, authenticated;
grant execute on function public.prubind_vapid_guardar(text, text) to service_role;

-- Destinatarios de cada aviso según autoridades (solo usuarios activos)
create or replace function public.prubind_destinatarios_aviso(p_prueba uuid, p_evento text)
returns table (id uuid, nombre text)
language sql stable security definer set search_path = '' as $$
  with p as (select * from public.pruebas_prubind where id = p_prueba),
  acc as (
    select unnest(case p_evento
      when 'nueva_prueba' then array['evaluar_calidad','evaluar_produccion','evaluar_seguridad','evaluar_mantenimiento',
                                     'capturar_calidad','capturar_produccion','capturar_seguridad','capturar_mantenimiento','dictaminar']
      when 'iniciada' then array['evaluar_calidad','evaluar_produccion','evaluar_seguridad','evaluar_mantenimiento',
                                 'capturar_calidad','capturar_produccion','capturar_seguridad','capturar_mantenimiento']
      when 'lista_dictamen' then array['dictaminar']
      when 'dictamen' then array['evaluar_calidad','evaluar_produccion','evaluar_seguridad','evaluar_mantenimiento','cerrar']
      else array[]::text[] end) accion
  )
  select distinct u.id, u.nombre
    from public.usuarios_prubind u, p
   where u.activo
     and (exists (select 1 from public.autoridades_prubind a join acc on acc.accion = a.accion
                  where a.activo and (a.tipo is null or a.tipo = p.tipo)
                    and (a.usuario_id = u.id or (a.puesto_id is not null and a.puesto_id = u.puesto_id)))
          or (p_evento = 'dictamen' and u.id = p.registrado_por))
$$;
revoke all on function public.prubind_destinatarios_aviso(uuid, text) from public, anon, authenticated;
grant execute on function public.prubind_destinatarios_aviso(uuid, text) to service_role;

-- Quien registra (e inicia) la prueba también la termina; también quien captura durante el proceso
do $$
declare d text; o text;
begin
  d := pg_get_functiondef('public.prubind_accion(uuid,text,jsonb)'::regprocedure);
  o := d;
  d := replace(d, $q$    perform public.prubind_req(p_prueba, 'ejecutar', array['en_ejecucion']);$q$,
    $q$    perform public.prubind_req(p_prueba, null, array['en_ejecucion']);
    if not (public.prubind_puede(p_prueba, 'preparar') or public.prubind_puede(p_prueba, 'ejecutar')) then
      raise exception 'No tiene autoridad para terminar la prueba.' using errcode = '42501';
    end if;$q$);
  if d = o then raise exception 'No se pudo ajustar terminar_ejecucion'; end if;
  execute d;
end $$;

-- La "preparación" ya no es una etapa: el paso interno registrada → en_preparacion solo indica que se empezó la formulación
create or replace function public.prubind_despues_prueba()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    perform public.prubind_log(new.id, 'estado', 'Prueba registrada con folio ' || new.folio || '.');
  elsif new.estado = 'en_preparacion' and old.estado = 'registrada' then
    perform public.prubind_log(new.id, 'sistema', 'Se empezó a registrar la formulación de la prueba.');
  end if;
  return new;
end $$;
