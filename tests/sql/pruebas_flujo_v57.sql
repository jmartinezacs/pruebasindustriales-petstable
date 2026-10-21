-- =====================================================================
-- v5.7 · Registro unificado (el inspector crea batches con su número) y
-- evaluación solo con la prueba terminada. Todo se REVIERTE.
-- =====================================================================
create or replace function pg_temp.como(p_email text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claims', json_build_object('role','authenticated','email',p_email)::text, true); end $$;
create or replace function pg_temp.falla(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return null; exception when others then return sqlerrm; end $$;
create or replace function pg_temp.met(p_cod text) returns uuid language sql as $$ select id from public.metodos_prubind where codigo = p_cod $$;
create or replace function pg_temp.t() returns text language plpgsql as $$
declare r text := ''; ok int := 0; ko int := 0; m text; p uuid; lote uuid; b29 uuid; b30 uuid; mu29 uuid; mu30 uuid; pl_ph uuid;
begin
begin
  execute 'set local role authenticated';
  perform pg_temp.como('laura.vasquez@petstable.mx');
  insert into public.pruebas_prubind (tipo, cambio, objetivo_desc, registrado_por, fecha_planeada)
  values ('cambio_formulacion', 'Prueba v5.7', 'Objetivo', gen_random_uuid(), public.prubind_hoy()) returning id into p;
  perform pg_temp.como('abigail.ordaz@petstable.mx');
  perform public.prubind_definir_parametros(p, array[pg_temp.met('FQ-PH')]);
  select id into pl_ph from public.plan_evaluacion_prubind where prueba_id = p;
  perform pg_temp.como('laura.vasquez@petstable.mx');
  perform public.prubind_accion(p, 'iniciar');

  -- El inspector registra pH por batch: se crean el lote del día y los batches 29 y 30 con su número
  perform pg_temp.como('jose.cabrera@petstable.mx');
  insert into public.lotes_diarios_prubind (prueba_id, codigo, fecha) values (p, 'L-TEST', public.prubind_hoy()) returning id into lote;
  insert into public.batches_prubind (prueba_id, lote_diario_id, numero, fecha_hora, resultado_op) values (p, lote, 29, now(), 'conforme') returning id into b29;
  insert into public.batches_prubind (prueba_id, lote_diario_id, numero, fecha_hora, resultado_op) values (p, lote, 30, now(), 'conforme') returning id into b30;
  insert into public.muestras_prubind (prueba_id, nivel, codigo, fecha_muestreo, batch_id) values (p, 'batch', '', public.prubind_hoy(), b29) returning id into mu29;
  insert into public.muestras_prubind (prueba_id, nivel, codigo, fecha_muestreo, batch_id) values (p, 'batch', '', public.prubind_hoy(), b30) returning id into mu30;
  insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, valor_num, capturado_por) values (p, pl_ph, mu29, pg_temp.met('FQ-PH'), 6.1, gen_random_uuid());
  if (select array_agg(numero order by numero) from public.batches_prubind where prueba_id = p) = array[29, 30] then ok:=ok+1; r:=r||E'\n✔ el inspector crea los batches 29 y 30 con su número'; else ko:=ko+1; r:=r||E'\n✘ batches'; end if;
  -- El batch 30 quedó sin datos (número mal escrito): se quita
  delete from public.muestras_prubind where id = mu30;
  delete from public.batches_prubind where id = b30;
  if not exists (select 1 from public.batches_prubind where id = b30) then ok:=ok+1; r:=r||E'\n✔ un batch sin datos se puede quitar'; else ko:=ko+1; r:=r||E'\n✘ quitar batch'; end if;

  -- No se evalúa ni se da veredicto antes de terminar
  perform pg_temp.como('abigail.ordaz@petstable.mx');
  m := pg_temp.falla(format($s$insert into public.evaluaciones_prubind (prueba_id, plan_id, area, evaluacion, observaciones, evaluado_por) values (%L, %L, 'calidad', 'cumple', '', gen_random_uuid())$s$, p, pl_ph));
  if m ilike '%se termina%' then ok:=ok+1; r:=r||E'\n✔ no se evalúa con la prueba en proceso'; else ko:=ko+1; r:=r||E'\n✘ '||coalesce(m,'evaluó en proceso'); end if;
  if not exists (select 1 from public.prubind_mis_pendientes() x where x.prueba_id = p and x.accion = 'evaluar') then ok:=ok+1; r:=r||E'\n✔ "Evaluar" no aparece en pendientes hasta terminar'; else ko:=ko+1; r:=r||E'\n✘ pendiente evaluar en proceso'; end if;

  perform pg_temp.como('laura.vasquez@petstable.mx');
  perform public.prubind_accion(p, 'terminar_ejecucion');
  perform pg_temp.como('abigail.ordaz@petstable.mx');
  if exists (select 1 from public.prubind_mis_pendientes() x where x.prueba_id = p and x.accion = 'evaluar') then ok:=ok+1; r:=r||E'\n✔ al terminar, el Jefe de Calidad ve "Evaluar"'; else ko:=ko+1; r:=r||E'\n✘ pendiente evaluar al terminar'; end if;
  insert into public.evaluaciones_prubind (prueba_id, plan_id, area, evaluacion, observaciones, evaluado_por) values (p, pl_ph, 'calidad', 'cumple', '', gen_random_uuid());
  insert into public.recomendaciones_prubind (prueba_id, area, sentido, recomendacion, emitido_por) values (p, 'calidad', 'favorable', 'Satisfactoria', gen_random_uuid());
  ok:=ok+1; r:=r||E'\n✔ con la prueba terminada evalúa y da su veredicto';
  raise exception 'ROLLBACK';
exception when others then
  if sqlerrm = 'ROLLBACK' then null;
  else ko:=ko+1; r:=r||E'\n✘ ERROR: '||sqlerrm; end if;
end;
return format('Correctas: %s · Fallidas: %s', ok, ko) || r;
end $$;
select pg_temp.t();
