-- =====================================================================
-- v4.1 · Ajustes del 20/10/2026
--   1. Cada área define SUS parámetros: Calidad → Jefe de Calidad,
--      Producción → Gerente de Producción, Seguridad → Supervisor de SSA,
--      Mantenimiento → Jefe de Mantenimiento (autoridad evaluar_<área>).
--      Quien registra marca si la prueba involucra Seguridad o Mantenimiento.
--   2. Seguridad y Mantenimiento no detienen la prueba: si no registran ni
--      evalúan su parte, la prueba avanza con Calidad y Producción.
--   3. Salmonella 25 g (PCR) y E. coli O157 (PCR): ausencia / presencia.
--   4. Nuevo producto ya no pide receta base.
--   5. Alta rápida de proveedor, materia prima y receta desde los menús.
-- No destructiva.
-- =====================================================================

-- 1. Áreas involucradas en cada prueba
alter table public.pruebas_prubind add column if not exists areas_involucradas text[] not null default array['calidad', 'produccion']
  check (areas_involucradas <@ array['calidad', 'produccion', 'seguridad', 'mantenimiento']::text[]);
update public.pruebas_prubind p set areas_involucradas = (
  select array_agg(distinct a) from unnest(array['calidad', 'produccion'] || public.prubind_areas_prueba(p.id)) a);

-- 3. Nombres de los análisis por PCR
update public.metodos_prubind set nombre = 'Salmonella 25 g (PCR)', tecnica = 'PCR' where codigo = 'MIC-SALM';
update public.metodos_prubind set nombre = 'E. coli O157 (PCR)', tecnica = 'PCR' where codigo = 'MIC-O157';

-- 4. Nuevo producto sin receta base
update public.tipos_prueba_prubind set campos_registro = '{}' where codigo = 'producto_nuevo';

-- 2. Solo Calidad y Producción son obligatorias para avanzar
create or replace function public.prubind_areas_obligatorias()
returns text[] language sql immutable set search_path = '' as $$ select array['calidad', 'produccion'] $$;

create or replace function public.prubind_sin_evaluar(p_prueba uuid, p_area text default null)
returns integer language sql stable security definer set search_path = '' as $$
  -- Sin área: solo cuenta las áreas obligatorias (Seguridad y Mantenimiento no detienen la prueba)
  select (select count(*) from public.plan_evaluacion_prubind pl join public.metodos_prubind m on m.id = pl.metodo_id
           join public.pruebas_prubind p on p.id = pl.prueba_id
          where pl.prueba_id = p_prueba and pl.incluido
            and (case when p_area is null then m.area = any (public.prubind_areas_obligatorias()) else m.area = p_area end)
            and (pl.obligatorio or exists (select 1 from public.resultados_prubind r where r.plan_id = pl.id and r.ejecucion = p.ejecucion_actual
                                           and (r.valor_num is not null or r.valor_opcion is not null)))
            and not exists (select 1 from public.evaluaciones_prubind e where e.plan_id = pl.id and e.ejecucion = p.ejecucion_actual))::int
       + (select count(*) from public.prueba_parametros_prubind x join public.pruebas_prubind p on p.id = x.prueba_id
          where x.prueba_id = p_prueba and (p_area is null or p_area = 'produccion')
            and not exists (select 1 from public.evaluaciones_prubind e where e.prueba_parametro_id = x.id and e.ejecucion = p.ejecucion_actual))::int
$$;

create or replace function public.prubind_eval_estado(p_prueba uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v public.pruebas_prubind%rowtype; r jsonb; v_areas text[];
begin
  select * into v from public.pruebas_prubind where id = p_prueba;
  if not found then return null; end if;
  v_areas := public.prubind_areas_prueba(v.id);
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
    'eval_total', (select count(*) from public.plan_evaluacion_prubind pl where pl.prueba_id = v.id and pl.incluido)
                  + (select count(*) from public.prueba_parametros_prubind x where x.prueba_id = v.id),
    -- Solo Calidad y Producción detienen el avance
    'eval_faltantes', public.prubind_sin_evaluar(v.id),
    'no_cumple', (select count(*) from public.evaluaciones_prubind e where e.prueba_id = v.id and e.ejecucion = v.ejecucion_actual and e.evaluacion = 'no_cumple'),
    'recom_faltantes', (select count(*) from unnest(v_areas) a
                        where a = any (public.prubind_areas_obligatorias())
                          and not exists (select 1 from public.recomendaciones_prubind x where x.prueba_id = v.id and x.ejecucion = v.ejecucion_actual and x.area = a)),
    'opcionales_pendientes', (select count(*) from unnest(v.areas_involucradas) a
                        where not (a = any (public.prubind_areas_obligatorias()))
                          and not exists (select 1 from public.recomendaciones_prubind x where x.prueba_id = v.id and x.ejecucion = v.ejecucion_actual and x.area = a)),
    'impl_requeridas', (select count(*) from public.autoridades_prubind a where a.activo and a.accion = 'autorizar_implementacion' and (a.tipo is null or a.tipo = v.tipo)),
    'impl_obtenidas', (select count(*) from public.autoridades_prubind a where a.activo and a.accion = 'autorizar_implementacion' and (a.tipo is null or a.tipo = v.tipo)
        and exists (select 1 from public.autorizaciones_prubind z where z.prueba_id = v.id and z.tipo = 'implementacion'
                    and ((a.puesto_id is not null and z.puesto_id = a.puesto_id) or (a.usuario_id is not null and z.autorizado_por = a.usuario_id))))
  ) into r;
  return r;
