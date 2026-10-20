-- =====================================================================
-- v3 · Simplificación (solicitud del 15/10/2026)
-- No destructiva: lo que deja de usarse se DESACTIVA (activo = false).
--   1. Puestos: "Jefa de Calidad" → "Jefe de Calidad"; nuevo "Ingeniero de
--      Procesos y Mejora Continua".
--   2. Tipos: "Producto nuevo" independiente; "Cambio en la receta" se
--      unifica en "Cambio de formulación" (el tipo anterior se desactiva).
--      En el registro se usa "Receta" en lugar de "Producto".
--   3. Equipo predeterminado por tipo (ULMA para empaque primario): sus
--      parámetros se cargan solos en la preparación.
--   4. Plantillas: mediciones organizadas por batch; empaque primario
--      centrado en sellado, vacío, lotificado y parámetros de la ULMA.
--   5. Responsables por etapa según la tabla del usuario.
--   6. Inspectores (autoridad de ejecutar) capturan análisis durante la
--      ejecución; la evaluación sigue siendo del Jefe de Calidad.
--   7. El producto de la prueba se deriva de la receta seleccionada.
-- =====================================================================

-- 1. Puestos
update public.puestos_prubind set nombre = 'Jefe de Calidad' where nombre = 'Jefa de Calidad';
insert into public.puestos_prubind (nombre)
select 'Ingeniero de Procesos y Mejora Continua'
where not exists (select 1 from public.puestos_prubind where nombre = 'Ingeniero de Procesos y Mejora Continua');

-- 2. Tipos de prueba
update public.tipos_prueba_prubind set nombre = 'Producto nuevo',
  descripcion = 'Desarrollo de una receta nueva. Independiente de los cambios de formulación.',
  campos_registro = array['receta'] where codigo = 'producto_nuevo';
update public.tipos_prueba_prubind set nombre = 'Cambio de formulación',
  descripcion = 'Agregar, quitar o modificar materias primas y cantidades de una receta existente.',
  campos_registro = array['receta'] where codigo = 'cambio_formulacion';
update public.tipos_prueba_prubind set activo = false,
  descripcion = 'Unificado en "Cambio de formulación" (15/10/2026). Se conserva para el historial.'
where codigo = 'cambio_receta';
update public.pruebas_prubind set tipo = 'cambio_formulacion' where tipo = 'cambio_receta';
update public.tipos_prueba_prubind set campos_registro = array['materia_prima', 'proveedor', 'receta'] where codigo = 'cambio_proveedor';
update public.tipos_prueba_prubind set campos_registro = array['empaque', 'proveedor', 'equipo'] where codigo = 'material_empaque';
update public.tipos_prueba_prubind set campos_registro = array['empaque', 'proveedor'] where codigo = 'empaque_secundario';
update public.tipos_prueba_prubind set campos_registro = array['receta', 'proceso', 'equipo'] where codigo = 'cambio_proceso';
update public.tipos_prueba_prubind set campos_registro = array['equipo', 'receta'] where codigo = 'cambio_equipo';
update public.tipos_prueba_prubind set campos_registro = array['receta'] where codigo = 'vida_util';
update public.objetivos_prubind set nombre = 'Validar una receta nueva' where nombre = 'Validar un producto o receta nueva';

-- 3. Equipo predeterminado por tipo (columna nueva, opcional)
alter table public.tipos_prueba_prubind add column if not exists equipo_id uuid references public.equipos_prubind(id) on delete set null;
update public.tipos_prueba_prubind set equipo_id = (select id from public.equipos_prubind where lower(nombre) = 'ulma')
where codigo = 'material_empaque' and equipo_id is null;

