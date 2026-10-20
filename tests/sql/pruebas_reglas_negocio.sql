-- =====================================================================
-- Pruebas de reglas de negocio · Pruebas industriales (_prubind)
-- Simula sesiones de cada usuario (JWT) con el rol "authenticated",
-- recorre el flujo completo y REVIERTE todo al final.
-- El resultado se muestra como mensaje de error (intencional: así se revierte).
-- Ejecutar en Supabase → SQL Editor.
-- =====================================================================
do $$
declare
  r text := '';
  ok int := 0; fail int := 0;
  v_p uuid; v_p2 uuid; v_b1 uuid; v_b2 uuid; v_i uuid; v_res uuid; v_n int;
begin
  -- Utilidades en línea: como(email) cambia la identidad; los bloques begin/exception verifican errores esperados
  execute 'set local role authenticated';

  -- ===== 1. Camila (admin + dirección) registra un producto nuevo =====
  perform set_config('request.jwt.claims', '{"role":"authenticated","email":"camila@petstable.mx"}', true);
  insert into public.pruebas_prubind (tipo, titulo, objetivo, num_batches, fecha_inicio, estado, creado_por)
  values ('producto_nuevo', 'Receta prueba', 'Validar receta nueva', 2, public.prubind_hoy(), 'aprobada', gen_random_uuid())
  returning id into v_p;
  select count(*) into v_n from public.batches_prubind where prueba_id = v_p;
  if v_n = 2 and (select estado from public.pruebas_prubind where id = v_p) = 'borrador' then ok := ok + 1; r := r || E'\n✔ alta genera 2 batches y fuerza borrador';
  else fail := fail + 1; r := r || E'\n✘ alta: batches=' || v_n; end if;

  -- ===== 2. Laura no puede registrar "producto nuevo" =====
  perform set_config('request.jwt.claims', '{"role":"authenticated","email":"laura.vasquez@petstable.mx"}', true);
  begin
    insert into public.pruebas_prubind (tipo, titulo, objetivo) values ('producto_nuevo', 'X prueba', 'Y objetivo');
    fail := fail + 1; r := r || E'\n✘ Laura creó producto nuevo';
  exception when others then ok := ok + 1; r := r || E'\n✔ Laura no crea producto nuevo';
  end;
  begin
    insert into public.pruebas_prubind (tipo, titulo, objetivo, insumo_cambio, proveedor_nuevo)
    values ('cambio_proveedor', 'Proveedor harina', 'Evaluar harina', 'Harina', 'Prov B') returning id into v_p2;
    ok := ok + 1; r := r || E'\n✔ Laura crea cambio de proveedor';
  exception when others then fail := fail + 1; r := r || E'\n✘ Laura no pudo crear cambio de proveedor: ' || sqlerrm;
  end;

  -- ===== 3. Estado solo vía RPC; Abigail no edita la prueba de Camila =====
  perform set_config('request.jwt.claims', '{"role":"authenticated","email":"camila@petstable.mx"}', true);
  begin
    update public.pruebas_prubind set estado = 'aprobada' where id = v_p;
    fail := fail + 1; r := r || E'\n✘ cambio directo de estado permitido';
  exception when others then ok := ok + 1; r := r || E'\n✔ estado directo bloqueado';
  end;
  perform set_config('request.jwt.claims', '{"role":"authenticated","email":"abigail.ordaz@petstable.mx"}', true);
  update public.pruebas_prubind set titulo = 'Hackeado' where id = v_p;
  if (select titulo from public.pruebas_prubind where id = v_p) = 'Receta prueba' then ok := ok + 1; r := r || E'\n✔ Abigail no edita prueba ajena (RLS)';
  else fail := fail + 1; r := r || E'\n✘ Abigail editó prueba ajena'; end if;

  -- ===== 4. Insumos: Camila solicita, Juan valida, Laura compra =====
  perform set_config('request.jwt.claims', '{"role":"authenticated","email":"camila@petstable.mx"}', true);
  insert into public.insumos_prubind (prueba_id, insumo, unidad, cantidad_por_batch, cantidad_solicitada)
  values (v_p, 'Pollo', 'kg', 50, 100) returning id into v_i;
  perform set_config('request.jwt.claims', '{"role":"authenticated","email":"laura.vasquez@petstable.mx"}', true);
  begin
    update public.insumos_prubind set estado = 'validado', cantidad_validada = 90 where id = v_i;
    fail := fail + 1; r := r || E'\n✘ Compras validó cantidades';
  exception when others then ok := ok + 1; r := r || E'\n✔ Compras no valida cantidades';
  end;
  perform set_config('request.jwt.claims', '{"role":"authenticated","email":"juan.rodriguez@petstable.mx"}', true);
  update public.insumos_prubind set estado = 'validado', cantidad_validada = 110 where id = v_i;
  perform set_config('request.jwt.claims', '{"role":"authenticated","email":"laura.vasquez@petstable.mx"}', true);
  update public.insumos_prubind set estado = 'en_compra', orden_compra = 'OC-1', cantidad_validada = 1 where id = v_i;
  begin
    update public.insumos_prubind set estado = 'recibido' where id = v_i;
    fail := fail + 1; r := r || E'\n✘ recepción sin cantidad';
  exception when others then ok := ok + 1; r := r || E'\n✔ recepción exige cantidad y fecha';
  end;
  update public.insumos_prubind set estado = 'recibido', cantidad_recibida = 110, fecha_recepcion = public.prubind_hoy() where id = v_i;
  select (estado = 'recibido' and cantidad_validada = 110 and validado_por is not null and compras_por is not null)::int into v_n
    from public.insumos_prubind where id = v_i;
  if v_n = 1 then ok := ok + 1; r := r || E'\n✔ flujo de insumo completo y validación congelada';
  else fail := fail + 1; r := r || E'\n✘ flujo de insumo'; end if;

  -- ===== 5. Ejecución y batches =====
  perform set_config('request.jwt.claims', '{"role":"authenticated","email":"juan.rodriguez@petstable.mx"}', true);
  begin
    perform public.prubind_cambiar_estado(v_p, 'iniciar');
    fail := fail + 1; r := r || E'\n✘ inició desde borrador';
  exception when others then ok := ok + 1; r := r || E'\n✔ no inicia desde borrador';
  end;
  perform set_config('request.jwt.claims', '{"role":"authenticated","email":"camila@petstable.mx"}', true);
  perform public.prubind_cambiar_estado(v_p, 'planear');
  perform set_config('request.jwt.claims', '{"role":"authenticated","email":"juan.rodriguez@petstable.mx"}', true);
  perform public.prubind_cambiar_estado(v_p, 'iniciar');
  select id into v_b1 from public.batches_prubind where prueba_id = v_p and numero = 1;
  select id into v_b2 from public.batches_prubind where prueba_id = v_p and numero = 2;
  begin
    update public.batches_prubind set estado = 'producido' where id = v_b1;
    fail := fail + 1; r := r || E'\n✘ producido sin fecha';
  exception when others then ok := ok + 1; r := r || E'\n✔ producido exige fecha real';
  end;
  update public.batches_prubind set estado = 'producido', fecha_real = public.prubind_hoy(), lote = 'l-001' where id = v_b1;
  begin
    perform public.prubind_cambiar_estado(v_p, 'evaluar');
    fail := fail + 1; r := r || E'\n✘ evaluación con batch programado';
  exception when others then ok := ok + 1; r := r || E'\n✔ no evalúa con batches programados';
  end;
  perform set_config('request.jwt.claims', '{"role":"authenticated","email":"abigail.ordaz@petstable.mx"}', true);
  begin
    update public.batches_prubind set estado = 'cancelado', motivo_cancelacion = 'x' where id = v_b2;
    fail := fail + 1; r := r || E'\n✘ Calidad canceló batch';
  exception when others then ok := ok + 1; r := r || E'\n✔ Calidad no modifica batches';
  end;

  -- ===== 6. Resultados de calidad =====
  insert into public.resultados_prubind (batch_id, prueba_id, tipo_analisis, parametro, valor, unidad, resultado, fecha_analisis)
  values (v_b1, gen_random_uuid(), 'fisicoquimico', 'Humedad', '72', '%', 'cumple', public.prubind_hoy()) returning id into v_res;
  if (select prueba_id from public.resultados_prubind where id = v_res) = v_p then ok := ok + 1; r := r || E'\n✔ resultado registrado (prueba_id forzado)';
  else fail := fail + 1; r := r || E'\n✘ resultado prueba_id'; end if;
  perform set_config('request.jwt.claims', '{"role":"authenticated","email":"juan.rodriguez@petstable.mx"}', true);
  begin
    insert into public.resultados_prubind (batch_id, prueba_id, tipo_analisis, parametro, valor, resultado, fecha_analisis)
    values (v_b1, v_p, 'proceso', 'Temp', '90', 'cumple', public.prubind_hoy());
    fail := fail + 1; r := r || E'\n✘ Producción capturó resultado';
  exception when others then ok := ok + 1; r := r || E'\n✔ Producción no captura resultados';
  end;
  begin
    update public.batches_prubind set estado = 'programado' where id = v_b1;
    fail := fail + 1; r := r || E'\n✘ revirtió batch con resultados';
  exception when others then ok := ok + 1; r := r || E'\n✔ no revierte batch con resultados';
  end;
  begin
    update public.pruebas_prubind set num_batches = 1 where id = v_p;  -- Juan no es responsable
    if (select num_batches from public.pruebas_prubind where id = v_p) = 2 then ok := ok + 1; r := r || E'\n✔ Juan no cambia datos generales';
    else fail := fail + 1; r := r || E'\n✘ Juan cambió num_batches'; end if;
  exception when others then ok := ok + 1; r := r || E'\n✔ Juan no cambia datos generales';
  end;
  update public.batches_prubind set estado = 'cancelado', motivo_cancelacion = 'Falla de equipo' where id = v_b2;
  perform public.prubind_cambiar_estado(v_p, 'evaluar');

  -- ===== 7. Dictámenes =====
  perform set_config('request.jwt.claims', '{"role":"authenticated","email":"camila@petstable.mx"}', true);
  begin
    perform public.prubind_dictamen_final(v_p, 'aprobada', null);
    fail := fail + 1; r := r || E'\n✘ dictamen final sin dictamen de calidad';
  exception when others then ok := ok + 1; r := r || E'\n✔ dictamen final exige dictamen de Calidad';
  end;
  perform set_config('request.jwt.claims', '{"role":"authenticated","email":"abigail.ordaz@petstable.mx"}', true);
  perform public.prubind_dictamen_calidad(v_p, 'conforme', 'Cumple todos los parámetros');
  begin
    perform public.prubind_dictamen_final(v_p, 'aprobada', null);
    fail := fail + 1; r := r || E'\n✘ Calidad emitió dictamen final';
  exception when others then ok := ok + 1; r := r || E'\n✔ Calidad no emite dictamen final';
  end;
  perform set_config('request.jwt.claims', '{"role":"authenticated","email":"camila@petstable.mx"}', true);
  begin
    perform public.prubind_dictamen_final(v_p, 'rechazada', '');
    fail := fail + 1; r := r || E'\n✘ rechazo sin motivo';
  exception when others then ok := ok + 1; r := r || E'\n✔ rechazo exige motivo';
  end;
  perform public.prubind_dictamen_final(v_p, 'aprobada', 'Se libera');
  if (select estado from public.pruebas_prubind where id = v_p) = 'aprobada' then ok := ok + 1; r := r || E'\n✔ prueba aprobada';
  else fail := fail + 1; r := r || E'\n✘ prueba no aprobada'; end if;
  begin
    update public.pruebas_prubind set titulo = 'Otro' where id = v_p;
    fail := fail + 1; r := r || E'\n✘ editó prueba cerrada';
  exception when others then ok := ok + 1; r := r || E'\n✔ prueba cerrada no se edita';
  end;
  select count(*) into v_n from public.seguimiento_prubind where prueba_id = v_p;
  if v_n >= 8 then ok := ok + 1; r := r || E'\n✔ seguimiento automático (' || v_n || ' eventos)';
  else fail := fail + 1; r := r || E'\n✘ seguimiento: ' || v_n; end if;
  begin
    perform public.prubind_dashboard(public.prubind_hoy() - 30, public.prubind_hoy());
    ok := ok + 1; r := r || E'\n✔ tablero responde';
  exception when others then fail := fail + 1; r := r || E'\n✘ tablero: ' || sqlerrm;
  end;

  -- ===== 8. Envasadora solo en material de empaque; cancelar exige motivo =====
  perform set_config('request.jwt.claims', '{"role":"authenticated","email":"laura.vasquez@petstable.mx"}', true);
  begin
    perform public.prubind_cambiar_estado(v_p2, 'cancelar', '');
    fail := fail + 1; r := r || E'\n✘ canceló sin motivo';
  exception when others then ok := ok + 1; r := r || E'\n✔ cancelar exige motivo';
  end;
  perform set_config('request.jwt.claims', '{"role":"authenticated","email":"camila@petstable.mx"}', true);
  update public.pruebas_prubind set fecha_inicio = public.prubind_hoy() where id = v_p2;
  perform public.prubind_cambiar_estado(v_p2, 'planear');
  begin
    insert into public.envasadora_prubind (prueba_id, parametro, valor) values (v_p2, 'Temp. sellado', '180');
    fail := fail + 1; r := r || E'\n✘ envasadora en cambio de proveedor';
  exception when others then ok := ok + 1; r := r || E'\n✔ envasadora solo en tipos que la usan';
  end;
  perform public.prubind_cambiar_estado(v_p2, 'cancelar', 'Proveedor no disponible');
  begin
    delete from public.pruebas_prubind where id = v_p2;
    select count(*) into v_n from public.pruebas_prubind where id = v_p2;
    if v_n = 1 then ok := ok + 1; r := r || E'\n✔ prueba no-borrador no se elimina';
    else fail := fail + 1; r := r || E'\n✘ se eliminó prueba cancelada'; end if;
  exception when others then ok := ok + 1; r := r || E'\n✔ prueba no-borrador no se elimina';
  end;

  -- ===== 9. Usuario sin acceso y anónimo =====
  perform set_config('request.jwt.claims', '{"role":"authenticated","email":"camila.delrio@petstable.mx"}', true);
  select count(*) into v_n from public.pruebas_prubind;
  if v_n = 0 then ok := ok + 1; r := r || E'\n✔ cuenta sin acceso no ve pruebas';
  else fail := fail + 1; r := r || E'\n✘ cuenta sin acceso ve ' || v_n; end if;
  execute 'set local role anon';
  begin
    select count(*) into v_n from public.pruebas_prubind;
    fail := fail + 1; r := r || E'\n✘ anónimo consultó';
  exception when others then ok := ok + 1; r := r || E'\n✔ anónimo sin acceso';
  end;
  execute 'reset role';

  raise exception E'RESULTADO: % correctas, % fallidas%', ok, fail, r;
end $$;