end $$;

-- Una vez enviada a dictamen, las áreas opcionales ya no pueden cambiar su parte
-- (se conserva la regla de estados de los disparadores existentes).

-- 1. Agregar / quitar parámetros: solo el responsable del área (evaluar_<área>)
create or replace function public.prubind_definir_parametros(p_prueba uuid, p_agregar uuid[], p_quitar uuid[] default '{}')
returns void language plpgsql security definer set search_path = '' as $$
declare
  v public.pruebas_prubind%rowtype; t public.tipos_prueba_prubind%rowtype;
  v_met uuid; v_pl uuid; v_area text; v_nom text; n_add int := 0; n_del int := 0;
begin
  if public.prubind_usuario_actual_id() is null then raise exception 'Usuario no autorizado.' using errcode = '42501'; end if;
  select * into v from public.pruebas_prubind where id = p_prueba for update;
  if not found then raise exception 'La prueba no existe.' using errcode = 'P0001'; end if;
  if v.estado not in ('registrada', 'en_preparacion', 'preparada', 'en_ejecucion') then
    raise exception 'Los parámetros se definen al registrar la prueba o durante el proceso.' using errcode = 'P0001';
  end if;
  select * into t from public.tipos_prueba_prubind where codigo = v.tipo;
  perform set_config('prubind.rpc', '1', true);
  foreach v_met in array coalesce(p_agregar, '{}') loop
    select area into v_area from public.metodos_prubind where id = v_met and activo;
    if v_area is null then raise exception 'Parámetro no válido o inactivo.' using errcode = 'P0001'; end if;
    if not public.prubind_puede_area(p_prueba, 'evaluar', v_area) then
      raise exception 'Los parámetros de % los define el responsable de esa área.', initcap(v_area) using errcode = '42501';
    end if;
    insert into public.plan_evaluacion_prubind (prueba_id, metodo_id, incluido, obligatorio, nivel, especificacion_id,
                                                crit_minimo, crit_maximo, crit_texto, crit_referencia, orden)
    select p_prueba, v_met, true, true,
           coalesce(pt.nivel, case when t.ejecucion_form = 'fabricacion' and v_area in ('calidad', 'produccion') then 'batch' else 'corrida' end),
           es.id, es.minimo, es.maximo, es.criterio_texto, es.referencia, coalesce(pt.orden, 900)
      from (select 1) one
      left join public.plantilla_evaluacion_prubind pt on pt.tipo = v.tipo and pt.metodo_id = v_met
      left join lateral (
        select s.* from public.especificaciones_prubind s
        where s.metodo_id = v_met and s.activo and s.vigente
          and (s.producto_id is null or s.producto_id = v.producto_id)
          and (s.materia_prima_id is null or s.materia_prima_id = v.materia_prima_id)
        order by (s.producto_id is not null) desc, (s.materia_prima_id is not null) desc, s.updated_at desc limit 1) es on true
    on conflict (prueba_id, metodo_id) do update set incluido = true, obligatorio = true;
    if not (v_area = any (v.areas_involucradas)) then
      update public.pruebas_prubind set areas_involucradas = areas_involucradas || v_area where id = p_prueba;
      v.areas_involucradas := v.areas_involucradas || v_area;
    end if;
    n_add := n_add + 1;
  end loop;
  foreach v_pl in array coalesce(p_quitar, '{}') loop
    select m.area, m.nombre into v_area, v_nom from public.plan_evaluacion_prubind pl join public.metodos_prubind m on m.id = pl.metodo_id
     where pl.id = v_pl and pl.prueba_id = p_prueba;
    if v_area is null then raise exception 'El parámetro no pertenece a esta prueba.' using errcode = 'P0001'; end if;
    if not public.prubind_puede_area(p_prueba, 'evaluar', v_area) then
      raise exception 'Los parámetros de % los define el responsable de esa área.', initcap(v_area) using errcode = '42501';
    end if;
    if exists (select 1 from public.resultados_prubind r where r.plan_id = v_pl) then
      raise exception 'El parámetro "%" ya tiene resultados registrados; bórrelos primero.', v_nom using errcode = 'P0001';
    end if;
    delete from public.plan_evaluacion_prubind where id = v_pl;
    n_del := n_del + 1;
  end loop;
  perform set_config('prubind.rpc', '', true);
  if n_add + n_del > 0 then
    perform public.prubind_log(p_prueba, 'sistema', 'Parámetros a evaluar actualizados (' || n_add || ' agregado(s), ' || n_del || ' quitado(s)).');
  end if;