-- 4. Plantillas y nombres visibles de los métodos
update public.metodos_prubind set nombre = 'Humedad' where codigo = 'BRO-HUM';
update public.metodos_prubind set nombre = 'Prueba de sellado' where codigo = 'EP-SELLO';
update public.metodos_prubind set nombre = 'Prueba de vacío' where codigo = 'EP-HERM';
update public.metodos_prubind set nombre = 'Lotificado o impresión correcta' where codigo = 'EP-COD';
-- Fabricación: todo se mide por batch
update public.plantilla_evaluacion_prubind set nivel = 'batch'
where tipo in ('producto_nuevo', 'cambio_formulacion', 'cambio_receta', 'cambio_proveedor', 'cambio_proceso', 'cambio_equipo')
  and nivel in ('lote_diario', 'compuesta');
-- Formulación y producto nuevo: la humedad se registra con los bromatológicos (sin duplicarla en fisicoquímicos)
update public.plantilla_evaluacion_prubind pt set activo = false
from public.metodos_prubind m
where m.id = pt.metodo_id and m.codigo = 'FQ-HUM' and pt.tipo in ('producto_nuevo', 'cambio_formulacion', 'cambio_receta');
-- Sensorial: se conserva como opcional (no forma parte de las mediciones obligatorias solicitadas)
update public.plantilla_evaluacion_prubind pt set obligatorio = false
from public.metodos_prubind m
where m.id = pt.metodo_id and m.categoria = 'sensorial' and pt.tipo in ('producto_nuevo', 'cambio_formulacion', 'cambio_receta');
-- Empaque primario: sellado, vacío y lotificado; especificaciones del film opcionales;
-- temperatura y parámetros de operación se registran como parámetros de la ULMA
update public.plantilla_evaluacion_prubind pt set activo = false
from public.metodos_prubind m
where m.id = pt.metodo_id and pt.tipo = 'material_empaque' and m.codigo in ('EP-PARAM', 'EP-TSELL', 'EP-VEL', 'EP-ABRE', 'EP-COMPAT', 'EP-COMPORT');
update public.plantilla_evaluacion_prubind pt set obligatorio = false
from public.metodos_prubind m
where m.id = pt.metodo_id and pt.tipo = 'material_empaque' and m.codigo in ('EP-CALIBRE', 'EP-ANCHO', 'EP-REPET', 'EP-BOBINA');

-- 5. Responsables por etapa
--   Preparación: Gerente de Producción
--   Ejecución: Jefe de Calidad e Inspector de Calidad (Jefe de Mantenimiento en proceso/equipo)
--   Evaluación: Jefe de Calidad
--   Dictamen: Dirección (Directora de Calidad y Director de Producción)
--   Cierre: Gerente de Procesos y Mejora Continua
update public.autoridades_prubind a set activo = false
from public.puestos_prubind p
where p.id = a.puesto_id and a.tipo is null and (
     (a.accion = 'preparar' and p.nombre in ('Jefe de Calidad', 'Gerente de Procesos y Mejora Continua'))
  or (a.accion = 'ejecutar' and p.nombre in ('Gerente de Producción', 'Supervisor de Producción'))
  or (a.accion = 'evaluar' and p.nombre in ('Directora de Calidad', 'Inspector de Calidad'))
  or (a.accion = 'cerrar' and p.nombre = 'Directora de Calidad'));
insert into public.autoridades_prubind (tipo, accion, puesto_id)
select null, x.accion, p.id
from (values ('ejecutar', 'Jefe de Calidad'), ('ejecutar', 'Inspector de Calidad'), ('dictaminar', 'Director de Producción'),
             ('preparar', 'Gerente de Producción'), ('evaluar', 'Jefe de Calidad'), ('cerrar', 'Gerente de Procesos y Mejora Continua'),
             ('dictaminar', 'Directora de Calidad')) x(accion, puesto)
join public.puestos_prubind p on p.nombre = x.puesto
on conflict (coalesce(tipo, '*'), accion, coalesce(puesto_id, usuario_id)) do update set activo = true;

-- 6. Captura de resultados: evaluar, o ejecutar mientras la prueba está en ejecución
create or replace function public.prubind_validar_resultado()
 returns trigger language plpgsql security definer set search_path = '' as $function$
