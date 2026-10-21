-- =====================================================================
-- Pruebas industriales · v5.3 · Marcar un pendiente como hecho
-- Cada persona puede quitar de su lista un pendiente que ya resolvió otra
-- persona (p. ej. otro inspector ya registró los datos). Solo afecta su propia
-- lista (campana, panel y recordatorio diario); no cambia la prueba.
-- =====================================================================
create table if not exists public.pendientes_hechos_prubind (
  id          uuid primary key default gen_random_uuid(),
  usuario_id  uuid not null references public.usuarios_prubind(id) on delete cascade,
  prueba_id   uuid not null references public.pruebas_prubind(id) on delete cascade,
  accion      text not null check (char_length(accion) <= 40),
  area        text not null default '' check (area in ('', 'calidad', 'produccion', 'seguridad', 'mantenimiento')),
  ejecucion   integer not null default 1,
  created_at  timestamptz not null default now(),
  unique (usuario_id, prueba_id, accion, area, ejecucion)
);
create index if not exists pendientes_hechos_prubind_prueba_idx on public.pendientes_hechos_prubind (prueba_id);
alter table public.pendientes_hechos_prubind enable row level security;
drop policy if exists pendientes_hechos_prubind_sel on public.pendientes_hechos_prubind;
create policy pendientes_hechos_prubind_sel on public.pendientes_hechos_prubind for select to authenticated
  using (usuario_id = (select public.prubind_usuario_actual_id()));
revoke all on public.pendientes_hechos_prubind from anon, public;
grant select on public.pendientes_hechos_prubind to authenticated;

-- La lista completa se conserva como prubind_mis_pendientes_todos(); la pública excluye lo marcado como hecho
do $$
declare d text;
begin
  if not exists (select 1 from pg_proc where proname = 'prubind_mis_pendientes_todos') then
    d := pg_get_functiondef('public.prubind_mis_pendientes()'::regprocedure);
    d := replace(d, 'public.prubind_mis_pendientes()', 'public.prubind_mis_pendientes_todos()');
    execute d;
  end if;
end $$;
revoke all on function public.prubind_mis_pendientes_todos() from public, anon, authenticated;

create or replace function public.prubind_mis_pendientes()
returns table (prueba_id uuid, folio text, cambio text, tipo_nombre text, estado text, accion text, area text,
               prioridad text, fecha_planeada date, tipo text)
language sql stable security definer set search_path = '' as $$
  select t.* from public.prubind_mis_pendientes_todos() t
  where not exists (
    select 1 from public.pendientes_hechos_prubind h join public.pruebas_prubind p on p.id = h.prueba_id
     where h.usuario_id = public.prubind_usuario_actual_id() and h.prueba_id = t.prueba_id
       and h.accion = t.accion and h.area = coalesce(t.area, '') and h.ejecucion = p.ejecucion_actual)
$$;
revoke all on function public.prubind_mis_pendientes() from public, anon;
grant execute on function public.prubind_mis_pendientes() to authenticated;

create or replace function public.prubind_pendiente_hecho(p_prueba uuid, p_accion text, p_area text default null, p_hecho boolean default true)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := public.prubind_usuario_actual_id(); v_ej int;
begin
  if uid is null then raise exception 'Usuario no autorizado.' using errcode = '42501'; end if;
  select ejecucion_actual into v_ej from public.pruebas_prubind where id = p_prueba;
  if v_ej is null then raise exception 'La prueba no existe.' using errcode = 'P0001'; end if;
  if p_hecho then
    insert into public.pendientes_hechos_prubind (usuario_id, prueba_id, accion, area, ejecucion)
    values (uid, p_prueba, p_accion, coalesce(p_area, ''), v_ej) on conflict do nothing;
  else
    delete from public.pendientes_hechos_prubind
     where usuario_id = uid and prueba_id = p_prueba and accion = p_accion and area = coalesce(p_area, '');
  end if;
end $$;
revoke all on function public.prubind_pendiente_hecho(uuid, text, text, boolean) from public, anon;
grant execute on function public.prubind_pendiente_hecho(uuid, text, text, boolean) to authenticated;

-- Volver a mostrar todo lo que la persona marcó como hecho
create or replace function public.prubind_pendientes_restablecer()
returns integer language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  delete from public.pendientes_hechos_prubind where usuario_id = public.prubind_usuario_actual_id();
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.prubind_pendientes_restablecer() from public, anon;
grant execute on function public.prubind_pendientes_restablecer() to authenticated;