end $$;

-- Quien registra (o su responsable) indica si la prueba involucra Seguridad o Mantenimiento
create or replace function public.prubind_areas_involucradas(p_prueba uuid, p_areas text[])
returns void language plpgsql security definer set search_path = '' as $$
declare v public.pruebas_prubind%rowtype; v_areas text[];
begin
  select * into v from public.pruebas_prubind where id = p_prueba for update;
  if not found then raise exception 'La prueba no existe.' using errcode = 'P0001'; end if;
  if not public.prubind_puede(p_prueba, 'preparar') then
    raise exception 'Solo quien registró la prueba puede cambiar las áreas involucradas.' using errcode = '42501';
  end if;
  if v.estado not in ('registrada', 'en_preparacion', 'preparada', 'en_ejecucion') then
    raise exception 'Las áreas se definen al registrar la prueba o durante el proceso.' using errcode = 'P0001';
  end if;
  -- Calidad y Producción siempre; un área con parámetros ya definidos no se puede quitar
  select array_agg(distinct a) into v_areas
    from unnest(array['calidad', 'produccion'] || coalesce(p_areas, '{}') || public.prubind_areas_prueba(p_prueba)) a
   where a in ('calidad', 'produccion', 'seguridad', 'mantenimiento');
  perform set_config('prubind.rpc', '1', true);
  update public.pruebas_prubind set areas_involucradas = v_areas where id = p_prueba;
  perform set_config('prubind.rpc', '', true);
end $$;

-- Pendientes: se agrega "definir parámetros" para el responsable de cada área involucrada
create or replace function public.prubind_mis_pendientes()
 returns table (prueba_id uuid, folio text, cambio text, tipo_nombre text, estado text, accion text)
 language plpgsql stable security definer set search_path = '' as $function$
#variable_conflict use_column
declare uid uuid := public.prubind_usuario_actual_id();
begin
  if uid is null then raise exception 'Usuario no autorizado.' using errcode = '42501'; end if;
  return query
  with p as (
    select x.*, t.nombre as tnom, public.prubind_areas_prueba(x.id) as areas
    from public.pruebas_prubind x join public.tipos_prueba_prubind t on t.codigo = x.tipo
    where x.estado not in ('cerrada_rechazada', 'cancelada')
  )
  select p.id, p.folio, p.cambio, p.tnom, p.estado, a.accion
  from p cross join lateral (values ('definir'), ('capturar'), ('evaluar'), ('recomendar'), ('dictaminar'), ('cerrar'), ('autorizar_implementacion')) a(accion)
  where case a.accion
    when 'definir' then p.estado in ('registrada', 'en_preparacion', 'preparada', 'en_ejecucion')
         and exists (select 1 from unnest(p.areas_involucradas) ar where public.prubind_tiene_autoridad(p.tipo, 'evaluar_' || ar)
                     and not (ar = any (p.areas)))
    when 'capturar' then p.estado in ('registrada', 'en_preparacion', 'preparada', 'en_ejecucion')
         and exists (select 1 from unnest(p.areas) ar where public.prubind_tiene_autoridad(p.tipo, 'capturar_' || ar))
    when 'evaluar' then p.estado in ('en_evaluacion', 'pendiente_resultados')
         and exists (select 1 from unnest(p.areas) ar where public.prubind_tiene_autoridad(p.tipo, 'evaluar_' || ar)
                     and public.prubind_sin_evaluar(p.id, ar) > 0)
    when 'recomendar' then p.estado in ('en_evaluacion', 'pendiente_resultados')
         and exists (select 1 from unnest(p.areas) ar where public.prubind_tiene_autoridad(p.tipo, 'evaluar_' || ar)
                     and public.prubind_sin_evaluar(p.id, ar) = 0
                     and not exists (select 1 from public.recomendaciones_prubind r where r.prueba_id = p.id and r.ejecucion = p.ejecucion_actual and r.area = ar))
    when 'dictaminar' then p.estado = 'pendiente_dictamen' and public.prubind_puede(p.id, 'dictaminar')
    when 'cerrar' then p.estado in ('aprobada', 'rechazada') and public.prubind_puede(p.id, 'cerrar')
    when 'autorizar_implementacion' then p.estado = 'cerrada_aprobada' and public.prubind_puede(p.id, 'autorizar_implementacion')
         and not exists (select 1 from public.autorizaciones_prubind z where z.prueba_id = p.id and z.tipo = 'implementacion'
                         and (z.autorizado_por = uid or (z.puesto_id is not null and z.puesto_id = public.prubind_puesto_actual())))
    else false end
  order by p.created_at;
