-- NOTA (v5.0): reglas anteriores. Desde v5 la prueba se inicia con "Iniciar prueba" antes de registrar datos
-- y participan solo las áreas que registran; las reglas vigentes se prueban en pruebas_flujo_v5.sql.
-- =====================================================================
-- v4.1 · Cada área define sus parámetros; Seguridad y Mantenimiento no
-- detienen la prueba; alta rápida de catálogos. Todo se REVIERTE.
-- =====================================================================
create or replace function pg_temp.como(p_email text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claims', json_build_object('role','authenticated','email',p_email)::text, true); end $$;
create or replace function pg_temp.falla(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return null; exception when others then return sqlerrm; end $$;
create or replace function pg_temp.met(p_cod text) returns uuid language sql as $$ select id from public.metodos_prubind where codigo = p_cod $$;
create or replace function pg_temp.t() returns text language plpgsql as $$
declare r text := ''; ok int := 0; ko int := 0; m text; p uuid; ld uuid; b uuid; mu uuid; prov uuid; prov2 uuid; e jsonb;
  pl_ph uuid; pl_mer uuid; pl_seg uuid;
begin
begin
  execute 'set local role authenticated';
  perform pg_temp.como('laura.vasquez@petstable.mx');
  insert into public.pruebas_prubind (tipo, cambio, objetivo_desc, batches_planeados, registrado_por) values ('cambio_proveedor', 'Prueba v41', 'Objetivo', 1, gen_random_uuid()) returning id into p;
  m := pg_temp.falla(format('select public.prubind_definir_parametros(%L, array[%L]::uuid[])', p, pg_temp.met('FQ-PH')));
  if m ilike '%responsable de esa área%' then ok:=ok+1; r:=r||E'\n✔ Compras no define parámetros de Calidad'; else ko:=ko+1; r:=r||E'\n✘ '||coalesce(m,'definió'); end if;
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L, %L::jsonb)', p, 'agregar_parametros', jsonb_build_object('metodos', jsonb_build_array(pg_temp.met('FQ-PH')))));
  if m is not null then ok:=ok+1; r:=r||E'\n✔ la acción genérica aplica la misma regla'; else ko:=ko+1; r:=r||E'\n✘ acción genérica permitió'; end if;
  perform public.prubind_areas_involucradas(p, array['seguridad']);
  perform pg_temp.como('abigail.ordaz@petstable.mx');
  if exists (select 1 from public.prubind_mis_pendientes() x where x.prueba_id = p and x.accion = 'definir') then ok:=ok+1; r:=r||E'\n✔ la Jefa de Calidad ve "definir parámetros"'; else ko:=ko+1; r:=r||E'\n✘ pendiente definir'; end if;
  perform public.prubind_definir_parametros(p, array[pg_temp.met('FQ-PH')]);
  m := pg_temp.falla(format('select public.prubind_definir_parametros(%L, array[%L]::uuid[])', p, pg_temp.met('PROD-MERMA')));
  if m is not null then ok:=ok+1; r:=r||E'\n✔ Calidad no define parámetros de Producción'; else ko:=ko+1; r:=r||E'\n✘ calidad definió producción'; end if;
  perform pg_temp.como('juan.rodriguez@petstable.mx');
  perform public.prubind_definir_parametros(p, array[pg_temp.met('PROD-MERMA')]);
  -- Seguridad involucrada con un parámetro que nadie registra (nadie tiene ese puesto aún)
  perform set_config('prubind.rpc', '1', true);
  insert into public.plan_evaluacion_prubind (prueba_id, metodo_id, nivel) values (p, pg_temp.met('SEG-EPP'), 'corrida') returning id into pl_seg;
  perform set_config('prubind.rpc', '', true);
  select id into pl_ph from public.plan_evaluacion_prubind where prueba_id = p and metodo_id = pg_temp.met('FQ-PH');
  select id into pl_mer from public.plan_evaluacion_prubind where prueba_id = p and metodo_id = pg_temp.met('PROD-MERMA');
  perform pg_temp.como('abigail.ordaz@petstable.mx');
  insert into public.lotes_diarios_prubind (prueba_id, codigo, fecha) values (p, 'L-1', public.prubind_hoy()) returning id into ld;
  insert into public.batches_prubind (prueba_id, lote_diario_id, numero, fecha_hora, resultado_op) values (p, ld, 0, now(), 'conforme') returning id into b;
  insert into public.muestras_prubind (prueba_id, nivel, batch_id, codigo, fecha_muestreo) values (p, 'batch', b, '', public.prubind_hoy()) returning id into mu;
  insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, valor_num, capturado_por) values (p, pl_ph, mu, pg_temp.met('FQ-PH'), 6, gen_random_uuid());
  perform pg_temp.como('juan.rodriguez@petstable.mx');
  insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, valor_num, capturado_por) values (p, pl_mer, mu, pg_temp.met('PROD-MERMA'), 2, gen_random_uuid());
  perform public.prubind_accion(p, 'terminar_ejecucion');
  insert into public.evaluaciones_prubind (prueba_id, plan_id, area, evaluacion, observaciones, evaluado_por) values (p, pl_mer, 'produccion', 'cumple', '', gen_random_uuid());
  insert into public.recomendaciones_prubind (prueba_id, area, sentido, recomendacion, emitido_por) values (p, 'produccion', 'favorable', 'Sin cambios', gen_random_uuid());
  perform pg_temp.como('abigail.ordaz@petstable.mx');
  insert into public.evaluaciones_prubind (prueba_id, plan_id, area, evaluacion, observaciones, evaluado_por) values (p, pl_ph, 'calidad', 'cumple', '', gen_random_uuid());
  insert into public.recomendaciones_prubind (prueba_id, area, sentido, recomendacion, emitido_por) values (p, 'calidad', 'favorable', 'Sin cambios', gen_random_uuid());
  e := public.prubind_eval_estado(p);
  perform public.prubind_accion(p, 'enviar_dictamen');
  if (select estado from public.pruebas_prubind where id = p) = 'pendiente_dictamen' and (e->>'opcionales_pendientes')::int = 1
    then ok:=ok+1; r:=r||E'\n✔ Seguridad sin registrar no detiene la prueba (pasa a dictamen; queda señalada)';
    else ko:=ko+1; r:=r||E'\n✘ dictamen: '||e::text; end if;
  perform pg_temp.como('camila@petstable.mx');
  perform public.prubind_accion(p, 'dictaminar', '{"dictamen":"aprobada"}');
  if (select estado from public.pruebas_prubind where id = p) = 'aprobada' then ok:=ok+1; r:=r||E'\n✔ Alta Dirección aprueba'; else ko:=ko+1; r:=r||E'\n✘ aprobar'; end if;
  perform pg_temp.como('laura.vasquez@petstable.mx');
  prov := public.prubind_alta_rapida('proveedor', 'Proveedor Prueba V41');
  prov2 := public.prubind_alta_rapida('proveedor', 'proveedor prueba v41 ');
  if prov = prov2 and public.prubind_alta_rapida('receta', 'Receta Prueba V41') is not null and public.prubind_alta_rapida('materia_prima', 'MP Prueba V41') is not null
    then ok:=ok+1; r:=r||E'\n✔ alta rápida de proveedor, receta y materia prima (sin duplicar)'; else ko:=ko+1; r:=r||E'\n✘ alta rápida'; end if;
  if (select nombre from public.metodos_prubind where codigo='MIC-SALM') = 'Salmonella 25 g (PCR)' then ok:=ok+1; r:=r||E'\n✔ Salmonella 25 g (PCR)'; else ko:=ko+1; end if;
  raise exception 'ROLLBACK';
exception when others then if sqlerrm <> 'ROLLBACK' then ko:=ko+1; r:=r||E'\n✘ ERROR: '||sqlerrm; end if;
end;
return format('Correctas: %s · Fallidas: %s', ok, ko) || r;
end $$;
select pg_temp.t();