declare
  v     public.pruebas_prubind%rowtype;
  pl    public.plan_evaluacion_prubind%rowtype;
  m     public.metodos_prubind%rowtype;
  uid   uuid := public.prubind_usuario_actual_id();
  v_pid uuid;
  v_rpc boolean := coalesce(current_setting('prubind.rpc', true), '') = '1';
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return coalesce(new, old); end if;
  if v_rpc then return coalesce(new, old); end if;
  v_pid := case when tg_op = 'DELETE' then old.prueba_id else new.prueba_id end;
  select * into v from public.pruebas_prubind where id = v_pid;
  if v.id is null then return coalesce(new, old); end if;

  if tg_op = 'UPDATE' and new.resolucion is distinct from old.resolucion
     and (to_jsonb(new) - 'resolucion' - 'updated_at') = (to_jsonb(old) - 'resolucion' - 'updated_at') then
    if not (public.prubind_puede(v_pid, 'evaluar') or public.prubind_puede(v_pid, 'dictaminar')) then
      raise exception 'No tiene autoridad para resolver no conformidades.' using errcode = '42501';
    end if;
    if v.estado not in ('en_evaluacion', 'pendiente_resultados', 'pendiente_dictamen') then
      raise exception 'La no conformidad solo se resuelve antes del dictamen.' using errcode = 'P0001';
    end if;
    new.resolucion := nullif(btrim(new.resolucion), '');
    return new;
  end if;

  if not (public.prubind_puede(v_pid, 'evaluar') or (v.estado = 'en_ejecucion' and public.prubind_puede(v_pid, 'ejecutar'))) then
    raise exception 'No tiene autoridad para capturar resultados en esta etapa.' using errcode = '42501';
  end if;
  if v.estado not in ('en_ejecucion', 'en_evaluacion', 'pendiente_resultados') then
    raise exception 'Los resultados se capturan durante la ejecución o la evaluación.' using errcode = 'P0001';
  end if;
  if tg_op = 'DELETE' then return old; end if;

  select * into pl from public.plan_evaluacion_prubind where id = new.plan_id and prueba_id = v_pid;
  if not found or not pl.incluido then
    raise exception 'El análisis no está en el plan de evaluación de esta prueba.' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.muestras_prubind s where s.id = new.muestra_id and s.prueba_id = v_pid and s.ejecucion = v.ejecucion_actual) then
    raise exception 'La muestra no pertenece a la ejecución actual de esta prueba.' using errcode = 'P0001';
  end if;
  select * into m from public.metodos_prubind where id = pl.metodo_id;
  if tg_op = 'UPDATE' and (new.plan_id, new.muestra_id) is distinct from (old.plan_id, old.muestra_id) then
    raise exception 'No se puede mover el resultado a otro análisis o muestra.' using errcode = 'P0001';
  end if;
  new.ejecucion := v.ejecucion_actual;
  new.metodo_id := pl.metodo_id;
  new.unidad_id := coalesce(new.unidad_id, m.unidad_id);
  new.justificacion := nullif(btrim(new.justificacion), '');
  new.valor_opcion := nullif(btrim(new.valor_opcion), '');

  if m.tipo_resultado = 'diluciones' then
    if new.dilucion is null or not (new.dilucion = any (m.diluciones)) then
      raise exception 'Indique una dilución válida para %: %.', m.nombre, array_to_string(m.diluciones, ', ') using errcode = 'P0001';
    end if;
  else
    new.dilucion := null;
  end if;
  if m.tipo_resultado in ('numerico', 'diluciones') then
    new.valor_opcion := null;
    if new.valor_num is null and new.estado in ('conforme', 'no_conforme') then
      raise exception 'Capture el valor numérico de %.', m.nombre using errcode = 'P0001';
    end if;
    if new.valor_num is not null and (pl.crit_minimo is not null or pl.crit_maximo is not null) then
      new.estado := case when (pl.crit_minimo is null or new.valor_num >= pl.crit_minimo)
                          and (pl.crit_maximo is null or new.valor_num <= pl.crit_maximo) then 'conforme' else 'no_conforme' end;
    end if;
  elsif m.tipo_resultado = 'presencia' then
    new.valor_num := null; new.unidad_id := null;
    if new.valor_opcion is not null and new.valor_opcion not in ('ausencia', 'presencia') then
      raise exception 'El resultado debe ser "ausencia" o "presencia".' using errcode = 'P0001';
    end if;
    if new.valor_opcion is not null and pl.crit_texto ilike '%ausencia%' then
      new.estado := case when new.valor_opcion = 'ausencia' then 'conforme' else 'no_conforme' end;
    end if;
  else
    new.valor_num := null;
    if new.valor_opcion is not null and cardinality(m.opciones) > 0 and not (new.valor_opcion = any (m.opciones)) then
      raise exception 'Opción no válida para %.', m.nombre using errcode = 'P0001';
    end if;
    if new.valor_opcion in ('conforme', 'no_conforme', 'no_aplica', 'pendiente') then new.estado := new.valor_opcion;
    elsif new.valor_opcion = 'no_evaluado' then new.estado := 'no_aplica'; end if;
  end if;
  if new.estado = 'no_conforme' and new.justificacion is null then
    raise exception '% no cumple el criterio: escriba una justificación breve.', m.nombre using errcode = 'P0001';
  end if;
  if new.estado <> 'pendiente' and new.fecha_lectura is null then new.fecha_lectura := now(); end if;
  if tg_op = 'INSERT' then
    new.capturado_por := uid; new.revisado_por := null; new.revisado_at := null; new.resolucion := null;
  else
    new.capturado_por := old.capturado_por; new.modificado_por := uid;
    if (new.valor_num, new.valor_opcion, new.estado, new.dilucion) is distinct from (old.valor_num, old.valor_opcion, old.estado, old.dilucion) then
      new.revisado_por := null; new.revisado_at := null;
    else
      new.revisado_por := old.revisado_por; new.revisado_at := old.revisado_at;
    end if;
  end if;
  return new;
