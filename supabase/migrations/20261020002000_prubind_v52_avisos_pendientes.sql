-- =====================================================================
-- Pruebas industriales · v5.2 · Más avisos
--  1. Aviso "prueba terminada" a los responsables de evaluar de las áreas
--     que participaron (deben evaluar y dar su veredicto).
--  2. Recordatorio diario (lunes a sábado, 08:00 de Ciudad de México) a cada
--     persona con pendientes: pg_cron + pg_net → Edge Function
--     recordatorios_prubind, protegida con un secreto en prubind_private.
--     En el recordatorio, a los administradores solo se les cuentan los
--     pendientes de sus autoridades reales (no todos los de la planta).
-- Solo objetos *_prubind. No destructiva.
-- =====================================================================

-- ---------- 1. Evento "terminada" ----------
do $$
declare c text;
begin
  for c in select conname from pg_constraint where conrelid = 'public.avisos_prubind'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) like '%nueva_prueba%' loop
    execute format('alter table public.avisos_prubind drop constraint %I', c);
  end loop;
end $$;
alter table public.avisos_prubind add constraint avisos_prubind_evento_check
  check (evento in ('nueva_prueba', 'iniciada', 'terminada', 'lista_dictamen', 'dictamen'));

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
      when 'terminada' then (select coalesce(array_agg('evaluar_' || a), '{}') from unnest(public.prubind_areas_participantes(p_prueba)) a)
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

-- ---------- 2. Recordatorio diario de pendientes ----------
-- Durante el cálculo del recordatorio el rol de administrador no amplía los pendientes
do $$
declare d text; o text;
begin
  d := pg_get_functiondef('public.prubind_es_admin()'::regprocedure); o := d;
  d := regexp_replace(d, 'select exists', $q$select coalesce(current_setting('prubind.sin_admin', true), '') <> '1' and exists$q$);
  if d = o then raise exception 'No se pudo ajustar prubind_es_admin'; end if;
  execute d;
end $$;

-- Pendientes por persona (solo quienes tienen notificaciones activas)
create or replace function public.prubind_pendientes_recordatorio()
returns table (usuario_id uuid, nombre text, total integer, pruebas integer, detalle text)
language plpgsql security definer set search_path = '' as $$
declare u record;
begin
  perform set_config('prubind.sin_admin', '1', true);
  for u in select distinct x.id, x.nombre, x.email from public.usuarios_prubind x
           join public.push_subs_prubind s on s.usuario_id = x.id where x.activo loop
    perform set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'email', u.email)::text, true);
    return query
      select u.id, u.nombre, count(*)::int, count(distinct m.prueba_id)::int,
             string_agg(distinct m.folio, ', ')
        from public.prubind_mis_pendientes() m
      having count(*) > 0;
  end loop;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('prubind.sin_admin', '', true);
end $$;
revoke all on function public.prubind_pendientes_recordatorio() from public, anon, authenticated;
grant execute on function public.prubind_pendientes_recordatorio() to service_role;

create table if not exists prubind_private.cron (
  id smallint primary key default 1 check (id = 1),
  secreto text not null default replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '')
);
insert into prubind_private.cron (id) values (1) on conflict do nothing;
revoke all on prubind_private.cron from public, anon, authenticated;

create or replace function public.prubind_cron_secreto()
returns text language sql stable security definer set search_path = '' as $$
  select secreto from prubind_private.cron where id = 1
$$;
revoke all on function public.prubind_cron_secreto() from public, anon, authenticated;
grant execute on function public.prubind_cron_secreto() to service_role;

-- 14:00 UTC = 08:00 en Ciudad de México (sin horario de verano), lunes a sábado
select cron.unschedule(jobid) from cron.job where jobname = 'prubind_recordatorio_pendientes';
select cron.schedule('prubind_recordatorio_pendientes', '0 14 * * 1-6', $cron$
  select net.http_post(
    url := 'https://domumnsezocubigfqwry.supabase.co/functions/v1/recordatorios_prubind',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-prubind-cron', (select secreto from prubind_private.cron where id = 1)),
    body := '{}'::jsonb,
    timeout_milliseconds := 20000)
$cron$);
