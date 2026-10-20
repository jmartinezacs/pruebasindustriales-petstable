-- =====================================================================
-- Pruebas industriales · Migración 5
-- Permite el borrado en cascada de insumos cuando se elimina una prueba en
-- borrador (la validación de estado solo aplica al borrar un insumo suelto).
-- =====================================================================
create or replace function public.prubind_validar_insumo()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_uid   uuid := public.prubind_usuario_actual_id();
  v_p     public.pruebas_prubind%rowtype;
  v_resp  boolean;
  v_prod  boolean := public.prubind_tiene_funcion('produccion');
  v_comp  boolean := public.prubind_tiene_funcion('compras');
  v_pid   uuid;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if v_uid is null then
    raise exception 'Usuario no autorizado.' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then v_pid := old.prueba_id; else v_pid := new.prueba_id; end if;
  select * into v_p from public.pruebas_prubind where id = v_pid;
  -- Borrado en cascada al eliminar un borrador: la prueba ya no existe
  if tg_op = 'DELETE' and v_p.id is null then return old; end if;
  v_resp := public.prubind_es_admin() or v_p.creado_por = v_uid;

  if tg_op = 'DELETE' then
    if old.estado <> 'solicitado' then
      raise exception 'Solo se eliminan solicitudes que no han sido validadas. Use "Cancelar".' using errcode = 'P0001';
    end if;
    if not (v_resp or v_prod or old.solicitado_por = v_uid) then
      raise exception 'No tiene permiso para eliminar esta solicitud.' using errcode = '42501';
    end if;
    return old;
  end if;

  new.insumo := btrim(regexp_replace(new.insumo, '\s+', ' ', 'g'));
  new.unidad := btrim(new.unidad);
  new.especificacion := nullif(btrim(new.especificacion), '');
  new.proveedor := nullif(btrim(new.proveedor), '');
  new.obs_validacion := nullif(btrim(new.obs_validacion), '');
  new.orden_compra := nullif(btrim(new.orden_compra), '');
  new.obs_compras := nullif(btrim(new.obs_compras), '');
  new.motivo_cancelacion := nullif(btrim(new.motivo_cancelacion), '');

  if tg_op = 'INSERT' then
    if v_p.estado not in ('borrador', 'planeada', 'en_ejecucion') then
      raise exception 'Solo se solicitan insumos para pruebas en borrador, planeadas o en ejecución.' using errcode = 'P0001';
    end if;
    if not (v_resp or v_prod) then
      raise exception 'Solo Producción, el responsable de la prueba o un administrador pueden solicitar insumos.' using errcode = '42501';
    end if;
    new.estado := 'solicitado'; new.solicitado_por := v_uid;
    new.cantidad_validada := null; new.obs_validacion := null; new.validado_por := null; new.validado_at := null;
    new.orden_compra := null; new.obs_compras := null; new.cantidad_recibida := null; new.fecha_recepcion := null;
    new.compras_por := null; new.motivo_cancelacion := null;
    return new;
  end if;

  -- UPDATE
  if new.prueba_id is distinct from old.prueba_id or new.solicitado_por is distinct from old.solicitado_por then
    raise exception 'No se puede cambiar la prueba ni el solicitante del insumo.' using errcode = 'P0001';
  end if;
  if old.estado in ('recibido', 'cancelado') then
    raise exception 'La solicitud del insumo ya está cerrada.' using errcode = 'P0001';
  end if;
  if v_p.estado in ('aprobada', 'rechazada', 'cancelada') and new.estado <> 'cancelado' then
    raise exception 'La prueba está cerrada; solo puede cancelar la solicitud.' using errcode = 'P0001';
  end if;

  -- Datos de la solicitud: editables solo mientras está "solicitado"
  if (new.insumo, new.especificacion, new.proveedor, new.unidad, new.cantidad_por_batch, new.cantidad_solicitada, new.fecha_requerida)
     is distinct from (old.insumo, old.especificacion, old.proveedor, old.unidad, old.cantidad_por_batch, old.cantidad_solicitada, old.fecha_requerida) then
    if old.estado <> 'solicitado' then
      raise exception 'El insumo ya fue validado; sus datos de solicitud no pueden cambiar.' using errcode = 'P0001';
    end if;
    if not (v_resp or v_prod or old.solicitado_por = v_uid) then
      raise exception 'No tiene permiso para editar esta solicitud.' using errcode = '42501';
    end if;
  end if;

  -- Los autores de cada etapa los asigna el servidor; nunca el cliente
  new.validado_por := old.validado_por; new.validado_at := old.validado_at; new.compras_por := old.compras_por;

  if new.estado is distinct from old.estado then
    -- Al avanzar a compra/recepción/cancelación la validación queda congelada
    if new.estado in ('en_compra', 'recibido', 'cancelado') then
      new.cantidad_validada := old.cantidad_validada; new.obs_validacion := old.obs_validacion;
    end if;
    if new.estado = 'validado' and old.estado = 'solicitado' then
      if not v_prod then raise exception 'Solo Producción valida las cantidades de insumos.' using errcode = '42501'; end if;
      if new.cantidad_validada is null then raise exception 'Indique la cantidad validada.' using errcode = 'P0001'; end if;
      new.validado_por := v_uid; new.validado_at := now();
    elsif new.estado = 'solicitado' and old.estado = 'validado' then
      if not v_prod then raise exception 'Solo Producción puede retirar su validación.' using errcode = '42501'; end if;
      new.cantidad_validada := null; new.validado_por := null; new.validado_at := null;
    elsif new.estado = 'en_compra' and old.estado = 'validado' then
      if not v_comp then raise exception 'Solo Compras registra la compra de insumos.' using errcode = '42501'; end if;
      new.compras_por := v_uid;
    elsif new.estado = 'recibido' and old.estado in ('validado', 'en_compra') then
      if not v_comp then raise exception 'Solo Compras registra la recepción de insumos.' using errcode = '42501'; end if;
      if new.cantidad_recibida is null or new.fecha_recepcion is null then
        raise exception 'Indique la cantidad recibida y la fecha de recepción.' using errcode = 'P0001';
      end if;
      if new.fecha_recepcion > public.prubind_hoy() then
        raise exception 'La fecha de recepción no puede ser futura.' using errcode = 'P0001';
      end if;
      new.compras_por := v_uid;
    elsif new.estado = 'cancelado' then
      if not (v_resp or v_prod or v_comp or old.solicitado_por = v_uid) then
        raise exception 'No tiene permiso para cancelar esta solicitud.' using errcode = '42501';
      end if;
      if new.motivo_cancelacion is null then raise exception 'Indique el motivo de la cancelación.' using errcode = 'P0001'; end if;
    else
      raise exception 'Cambio de estado de insumo no permitido (% → %).', old.estado, new.estado using errcode = 'P0001';
    end if;
  else
    -- Sin cambio de estado: validar quién toca los campos de cada etapa
    if (new.cantidad_validada, new.obs_validacion) is distinct from (old.cantidad_validada, old.obs_validacion) then
      if not v_prod then raise exception 'Solo Producción modifica la validación.' using errcode = '42501'; end if;
      if old.estado not in ('solicitado', 'validado') then
        raise exception 'El insumo ya está en compra; la validación no puede cambiar.' using errcode = 'P0001';
      end if;
    end if;
    if (new.orden_compra, new.obs_compras, new.cantidad_recibida, new.fecha_recepcion) is distinct from
       (old.orden_compra, old.obs_compras, old.cantidad_recibida, old.fecha_recepcion) and not v_comp then
      raise exception 'Solo Compras modifica los datos de compra.' using errcode = '42501';
    end if;
  end if;
  if new.estado <> 'cancelado' then new.motivo_cancelacion := null; end if;
  return new;
end $$;
