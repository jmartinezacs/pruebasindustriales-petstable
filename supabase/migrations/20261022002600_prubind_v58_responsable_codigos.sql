-- =====================================================================
-- Pruebas industriales v5.8
--  · Responsable de la prueba (responsable_inicial_id): se asigna en el
--    registro y es quien la INICIA y la TERMINA (o un administrador). Si no
--    se indica, es quien la registra.
--  · Código automático de cada parámetro: área (CAL, PRO, SEG, MAN) + las
--    dos primeras palabras significativas del nombre (p. ej. CAL-TEMP-COCC).
--    Se recalculan los códigos existentes.
--  · El dictamen "Rechazada" ya no pide motivo de catálogo: pide la
--    explicación en la conclusión (el catálogo de motivos se retira de la app).
-- No destructiva: no borra tablas ni columnas.
-- =====================================================================

-- ---------- 1. Código automático de parámetros ----------
create or replace function public.prubind_codigo_parametro(p_nombre text, p_area text, p_id uuid default null)
returns text language plpgsql stable set search_path = '' as $$
declare
  v_pre  text := case p_area when 'calidad' then 'CAL' when 'produccion' then 'PRO' when 'seguridad' then 'SEG' else 'MAN' end;
  v_txt  text := upper(translate(coalesce(p_nombre, ''), 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN'));
  w      text[];
  v_base text;
  v_cod  text;
  n      integer := 1;
begin
  select array_agg(t order by i) into w
    from regexp_split_to_table(regexp_replace(v_txt, '[^A-Z0-9 ]', ' ', 'g'), '\s+') with ordinality s(t, i)
   where t <> '' and t not in ('DE', 'DEL', 'LA', 'LAS', 'EL', 'LOS', 'Y', 'O', 'E', 'EN', 'A', 'AL', 'CON', 'POR', 'PARA', 'SIN', 'UN', 'UNA', 'G');
  if w is null then w := array['PARAM']; end if;
  v_base := left(w[1], 4) || coalesce('-' || left(w[2], 4), '');
  v_cod := v_pre || '-' || v_base;
  while exists (select 1 from public.metodos_prubind m where m.codigo = v_cod and m.id is distinct from p_id) loop
    n := n + 1;
    v_cod := v_pre || '-' || v_base || '-' || n;
  end loop;
  return left(v_cod, 30);
end $$;
revoke all on function public.prubind_codigo_parametro(text, text, uuid) from public, anon;

create or replace function public.prubind_metodo_codigo()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' or new.nombre is distinct from old.nombre or new.area is distinct from old.area then
    new.codigo := public.prubind_codigo_parametro(new.nombre, new.area, new.id);
  end if;
  return new;
end $$;
revoke all on function public.prubind_metodo_codigo() from public, anon, authenticated;

drop trigger if exists prubind_metodo_codigo on public.metodos_prubind;
create trigger prubind_metodo_codigo before insert or update on public.metodos_prubind
  for each row execute function public.prubind_metodo_codigo();

-- Recalcular los códigos existentes (primero temporales para no chocar)
update public.metodos_prubind set codigo = 'TMP-' || upper(left(replace(id::text, '-', ''), 20));
do $$
declare r record;
begin
  for r in select id, nombre, area from public.metodos_prubind order by activo desc, area, nombre loop
    update public.metodos_prubind set codigo = public.prubind_codigo_parametro(r.nombre, r.area, r.id) where id = r.id;
  end loop;
end $$;

-- ---------- 2. Responsable de la prueba ----------
create or replace function public.prubind_responsable_prueba()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.responsable_inicial_id := coalesce(new.responsable_inicial_id, new.registrado_por);
  if new.responsable_inicial_id is not null and not exists (select 1 from public.usuarios_prubind u where u.id = new.responsable_inicial_id and u.activo) then
    raise exception 'El responsable de la prueba debe ser un usuario activo.' using errcode = 'P0001';
  end if;
  return new;
end $$;
revoke all on function public.prubind_responsable_prueba() from public, anon, authenticated;
-- Se llama "pruebas_prubind_zz_…" para correr después de pruebas_prubind_validar (que asigna registrado_por)
drop trigger if exists pruebas_prubind_zz_responsable on public.pruebas_prubind;
create trigger pruebas_prubind_zz_responsable before insert or update of responsable_inicial_id on public.pruebas_prubind
  for each row execute function public.prubind_responsable_prueba();

create or replace function public.prubind_puede(p_prueba uuid, p_accion text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare
  v   public.pruebas_prubind%rowtype;
  uid uuid := public.prubind_usuario_actual_id();
begin
  if uid is null then return false; end if;
  select * into v from public.pruebas_prubind where id = p_prueba;
  if not found then return false; end if;
  return coalesce(case p_accion
    -- Inicia y termina la prueba: su responsable (o un administrador)
    when 'responsable' then uid = coalesce(v.responsable_inicial_id, v.registrado_por) or public.prubind_es_admin()
    when 'preparar' then uid is not distinct from v.registrado_por or uid is not distinct from v.responsable_inicial_id
                         or uid is not distinct from v.responsable_ejecucion_id or public.prubind_tiene_autoridad(v.tipo, 'preparar')
    when 'abastecer' then public.prubind_tiene_autoridad(v.tipo, 'abastecer') or public.prubind_puede(p_prueba, 'preparar')
    when 'ejecutar'  then uid is not distinct from v.responsable_ejecucion_id or public.prubind_tiene_autoridad(v.tipo, 'ejecutar')
                         or public.prubind_tiene_autoridad_prefijo(v.tipo, 'capturar_')
    when 'evaluar'   then public.prubind_tiene_autoridad(v.tipo, 'evaluar') or public.prubind_tiene_autoridad_prefijo(v.tipo, 'evaluar_')
    when 'cancelar'  then uid is not distinct from v.registrado_por or uid is not distinct from v.responsable_inicial_id
                         or public.prubind_tiene_autoridad(v.tipo, 'cerrar') or public.prubind_tiene_autoridad(v.tipo, 'dictaminar')
    else public.prubind_tiene_autoridad(v.tipo, p_accion)
  end, false);
end $$;

-- ---------- 3. Iniciar / terminar solo el responsable; rechazo con explicación ----------
do $$
declare d text := pg_get_functiondef('public.prubind_accion(uuid,text,jsonb)'::regprocedure); n text;
begin
  n := replace(d, $a$perform public.prubind_req(p_prueba, 'preparar', array['registrada','en_preparacion','preparada'], 'La prueba ya se inició.');$a$,
    $a$perform public.prubind_req(p_prueba, null, array['registrada','en_preparacion','preparada'], 'La prueba ya se inició.');
    if not public.prubind_puede(p_prueba, 'responsable') then raise exception 'Solo el responsable de la prueba la inicia.' using errcode = '42501'; end if;$a$);
  if n = d then raise exception 'No se encontró el bloque de iniciar.'; end if; d := n;
  n := replace(d, $a$if not (public.prubind_puede(p_prueba, 'preparar') or public.prubind_puede(p_prueba, 'ejecutar')) then
      raise exception 'No tiene autoridad para terminar la prueba.'$a$,
    $a$if not public.prubind_puede(p_prueba, 'responsable') then
      raise exception 'Solo el responsable de la prueba la termina.'$a$);
  if n = d then raise exception 'No se encontró el bloque de terminar.'; end if; d := n;
  n := replace(d, $a$if v_mot is null or not exists (select 1 from public.motivos_prubind where id = v_mot and tipo = 'rechazo') then
        raise exception 'Seleccione el motivo de rechazo.'$a$,
    $a$if v_txt is null then
        raise exception 'Explique en la conclusión por qué se rechaza.'$a$);
  if n = d then raise exception 'No se encontró el bloque de rechazo.'; end if;
  execute n;
end $$;

do $$
declare d text := pg_get_functiondef('public.prubind_mis_pendientes_todos()'::regprocedure); n text;
begin
  n := replace(d, $a$from p where p.estado in ('registrada', 'en_preparacion', 'preparada') and public.prubind_puede(p.id, 'preparar')$a$,
                  $a$from p where p.estado in ('registrada', 'en_preparacion', 'preparada') and public.prubind_puede(p.id, 'responsable')$a$);
  if n = d then raise exception 'No se encontró el pendiente iniciar.'; end if; d := n;
  n := replace(d, $a$from p where p.estado = 'en_ejecucion' and public.prubind_puede(p.id, 'preparar')$a$,
                  $a$from p where p.estado = 'en_ejecucion' and public.prubind_puede(p.id, 'responsable')$a$);
  if n = d then raise exception 'No se encontró el pendiente terminar.'; end if;
  execute n;
end $$;
