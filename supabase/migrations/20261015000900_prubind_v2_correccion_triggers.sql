-- =====================================================================
-- Pruebas industriales · v2 · Migración 9
-- Corrección: PL/pgSQL no evalúa en corto circuito los campos de NEW/OLD.
-- Los triggers compartidos por varias tablas leen los campos opcionales con
-- to_jsonb() para no fallar en tablas que no los tienen.
-- =====================================================================
create or replace function public.prubind_validar_prep()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v       public.pruebas_prubind%rowtype;
  v_pid   uuid;
  v_solo_abasto boolean := false;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return coalesce(new, old); end if;
  if coalesce(current_setting('prubind.rpc', true), '') = '1' then return coalesce(new, old); end if;
  v_pid := case when tg_op = 'DELETE' then old.prueba_id else new.prueba_id end;
  select * into v from public.pruebas_prubind where id = v_pid;
  if v.id is null then return coalesce(new, old); end if;  -- borrado en cascada
  if tg_op = 'UPDATE' and new.prueba_id is distinct from old.prueba_id then
    raise exception 'No se puede mover el registro a otra prueba.' using errcode = 'P0001';
  end if;

  -- Compras/Almacén actualizan compra y disponibilidad hasta la ejecución
  -- (condiciones anidadas: PL/pgSQL no evalúa en corto circuito los campos del registro)
  if tg_table_name = 'prueba_materiales_prubind' and tg_op = 'UPDATE' then
    if (to_jsonb(new) ->> 'materia_prima_id', to_jsonb(new) ->> 'cantidad', to_jsonb(new) ->> 'unidad_id')
       is not distinct from (to_jsonb(old) ->> 'materia_prima_id', to_jsonb(old) ->> 'cantidad', to_jsonb(old) ->> 'unidad_id') then
      v_solo_abasto := true;
      perform public.prubind_req(v_pid, 'abastecer', array['registrada','en_preparacion','preparada','en_ejecucion']);
      new := jsonb_populate_record(new, jsonb_build_object('actualizado_por', public.prubind_usuario_actual_id(),
               'observaciones', nullif(btrim(to_jsonb(new) ->> 'observaciones'), '')));
      return new;
    end if;
  end if;

  perform public.prubind_req(v_pid, 'preparar', array['registrada','en_preparacion'],
    'La preparación solo se modifica antes de marcar la prueba como preparada.');

  if tg_table_name = 'plan_evaluacion_prubind' and v.plan_confirmado_at is not null then
    perform set_config('prubind.rpc', '1', true);
    update public.pruebas_prubind set plan_confirmado_at = null, plan_confirmado_por = null where id = v_pid;
    perform set_config('prubind.rpc', '', true);
  end if;
  if v.estado = 'registrada' then
    perform public.prubind_set_estado(v_pid, 'en_preparacion', null);  -- el trigger de pruebas registra el evento
  end if;
  if tg_op = 'DELETE' then return old; end if;

  if tg_table_name = 'prueba_formulacion_prubind' then
    if new.accion <> 'sustituir' then
      new.sustituye_a_id := null;
      new.accion := case
        when new.cantidad_original is null then 'agregar'
        when coalesce(new.cantidad_propuesta, 0) = 0 then 'retirar'
        when new.cantidad_propuesta <> new.cantidad_original then 'modificar'
        else 'sin_cambio' end;
    elsif new.sustituye_a_id is null then
      raise exception 'Indique qué materia prima se sustituye.' using errcode = 'P0001';
    end if;
  elsif tg_table_name = 'prueba_materiales_prubind' then
    new.actualizado_por := public.prubind_usuario_actual_id();
    new.observaciones := nullif(btrim(new.observaciones), '');
  elsif tg_table_name = 'prueba_parametros_prubind' then
    new.nombre := btrim(new.nombre);
    if new.parametro_id is not null then
      select p.nombre, p.unidad_id, p.minimo, p.maximo, p.referencia
        into new.nombre, new.unidad_id, new.minimo, new.maximo, new.referencia
        from public.equipo_parametros_prubind p where p.id = new.parametro_id and p.equipo_id = new.equipo_id;
      if not found then raise exception 'El parámetro no pertenece al equipo.' using errcode = 'P0001'; end if;
    end if;
  elsif tg_table_name = 'plan_evaluacion_prubind' then
    if tg_op = 'UPDATE' and new.metodo_id is distinct from old.metodo_id then
      raise exception 'No se puede cambiar el método de un renglón del plan.' using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;

