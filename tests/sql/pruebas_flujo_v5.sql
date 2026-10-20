-- =====================================================================
-- v5.0 · Inicio explícito, áreas independientes, "sin parámetros",
-- "No se pudo determinar" y bromatológicos pendientes. Todo se REVIERTE.
-- =====================================================================
create or replace function pg_temp.como(p_email text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claims', json_build_object('role','authenticated','email',p_email)::text, true); end $$;
create or replace function pg_temp.falla(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return null; exception when others then return sqlerrm; end $$;
create or replace function pg_temp.met(p_cod text) returns uuid language sql as $$ select id from public.metodos_prubind where codigo = p_cod $$;
create or replace function pg_temp.t() returns text language plpgsql as $$
declare r text := ''; ok int := 0; ko int := 0; m text; p uuid; mu uuid; e jsonb; pl_ph uuid; pl_hum uuid; est text;
begin
begin
  execute 'set local role authenticated';
  perform pg_temp.como('laura.vasquez@petstable.mx');
  insert into public.pruebas_prubind (tipo, cambio, objetivo_desc, registrado_por) values ('cambio_formulacion', 'Prueba v5', 'Objetivo', gen_random_uuid()) returning id into p;
  if exists (select 1 from public.prubind_mis_pendientes() x where x.prueba_id = p and x.accion = 'iniciar') then ok:=ok+1; r:=r||E'\n✔ quien registra ve "Iniciar prueba"'; else ko:=ko+1; r:=r||E'\n✘ pendiente iniciar'; end if;

  perform pg_temp.como('abigail.ordaz@petstable.mx');
  perform public.prubind_definir_parametros(p, array[pg_temp.met('FQ-PH'), pg_temp.met('BRO-HUM')]);
  select id into pl_ph from public.plan_evaluacion_prubind where prueba_id = p and metodo_id = pg_temp.met('FQ-PH');
  select id into pl_hum from public.plan_evaluacion_prubind where prueba_id = p and metodo_id = pg_temp.met('BRO-HUM');
  m := pg_temp.falla(format($s$insert into public.muestras_prubind (prueba_id, nivel, codigo, fecha_muestreo) values (%L, 'corrida', '', public.prubind_hoy())$s$, p));
  if m is not null then ok:=ok+1; r:=r||E'\n✔ no se registran datos antes de iniciar'; else ko:=ko+1; r:=r||E'\n✘ registró antes de iniciar'; end if;
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L, %L::jsonb)', p, 'iniciar', '{}'));
  if m is not null then ok:=ok+1; r:=r||E'\n✔ solo quien registra inicia la prueba'; else ko:=ko+1; r:=r||E'\n✘ Calidad inició'; end if;

  perform pg_temp.como('juan.rodriguez@petstable.mx');
  if exists (select 1 from public.prubind_mis_pendientes() x where x.prueba_id = p and x.accion = 'definir' and x.area = 'produccion') then ok:=ok+1; r:=r||E'\n✔ Producción ve "definir parámetros" de su área'; else ko:=ko+1; r:=r||E'\n✘ pendiente definir producción'; end if;
  perform public.prubind_area_sin_parametros(p, 'produccion', 'No cambia el proceso');
  if not exists (select 1 from public.prubind_mis_pendientes() x where x.prueba_id = p and x.accion = 'definir' and x.area = 'produccion')
     and (public.prubind_eval_estado(p) -> 'sin_parametros') ? 'produccion' then ok:=ok+1; r:=r||E'\n✔ "Nada que evaluar por mi área" quita el pendiente'; else ko:=ko+1; r:=r||E'\n✘ sin parámetros'; end if;
  m := pg_temp.falla(format('select public.prubind_area_sin_parametros(%L, %L)', p, 'calidad'));
  if m is not null then ok:=ok+1; r:=r||E'\n✔ Producción no lo indica por Calidad'; else ko:=ko+1; r:=r||E'\n✘ marcó calidad'; end if;

  perform pg_temp.como('laura.vasquez@petstable.mx');
  perform public.prubind_accion(p, 'iniciar');
  if (select estado from public.pruebas_prubind where id = p) = 'en_ejecucion' and public.prubind_estado_txt('en_ejecucion') = 'En proceso' then ok:=ok+1; r:=r||E'\n✔ iniciar → "En proceso"'; else ko:=ko+1; r:=r||E'\n✘ iniciar'; end if;

  perform pg_temp.como('abigail.ordaz@petstable.mx');
  insert into public.muestras_prubind (prueba_id, nivel, codigo, fecha_muestreo) values (p, 'corrida', '', public.prubind_hoy()) returning id into mu;
  insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, valor_num, capturado_por) values (p, pl_ph, mu, pg_temp.met('FQ-PH'), 6, gen_random_uuid());
  -- Evalúa y da su veredicto mientras la prueba sigue en proceso; la humedad (laboratorio) queda pendiente
  m := pg_temp.falla(format($s$insert into public.evaluaciones_prubind (prueba_id, plan_id, area, evaluacion, observaciones, evaluado_por) values (%L, %L, 'calidad', 'cumple', '', gen_random_uuid())$s$, p, pl_hum));
  if m ilike '%No se pudo determinar%' then ok:=ok+1; r:=r||E'\n✔ sin resultado no se marca Cumple'; else ko:=ko+1; r:=r||E'\n✘ '||coalesce(m,'marcó cumple sin resultado'); end if;
  m := pg_temp.falla(format($s$insert into public.evaluaciones_prubind (prueba_id, plan_id, area, evaluacion, observaciones, evaluado_por) values (%L, %L, 'calidad', 'no_determinado', '', gen_random_uuid())$s$, p, pl_hum));
  if m ilike '%no se pudo determinar%' then ok:=ok+1; r:=r||E'\n✔ "No se pudo determinar" pide explicación'; else ko:=ko+1; r:=r||E'\n✘ '||coalesce(m,'sin explicación'); end if;
  insert into public.evaluaciones_prubind (prueba_id, plan_id, area, evaluacion, observaciones, evaluado_por) values (p, pl_ph, 'calidad', 'cumple', '', gen_random_uuid());
  e := public.prubind_eval_estado(p);
  if (e->>'eval_faltantes')::int = 0 and (e->>'sin_resultado')::int = 1 then ok:=ok+1; r:=r||E'\n✔ la humedad pendiente no detiene la evaluación'; else ko:=ko+1; r:=r||E'\n✘ '||e::text; end if;
  insert into public.recomendaciones_prubind (prueba_id, area, sentido, recomendacion, emitido_por) values (p, 'calidad', 'favorable', 'Satisfactoria', gen_random_uuid());
  ok:=ok+1; r:=r||E'\n✔ Calidad registra su veredicto con la prueba en proceso';
  m := pg_temp.falla(format($s$insert into public.recomendaciones_prubind (prueba_id, area, sentido, recomendacion, emitido_por) values (%L, 'seguridad', 'favorable', 'x x x', gen_random_uuid())$s$, p));
  if m is not null then ok:=ok+1; r:=r||E'\n✔ un área sin datos no registra veredicto'; else ko:=ko+1; r:=r||E'\n✘ veredicto sin datos'; end if;

  perform pg_temp.como('laura.vasquez@petstable.mx');
  perform public.prubind_accion(p, 'terminar_ejecucion');
  select estado into est from public.pruebas_prubind where id = p;
  e := public.prubind_eval_estado(p);
  if est = 'pendiente_dictamen' and e->'participantes' = '["calidad"]'::jsonb then ok:=ok+1; r:=r||E'\n✔ al terminar pasa sola a dictamen: solo participó Calidad'; else ko:=ko+1; r:=r||E'\n✘ terminar: '||est||' '||e::text; end if;

  perform pg_temp.como('camila@petstable.mx');
  if exists (select 1 from public.prubind_mis_pendientes() x where x.prueba_id = p and x.accion = 'dictaminar') then ok:=ok+1; r:=r||E'\n✔ Alta Dirección ve "Emitir dictamen"'; else ko:=ko+1; r:=r||E'\n✘ pendiente dictamen'; end if;
  if (select count(*) from public.prubind_destinatarios_aviso(p, 'lista_dictamen')) = 0 then
    -- authenticated no puede ejecutarla (solo service_role)
    ko:=ko+1; r:=r||E'\n✘ destinatarios visibles para authenticated';
  end if;
  raise exception 'ROLLBACK';
exception when others then
  if sqlerrm = 'ROLLBACK' then null;
  elsif sqlerrm ilike '%permission denied for function prubind_destinatarios_aviso%' then ok:=ok+1; r:=r||E'\n✔ los destinatarios de avisos solo los consulta el servidor';
  else ko:=ko+1; r:=r||E'\n✘ ERROR: '||sqlerrm; end if;
end;
return format('Correctas: %s · Fallidas: %s', ok, ko) || r;
end $$;
select pg_temp.t();
