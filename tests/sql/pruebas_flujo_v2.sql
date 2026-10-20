-- =====================================================================
-- Pruebas del flujo v2 (seis etapas). Simula sesiones de usuarios con
-- puestos asignados SOLO dentro de esta transacción y REVIERTE todo.
-- El resultado se muestra como mensaje de error (intencional).
-- Ejecutar en Supabase → SQL Editor.
-- =====================================================================
create or replace function pg_temp.como(p_email text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claims', json_build_object('role','authenticated','email',p_email)::text, true); end $$;
create or replace function pg_temp.falla(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return null; exception when others then return sqlerrm; end $$;

do $$
declare
  r text := ''; ok int := 0; ko int := 0; m text;
  kg uuid; mp1 uuid; mp2 uuid; prod uuid; rec uuid; v1 uuid; v2 uuid; p uuid; p2 uuid; ld uuid; b1 uuid; b2 uuid;
  lmp uuid; s1 uuid; s2 uuid; sc uuid; sr uuid; res uuid; n int; st text; v_folio text;
  pl_ph uuid; pl_meso uuid; pl_salm uuid; pl_color uuid; pl_pro uuid;
begin
  -- Puestos de prueba (solo en esta transacción)
  update public.usuarios_prubind u set puesto_id = (select id from public.puestos_prubind where nombre = x.puesto)
  from (values ('abigail.ordaz@petstable.mx','Jefa de Calidad'), ('juan.rodriguez@petstable.mx','Gerente de Producción'),
               ('camila@petstable.mx','Directora de Calidad'), ('laura.vasquez@petstable.mx','Gerente de Compras'),
               ('rafa@petstable.mx','Supervisor de Producción'), ('nelisa.ramirez@petstable.mx','Director de Producción')) x(email, puesto)
  where u.email = x.email;
  select id into kg from public.unidades_prubind where simbolo = 'kg';
  execute 'set local role authenticated';

  -- ===== Catálogo y receta oficial (admin) =====
  perform pg_temp.como('javier.martinez@petstable.mx');
  insert into public.productos_prubind (nombre) values ('Croqueta adulto prueba') returning id into prod;
  insert into public.materias_primas_prubind (nombre, unidad_id) values ('Harina de prueba', kg) returning id into mp1;
  insert into public.materias_primas_prubind (nombre, unidad_id) values ('Grasa de prueba', kg) returning id into mp2;
  insert into public.recetas_prubind (producto_id, nombre) values (prod, 'Receta prueba') returning id into rec;
  insert into public.receta_versiones_prubind (receta_id, version) values (rec, 'v1') returning id into v1;
  insert into public.receta_ingredientes_prubind (version_id, materia_prima_id, cantidad, unidad_id) values (v1, mp1, 150, kg), (v1, mp2, 20, kg);
  update public.receta_versiones_prubind set estado = 'vigente' where id = v1;
  m := pg_temp.falla(format('update public.receta_ingredientes_prubind set cantidad = 1 where version_id = %L', v1));
  if m is not null then ok := ok + 1; r := r || E'\n✔ receta vigente protegida'; else ko := ko + 1; r := r || E'\n✘ se modificó receta vigente'; end if;
  perform pg_temp.como('juan.rodriguez@petstable.mx');
  m := pg_temp.falla(format('insert into public.productos_prubind (nombre) values (%L)', 'X producto'));
  if m is not null then ok := ok + 1; r := r || E'\n✔ usuario no edita catálogos'; else ko := ko + 1; r := r || E'\n✘ usuario editó catálogo'; end if;

  -- ===== Etapa 1 · Registro =====
  m := pg_temp.falla(format('insert into public.pruebas_prubind (tipo, cambio, prioridad, registrado_por) values (%L,%L,%L,%L)',
        'cambio_formulacion', 'Reducir grasa', 'urgente', gen_random_uuid()));
  if m ilike '%justifi%' then ok := ok + 1; r := r || E'\n✔ prioridad urgente exige justificación'; else ko := ko + 1; r := r || E'\n✘ urgente sin justificación: ' || coalesce(m,'ok'); end if;
  insert into public.pruebas_prubind (tipo, cambio, prioridad, producto_id, receta_version_id, proveedor_id, registrado_por, estado)
  values ('cambio_formulacion', 'Reducir grasa 10 %', 'normal', prod, v1, null, gen_random_uuid(), 'cerrada_aprobada') returning id, folio, estado into p, v_folio, st;
  if v_folio ~ '^PI-\d{4}-\d{3}$' and st = 'registrada' then ok := ok + 1; r := r || E'\n✔ folio ' || v_folio || ' y estado Registrada';
  else ko := ko + 1; r := r || E'\n✘ folio/estado: ' || v_folio || ' ' || st; end if;

  -- ===== Etapa 2 · Preparación =====
  perform pg_temp.como('javier.martinez@petstable.mx');
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L)', p, 'generar_plan'));
  if m is not null then ok := ok + 1; r := r || E'\n✔ administrador sin autoridad técnica no prepara'; else ko := ko + 1; r := r || E'\n✘ admin preparó'; end if;
  perform pg_temp.como('juan.rodriguez@petstable.mx');
  perform public.prubind_accion(p, 'copiar_receta');
  update public.prueba_formulacion_prubind set cantidad_propuesta = 18 where prueba_id = p and materia_prima_id = mp2;
  select accion into st from public.prueba_formulacion_prubind where prueba_id = p and materia_prima_id = mp2;
  if st = 'modificar' and (select count(*) from public.receta_ingredientes_prubind where version_id = v1 and cantidad = 20) = 1
    then ok := ok + 1; r := r || E'\n✔ formulación propuesta separada; receta original intacta';
    else ko := ko + 1; r := r || E'\n✘ formulación: ' || coalesce(st,'?'); end if;
  update public.pruebas_prubind set batches_planeados = 2, peso_objetivo_kg = 232, fecha_planeada = public.prubind_hoy() where id = p;
  select estado into st from public.pruebas_prubind where id = p;
  if st = 'en_preparacion' then ok := ok + 1; r := r || E'\n✔ pasa a En preparación'; else ko := ko + 1; r := r || E'\n✘ estado ' || st; end if;
  perform public.prubind_accion(p, 'generar_plan');
  select count(*) into n from public.plan_evaluacion_prubind where prueba_id = p;
  if n = 17 then ok := ok + 1; r := r || E'\n✔ plan generado desde plantilla (17)'; else ko := ko + 1; r := r || E'\n✘ plan ' || n; end if;
  update public.plan_evaluacion_prubind pl set obligatorio = (m2.codigo in ('FQ-PH','MIC-MESO','MIC-SALM','SEN-COLOR','BRO-PRO'))
    from public.metodos_prubind m2 where m2.id = pl.metodo_id and pl.prueba_id = p;
  update public.plan_evaluacion_prubind pl set incluido = false
    from public.metodos_prubind m2 where m2.id = pl.metodo_id and pl.prueba_id = p and m2.codigo in ('SEN-SABOR','MIC-O157');
  select crit_texto into st from public.plan_evaluacion_prubind pl join public.metodos_prubind m2 on m2.id = pl.metodo_id where pl.prueba_id = p and m2.codigo = 'MIC-SALM';
  if st = 'Ausencia en 25 g' then ok := ok + 1; r := r || E'\n✔ criterio copiado al plan'; else ko := ko + 1; r := r || E'\n✘ criterio ' || coalesce(st,'null'); end if;
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L)', p, 'marcar_preparada'));
  if m ilike '%plan%' then ok := ok + 1; r := r || E'\n✔ no se prepara sin confirmar el plan'; else ko := ko + 1; r := r || E'\n✘ preparada sin plan: ' || coalesce(m,'ok'); end if;
  perform public.prubind_accion(p, 'confirmar_plan');
  perform public.prubind_accion(p, 'calcular_materiales');
  select cantidad into n from public.prueba_materiales_prubind where prueba_id = p and materia_prima_id = mp2;
  if n = 36 then ok := ok + 1; r := r || E'\n✔ materiales = propuesta × batches (36 kg)'; else ko := ko + 1; r := r || E'\n✘ materiales ' || n; end if;
  update public.pruebas_prubind set responsable_ejecucion_id = (select id from public.usuarios_prubind where email = 'rafa@petstable.mx') where id = p;
  perform public.prubind_accion(p, 'marcar_preparada');
  perform pg_temp.como('laura.vasquez@petstable.mx');
  update public.prueba_materiales_prubind set disponibilidad = 'disponible', requiere_compra = false where prueba_id = p;
  if (select bool_and(disponibilidad = 'disponible') from public.prueba_materiales_prubind where prueba_id = p) then ok := ok + 1; r := r || E'\n✔ Compras actualiza disponibilidad';
  else ko := ko + 1; r := r || E'\n✘ disponibilidad'; end if;
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L)', p, 'autorizar_ejecucion'));
  if m is not null then ok := ok + 1; r := r || E'\n✔ Compras no autoriza ejecución'; else ko := ko + 1; r := r || E'\n✘ compras autorizó'; end if;

  -- ===== Etapa 3 · Ejecución =====
  perform pg_temp.como('rafa@petstable.mx');
  m := pg_temp.falla(format('insert into public.lotes_diarios_prubind (prueba_id, codigo, fecha) values (%L, %L, current_date)', p, 'L1'));
  if m ilike '%autoriza%' then ok := ok + 1; r := r || E'\n✔ no se ejecuta sin autorización'; else ko := ko + 1; r := r || E'\n✘ ejecutó sin autorización: ' || coalesce(m,'ok'); end if;
  perform pg_temp.como('juan.rodriguez@petstable.mx');
  perform public.prubind_accion(p, 'autorizar_ejecucion', '{"texto":"Se autoriza"}');
  perform pg_temp.como('laura.vasquez@petstable.mx');
  insert into public.lotes_mp_prubind (materia_prima_id, lote) values (mp1, 'MP-001') returning id into lmp;
  perform pg_temp.como('rafa@petstable.mx');
  insert into public.lotes_diarios_prubind (prueba_id, codigo, fecha) values (p, 'l-151026', current_date) returning id into ld;
  insert into public.batches_prubind (prueba_id, lote_diario_id, numero, fecha_hora, receta_version_id, peso_real_kg, temp_coccion_c, consistencia_cm_s)
  values (p, ld, 0, now(), v1, 231.4, 92, 3.1) returning id into b1;
  insert into public.batches_prubind (prueba_id, lote_diario_id, numero, fecha_hora, peso_real_kg) values (p, ld, 0, now(), 244.0) returning id into b2;
  insert into public.batch_lotes_mp_prubind (batch_id, lote_mp_id, cantidad) values (b1, lmp, 150);
  select estado into st from public.pruebas_prubind where id = p;
  if st = 'en_ejecucion' and (select numero from public.batches_prubind where id = b2) = 2 then ok := ok + 1; r := r || E'\n✔ En ejecución; batches numerados en el lote diario';
  else ko := ko + 1; r := r || E'\n✘ ejecución ' || st; end if;
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L)', p, 'terminar_ejecucion'));
  if m ilike '%pendiente%' then ok := ok + 1; r := r || E'\n✔ no termina con batches pendientes'; else ko := ko + 1; r := r || E'\n✘ terminó: ' || coalesce(m,'ok'); end if;
  m := pg_temp.falla(format('update public.batches_prubind set resultado_op = %L where id = %L', 'no_conforme', b2));
  if m ilike '%incidencia%' then ok := ok + 1; r := r || E'\n✔ batch no conforme exige incidencia'; else ko := ko + 1; r := r || E'\n✘ nc sin incidencia'; end if;
  update public.batches_prubind set resultado_op = 'conforme' where prueba_id = p;
  perform public.prubind_accion(p, 'terminar_ejecucion');

  -- ===== Etapa 4 · Evaluación =====
  perform pg_temp.como('laura.vasquez@petstable.mx');
  m := pg_temp.falla(format('insert into public.muestras_prubind (prueba_id, nivel, batch_id, codigo) values (%L,%L,%L,%L)', p, 'batch', b1, ''));
  if m is not null then ok := ok + 1; r := r || E'\n✔ Compras no registra muestras'; else ko := ko + 1; r := r || E'\n✘ compras registró muestra'; end if;
  perform pg_temp.como('abigail.ordaz@petstable.mx');
  insert into public.muestras_prubind (prueba_id, nivel, batch_id, codigo, fecha_muestreo) values (p, 'batch', b1, '', current_date) returning id into s1;
  insert into public.muestras_prubind (prueba_id, nivel, lote_diario_id, codigo) values (p, 'lote_diario', ld, '') returning id into s2;
  insert into public.muestras_prubind (prueba_id, nivel, codigo) values (p, 'compuesta', '') returning id into sc;
  insert into public.muestra_batches_prubind values (sc, b1), (sc, b2);
  select pl.id into pl_ph from public.plan_evaluacion_prubind pl join public.metodos_prubind x on x.id = pl.metodo_id where pl.prueba_id = p and x.codigo = 'FQ-PH';
  select pl.id into pl_meso from public.plan_evaluacion_prubind pl join public.metodos_prubind x on x.id = pl.metodo_id where pl.prueba_id = p and x.codigo = 'MIC-MESO';
  select pl.id into pl_salm from public.plan_evaluacion_prubind pl join public.metodos_prubind x on x.id = pl.metodo_id where pl.prueba_id = p and x.codigo = 'MIC-SALM';
  select pl.id into pl_color from public.plan_evaluacion_prubind pl join public.metodos_prubind x on x.id = pl.metodo_id where pl.prueba_id = p and x.codigo = 'SEN-COLOR';
  select pl.id into pl_pro from public.plan_evaluacion_prubind pl join public.metodos_prubind x on x.id = pl.metodo_id where pl.prueba_id = p and x.codigo = 'BRO-PRO';
  insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, valor_num, estado, capturado_por) values (p, pl_ph, s1, pl_ph, 6.1, 'conforme', gen_random_uuid());
  m := pg_temp.falla(format('insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, valor_num, estado, capturado_por) values (%L,%L,%L,%L,120,%L,%L)',
        p, pl_meso, s2, pl_meso, 'conforme', gen_random_uuid()));
  if m ilike '%dilución%' then ok := ok + 1; r := r || E'\n✔ mesófilos exige dilución válida'; else ko := ko + 1; r := r || E'\n✘ dilución: ' || coalesce(m,'ok'); end if;
  insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, dilucion, valor_num, estado, capturado_por)
  values (p, pl_meso, s2, pl_meso, '10⁻¹', 120, 'conforme', gen_random_uuid());
  m := pg_temp.falla(format('insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, dilucion, valor_num, estado, capturado_por) values (%L,%L,%L,%L,%L,40,%L,%L)',
        p, pl_meso, s2, pl_meso, '10⁻²', 'no_conforme', gen_random_uuid()));
  if m ilike '%justificación%' then ok := ok + 1; r := r || E'\n✔ no conforme exige justificación'; else ko := ko + 1; r := r || E'\n✘ nc sin justificación'; end if;
  insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, dilucion, valor_num, estado, justificacion, capturado_por)
  values (p, pl_meso, s2, pl_meso, '10⁻²', 40, 'no_conforme', 'Conteo fuera de lo esperado', gen_random_uuid()) returning id into res;
  insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, valor_opcion, capturado_por) values (p, pl_salm, s2, pl_salm, 'ausencia', gen_random_uuid());
  select estado into st from public.resultados_prubind where plan_id = pl_salm;
  if st = 'conforme' then ok := ok + 1; r := r || E'\n✔ Salmonella ausencia → conforme por criterio'; else ko := ko + 1; r := r || E'\n✘ salmonella ' || st; end if;
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L)', p, 'enviar_dictamen'));
  if m ilike '%obligatorio%' then ok := ok + 1; r := r || E'\n✔ no pasa a dictamen con obligatorios faltantes'; else ko := ko + 1; r := r || E'\n✘ dictamen con faltantes: ' || coalesce(m,'ok'); end if;
  insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, valor_opcion, capturado_por) values (p, pl_color, s2, pl_color, 'conforme', gen_random_uuid());
  insert into public.resultados_prubind (prueba_id, plan_id, muestra_id, metodo_id, valor_num, estado, capturado_por) values (p, pl_pro, sc, pl_pro, 24.5, 'conforme', gen_random_uuid());
  perform public.prubind_accion(p, 'enviar_dictamen');

  -- ===== Etapa 5 · Dictamen =====
  perform pg_temp.como('javier.martinez@petstable.mx');
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L, %L)', p, 'dictaminar', '{"dictamen":"aprobada"}'));
  if m is not null then ok := ok + 1; r := r || E'\n✔ administrador no dictamina'; else ko := ko + 1; r := r || E'\n✘ admin dictaminó'; end if;
  perform pg_temp.como('camila@petstable.mx');
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L, %L)', p, 'dictaminar', '{"dictamen":"aprobada"}'));
  if m ilike '%sin resolver%' then ok := ok + 1; r := r || E'\n✔ no aprueba con incumplimientos sin resolver'; else ko := ko + 1; r := r || E'\n✘ aprobó con NC: ' || coalesce(m,'ok'); end if;
  update public.resultados_prubind set resolucion = 'Se acepta: el conteo válido es el de la dilución 10⁻¹' where id = res;
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L, %L)', p, 'dictaminar', '{"dictamen":"aprobada"}'));
  if m ilike '%revisión%' then ok := ok + 1; r := r || E'\n✔ bromatología requiere revisión de la Directora de Calidad'; else ko := ko + 1; r := r || E'\n✘ revisión: ' || coalesce(m,'ok'); end if;
  perform public.prubind_accion(p, 'revisar_resultado', jsonb_build_object('resultado_id', (select id from public.resultados_prubind where plan_id = pl_pro)));
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L, %L)', p, 'dictaminar', '{"dictamen":"rechazada"}'));
  if m ilike '%motivo%' then ok := ok + 1; r := r || E'\n✔ rechazo exige motivo del catálogo'; else ko := ko + 1; r := r || E'\n✘ rechazo sin motivo'; end if;
  perform public.prubind_accion(p, 'dictaminar', '{"dictamen":"aprobada","texto":"Cumple"}');

  -- ===== Etapa 6 · Cierre e implementación =====
  perform pg_temp.como('juan.rodriguez@petstable.mx');
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L)', p, 'cerrar'));
  if m is not null then ok := ok + 1; r := r || E'\n✔ Producción no cierra'; else ko := ko + 1; r := r || E'\n✘ producción cerró'; end if;
  perform pg_temp.como('camila@petstable.mx');
  perform public.prubind_accion(p, 'cerrar');
  perform public.prubind_accion(p, 'autorizar_implementacion', '{"texto":"Calidad autoriza"}');
  perform pg_temp.como('javier.martinez@petstable.mx');
  m := pg_temp.falla(format('select public.prubind_accion(%L, %L, %L)', p, 'publicar_formulacion', '{"version":"v2"}'));
  if m ilike '%Faltan autorizaciones%' then ok := ok + 1; r := r || E'\n✔ receta nueva exige todas las autorizaciones (1 de 2)'; else ko := ko + 1; r := r || E'\n✘ publicó: ' || coalesce(m,'ok'); end if;
  perform pg_temp.como('nelisa.ramirez@petstable.mx');
  perform public.prubind_accion(p, 'autorizar_implementacion');
  perform pg_temp.como('javier.martinez@petstable.mx');
  perform public.prubind_accion(p, 'publicar_formulacion', '{"version":"v2"}');
  select id into v2 from public.receta_versiones_prubind where receta_id = rec and estado = 'vigente';
  if (select estado from public.receta_versiones_prubind where id = v1) = 'historica'
     and (select cantidad from public.receta_ingredientes_prubind where version_id = v2 and materia_prima_id = mp2) = 18
     and (select cantidad from public.receta_ingredientes_prubind where version_id = v1 and materia_prima_id = mp2) = 20
    then ok := ok + 1; r := r || E'\n✔ v2 vigente con la formulación aprobada; v1 histórica intacta';
    else ko := ko + 1; r := r || E'\n✘ publicación de receta'; end if;
  m := pg_temp.falla(format('update public.pruebas_prubind set cambio = %L where id = %L', 'X', p));
  if m is not null then ok := ok + 1; r := r || E'\n✔ prueba cerrada inmutable'; else ko := ko + 1; r := r || E'\n✘ se editó cerrada'; end if;

  -- ===== Empaque primario: controles, repetición y cancelación =====
  perform pg_temp.como('rafa@petstable.mx');
  insert into public.pruebas_prubind (tipo, cambio, empaque, registrado_por) values ('material_empaque', 'Film 80 µm', 'Film PET/PE 80 µm', gen_random_uuid()) returning id into p2;
  perform public.prubind_accion(p2, 'generar_plan');
  if exists (select 1 from public.plan_evaluacion_prubind pl join public.metodos_prubind x on x.id = pl.metodo_id where pl.prueba_id = p2 and x.categoria <> 'empaque_primario')
    then ko := ko + 1; r := r || E'\n✘ empaque con análisis de alimento';
    else ok := ok + 1; r := r || E'\n✔ empaque primario solo muestra controles de empaque'; end if;
  update public.plan_evaluacion_prubind set obligatorio = false where prueba_id = p2;
  perform public.prubind_accion(p2, 'confirmar_plan');
  update public.pruebas_prubind set responsable_ejecucion_id = (select id from public.usuarios_prubind where email = 'rafa@petstable.mx') where id = p2;
  perform public.prubind_accion(p2, 'marcar_preparada');
  perform pg_temp.como('juan.rodriguez@petstable.mx');
  perform public.prubind_accion(p2, 'autorizar_ejecucion');
  perform pg_temp.como('rafa@petstable.mx');
  insert into public.ejecucion_controles_prubind (prueba_id, nombre, valor, resultado) values (p2, 'Temperatura de sellado', '165', 'conforme');
  perform public.prubind_accion(p2, 'terminar_ejecucion');
  perform pg_temp.como('abigail.ordaz@petstable.mx');
  insert into public.muestras_prubind (prueba_id, nivel, codigo) values (p2, 'corrida', '') returning id into sr;
  perform public.prubind_accion(p2, 'enviar_dictamen');
  perform pg_temp.como('camila@petstable.mx');
  perform public.prubind_accion(p2, 'dictaminar', '{"dictamen":"requiere_repeticion","texto":"Ajustar temperatura"}');
  perform pg_temp.como('rafa@petstable.mx');
  perform public.prubind_accion(p2, 'nueva_ejecucion');
  select estado, ejecucion_actual into st, n from public.pruebas_prubind where id = p2;
  if st = 'en_preparacion' and n = 2 and (select count(*) from public.ejecucion_controles_prubind where prueba_id = p2 and ejecucion = 1) = 1
    then ok := ok + 1; r := r || E'\n✔ repetición: ejecución #2 vinculada con historial conservado';
    else ko := ko + 1; r := r || E'\n✘ repetición ' || st || ' ' || n; end if;
  perform public.prubind_accion(p2, 'cancelar', '{"texto":"Se pospone"}');
  if (select estado from public.pruebas_prubind where id = p2) = 'cancelada' then ok := ok + 1; r := r || E'\n✔ cancelación con motivo'; else ko := ko + 1; r := r || E'\n✘ cancelación'; end if;

  -- Pendientes, tablero y accesos
  perform pg_temp.como('camila@petstable.mx');
  select count(*) into n from public.prubind_mis_pendientes();
  perform public.prubind_dashboard(public.prubind_hoy() - 30, public.prubind_hoy());
  ok := ok + 1; r := r || E'\n✔ pendientes y tablero responden (' || n || ' pendientes)';
  select count(*) into n from public.seguimiento_prubind where prueba_id = p;
  r := r || E'\n· seguimiento de la prueba 1: ' || n || ' eventos';
  perform pg_temp.como('camila.delrio@petstable.mx');
  select count(*) into n from public.pruebas_prubind;
  if n = 0 then ok := ok + 1; r := r || E'\n✔ cuenta sin acceso no ve pruebas'; else ko := ko + 1; r := r || E'\n✘ sin acceso ve ' || n; end if;
  execute 'set local role anon';
  m := pg_temp.falla('select count(*) from public.pruebas_prubind');
  if m is not null then ok := ok + 1; r := r || E'\n✔ anónimo sin acceso'; else ko := ko + 1; r := r || E'\n✘ anónimo consultó'; end if;
  execute 'reset role';
  raise exception E'RESULTADO: % correctas, % fallidas%', ok, ko, r;
end $$;
