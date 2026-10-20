-- NOTA (v5.0): reglas anteriores. Desde v5 la prueba se inicia con "Iniciar prueba" antes de registrar datos
-- y participan solo las áreas que registran; las reglas vigentes se prueban en pruebas_flujo_v5.sql.
-- =====================================================================
-- Pruebas del flujo por áreas (v4) con los usuarios y puestos reales.
-- Todo se REVIERTE. Ejecutar completo en Supabase → SQL Editor; el
-- resultado se devuelve como texto.
-- =====================================================================
create or replace function pg_temp.como(p_email text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claims', json_build_object('role','authenticated','email',p_email)::text, true); end $$;
create or replace function pg_temp.falla(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return null; exception when others then return sqlerrm; end $$;
create or replace function pg_temp.met(p_cod text) returns uuid language sql as $$ select id from public.metodos_prubind where codigo = p_cod $$;

create or replace function pg_temp.flujo() returns text language plpgsql as $$
declare
  r text := ''; ok int := 0; ko int := 0; m text;
  p uuid; ld uuid; b1 uuid; mu uuid; mc uuid; st text; v_folio text; v_nuevo uuid; n int; e jsonb;
  pl_ph uuid; pl_temp uuid; pl_merma uuid; pl_salm uuid; pl_seg uuid; pl_nuevo uuid;

begin
begin
  execute 'set local role authenticated';

  -- 1. Registro (cualquier persona): el objetivo es obligatorio
  perform pg_temp.como('laura.vasquez@petstable.mx');
  m := pg_temp.falla($q$insert into public.pruebas_prubind (tipo, cambio, registrado_por) values ('cambio_proveedor', 'Harina de arroz proveedor B', gen_random_uuid())$q$);
  if m ilike '%objetivo%' then ok := ok + 1; r := r || E'\n✔ sin objetivo no se registra'; else ko := ko + 1; r := r || E'\n✘ objetivo: ' || coalesce(m, 'se registró'); end if;
  m := pg_temp.falla($q$insert into public.pruebas_prubind (tipo, cambio, objetivo_desc, registrado_por) values ('vida_util', 'x', 'y', gen_random_uuid())$q$);
  if m ilike '%no está activo%' then ok := ok + 1; r := r || E'\n✔ tipos fuera de los 5 principales ya no se registran'; else ko := ko + 1; r := r || E'\n✘ vida_util: ' || coalesce(m, 'se registró'); end if;
  insert into public.pruebas_prubind (tipo, cambio, objetivo_desc, fecha_planeada, batches_planeados, cantidad_evaluar, cantidad_unidad_id, registrado_por)
  values ('cambio_proveedor', 'Harina de arroz proveedor B', 'Verificar que la harina del proveedor B no afecte merma ni calidad', public.prubind_hoy(), 2,
          500, (select id from public.unidades_prubind where simbolo = 'kg'), gen_random_uuid())
  returning id, folio, estado into p, v_folio, st;
  if st = 'registrada' then ok := ok + 1; r := r || E'\n✔ Gerente de Compras registra ' || v_folio || ' (fecha, objetivo, batches, cantidad)'; else ko := ko + 1; r := r || E'\n✘ registro'; end if;

  -- 2. Parámetros a evaluar por área, desde el registro
  perform public.prubind_accion(p, 'agregar_parametros', jsonb_build_object('metodos', jsonb_build_array(
    pg_temp.met('FQ-PH'), pg_temp.met('FQ-TEMP'), pg_temp.met('PROD-MERMA'), pg_temp.met('MIC-SALM'), pg_temp.met('SEG-EPP'))));
  v_nuevo := public.prubind_nuevo_parametro('Tiempo de enfriamiento', 'produccion', 'numerico', (select id from public.unidades_prubind where simbolo = 'min'), 'cambio_proveedor');
  perform public.prubind_accion(p, 'agregar_parametros', jsonb_build_object('metodos', jsonb_build_array(v_nuevo)));
  select id into pl_ph from public.plan_evaluacion_prubind where prueba_id = p and metodo_id = pg_temp.met('FQ-PH');
  select id into pl_temp from public.plan_evaluacion_prubind where prueba_id = p and metodo_id = pg_temp.met('FQ-TEMP');
  select id into pl_merma from public.plan_evaluacion_prubind where prueba_id = p and metodo_id = pg_temp.met('PROD-MERMA');
  select id into pl_salm from public.plan_evaluacion_prubind where prueba_id = p and metodo_id = pg_temp.met('MIC-SALM');
  select id into pl_seg from public.plan_evaluacion_prubind where prueba_id = p and metodo_id = pg_temp.met('SEG-EPP');
  select id into pl_nuevo from public.plan_evaluacion_prubind where prueba_id = p and metodo_id = v_nuevo;
  if public.prubind_areas_prueba(p) = array['calidad','produccion','seguridad'] and pl_nuevo is not null
     and (select nivel from public.plan_evaluacion_prubind where id = pl_seg) = 'corrida' and (select nivel from public.plan_evaluacion_prubind where id = pl_ph) = 'batch'
     and exists (select 1 from public.plantilla_evaluacion_prubind where tipo = 'cambio_proveedor' and metodo_id = v_nuevo and activo)
    then ok := ok + 1; r := r || E'\n✔ parámetros por área (Calidad, Producción, Seguridad) y parámetro nuevo guardado en catálogo y plantilla';
    else ko := ko + 1; r := r || E'\n✘ parámetros: ' || array_to_string(public.prubind_areas_prueba(p), ','); end if;

  -- Pendientes: Producción ve "capturar"; Compras no
  perform pg_temp.como('juan.rodriguez@petstable.mx');
  if exists (select 1 from public.prubind_mis_pendientes() x where x.prueba_id = p and x.accion = 'capturar') then ok := ok + 1; r := r || E'\n✔ el Gerente de Producción la ve como pendiente de capturar'; else ko := ko + 1; r := r || E'\n✘ pendiente de Producción'; end if;

  -- 3. Registro durante el proceso
  perform pg_temp.como('laura.vasquez@petstable.mx');
  m := pg_temp.falla(format($q$insert into public.lotes_diarios_prubind (prueba_id, codigo, fecha) values (%L, 'L-1', current_date)$q$, p));
  if m is not null then ok := ok + 1; r := r || E'\n✔ Compras no captura datos del proceso'; else ko := ko + 1; r := r || E'\n✘ Compras capturó'; end if;
  perform pg_temp.como('abigail.ordaz@petstable.mx');
  insert into public.lotes_diarios_prubind (prueba_id, codigo, fecha) values (p, 'L-1', public.prubind_hoy()) returning id into ld;
  insert into public.batches_prubind (prueba_id, lote_diario_id, numero, fecha_hora, resultado_op) values (p, ld, 0, now(), 'conforme') returning id into b1;
  insert into public.muestras_prubind (prueba_id, nivel, batch_id, codigo, fecha_muestreo) values (p, 'batch', b1, '', public.prubind_hoy()) returning id into mu;
  insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, valor_num, capturado_por) values (p, pl_ph, mu, pg_temp.met('FQ-PH'), 6.2, gen_random_uuid());
  insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, valor_opcion, capturado_por) values (p, pl_salm, mu, pg_temp.met('MIC-SALM'), 'ausencia', gen_random_uuid());
  select estado into st from public.pruebas_prubind where id = p;
  if st = 'en_ejecucion' then ok := ok + 1; r := r || E'\n✔ Calidad (Jefe/Inspector) captura pH y Salmonella; la prueba pasa a "en proceso" sin preparación'; else ko := ko + 1; r := r || E'\n✘ estado ' || st; end if;
  m := pg_temp.falla(format($q$insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, valor_num, capturado_por) values (%L, %L, %L, %L, 2, gen_random_uuid())$q$, p, pl_merma, mu, pg_temp.met('PROD-MERMA')));
  if m ilike '%Produccion%' then ok := ok + 1; r := r || E'\n✔ Calidad no captura parámetros de Producción'; else ko := ko + 1; r := r || E'\n✘ Calidad capturó merma: ' || coalesce(m, 'sí'); end if;
  perform pg_temp.como('juan.rodriguez@petstable.mx');
  insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, valor_num, capturado_por) values (p, pl_merma, mu, pg_temp.met('PROD-MERMA'), 2.5, gen_random_uuid());
  insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, valor_num, capturado_por) values (p, pl_nuevo, mu, v_nuevo, 18, gen_random_uuid());
  ok := ok + 1; r := r || E'\n✔ Producción captura merma y el parámetro nuevo';
  -- Seguridad: nadie tiene ese puesto aún → el registrante quita el parámetro (sin resultados)
  perform pg_temp.como('abigail.ordaz@petstable.mx');
  insert into public.muestras_prubind (prueba_id, nivel, codigo, fecha_muestreo) values (p, 'corrida', '', public.prubind_hoy()) returning id into mc;
  m := pg_temp.falla(format($q$insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, valor_opcion, capturado_por) values (%L, %L, %L, %L, 'conforme', gen_random_uuid())$q$, p, pl_seg, mc, pg_temp.met('SEG-EPP')));
  if m ilike '%Seguridad%' then ok := ok + 1; r := r || E'\n✔ Calidad no captura parámetros de Seguridad'; else ko := ko + 1; r := r || E'\n✘ seguridad: ' || coalesce(m, 'capturó'); end if;
  perform pg_temp.como('laura.vasquez@petstable.mx');
  perform public.prubind_accion(p, 'quitar_parametro', jsonb_build_object('plan_id', pl_seg));
  m := pg_temp.falla(format($q$update public.pruebas_prubind set cambio = 'otro' where id = %L$q$, p));
  if public.prubind_areas_prueba(p) = array['calidad','produccion'] and m is not null
    then ok := ok + 1; r := r || E'\n✔ se quita un parámetro sin resultados; el registro ya no se edita una vez iniciada la captura';
    else ko := ko + 1; r := r || E'\n✘ quitar/editar: ' || coalesce(m, 'editó'); end if;

  perform pg_temp.como('abigail.ordaz@petstable.mx');
  perform public.prubind_accion(p, 'terminar_ejecucion');
  select estado into st from public.pruebas_prubind where id = p;
  if st = 'en_evaluacion' then ok := ok + 1; r := r || E'\n✔ termina el registro durante el proceso → resultados'; else ko := ko + 1; r := r || E'\n✘ terminar: ' || st; end if;

  -- 4/5. Resultados: cada jefe evalúa su área (Cumple / No cumple + observaciones)
  perform pg_temp.como('juan.rodriguez@petstable.mx');
  m := pg_temp.falla(format($q$insert into public.evaluaciones_prubind (prueba_id, plan_id, area, evaluacion, observaciones, evaluado_por) values (%L, %L, 'calidad', 'cumple', '', gen_random_uuid())$q$, p, pl_ph));
  if m is not null then ok := ok + 1; r := r || E'\n✔ Producción no evalúa parámetros de Calidad'; else ko := ko + 1; r := r || E'\n✘ Producción evaluó Calidad'; end if;
  perform pg_temp.como('abigail.ordaz@petstable.mx');
  m := pg_temp.falla(format($q$insert into public.evaluaciones_prubind (prueba_id, plan_id, area, evaluacion, observaciones, evaluado_por) values (%L, %L, 'calidad', 'no_cumple', '', gen_random_uuid())$q$, p, pl_ph));
  if m ilike '%no cumple%' then ok := ok + 1; r := r || E'\n✔ "No cumple" exige explicar por qué'; else ko := ko + 1; r := r || E'\n✘ no cumple sin obs: ' || coalesce(m, 'aceptado'); end if;
  insert into public.evaluaciones_prubind (prueba_id, plan_id, area, evaluacion, observaciones, evaluado_por) values (p, pl_ph, 'calidad', 'no_cumple', 'pH por arriba de lo habitual', gen_random_uuid());
  insert into public.evaluaciones_prubind (prueba_id, plan_id, area, evaluacion, observaciones, evaluado_por) values (p, pl_salm, 'calidad', 'cumple', '', gen_random_uuid());
  if (select observaciones from public.evaluaciones_prubind where plan_id = pl_salm) = 'Sin observaciones' then ok := ok + 1; r := r || E'\n✔ "Cumple" queda "Sin observaciones" de forma predeterminada'; else ko := ko + 1; r := r || E'\n✘ obs predeterminada'; end if;
  m := pg_temp.falla(format($q$insert into public.evaluaciones_prubind (prueba_id, plan_id, area, evaluacion, observaciones, evaluado_por) values (%L, %L, 'calidad', 'cumple', '', gen_random_uuid())$q$, p, pl_temp));
  if m ilike '%resultado%' then ok := ok + 1; r := r || E'\n✔ no se evalúa un parámetro sin resultado'; else ko := ko + 1; r := r || E'\n✘ evaluó sin resultado: ' || coalesce(m, 'sí'); end if;
  -- La temperatura se completa en esta etapa; cambiar un valor anula su evaluación
  insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, valor_num, capturado_por) values (p, pl_temp, mu, pg_temp.met('FQ-TEMP'), 82, gen_random_uuid());
  update public.resultados_prubind set valor_num = 6.0 where plan_id = pl_ph;
  if not exists (select 1 from public.evaluaciones_prubind where plan_id = pl_ph) then ok := ok + 1; r := r || E'\n✔ si cambia un resultado, su evaluación se vuelve a hacer'; else ko := ko + 1; r := r || E'\n✘ evaluación no se anuló'; end if;
  insert into public.evaluaciones_prubind (prueba_id, plan_id, area, evaluacion, observaciones, evaluado_por) values (p, pl_ph, 'calidad', 'no_cumple', 'pH por arriba de lo habitual', gen_random_uuid());
  insert into public.evaluaciones_prubind (prueba_id, plan_id, area, evaluacion, observaciones, evaluado_por) values (p, pl_temp, 'calidad', 'cumple', 'Sin observaciones', gen_random_uuid());

  -- 6. Recomendaciones por área
  perform pg_temp.como('juan.rodriguez@petstable.mx');
  m := pg_temp.falla(format($q$insert into public.recomendaciones_prubind (prueba_id, area, sentido, recomendacion, emitido_por) values (%L, 'produccion', 'favorable', 'Sin cambios en merma', gen_random_uuid())$q$, p));
  if m ilike '%Evalúe primero%' then ok := ok + 1; r := r || E'\n✔ la recomendación requiere evaluar antes todos los parámetros del área'; else ko := ko + 1; r := r || E'\n✘ recomendó antes: ' || coalesce(m, 'sí'); end if;
  insert into public.evaluaciones_prubind (prueba_id, plan_id, area, evaluacion, observaciones, evaluado_por) values (p, pl_merma, 'produccion', 'cumple', '', gen_random_uuid());
  insert into public.evaluaciones_prubind (prueba_id, plan_id, area, evaluacion, observaciones, evaluado_por) values (p, pl_nuevo, 'produccion', 'cumple', '', gen_random_uuid());
  insert into public.recomendaciones_prubind (prueba_id, area, sentido, recomendacion, emitido_por) values (p, 'produccion', 'favorable', 'La merma y los tiempos no cambian; se recomienda el proveedor B.', gen_random_uuid());
  perform pg_temp.como('abigail.ordaz@petstable.mx');
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L)', p, 'enviar_dictamen'));
  if m ilike '%recomendaciones%' then ok := ok + 1; r := r || E'\n✔ no pasa a dictamen sin la recomendación de cada área'; else ko := ko + 1; r := r || E'\n✘ dictamen sin recomendaciones: ' || coalesce(m, 'pasó'); end if;
  insert into public.recomendaciones_prubind (prueba_id, area, sentido, recomendacion, emitido_por) values (p, 'calidad', 'favorable', 'pH ligeramente alto; vigilar en los primeros lotes.', gen_random_uuid());
  perform public.prubind_accion(p, 'enviar_dictamen');
  e := public.prubind_eval_estado(p);
  if (select estado from public.pruebas_prubind where id = p) = 'pendiente_dictamen' and (e ->> 'eval_faltantes')::int = 0 and (e ->> 'no_cumple')::int = 1
    then ok := ok + 1; r := r || E'\n✔ evaluaciones y recomendaciones completas → pendiente de dictamen';
    else ko := ko + 1; r := r || E'\n✘ enviar a dictamen'; end if;

  -- 7. Dictamen (Alta Dirección) y cierre
  perform pg_temp.como('juan.rodriguez@petstable.mx');
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L, %L::jsonb)', p, 'dictaminar', '{"dictamen":"aprobada","texto":"ok"}'));
  if m is not null then ok := ok + 1; r := r || E'\n✔ el Gerente de Producción no dictamina'; else ko := ko + 1; r := r || E'\n✘ Producción dictaminó'; end if;
  perform pg_temp.como('camila@petstable.mx');
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L, %L::jsonb)', p, 'dictaminar', '{"dictamen":"aprobada"}'));
  if m ilike '%no cumplen%' then ok := ok + 1; r := r || E'\n✔ aprobar con parámetros que no cumplen exige explicar la conclusión'; else ko := ko + 1; r := r || E'\n✘ aprobación sin texto: ' || coalesce(m, 'pasó'); end if;
  perform public.prubind_accion(p, 'dictaminar', '{"dictamen":"aprobada","texto":"Se aprueba; Calidad vigilará el pH."}');
  perform pg_temp.como('javier.martinez@petstable.mx');
  perform public.prubind_accion(p, 'cerrar');
  if (select estado from public.pruebas_prubind where id = p) = 'cerrada_aprobada' then ok := ok + 1; r := r || E'\n✔ Dirección dictamina y el Gerente de Procesos cierra'; else ko := ko + 1; r := r || E'\n✘ cierre'; end if;

  raise exception 'ROLLBACK_PRUEBAS';
exception when others then
  if sqlerrm <> 'ROLLBACK_PRUEBAS' then r := r || E'\n✘ ERROR INESPERADO: ' || sqlerrm; ko := ko + 1; end if;
end;
return format('Correctas: %s · Fallidas: %s', ok, ko) || r;
end $$;
select pg_temp.flujo() as resultado;
