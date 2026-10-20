-- =====================================================================
-- v4.2 · Ajustes del 20/10/2026 (tarde)
--   1. Seguridad y Mantenimiento participan SIEMPRE (con parámetros propios).
--      Para avanzar a dictamen solo se exigen Calidad y Producción, para que
--      la prueba no se detenga si un área no registra su parte.
--   2. Parámetros de la ULMA como parámetros de Mantenimiento (con su rango).
--      El campo "Equipo" ya no se pide en el registro.
--   3. Sin número de batches: el registro durante el proceso se hace por la
--      prueba completa o por cada batch que se agregue; terminar no exige batches.
--   4. Panel: evaluaciones Cumple / No cumple por área en el periodo.
-- No destructiva: lo que deja de usarse se desactiva o se oculta.
-- =====================================================================

-- 1. Todas las áreas involucradas
alter table public.pruebas_prubind alter column areas_involucradas set default array['calidad', 'produccion', 'seguridad', 'mantenimiento'];
update public.pruebas_prubind set areas_involucradas = array['calidad', 'produccion', 'seguridad', 'mantenimiento']
where estado not in ('cerrada_aprobada', 'cerrada_rechazada', 'cancelada');

-- Parámetros de Seguridad (cualitativos) y Mantenimiento
insert into public.metodos_prubind (codigo, nombre, categoria, area, tipo_resultado, unidad_id, opciones)
select x.codigo, x.nombre, x.categoria, x.area, x.tipo, (select id from public.unidades_prubind where simbolo = x.unidad), x.opciones
from (values
  ('SEG-INC',    'Sin incidentes ni condiciones inseguras durante la prueba',     'seguridad', 'seguridad', 'opcion', null, '{conforme,no_conforme,no_aplica}'::text[]),
  ('SEG-LOTO',   'Bloqueo y etiquetado de energías en ajustes y limpieza',        'seguridad', 'seguridad', 'opcion', null, '{conforme,no_conforme,no_aplica}'::text[]),
  ('SEG-SENAL',  'Señalización y delimitación del área',                          'seguridad', 'seguridad', 'opcion', null, '{conforme,no_conforme,no_aplica}'::text[]),
  ('SEG-ERGO',   'Manejo manual de cargas y ergonomía',                           'seguridad', 'seguridad', 'opcion', null, '{conforme,no_conforme,no_aplica}'::text[]),
  ('SEG-ORDEN',  'Orden y limpieza del área',                                     'seguridad', 'seguridad', 'opcion', null, '{conforme,no_conforme,no_aplica}'::text[]),
  ('SEG-RESID',  'Manejo de residuos y derrames',                                 'seguridad', 'seguridad', 'opcion', null, '{conforme,no_conforme,no_aplica}'::text[]),
  ('MANT-PAROS', 'Paros no programados del equipo',                               'equipo', 'mantenimiento', 'numerico', null, '{}'::text[]),
  ('MANT-AJUSTE','Tiempo de ajuste o cambio de formato',                          'equipo', 'mantenimiento', 'numerico', 'min', '{}'::text[]),
  ('MANT-RUIDO', 'Ruidos, vibraciones o calentamiento anormal',                   'equipo', 'mantenimiento', 'opcion', null, '{conforme,no_conforme,no_aplica}'::text[]),
  ('MANT-DESG',  'Desgaste o daño en piezas y herramentales',                     'equipo', 'mantenimiento', 'opcion', null, '{conforme,no_conforme,no_aplica}'::text[]),
  ('MANT-FUGAS', 'Fugas de aire, vapor, agua o aceite',                           'equipo', 'mantenimiento', 'opcion', null, '{conforme,no_conforme,no_aplica}'::text[]),
  ('MANT-ULMA-TF','Temperatura de termoformado (ULMA)',                           'equipo', 'mantenimiento', 'numerico', '°C', '{}'::text[]),
  ('MANT-ULMA-TS','Temperatura de termosellado (ULMA)',                           'equipo', 'mantenimiento', 'numerico', '°C', '{}'::text[]),
  ('MANT-ULMA-AV','Avance (ULMA)',                                                'equipo', 'mantenimiento', 'numerico', 'mm', '{}'::text[])
) x(codigo, nombre, categoria, area, tipo, unidad, opciones)
on conflict (codigo) do nothing;

-- Rangos de la ULMA tomados de los parámetros del equipo (misma referencia: hoja de Procesos)
insert into public.especificaciones_prubind (metodo_id, minimo, maximo, criterio_texto, referencia)
select m.id, p.minimo, p.maximo,
       case when p.minimo is null and p.maximo is null then 'Referencia ' || coalesce(nullif(split_part(p.referencia, ' · ', 1), ''), 'del equipo') end,
       coalesce(nullif(split_part(p.referencia, ' · ', 2), ''), p.referencia, 'Parámetros del equipo ULMA')