create or replace function public.prubind_validar_ejecucion()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v     public.pruebas_prubind%rowtype;
  v_pid uuid;
  uid   uuid := public.prubind_usuario_actual_id();
  v_ok  boolean;
  v_res boolean := false;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return coalesce(new, old); end if;
  if tg_table_name = 'batch_lotes_mp_prubind' then
    select b.prueba_id into v_pid from public.batches_prubind b where b.id = case when tg_op = 'DELETE' then old.batch_id else new.batch_id end;
  else
    v_pid := case when tg_op = 'DELETE' then old.prueba_id else new.prueba_id end;
  end if;
  select * into v from public.pruebas_prubind where id = v_pid;
  if v.id is null then return coalesce(new, old); end if;

  -- Resolución de una no conformidad (en evaluación o dictamen)
  if tg_op = 'UPDATE' and tg_table_name in ('batches_prubind', 'ejecucion_controles_prubind')
     and (to_jsonb(new) ->> 'resolucion') is distinct from (to_jsonb(old) ->> 'resolucion')
     and (to_jsonb(new) - 'resolucion' - 'updated_at') = (to_jsonb(old) - 'resolucion' - 'updated_at') then
    if not (public.prubind_puede(v_pid, 'evaluar') or public.prubind_puede(v_pid, 'dictaminar')) then
      raise exception 'No tiene autoridad para resolver no conformidades.' using errcode = '42501';
    end if;
    if v.estado not in ('en_ejecucion', 'en_evaluacion', 'pendiente_resultados', 'pendiente_dictamen') then
      raise exception 'La no conformidad solo se resuelve antes del dictamen.' using errcode = 'P0001';
    end if;
    new := jsonb_populate_record(new, jsonb_build_object('resolucion', nullif(btrim(to_jsonb(new) ->> 'resolucion'), '')));
    return new;
  end if;

  perform public.prubind_req(v_pid, 'ejecutar', null);
  if not public.prubind_ejecucion_abierta(v_pid) then
    raise exception 'La ejecución no está abierta: la prueba debe estar preparada%.',
      case when v.estado = 'preparada' then ' y con la autorización de ejecución' else '' end using errcode = 'P0001';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  if tg_table_name <> 'batch_lotes_mp_prubind' then
    if tg_op = 'UPDATE' and (new.prueba_id is distinct from old.prueba_id or new.ejecucion is distinct from old.ejecucion) then
      raise exception 'No se puede mover el registro a otra prueba o ejecución.' using errcode = 'P0001';
    end if;
    if tg_op = 'INSERT' then new.ejecucion := v.ejecucion_actual; end if;
  end if;

  if tg_table_name = 'lotes_diarios_prubind' then
    new.codigo := upper(btrim(new.codigo));
    if tg_op = 'INSERT' then new.created_by := uid; end if;
  elsif tg_table_name = 'batches_prubind' then
    if not exists (select 1 from public.lotes_diarios_prubind l where l.id = new.lote_diario_id and l.prueba_id = v_pid and l.ejecucion = new.ejecucion) then
      raise exception 'El batch debe pertenecer a un lote diario de esta prueba y ejecución.' using errcode = 'P0001';
    end if;
    if new.numero is null or new.numero = 0 then
      select coalesce(max(numero), 0) + 1 into new.numero from public.batches_prubind where prueba_id = v_pid and ejecucion = new.ejecucion;
    end if;
    if new.fecha_hora > now() + interval '15 minutes' then
      raise exception 'La fecha y hora de producción no puede ser futura.' using errcode = 'P0001';
    end if;
    new.identificador := nullif(upper(btrim(new.identificador)), '');
    new.incidencias := nullif(btrim(new.incidencias), '');
    if new.resultado_op = 'no_conforme' and new.incidencias is null then
      raise exception 'Describa la incidencia o desviación del batch no conforme.' using errcode = 'P0001';
    end if;
    if tg_op = 'INSERT' then new.capturado_por := uid; new.responsable_id := coalesce(new.responsable_id, uid); end if;
  elsif tg_table_name = 'ejecucion_controles_prubind' then
    new.nombre := btrim(new.nombre);
    new.valor := nullif(btrim(new.valor), '');
    new.observaciones := nullif(btrim(new.observaciones), '');
    if new.resultado = 'no_conforme' and new.observaciones is null then
      raise exception 'Justifique el resultado no conforme en observaciones.' using errcode = 'P0001';
    end if;
    if new.resultado <> 'pendiente' and new.fecha_hora is null then new.fecha_hora := now(); end if;
    if tg_op = 'INSERT' then new.responsable_id := coalesce(new.responsable_id, uid); end if;
  elsif tg_table_name = 'batch_lotes_mp_prubind' then
    if not exists (select 1 from public.lotes_mp_prubind l where l.id = new.lote_mp_id and l.activo) then
      raise exception 'El lote de materia prima no existe o está inactivo.' using errcode = 'P0001';
    end if;
  end if;

  if v.estado = 'preparada' then
    perform public.prubind_set_estado(v_pid, 'en_ejecucion', 'Inició la ejecución #' || v.ejecucion_actual || '.');
  end if;
  return new;
end $$;
