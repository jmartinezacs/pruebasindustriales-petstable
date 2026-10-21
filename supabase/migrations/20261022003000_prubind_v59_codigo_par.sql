-- v5.9 · Código de parámetro sencillo y consecutivo: PAR-001, PAR-002…
-- Se asigna solo al crear el parámetro y ya no cambia aunque se edite el nombre o el área.
-- Se renumeran los existentes por área y nombre (activos primero).
create or replace function public.prubind_codigo_parametro(p_nombre text, p_area text, p_id uuid default null)
returns text language plpgsql stable set search_path = '' as $$
declare n integer;
begin
  select coalesce(max(substring(codigo from '^PAR-(\d+)$')::int), 0) + 1 into n
    from public.metodos_prubind where codigo ~ '^PAR-\d+$' and id is distinct from p_id;
  return 'PAR-' || lpad(n::text, 3, '0');
end $$;
revoke all on function public.prubind_codigo_parametro(text, text, uuid) from public, anon;

create or replace function public.prubind_metodo_codigo()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.codigo := public.prubind_codigo_parametro(new.nombre, new.area, new.id);
  else
    new.codigo := old.codigo;   -- el código no cambia
  end if;
  return new;
end $$;
revoke all on function public.prubind_metodo_codigo() from public, anon, authenticated;

-- Renumerar: primero temporales, luego consecutivos (el trigger conserva el código en UPDATE, así que se desactiva un momento)
alter table public.metodos_prubind disable trigger prubind_metodo_codigo;
update public.metodos_prubind set codigo = 'TMP-' || upper(left(replace(id::text, '-', ''), 20));
with orden as (
  select id, row_number() over (order by activo desc,
           array_position(array['calidad', 'produccion', 'seguridad', 'mantenimiento'], area), nombre) n
    from public.metodos_prubind)
update public.metodos_prubind m set codigo = 'PAR-' || lpad(o.n::text, 3, '0') from orden o where o.id = m.id;
alter table public.metodos_prubind enable trigger prubind_metodo_codigo;
