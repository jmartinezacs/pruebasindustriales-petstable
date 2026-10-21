-- =====================================================================
-- v5.8 · Responsable que inicia y termina, rechazo con explicación (sin
-- catálogo de motivos) y código automático de parámetros. Todo se REVIERTE.
-- =====================================================================
create or replace function pg_temp.como(p_email text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claims', json_build_object('role','authenticated','email',p_email)::text, true); end $$;
create or replace function pg_temp.falla(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return null; exception when others then return sqlerrm; end $$;
create or replace function pg_temp.t() returns text language plpgsql as $$
declare r text := ''; ok int := 0; ko int := 0; m text; p uuid; juan uuid; pl uuid; mu uuid; met uuid; cod text;
begin
begin
  execute 'set local role authenticated';
  -- Laura registra la prueba y asigna a Juan como responsable
  perform pg_temp.como('laura.vasquez@petstable.mx');
  select id into juan from public.usuarios_prubind where email = 'juan.rodriguez@petstable.mx';
  insert into public.pruebas_prubind (tipo, cambio, objetivo_desc, registrado_por, fecha_planeada, responsable_inicial_id)
  values ('cambio_formulacion', 'Prueba v5.8', 'Objetivo', gen_random_uuid(), public.prubind_hoy(), juan) returning id into p;
  if not exists (select 1 from public.prubind_mis_pendientes() x where x.prueba_id = p and x.accion = 'iniciar') then ok:=ok+1; r:=r||E'\n✔ quien registró no ve "Iniciar" si no es la responsable'; else ko:=ko+1; r:=r||E'\n✘ pendiente iniciar a quien registró'; end if;
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L)', p, 'iniciar'));
  if m ilike '%responsable%' then ok:=ok+1; r:=r||E'\n✔ quien registró no la inicia'; else ko:=ko+1; r:=r||E'\n✘ '||coalesce(m,'inició quien registró'); end if;

  perform pg_temp.como('abigail.ordaz@petstable.mx');
  select id into met from public.metodos_prubind where codigo = 'CAL-PH';
  perform public.prubind_definir_parametros(p, array[met]);
  select id into pl from public.plan_evaluacion_prubind where prueba_id = p;
  -- Código automático de un parámetro nuevo
  met := public.prubind_nuevo_parametro('Tiempo de enfriamiento', 'calidad', 'numerico');
  select codigo into cod from public.metodos_prubind where id = met;
  if cod = 'CAL-TIEM-ENFR' then ok:=ok+1; r:=r||E'\n✔ código automático: '||cod; else ko:=ko+1; r:=r||E'\n✘ código: '||coalesce(cod,'—'); end if;

  perform pg_temp.como('juan.rodriguez@petstable.mx');
  if exists (select 1 from public.prubind_mis_pendientes() x where x.prueba_id = p and x.accion = 'iniciar') then ok:=ok+1; r:=r||E'\n✔ el responsable ve "Iniciar la prueba"'; else ko:=ko+1; r:=r||E'\n✘ pendiente iniciar al responsable'; end if;
  perform public.prubind_accion(p, 'iniciar');
  ok:=ok+1; r:=r||E'\n✔ el responsable la inicia';

  perform pg_temp.como('jose.cabrera@petstable.mx');
  insert into public.muestras_prubind (prueba_id, nivel, codigo, fecha_muestreo) values (p, 'corrida', '', public.prubind_hoy()) returning id into mu;
  insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, valor_num, capturado_por)
  select p, pl, mu, metodo_id, 6, gen_random_uuid() from public.plan_evaluacion_prubind where id = pl;
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L)', p, 'terminar_ejecucion'));
  if m ilike '%responsable%' then ok:=ok+1; r:=r||E'\n✔ un inspector no termina la prueba'; else ko:=ko+1; r:=r||E'\n✘ '||coalesce(m,'terminó el inspector'); end if;
  perform pg_temp.como('laura.vasquez@petstable.mx');
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L)', p, 'terminar_ejecucion'));
  if m ilike '%responsable%' then ok:=ok+1; r:=r||E'\n✔ quien registró tampoco la termina'; else ko:=ko+1; r:=r||E'\n✘ '||coalesce(m,'terminó quien registró'); end if;
  perform pg_temp.como('juan.rodriguez@petstable.mx');
  perform public.prubind_accion(p, 'terminar_ejecucion');
  ok:=ok+1; r:=r||E'\n✔ el responsable la termina';

  perform pg_temp.como('abigail.ordaz@petstable.mx');
  insert into public.evaluaciones_prubind (prueba_id, plan_id, area, evaluacion, observaciones, evaluado_por) values (p, pl, 'calidad', 'no_cumple', 'Fuera de lo esperado', gen_random_uuid());
  insert into public.recomendaciones_prubind (prueba_id, area, sentido, recomendacion, emitido_por) values (p, 'calidad', 'no_favorable', 'No satisfactoria', gen_random_uuid());
  perform public.prubind_accion(p, 'enviar_dictamen');
  perform pg_temp.como('camila@petstable.mx');
  m := pg_temp.falla(format($s$select public.prubind_accion(%L, 'dictaminar', '{"dictamen":"rechazada"}')$s$, p));
  if m ilike '%conclusión%' then ok:=ok+1; r:=r||E'\n✔ rechazar pide la explicación en la conclusión'; else ko:=ko+1; r:=r||E'\n✘ '||coalesce(m,'rechazó sin explicación'); end if;
  perform public.prubind_accion(p, 'dictaminar', '{"dictamen":"rechazada","texto":"El pH no cumple"}');
  if (select estado from public.pruebas_prubind where id = p) = 'rechazada' then ok:=ok+1; r:=r||E'\n✔ rechazo sin catálogo de motivos'; else ko:=ko+1; r:=r||E'\n✘ rechazo'; end if;
  raise exception 'ROLLBACK';
exception when others then
  if sqlerrm = 'ROLLBACK' then null;
  else ko:=ko+1; r:=r||E'\n✘ ERROR: '||sqlerrm; end if;
end;
return format('Correctas: %s · Fallidas: %s', ok, ko) || r;
end $$;
select pg_temp.t();
