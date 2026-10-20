-- =====================================================================
-- Pruebas del flujo simplificado (v3) con los puestos reales asignados.
-- Todo se REVIERTE. Ejecutar completo en Supabase → SQL Editor; el
-- resultado se devuelve como texto en la columna "resultado".
-- =====================================================================
create or replace function pg_temp.como(p_email text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claims', json_build_object('role','authenticated','email',p_email)::text, true); end $$;
create or replace function pg_temp.falla(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return null; exception when others then return sqlerrm; end $$;

create or replace function pg_temp.flujo() returns text language plpgsql as $$
declare
  r text := ''; ok int := 0; ko int := 0; m text; res text;
  v_cc uuid; p uuid; p2 uuid; ld uuid; b1 uuid; mu uuid; pl uuid; n int; st text; v_folio text; v_prod uuid; ulma uuid;
begin
begin
  execute 'set local role authenticated';
  perform pg_temp.como('laura.vasquez@petstable.mx');
  select v.id into v_cc from public.receta_versiones_prubind v join public.recetas_prubind x on x.id = v.receta_id where x.nombre = 'Chicken Chase' and v.estado = 'vigente';
  select producto_id into v_prod from public.recetas_prubind where nombre = 'Chicken Chase';

  -- Tipos
  perform pg_temp.como('laura.vasquez@petstable.mx');
  m := pg_temp.falla($q$insert into public.pruebas_prubind (tipo, cambio, registrado_por) values ('cambio_receta', 'x', gen_random_uuid())$q$);
  if m ilike '%no está activo%' then ok := ok + 1; r := r || E'\n✔ "Cambio en la receta" ya no se registra (unificado)'; else ko := ko + 1; r := r || E'\n✘ cambio_receta: ' || coalesce(m, 'se registró'); end if;

  -- 1. Registro y planeación (Gerente de Compras)
  insert into public.pruebas_prubind (tipo, cambio, receta_version_id, fecha_planeada, batches_planeados, registrado_por)
  values ('cambio_formulacion', 'Reducir filete y aumentar recorte', v_cc, public.prubind_hoy() + 1, 2, gen_random_uuid())
  returning id, folio, estado into p, v_folio, st;
  if st = 'registrada' and (select producto_id from public.pruebas_prubind where id = p) = v_prod and (select batches_planeados from public.pruebas_prubind where id = p) = 2
    then ok := ok + 1; r := r || E'\n✔ registro ' || v_folio || ' con fecha y batches; la receta define el producto';
    else ko := ko + 1; r := r || E'\n✘ registro ' || coalesce(st, '?'); end if;
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L)', p, 'generar_plan'));
  if m is null then ok := ok + 1; r := r || E'\n✔ quien registra puede ajustar la planeación'; else ko := ko + 1; r := r || E'\n✘ registro no ajusta: ' || m; end if;

  -- 2. Preparación (Gerente de Producción)
  perform pg_temp.como('javier.martinez@petstable.mx');
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L)', p, 'confirmar_plan'));
  if m is not null then ok := ok + 1; r := r || E'\n✔ Gerente de Procesos ya no prepara'; else ko := ko + 1; r := r || E'\n✘ Procesos preparó'; end if;
  perform pg_temp.como('juan.rodriguez@petstable.mx');
  perform public.prubind_accion(p, 'copiar_receta');
  perform public.prubind_accion(p, 'generar_plan');
  select count(*) into n from public.plan_evaluacion_prubind pl2 where pl2.prueba_id = p;
  if n = 16 and not exists (select 1 from public.plan_evaluacion_prubind pl2 join public.metodos_prubind m2 on m2.id = pl2.metodo_id where pl2.prueba_id = p and (m2.codigo = 'FQ-HUM' or pl2.nivel <> 'batch'))
    then ok := ok + 1; r := r || E'\n✔ plan de 16 análisis, todos por batch, humedad solo en bromatología';
    else ko := ko + 1; r := r || E'\n✘ plan: ' || n; end if;
  -- quitar una materia prima (cantidad 0) y agregar otra
  update public.prueba_formulacion_prubind set cantidad_propuesta = 0 where prueba_id = p and materia_prima_id = (select id from public.materias_primas_prubind where nombre = 'Chícharo');
  insert into public.prueba_formulacion_prubind (prueba_id, materia_prima_id, cantidad_propuesta, unidad_id, accion)
  values (p, (select id from public.materias_primas_prubind where nombre = 'Camote'), 3, (select id from public.unidades_prubind where simbolo = 'kg'), 'agregar');
  if (select accion from public.prueba_formulacion_prubind where prueba_id = p and materia_prima_id = (select id from public.materias_primas_prubind where nombre = 'Chícharo')) = 'retirar'
     and (select count(*) from public.receta_ingredientes_prubind where version_id = v_cc) = 19
    then ok := ok + 1; r := r || E'\n✔ formulación: quitar (0) queda como "retirar" y se agrega otra; receta oficial intacta';
    else ko := ko + 1; r := r || E'\n✘ formulación'; end if;
  update public.pruebas_prubind set responsable_ejecucion_id = (select id from public.usuarios_prubind where email = 'abigail.ordaz@petstable.mx') where id = p;
  -- (prueba) solo pH y humedad obligatorios, para no capturar los 16 análisis
  update public.plan_evaluacion_prubind x set obligatorio = (m2.codigo in ('FQ-PH', 'BRO-HUM')) from public.metodos_prubind m2 where m2.id = x.metodo_id and x.prueba_id = p;
  perform public.prubind_accion(p, 'confirmar_plan');
  perform public.prubind_accion(p, 'calcular_materiales');
  perform public.prubind_accion(p, 'marcar_preparada');
  perform public.prubind_accion(p, 'autorizar_ejecucion', '{"texto":"Autorizada al preparar"}');
  if (select estado from public.pruebas_prubind where id = p) = 'preparada' and (public.prubind_eval_estado(p) ->> 'aut_ejecucion')::boolean
    then ok := ok + 1; r := r || E'\n✔ Gerente de Producción prepara y autoriza en el mismo paso';
    else ko := ko + 1; r := r || E'\n✘ preparación/autorización'; end if;

  -- 3. Ejecución por batch (Jefe de Calidad)
  m := pg_temp.falla(format('insert into public.lotes_diarios_prubind (prueba_id, codigo, fecha) values (%L, %L, current_date)', p, 'L-X'));
  if m is not null then ok := ok + 1; r := r || E'\n✔ Producción ya no captura la ejecución'; else ko := ko + 1; r := r || E'\n✘ Producción ejecutó'; end if;
  perform pg_temp.como('abigail.ordaz@petstable.mx');
  insert into public.lotes_diarios_prubind (prueba_id, codigo, fecha) values (p, 'L-151026', current_date) returning id into ld;
  insert into public.batches_prubind (prueba_id, lote_diario_id, numero, fecha_hora, temp_coccion_c, consistencia_cm_s, peso_real_kg, resultado_op)
  values (p, ld, 0, now(), 92, 3.1, 231, 'conforme') returning id into b1;
  insert into public.muestras_prubind (prueba_id, nivel, batch_id, codigo, fecha_muestreo) values (p, 'batch', b1, '', current_date) returning id into mu;
  select x.id into pl from public.plan_evaluacion_prubind x join public.metodos_prubind m2 on m2.id = x.metodo_id where x.prueba_id = p and m2.codigo = 'FQ-PH';
  insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, valor_num, estado, capturado_por) values (p, pl, mu, pl, 6.2, 'pendiente', gen_random_uuid());
  select x.id into pl from public.plan_evaluacion_prubind x join public.metodos_prubind m2 on m2.id = x.metodo_id where x.prueba_id = p and m2.codigo = 'BRO-HUM';
  insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, valor_num, estado, capturado_por) values (p, pl, mu, pl, 9.4, 'pendiente', gen_random_uuid());
  if (select estado from public.pruebas_prubind where id = p) = 'en_ejecucion' and (select count(*) from public.resultados_prubind where prueba_id = p) = 2
    then ok := ok + 1; r := r || E'\n✔ Calidad captura el batch con proceso, pH y humedad durante la ejecución';
    else ko := ko + 1; r := r || E'\n✘ ejecución'; end if;
  perform public.prubind_accion(p, 'terminar_ejecucion');

  -- 4. Evaluación (Jefe de Calidad): evaluar y completar
  update public.resultados_prubind set estado = 'conforme' where prueba_id = p;
  if not exists (select 1 from public.resultados_prubind where prueba_id = p and estado = 'pendiente') then ok := ok + 1; r := r || E'\n✔ Jefe de Calidad evalúa los resultados sin criterio';
  else ko := ko + 1; r := r || E'\n✘ evaluación'; end if;
  perform public.prubind_accion(p, 'enviar_dictamen');

  -- 5. Dictamen (Dirección)
  perform pg_temp.como('juan.rodriguez@petstable.mx');
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L, %L)', p, 'dictaminar', '{"dictamen":"aprobada"}'));
  if m is not null then ok := ok + 1; r := r || E'\n✔ Producción no dictamina'; else ko := ko + 1; r := r || E'\n✘ Producción dictaminó'; end if;
  perform pg_temp.como('camila@petstable.mx');
  -- La humedad (bromatología) la revisa la Directora de Calidad antes del dictamen
  perform public.prubind_accion(p, 'revisar_resultado', jsonb_build_object('resultado_id', (select x.id from public.resultados_prubind x join public.metodos_prubind m2 on m2.id = x.metodo_id where x.prueba_id = p and m2.codigo = 'BRO-HUM')));
  perform public.prubind_accion(p, 'dictaminar', '{"dictamen":"aprobada","texto":"Cumple"}');
  if (select estado from public.pruebas_prubind where id = p) = 'aprobada' then ok := ok + 1; r := r || E'\n✔ Dirección (Directora de Calidad) dictamina';
  else ko := ko + 1; r := r || E'\n✘ dictamen'; end if;
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L)', p, 'cerrar'));
  if m is not null then ok := ok + 1; r := r || E'\n✔ Directora de Calidad ya no cierra'; else ko := ko + 1; r := r || E'\n✘ Calidad cerró'; end if;

  -- 6. Cierre (Gerente de Procesos y Mejora Continua)
  perform pg_temp.como('javier.martinez@petstable.mx');
  perform public.prubind_accion(p, 'cerrar');
  if (select estado from public.pruebas_prubind where id = p) = 'cerrada_aprobada' then ok := ok + 1; r := r || E'\n✔ Gerente de Procesos cierra la prueba';
  else ko := ko + 1; r := r || E'\n✘ cierre'; end if;

  -- Empaque primario: ULMA y controles de empaque
  perform pg_temp.como('laura.vasquez@petstable.mx');
  select equipo_id into ulma from public.tipos_prueba_prubind where codigo = 'material_empaque';
  insert into public.pruebas_prubind (tipo, cambio, empaque, equipo_id, registrado_por) values ('material_empaque', 'Film reciclable', 'Film 80 µm', ulma, gen_random_uuid()) returning id into p2;
  perform pg_temp.como('juan.rodriguez@petstable.mx');
  perform public.prubind_accion(p2, 'generar_plan');
  insert into public.prueba_parametros_prubind (prueba_id, equipo_id, parametro_id, nombre)
  select p2, ulma, x.id, x.nombre from public.equipo_parametros_prubind x where x.equipo_id = ulma;
  select string_agg(m2.codigo, ',' order by pl2.orden) into st from public.plan_evaluacion_prubind pl2 join public.metodos_prubind m2 on m2.id = pl2.metodo_id where pl2.prueba_id = p2 and pl2.obligatorio;
  if st = 'EP-SELLO,EP-HERM,EP-COD' and (select count(*) from public.prueba_parametros_prubind where prueba_id = p2 and minimo is not null) = 2
    then ok := ok + 1; r := r || E'\n✔ empaque: obligatorios sellado, vacío y lotificado; parámetros de la ULMA con rangos';
    else ko := ko + 1; r := r || E'\n✘ empaque: ' || coalesce(st, '—'); end if;

  -- Recetas: descartar cambios sin publicar (administrador)
  execute 'reset role';
  execute 'set local role authenticated';
  perform pg_temp.como('javier.martinez@petstable.mx');
  perform public.prubind_clonar_version(v_cc, 'v9');
  m := pg_temp.falla($q$delete from public.receta_ingredientes_prubind where version_id = (select id from public.receta_versiones_prubind where version = 'v9')$q$);
  m := coalesce(m, pg_temp.falla($q$delete from public.receta_versiones_prubind where version = 'v9'$q$));
  if m is null and not exists (select 1 from public.receta_versiones_prubind where version = 'v9') and (select estado from public.receta_versiones_prubind where id = v_cc) = 'vigente'
    then ok := ok + 1; r := r || E'\n✔ recetas: se descartan cambios sin publicar; la vigente no cambia';
    else ko := ko + 1; r := r || E'\n✘ descartar: ' || coalesce(m, '?'); end if;

  execute 'reset role';
  raise exception E'RESULTADO: % correctas, % fallidas%', ok, ko, r;
exception when others then res := sqlerrm;
end;
return res;
end $$;
select pg_temp.flujo() as resultado;