end $function$;

-- 5. Alta rápida desde los menús del registro (cualquier usuario del sistema)
create or replace function public.prubind_alta_rapida(p_tipo text, p_nombre text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_nom text := btrim(coalesce(p_nombre, '')); v_id uuid; v_prod uuid; v_rec uuid;
begin
  if not public.prubind_es_miembro() then raise exception 'Usuario no autorizado.' using errcode = '42501'; end if;
  if char_length(v_nom) not between 2 and 150 then raise exception 'Escriba el nombre (2 a 150 caracteres).' using errcode = 'P0001'; end if;
  if p_tipo = 'proveedor' then
    select id into v_id from public.proveedores_prubind where lower(btrim(nombre)) = lower(v_nom);
    if v_id is null then insert into public.proveedores_prubind (nombre) values (v_nom) returning id into v_id; end if;
  elsif p_tipo = 'materia_prima' then
    select id into v_id from public.materias_primas_prubind where lower(btrim(nombre)) = lower(v_nom);
    if v_id is null then
      insert into public.materias_primas_prubind (nombre, unidad_id) values (v_nom, (select id from public.unidades_prubind where simbolo = 'kg')) returning id into v_id;
    end if;
  elsif p_tipo = 'receta' then
    -- Devuelve la versión vigente (la receta nueva se crea sin ingredientes; se completan en la formulación o en Recetas)
    select rv.id into v_id from public.recetas_prubind r join public.receta_versiones_prubind rv on rv.receta_id = r.id and rv.estado = 'vigente'
     where lower(btrim(r.nombre)) = lower(v_nom);
    if v_id is null then
      if exists (select 1 from public.recetas_prubind where lower(btrim(nombre)) = lower(v_nom)) then
        raise exception 'La receta "%" existe pero no tiene una versión vigente; publíquela en Recetas.', v_nom using errcode = 'P0001';
      end if;
      select id into v_prod from public.productos_prubind where lower(btrim(nombre)) = lower(v_nom);
      if v_prod is null then insert into public.productos_prubind (nombre) values (v_nom) returning id into v_prod; end if;
      insert into public.recetas_prubind (producto_id, nombre) values (v_prod, v_nom) returning id into v_rec;
      insert into public.receta_versiones_prubind (receta_id, version, estado, notas)
      values (v_rec, 'v1', 'vigente', 'Alta rápida desde el registro de una prueba; sin ingredientes capturados.') returning id into v_id;
    end if;
  else
    raise exception 'Tipo no válido.' using errcode = 'P0001';
  end if;
  return v_id;
end $$;

do $$
declare f text;
begin
  foreach f in array array['prubind_definir_parametros(uuid,uuid[],uuid[])', 'prubind_areas_involucradas(uuid,text[])',
    'prubind_alta_rapida(text,text)', 'prubind_mis_pendientes()', 'prubind_eval_estado(uuid)', 'prubind_sin_evaluar(uuid,text)',
    'prubind_areas_obligatorias()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- La vista expone la columna nueva (p.* se expande al crearla)
drop view if exists public.v_pruebas_prubind;
create view public.v_pruebas_prubind with (security_invoker = true) as
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
         where d.prueba_id = p.id order by d.created_at desc limit 1) as ultimo_dictamen,
       cu.simbolo as cantidad_unidad
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
left join public.usuarios_prubind ux on ux.id = p.cancelado_por
left join public.unidades_prubind cu on cu.id = p.cantidad_unidad_id;
revoke all on public.v_pruebas_prubind from anon, public;
grant select on public.v_pruebas_prubind to authenticated;

-- La acción genérica agregar/quitar_parametro aplica la misma regla (solo el responsable del área)
do $$
declare d text; n text;
begin
  select pg_get_functiondef('public.prubind_accion(uuid,text,jsonb)'::regprocedure) into d;
  n := replace(d, 'public.prubind_puede(p_prueba, ''preparar'') or public.prubind_puede_area(p_prueba, ''capturar'', v_area)',
                  'public.prubind_puede_area(p_prueba, ''evaluar'', v_area)');
  if n = d then raise exception 'No se encontró la regla a reemplazar en prubind_accion'; end if;
  execute n;
end $$;