end $function$;

-- 7. El producto se deriva de la receta (en pantalla solo se elige la receta)
create or replace function public.prubind_validar_prueba()
 returns trigger language plpgsql security definer set search_path = '' as $function$
declare
  uid   uuid := public.prubind_usuario_actual_id();
  v_rpc boolean := coalesce(current_setting('prubind.rpc', true), '') = '1';
  t     public.tipos_prueba_prubind%rowtype;
  v_n   integer;
  v_anio integer;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return coalesce(new, old); end if;
  if uid is null then raise exception 'Usuario no autorizado para Pruebas industriales.' using errcode = '42501'; end if;

  if tg_op = 'DELETE' then
    if old.estado <> 'registrada' then
      raise exception 'Solo se eliminan pruebas en estado "Registrada". Las demás se cancelan con motivo.' using errcode = 'P0001';
    end if;
    if not (uid = old.registrado_por or public.prubind_es_admin()) then
      raise exception 'Solo quien registró la prueba puede eliminarla.' using errcode = '42501';
    end if;
    if exists (select 1 from public.adjuntos_prubind a where a.prueba_id = old.id) then
      raise exception 'Elimine primero los archivos adjuntos.' using errcode = 'P0001';
    end if;
    return old;
  end if;

  select * into t from public.tipos_prueba_prubind where codigo = new.tipo;
  new.cambio := btrim(new.cambio);
  new.objetivo_desc := nullif(btrim(new.objetivo_desc), '');
  new.prioridad_just := case when new.prioridad = 'normal' then null else nullif(btrim(new.prioridad_just), '') end;
  new.proceso := nullif(btrim(new.proceso), '');
  new.empaque := nullif(btrim(new.empaque), '');
  new.plan_muestreo := nullif(btrim(new.plan_muestreo), '');
  if not ('receta' = any (t.campos_registro)) then new.receta_version_id := null; end if;
  new.producto_id := case
    when new.receta_version_id is not null then (select r.producto_id from public.receta_versiones_prubind rv
                                                   join public.recetas_prubind r on r.id = rv.receta_id where rv.id = new.receta_version_id)
    when 'producto' = any (t.campos_registro) then new.producto_id
    else null end;
  if not ('materia_prima' = any (t.campos_registro)) then new.materia_prima_id := null; end if;
  if not ('proveedor' = any (t.campos_registro)) then new.proveedor_id := null; end if;
  if not ('equipo' = any (t.campos_registro)) then new.equipo_id := null; end if;
  if not ('proceso' = any (t.campos_registro)) then new.proceso := null; end if;
  if not ('empaque' = any (t.campos_registro)) then new.empaque := null; end if;
  if new.prioridad <> 'normal' and new.prioridad_just is null then
    raise exception 'Justifique la prioridad alta o urgente.' using errcode = 'P0001';
  end if;
  if new.objetivo_id is not null and not exists (select 1 from public.objetivos_prubind o where o.id = new.objetivo_id and (o.tipo is null or o.tipo = new.tipo)) then
    raise exception 'El objetivo no corresponde al tipo de prueba.' using errcode = 'P0001';
  end if;
  if new.receta_version_id is not null and (tg_op = 'INSERT' or new.receta_version_id is distinct from old.receta_version_id)
     and not exists (select 1 from public.receta_versiones_prubind r where r.id = new.receta_version_id and r.estado = 'vigente') then
    raise exception 'Seleccione una receta vigente.' using errcode = 'P0001';
  end if;

  if tg_op = 'INSERT' then
    if not public.prubind_puede_crear_tipo(new.tipo) then
      raise exception 'El tipo de prueba no está activo.' using errcode = 'P0001';
    end if;
    v_anio := extract(year from public.prubind_hoy())::integer;
    insert into public.folios_prubind as f (anio, ultimo) values (v_anio, 1)
      on conflict (anio) do update set ultimo = f.ultimo + 1 returning ultimo into v_n;
    new.anio := v_anio; new.consecutivo := v_n;
    new.folio := 'PI-' || v_anio || '-' || lpad(v_n::text, 3, '0');
    new.registrado_por := uid;
    new.estado := 'registrada'; new.ejecucion_actual := 1;
    new.plan_confirmado_at := null; new.plan_confirmado_por := null;
    new.motivo_cancelacion := null; new.cancelado_por := null; new.cancelado_at := null;
    new.disposicion_cierre := null; new.cerrada_por := null; new.cerrada_at := null;
    return new;
  end if;

  if v_rpc then return new; end if;
  if (new.folio, new.anio, new.consecutivo, new.tipo, new.registrado_por, new.estado, new.ejecucion_actual,
      new.plan_confirmado_at, new.plan_confirmado_por, new.motivo_cancelacion, new.cancelado_por, new.cancelado_at,
      new.disposicion_cierre, new.cerrada_por, new.cerrada_at)
     is distinct from
     (old.folio, old.anio, old.consecutivo, old.tipo, old.registrado_por, old.estado, old.ejecucion_actual,
      old.plan_confirmado_at, old.plan_confirmado_por, old.motivo_cancelacion, old.cancelado_por, old.cancelado_at,
      old.disposicion_cierre, old.cerrada_por, old.cerrada_at) then
    raise exception 'El folio, el tipo y el estado solo cambian mediante las acciones de la prueba.' using errcode = 'P0001';
  end if;
  if old.estado not in ('registrada', 'en_preparacion') then
    raise exception 'Los datos de registro y preparación solo se modifican antes de marcar la prueba como preparada.' using errcode = 'P0001';
  end if;
  if not public.prubind_puede(old.id, 'preparar') then
    raise exception 'No tiene autoridad para modificar esta prueba.' using errcode = '42501';
  end if;
  if old.estado = 'registrada' and (new.fecha_planeada, new.batches_planeados, new.peso_objetivo_kg, new.responsable_ejecucion_id, new.plan_muestreo)
       is distinct from (old.fecha_planeada, old.batches_planeados, old.peso_objetivo_kg, old.responsable_ejecucion_id, old.plan_muestreo) then
    new.estado := 'en_preparacion';
  end if;
  return new;
end $function$;