from (values ('MANT-ULMA-TF', 'Termoformado'), ('MANT-ULMA-TS', 'Termosellado'), ('MANT-ULMA-AV', 'Avance')) x(codigo, par)
join public.metodos_prubind m on m.codigo = x.codigo
join public.equipo_parametros_prubind p on p.nombre = x.par
join public.equipos_prubind e on e.id = p.equipo_id and lower(e.nombre) = 'ulma'
where not exists (select 1 from public.especificaciones_prubind s where s.metodo_id = m.id);

-- Plantillas: Seguridad y Mantenimiento en los 5 tipos ("obligatorio" = sugerido)
insert into public.plantilla_evaluacion_prubind (tipo, metodo_id, obligatorio, nivel, orden, activo)
select t.tipo, m.id, x.sugerido, 'corrida', x.orden, true
from (values
  ('SEG-EPP', true, 70), ('SEG-RIESGO', true, 71), ('SEG-COND', true, 72), ('SEG-INC', true, 73),
  ('SEG-LOTO', false, 74), ('SEG-SENAL', false, 75), ('SEG-ERGO', false, 76), ('SEG-ORDEN', false, 77), ('SEG-RESID', false, 78),
  ('EQ-FUNC', true, 80), ('MANT-PAROS', true, 81), ('MANT-RUIDO', true, 82), ('MANT-AJUSTE', false, 83), ('MANT-DESG', false, 84),
  ('MANT-FUGAS', false, 85), ('EQ-PARAM', false, 86), ('EQ-INST', false, 87), ('EQ-LIMP', false, 88)
) x(codigo, sugerido, orden)
join public.metodos_prubind m on m.codigo = x.codigo
cross join (values ('producto_nuevo'), ('cambio_formulacion'), ('cambio_proveedor'), ('material_empaque'), ('cambio_proceso')) t(tipo)
on conflict (tipo, metodo_id) do update set obligatorio = excluded.obligatorio, nivel = excluded.nivel, orden = excluded.orden, activo = true;
insert into public.plantilla_evaluacion_prubind (tipo, metodo_id, obligatorio, nivel, orden, activo)
select 'material_empaque', m.id, true, 'corrida', x.orden, true
from (values ('MANT-ULMA-TF', 79), ('MANT-ULMA-TS', 79), ('MANT-ULMA-AV', 79)) x(codigo, orden)
join public.metodos_prubind m on m.codigo = x.codigo
on conflict (tipo, metodo_id) do update set obligatorio = true, activo = true;

-- 2. El registro ya no pide equipo (ni número de batches)
update public.tipos_prueba_prubind set campos_registro = array_remove(campos_registro, 'equipo'), equipo_id = null
where codigo in ('material_empaque', 'cambio_proceso');

-- 3. Terminar el registro en proceso: basta con haber registrado algún dato
do $$
declare d text; n text;
begin
  select pg_get_functiondef('public.prubind_accion(uuid,text,jsonb)'::regprocedure) into d;
  n := replace(d, $r$if (e ->> 'batches')::int = 0 then raise exception 'Registre al menos un batch.' using errcode = 'P0001'; end if;$r$,
                  $r$if (e ->> 'batches')::int = 0 and (e ->> 'resultados')::int = 0 then raise exception 'Registre al menos un dato de la prueba.' using errcode = 'P0001'; end if;$r$);
  if n = d then raise exception 'No se encontró la regla de batches en prubind_accion'; end if;
  execute n;
end $$;

-- 4. Panel: evaluaciones por área en el periodo
do $$
declare d text; n text;
begin
  select pg_get_functiondef('public.prubind_dashboard(date,date)'::regprocedure) into d;
  n := replace(d, $r$'serie', coalesce($r$,
    $r$'evaluaciones_por_area', coalesce((select jsonb_agg(jsonb_build_object('area', area, 'cumple', c, 'no_cumple', nc) order by array_position(array['calidad','produccion','seguridad','mantenimiento'], area))
         from (select e.area, count(*) filter (where e.evaluacion = 'cumple') c, count(*) filter (where e.evaluacion = 'no_cumple') nc
                 from public.evaluaciones_prubind e
                where (e.updated_at at time zone 'America/Mexico_City')::date between p_desde and p_hasta group by e.area) s), '[]'::jsonb),
    'serie', coalesce($r$);
  if n = d then raise exception 'No se encontró el punto de inserción en prubind_dashboard'; end if;
  execute n;
end $$;
