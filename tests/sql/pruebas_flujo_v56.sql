-- =====================================================================
-- v5.6 · Permisos por puesto, valores "Pendiente", evaluación durante el
-- proceso, rango de fechas, terminado automático, dictamen que completa
-- pendientes y evidencia por parámetro. Todo se REVIERTE.
-- =====================================================================
create or replace function pg_temp.como(p_email text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claims', json_build_object('role','authenticated','email',p_email)::text, true); end $$;
create or replace function pg_temp.falla(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return null; exception when others then return sqlerrm; end $$;
create or replace function pg_temp.met(p_cod text) returns uuid language sql as $$ select id from public.metodos_prubind where codigo = p_cod $$;
create or replace function pg_temp.t() returns text language plpgsql as $$
declare r text := ''; ok int := 0; ko int := 0; m text; p uuid; mu uuid; e jsonb; pl_ph uuid; pl_hum uuid; pl_epp uuid; est text; rid uuid;
begin
begin
  execute 'set local role authenticated';

  -- Parámetros: solo el responsable del área los define o crea
  perform pg_temp.como('laura.vasquez@petstable.mx');
  m := pg_temp.falla(format($s$insert into public.pruebas_prubind (tipo, cambio, objetivo_desc, registrado_por, fecha_planeada, fecha_fin) values ('cambio_formulacion', 'x', 'x', gen_random_uuid(), %L, %L)$s$, public.prubind_hoy(), public.prubind_hoy() - 1));
  if m ilike '%fecha final%' then ok:=ok+1; r:=r||E'\n✔ la fecha final no puede ser anterior a la inicial'; else ko:=ko+1; r:=r||E'\n✘ '||coalesce(m,'aceptó rango invertido'); end if;
  insert into public.pruebas_prubind (tipo, cambio, objetivo_desc, registrado_por, fecha_planeada, fecha_fin)
  values ('cambio_formulacion', 'Prueba v5.6', 'Objetivo', gen_random_uuid(), public.prubind_hoy() - 2, public.prubind_hoy() - 1) returning id into p;

  perform pg_temp.como('julian.pacheco@petstable.mx');
  m := pg_temp.falla(format('select public.prubind_definir_parametros(%L, array[%L]::uuid[])', p, pg_temp.met('FQ-PH')));
  if m is not null then ok:=ok+1; r:=r||E'\n✔ el Ingeniero de Seguridad ya no define parámetros de Calidad'; else ko:=ko+1; r:=r||E'\n✘ Ingeniero definió Calidad'; end if;
  m := pg_temp.falla($s$select public.prubind_nuevo_parametro('Ruido en el área', 'seguridad', 'numerico')$s$);
  if m ilike '%responsable%' then ok:=ok+1; r:=r||E'\n✔ solo el responsable del área crea parámetros nuevos'; else ko:=ko+1; r:=r||E'\n✘ '||coalesce(m,'Ingeniero creó parámetro'); end if;

  perform pg_temp.como('abigail.ordaz@petstable.mx');
  perform public.prubind_definir_parametros(p, array[pg_temp.met('FQ-PH'), pg_temp.met('BRO-HUM')]);
  perform pg_temp.como('kevin.hernandez@petstable.mx');
  perform public.prubind_definir_parametros(p, array[pg_temp.met('SEG-EPP')]);
  select id into pl_ph from public.plan_evaluacion_prubind where prueba_id = p and metodo_id = pg_temp.met('FQ-PH');
  select id into pl_hum from public.plan_evaluacion_prubind where prueba_id = p and metodo_id = pg_temp.met('BRO-HUM');
  select id into pl_epp from public.plan_evaluacion_prubind where prueba_id = p and metodo_id = pg_temp.met('SEG-EPP');
  ok:=ok+1; r:=r||E'\n✔ Jefe de Calidad y Supervisor de Seguridad definen los suyos';

  perform pg_temp.como('laura.vasquez@petstable.mx');
  perform public.prubind_accion(p, 'iniciar');

  -- Captura: inspector (Calidad) y Ingeniero de Seguridad (Seguridad)
  perform pg_temp.como('jose.cabrera@petstable.mx');
  insert into public.muestras_prubind (prueba_id, nivel, codigo, fecha_muestreo) values (p, 'corrida', '', public.prubind_hoy()) returning id into mu;
  insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, valor_num, capturado_por) values (p, pl_ph, mu, pg_temp.met('FQ-PH'), 6, gen_random_uuid());
  insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, valor_num, estado, capturado_por) values (p, pl_hum, mu, pg_temp.met('BRO-HUM'), null, 'conforme', gen_random_uuid()) returning id into rid;
  if (select estado from public.resultados_prubind where id = rid) = 'pendiente' then ok:=ok+1; r:=r||E'\n✔ el inspector marca un valor como "Pendiente"'; else ko:=ko+1; r:=r||E'\n✘ marca pendiente'; end if;
  insert into public.adjuntos_prubind (prueba_id, plan_id, nombre, ruta, subido_por) values (p, pl_ph, 'foto.jpg', p::text || '/foto.jpg', gen_random_uuid());
  ok:=ok+1; r:=r||E'\n✔ evidencia ligada al parámetro';

  perform pg_temp.como('julian.pacheco@petstable.mx');
  insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, valor_opcion, capturado_por) values (p, pl_epp, mu, pg_temp.met('SEG-EPP'), 'conforme', gen_random_uuid());
  m := pg_temp.falla(format($s$update public.resultados_prubind set valor_num = 7 where plan_id = %L$s$, pl_ph));
  if m ilike '%autoridad%' then ok:=ok+1; r:=r||E'\n✔ el Ingeniero registra Seguridad pero no Calidad'; else ko:=ko+1; r:=r||E'\n✘ '||coalesce(m,'Ingeniero modificó Calidad'); end if;

  -- Durante el proceso: el Jefe de Calidad ve "Evaluar" y quien registró ve "Terminar la prueba"
  perform pg_temp.como('abigail.ordaz@petstable.mx');
  if exists (select 1 from public.prubind_mis_pendientes() x where x.prueba_id = p and x.accion = 'evaluar' and x.area = 'calidad') then ok:=ok+1; r:=r||E'\n✔ el Jefe de Calidad ve "Evaluar" con la prueba en proceso'; else ko:=ko+1; r:=r||E'\n✘ pendiente evaluar en proceso'; end if;
  insert into public.evaluaciones_prubind (prueba_id, plan_id, area, evaluacion, observaciones, evaluado_por) values (p, pl_ph, 'calidad', 'cumple', '', gen_random_uuid());
  insert into public.recomendaciones_prubind (prueba_id, area, sentido, recomendacion, emitido_por) values (p, 'calidad', 'favorable', 'Satisfactoria', gen_random_uuid());
  perform pg_temp.como('kevin.hernandez@petstable.mx');
  insert into public.evaluaciones_prubind (prueba_id, plan_id, area, evaluacion, observaciones, evaluado_por) values (p, pl_epp, 'seguridad', 'cumple', '', gen_random_uuid());
  insert into public.recomendaciones_prubind (prueba_id, area, sentido, recomendacion, emitido_por) values (p, 'seguridad', 'favorable', 'Satisfactoria', gen_random_uuid());
  perform pg_temp.como('laura.vasquez@petstable.mx');
  if exists (select 1 from public.prubind_mis_pendientes() x where x.prueba_id = p and x.accion = 'terminar') then ok:=ok+1; r:=r||E'\n✔ quien registró ve "Terminar la prueba" al concluir la fecha'; else ko:=ko+1; r:=r||E'\n✘ pendiente terminar'; end if;

  -- Terminado automático (pg_cron)
  execute 'reset role';
  perform public.prubind_autoterminar();
  execute 'set local role authenticated';
  select estado into est from public.pruebas_prubind where id = p;
  if est = 'pendiente_dictamen' then ok:=ok+1; r:=r||E'\n✔ se terminó sola al pasar su fecha y pasó a dictamen'; else ko:=ko+1; r:=r||E'\n✘ autoterminar: '||est; end if;

  -- Dictamen: el Jefe ya no captura; quien dictamina completa el pendiente y lo evalúa
  perform pg_temp.como('abigail.ordaz@petstable.mx');
  m := pg_temp.falla(format('update public.resultados_prubind set valor_num = 10 where id = %L', rid));
  if m is not null then ok:=ok+1; r:=r||E'\n✔ en dictamen las áreas ya no modifican valores'; else ko:=ko+1; r:=r||E'\n✘ el área modificó en dictamen'; end if;
  perform pg_temp.como('camila@petstable.mx');
  update public.resultados_prubind set valor_num = 10 where id = rid;
  insert into public.evaluaciones_prubind (prueba_id, plan_id, area, evaluacion, observaciones, evaluado_por) values (p, pl_hum, 'calidad', 'cumple', '', gen_random_uuid());
  e := public.prubind_eval_estado(p);
  if (e->>'eval_faltantes')::int = 0 then ok:=ok+1; r:=r||E'\n✔ quien dictamina completa y evalúa el valor pendiente'; else ko:=ko+1; r:=r||E'\n✘ '||e::text; end if;
  perform public.prubind_accion(p, 'dictaminar', '{"dictamen":"aprobada"}');
  if (select estado from public.pruebas_prubind where id = p) = 'aprobada' then ok:=ok+1; r:=r||E'\n✔ dictamen aprobado'; else ko:=ko+1; r:=r||E'\n✘ dictamen'; end if;
  raise exception 'ROLLBACK';
exception when others then
  if sqlerrm = 'ROLLBACK' then null;
  else ko:=ko+1; r:=r||E'\n✘ ERROR: '||sqlerrm; end if;
end;
return format('Correctas: %s · Fallidas: %s', ok, ko) || r;
end $$;
select pg_temp.t();
