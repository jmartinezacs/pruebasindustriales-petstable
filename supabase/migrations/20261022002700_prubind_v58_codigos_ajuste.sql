-- v5.8 · Ajuste de códigos automáticos de parámetros:
--  · "no", "ni", "se" y "durante" no forman parte del código.
--  · Si dos nombres empiezan igual, la segunda palabra se alarga (TERMOF / TERMOS)
--    antes de recurrir a un número.
--  · Sin categorías, las dos "Humedad" de Calidad se distinguen por nombre:
--    la bromatológica pasa a "Humedad (laboratorio)".
create or replace function public.prubind_codigo_parametro(p_nombre text, p_area text, p_id uuid default null)
returns text language plpgsql stable set search_path = '' as $$
declare
  v_pre  text := case p_area when 'calidad' then 'CAL' when 'produccion' then 'PRO' when 'seguridad' then 'SEG' else 'MAN' end;
  v_txt  text := upper(translate(coalesce(p_nombre, ''), 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN'));
  w      text[];
  v_cod  text;
  v_largo integer;
  n      integer := 1;
begin
  select array_agg(t order by i) into w
    from regexp_split_to_table(regexp_replace(v_txt, '[^A-Z0-9 ]', ' ', 'g'), '\s+') with ordinality s(t, i)
   where t <> '' and t not in ('DE', 'DEL', 'LA', 'LAS', 'EL', 'LOS', 'Y', 'O', 'E', 'EN', 'A', 'AL', 'CON', 'POR', 'PARA', 'SIN', 'UN', 'UNA', 'G',
                               'NO', 'NI', 'SE', 'DURANTE');
  if w is null then w := array['PARAM']; end if;
  foreach v_largo in array array[4, 6, 8] loop
    v_cod := left(v_pre || '-' || left(w[1], 4) || coalesce('-' || left(w[2], v_largo), ''), 30);
    if not exists (select 1 from public.metodos_prubind m where m.codigo = v_cod and m.id is distinct from p_id) then return v_cod; end if;
  end loop;
  loop
    n := n + 1;
    v_cod := left(v_pre || '-' || left(w[1], 4) || coalesce('-' || left(w[2], 4), ''), 27) || '-' || n;
    exit when not exists (select 1 from public.metodos_prubind m where m.codigo = v_cod and m.id is distinct from p_id);
  end loop;
  return v_cod;
end $$;
revoke all on function public.prubind_codigo_parametro(text, text, uuid) from public, anon;

update public.metodos_prubind set nombre = 'Humedad (laboratorio)'
 where nombre = 'Humedad' and area = 'calidad' and categoria = 'bromatologia';

update public.metodos_prubind set codigo = 'TMP-' || upper(left(replace(id::text, '-', ''), 20));
do $$
declare r record;
begin
  for r in select id, nombre, area from public.metodos_prubind order by activo desc, area, nombre loop
    update public.metodos_prubind set codigo = public.prubind_codigo_parametro(r.nombre, r.area, r.id) where id = r.id;
  end loop;
end $$;
