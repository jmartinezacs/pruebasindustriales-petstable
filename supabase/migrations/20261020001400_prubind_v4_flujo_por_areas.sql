-- =====================================================================
-- v4 · Flujo por áreas (narración del usuario, 20/10/2026)
--   1. Registro: cualquier persona registra la prueba con fecha, objetivo,
--      tipo y los PARÁMETROS A EVALUAR por área. Sin etapa de preparación.
--   2. Áreas: Calidad (siempre), Producción (siempre), Seguridad y
--      Mantenimiento (cuando la prueba los involucra).
--   3. Registro durante el proceso: Calidad → Inspectores; Producción →
--      Supervisores; Seguridad → Supervisor de Seguridad, Salud y Ambiente;
--      Mantenimiento → Jefe de Mantenimiento.
--   4. Evaluaciones complementarias (sensorial, microbiología, bromatología)
--      solo para materia prima, reformulación y producto nuevo.
--   5. Resultados por parámetro: Cumple / No cumple + observaciones (obligatorias
--      si no cumple). Evalúa el jefe de cada área.
--   6. Recomendaciones por área. 7. Dictamen de Alta Dirección. Cierre se conserva.
--   Tipos: solo los 5 principales quedan activos (los demás se desactivan).
-- No destructiva: lo que deja de usarse se DESACTIVA; ningún dato se elimina.
-- =====================================================================

-- ---------- 1. Puesto nuevo --------------------------------------------
insert into public.puestos_prubind (nombre)
select 'Supervisor de Seguridad, Salud y Ambiente'
where not exists (select 1 from public.puestos_prubind where lower(nombre) = lower('Supervisor de Seguridad, Salud y Ambiente'));

-- ---------- 2. Área de cada parámetro ----------------------------------
alter table public.metodos_prubind drop constraint if exists metodos_prubind_categoria_check;
alter table public.metodos_prubind add constraint metodos_prubind_categoria_check check (categoria in ('fisicoquimica','sensorial','microbiologia',
  'bromatologia','empaque_primario','empaque_secundario','proceso','equipo','materia_prima','vida_util','seguridad','general'));
alter table public.metodos_prubind add column if not exists area text not null default 'calidad'
  check (area in ('calidad','produccion','seguridad','mantenimiento'));
update public.metodos_prubind set area = case categoria when 'proceso' then 'produccion' when 'equipo' then 'mantenimiento'
  when 'seguridad' then 'seguridad' else 'calidad' end;
-- La humedad bromatológica la evalúa el Jefe de Calidad (sin revisión adicional de la Directora)
update public.metodos_prubind set revisa_puesto_id = null where categoria = 'bromatologia';

-- Parámetros nuevos (sin criterios de aceptación: no se inventan límites)
insert into public.metodos_prubind (codigo, nombre, categoria, area, tipo_resultado, unidad_id, opciones)
select x.codigo, x.nombre, x.categoria, x.area, x.tipo, (select id from public.unidades_prubind where simbolo = x.unidad), x.opciones
from (values
  ('FQ-TEMP',     'Temperatura de cocción',         'fisicoquimica', 'calidad',    'numerico', '°C',   '{}'::text[]),
  ('FQ-CONS',     'Consistencia',                   'fisicoquimica', 'calidad',    'numerico', 'cm/s', '{}'::text[]),
  ('PROD-MERMA',  'Merma',                          'proceso',       'produccion', 'numerico', '%',    '{}'::text[]),
  ('PROD-TACOND', 'Tiempo de acondicionamiento',    'proceso',       'produccion', 'numerico', 'min',  '{}'::text[]),
  ('PROD-TCOC',   'Tiempo de cocción',              'proceso',       'produccion', 'numerico', 'min',  '{}'::text[]),
  ('PROD-TMOL',   'Tiempo de molienda',             'proceso',       'produccion', 'numerico', 'min',  '{}'::text[]),
  ('SEG-EPP',     'Equipo de protección personal adecuado',             'seguridad', 'seguridad', 'opcion', null, '{conforme,no_conforme,no_aplica}'::text[]),
  ('SEG-RIESGO',  'El personal no se expone a riesgos durante la prueba', 'seguridad', 'seguridad', 'opcion', null, '{conforme,no_conforme,no_aplica}'::text[]),
  ('SEG-COND',    'Condiciones seguras del área y del equipo',          'seguridad', 'seguridad', 'opcion', null, '{conforme,no_conforme,no_aplica}'::text[])
) x(codigo, nombre, categoria, area, tipo, unidad, opciones)
on conflict (codigo) do nothing;

-- ---------- 3. Tipos de prueba: los 5 de la narración ------------------
update public.tipos_prueba_prubind set nombre = 'Nuevo producto', orden = 1 where codigo = 'producto_nuevo';
update public.tipos_prueba_prubind set nombre = 'Cambio en la formulación', orden = 2 where codigo = 'cambio_formulacion';
update public.tipos_prueba_prubind set nombre = 'Cambio de proveedor', orden = 3 where codigo = 'cambio_proveedor';
update public.tipos_prueba_prubind set nombre = 'Material de empaque', orden = 4,
  descripcion = 'Prueba de un material de empaque (film, insumos de empaque) en la línea.' where codigo = 'material_empaque';
update public.tipos_prueba_prubind set nombre = 'Cambio en el proceso', orden = 5 where codigo = 'cambio_proceso';
update public.tipos_prueba_prubind set activo = false
where codigo in ('cambio_especificacion_mp', 'empaque_secundario', 'cambio_equipo', 'vida_util');
-- Sin autorización de ejecución separada: se captura en cuanto se registra
update public.tipos_prueba_prubind set requiere_aut_ejecucion = false;

-- ---------- 4. Plantillas: parámetros sugeridos por tipo y área ---------
-- "obligatorio" en la plantilla = sugerido (aparece marcado al registrar).
update public.plantilla_evaluacion_prubind set activo = false
where tipo in ('producto_nuevo', 'cambio_formulacion', 'cambio_proveedor', 'material_empaque', 'cambio_proceso');
insert into public.plantilla_evaluacion_prubind (tipo, metodo_id, obligatorio, nivel, orden, activo)
select t.tipo, m.id, x.sugerido, case when t.fab and x.nivel_fab = 'batch' then 'batch' else 'corrida' end, x.orden, true
from (values
  -- Calidad · durante el proceso
  ('FQ-TEMP', true, 'batch', 10, 'fab'), ('FQ-CONS', true, 'batch', 11, 'fab'), ('FQ-HUM', true, 'batch', 12, 'fab'), ('FQ-PH', true, 'batch', 13, 'fab'),
  ('EP-SELLO', true, 'corrida', 10, 'emp'), ('EP-HERM', true, 'corrida', 11, 'emp'), ('EP-COD', true, 'corrida', 12, 'emp'),
  ('EP-CALIBRE', false, 'corrida', 13, 'emp'), ('EP-ANCHO', false, 'corrida', 14, 'emp'), ('EP-REPET', false, 'corrida', 15, 'emp'), ('EP-BOBINA', false, 'corrida', 16, 'emp'),
  ('MP-COA', false, 'corrida', 50, 'prov'), ('MP-FT', false, 'corrida', 51, 'prov'), ('MP-INSP', false, 'corrida', 52, 'prov'),
  -- Calidad · evaluaciones complementarias (materia prima, reformulación y producto nuevo)
  ('SEN-OLOR', true, 'batch', 20, 'comp'), ('SEN-COLOR', true, 'batch', 21, 'comp'), ('SEN-SABOR', true, 'batch', 22, 'comp'), ('SEN-TEXTURA', true, 'batch', 23, 'comp'),
  ('MIC-SALM', true, 'batch', 30, 'comp'), ('MIC-ECOLI', true, 'batch', 31, 'comp'), ('MIC-MESO', true, 'batch', 32, 'comp'),
  ('MIC-HONGOS', true, 'batch', 33, 'comp'), ('MIC-LEV', true, 'batch', 34, 'comp'), ('MIC-COLI', false, 'batch', 35, 'comp'), ('MIC-O157', false, 'batch', 36, 'comp'),
  ('BRO-PRO', true, 'batch', 40, 'comp'), ('BRO-GRA', true, 'batch', 41, 'comp'), ('BRO-HUM', true, 'batch', 42, 'comp'), ('BRO-CEN', true, 'batch', 43, 'comp'),
  -- Producción · dinámicos
  ('PROD-MERMA', true, 'batch', 60, 'todos'), ('PROD-TACOND', true, 'batch', 61, 'fab'), ('PROD-TCOC', true, 'batch', 62, 'fab'), ('PROD-TMOL', true, 'batch', 63, 'fab'),
  ('PR-PARAM', false, 'corrida', 64, 'proc'), ('PR-REND', false, 'corrida', 65, 'proc'),
  -- Seguridad (siempre los mismos; se incluyen si la prueba involucra seguridad)
  ('SEG-EPP', true, 'corrida', 70, 'todos'), ('SEG-RIESGO', true, 'corrida', 71, 'todos'), ('SEG-COND', true, 'corrida', 72, 'todos'),
  -- Mantenimiento (se incluyen si la prueba involucra máquinas o equipos)
  ('EQ-FUNC', true, 'corrida', 80, 'todos'), ('EQ-PARAM', true, 'corrida', 81, 'todos'), ('EQ-INST', false, 'corrida', 82, 'todos'), ('EQ-LIMP', false, 'corrida', 83, 'todos')
) x(codigo, sugerido, nivel_fab, orden, aplica)
join public.metodos_prubind m on m.codigo = x.codigo
join (values ('producto_nuevo', true), ('cambio_formulacion', true), ('cambio_proveedor', true), ('cambio_proceso', true), ('material_empaque', false)) t(tipo, fab)
  on x.aplica = 'todos'
  or (x.aplica = 'fab' and t.fab)
  or (x.aplica = 'emp' and t.tipo = 'material_empaque')
  or (x.aplica = 'comp' and t.tipo in ('producto_nuevo', 'cambio_formulacion', 'cambio_proveedor'))
  or (x.aplica = 'prov' and t.tipo = 'cambio_proveedor')
  or (x.aplica = 'proc' and t.tipo = 'cambio_proceso')
on conflict (tipo, metodo_id) do update set obligatorio = excluded.obligatorio, nivel = excluded.nivel, orden = excluded.orden, activo = true;

-- ---------- 5. Autoridades por área ------------------------------------
alter table public.autoridades_prubind drop constraint if exists autoridades_prubind_accion_check;
alter table public.autoridades_prubind add constraint autoridades_prubind_accion_check check (accion in ('preparar','abastecer','autorizar_ejecucion',
  'ejecutar','evaluar','dictaminar','cerrar','autorizar_implementacion',
  'capturar_calidad','capturar_produccion','capturar_seguridad','capturar_mantenimiento',
  'evaluar_calidad','evaluar_produccion','evaluar_seguridad','evaluar_mantenimiento'));
-- Ya no hay preparación, abastecimiento ni autorización de ejecución; captura y evaluación pasan a ser por área
update public.autoridades_prubind set activo = false
where accion in ('preparar', 'abastecer', 'autorizar_ejecucion', 'ejecutar', 'evaluar');
insert into public.autoridades_prubind (tipo, accion, puesto_id)
select null, x.accion, p.id
from (values
  ('capturar_calidad', 'Inspector de Calidad'), ('capturar_calidad', 'Jefe de Calidad'),
  ('capturar_produccion', 'Supervisor de Producción'), ('capturar_produccion', 'Gerente de Producción'),
  ('capturar_seguridad', 'Supervisor de Seguridad, Salud y Ambiente'),
  ('capturar_mantenimiento', 'Jefe de Mantenimiento'),
  ('evaluar_calidad', 'Jefe de Calidad'),
  ('evaluar_produccion', 'Gerente de Producción'),
  ('evaluar_seguridad', 'Supervisor de Seguridad, Salud y Ambiente'),
  ('evaluar_mantenimiento', 'Jefe de Mantenimiento')
) x(accion, puesto)
join public.puestos_prubind p on p.nombre = x.puesto
on conflict (coalesce(tipo, '*'), accion, coalesce(puesto_id, usuario_id)) do update set activo = true;

-- ---------- 6. Registro: cantidad a evaluar -----------------------------
alter table public.pruebas_prubind
  add column if not exists cantidad_evaluar numeric(14,3) check (cantidad_evaluar is null or cantidad_evaluar > 0),
  add column if not exists cantidad_unidad_id uuid references public.unidades_prubind(id) on delete restrict;
create index if not exists pruebas_prubind_cantidad_unidad_id_idx on public.pruebas_prubind (cantidad_unidad_id);

-- ---------- 7. Evaluación por parámetro y recomendaciones por área -----
create table if not exists public.evaluaciones_prubind (
  id                  uuid primary key default gen_random_uuid(),
  prueba_id           uuid not null references public.pruebas_prubind(id) on delete restrict,
  ejecucion           integer not null default 1,
  plan_id             uuid references public.plan_evaluacion_prubind(id) on delete cascade,
  prueba_parametro_id uuid references public.prueba_parametros_prubind(id) on delete cascade,
  area                text not null check (area in ('calidad','produccion','seguridad','mantenimiento')),
  evaluacion          text not null check (evaluacion in ('cumple','no_cumple')),
  observaciones       text not null check (char_length(btrim(observaciones)) between 1 and 500),
  evaluado_por        uuid not null references public.usuarios_prubind(id) on delete restrict,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint evaluaciones_prubind_objeto_ck check ((plan_id is null) <> (prueba_parametro_id is null))
);
create unique index if not exists evaluaciones_prubind_plan_uk on public.evaluaciones_prubind (plan_id, ejecucion) where plan_id is not null;
create unique index if not exists evaluaciones_prubind_par_uk on public.evaluaciones_prubind (prueba_parametro_id, ejecucion) where prueba_parametro_id is not null;
create index if not exists evaluaciones_prubind_prueba_idx on public.evaluaciones_prubind (prueba_id, ejecucion);
create index if not exists evaluaciones_prubind_por_idx on public.evaluaciones_prubind (evaluado_por);

create table if not exists public.recomendaciones_prubind (
  id            uuid primary key default gen_random_uuid(),
  prueba_id     uuid not null references public.pruebas_prubind(id) on delete restrict,
  ejecucion     integer not null default 1,
  area          text not null check (area in ('calidad','produccion','seguridad','mantenimiento')),
  sentido       text not null check (sentido in ('favorable','no_favorable','repetir')),
  recomendacion text not null check (char_length(btrim(recomendacion)) between 3 and 1000),
  emitido_por   uuid not null references public.usuarios_prubind(id) on delete restrict,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create unique index if not exists recomendaciones_prubind_uk on public.recomendaciones_prubind (prueba_id, ejecucion, area);
create index if not exists recomendaciones_prubind_por_idx on public.recomendaciones_prubind (emitido_por);

alter table public.evaluaciones_prubind enable row level security;
alter table public.recomendaciones_prubind enable row level security;
do $$
declare t text;
begin
  foreach t in array array['evaluaciones_prubind', 'recomendaciones_prubind'] loop
    execute format('drop policy if exists %I on public.%I', t || '_sel', t);
    execute format('create policy %I on public.%I for select to authenticated using ((select public.prubind_es_miembro()))', t || '_sel', t);
    execute format('drop policy if exists %I on public.%I', t || '_ins', t);
    execute format('create policy %I on public.%I for insert to authenticated with check ((select public.prubind_es_miembro()))', t || '_ins', t);
    execute format('drop policy if exists %I on public.%I', t || '_upd', t);
    execute format('create policy %I on public.%I for update to authenticated using ((select public.prubind_es_miembro())) with check ((select public.prubind_es_miembro()))', t || '_upd', t);
    execute format('drop policy if exists %I on public.%I', t || '_del', t);
    execute format('create policy %I on public.%I for delete to authenticated using ((select public.prubind_es_miembro()))', t || '_del', t);
    execute format('revoke all on public.%I from anon, public', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('drop trigger if exists %I on public.%I', t || '_touch', t);
    execute format('create trigger %I before update on public.%I for each row execute function public.prubind_touch_updated_at()', t || '_touch', t);
    execute format('drop trigger if exists %I on public.%I', t || '_audit', t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.prubind_auditar()', t || '_audit', t);
  end loop;
end $$;

-- ---------- 8. Funciones de autoridad ----------------------------------
create or replace function public.prubind_accion_txt(p text)
returns text language sql immutable set search_path = '' as $$
  select case p when 'preparar' then 'modificar el registro de la prueba' when 'abastecer' then 'abastecimiento de materiales'
    when 'autorizar_ejecucion' then 'autorizar la ejecución' when 'ejecutar' then 'registrar datos durante el proceso' when 'evaluar' then 'evaluar resultados'
    when 'dictaminar' then 'emitir el dictamen' when 'cerrar' then 'cerrar la prueba' when 'autorizar_implementacion' then 'autorizar la implementación'
    when 'cancelar' then 'cancelar la prueba'
    when 'capturar_calidad' then 'registrar parámetros de Calidad' when 'capturar_produccion' then 'registrar parámetros de Producción'
    when 'capturar_seguridad' then 'registrar parámetros de Seguridad' when 'capturar_mantenimiento' then 'registrar parámetros de Mantenimiento'
    when 'evaluar_calidad' then 'evaluar los resultados de Calidad' when 'evaluar_produccion' then 'evaluar los resultados de Producción'
    when 'evaluar_seguridad' then 'evaluar los resultados de Seguridad' when 'evaluar_mantenimiento' then 'evaluar los resultados de Mantenimiento'
    else p end
$$;

-- ¿Tiene alguna autoridad cuyo nombre empiece con el prefijo (p. ej. "capturar_")?
create or replace function public.prubind_tiene_autoridad_prefijo(p_tipo text, p_prefijo text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.autoridades_prubind a
    where a.activo and left(a.accion, char_length(p_prefijo)) = p_prefijo and (a.tipo is null or a.tipo = p_tipo)
      and ((a.usuario_id is not null and a.usuario_id = public.prubind_usuario_actual_id())
        or (a.puesto_id is not null and a.puesto_id = public.prubind_puesto_actual())))
$$;

create or replace function public.prubind_puede(p_prueba uuid, p_accion text)
 returns boolean language plpgsql stable security definer set search_path = '' as $function$
declare
  v   public.pruebas_prubind%rowtype;
  uid uuid := public.prubind_usuario_actual_id();
begin
  if uid is null then return false; end if;
  select * into v from public.pruebas_prubind where id = p_prueba;
  if not found then return false; end if;
  return coalesce(case p_accion
    when 'preparar' then uid is not distinct from v.registrado_por or uid is not distinct from v.responsable_inicial_id
                         or uid is not distinct from v.responsable_ejecucion_id or public.prubind_tiene_autoridad(v.tipo, 'preparar')
    when 'abastecer' then public.prubind_tiene_autoridad(v.tipo, 'abastecer') or public.prubind_puede(p_prueba, 'preparar')
    -- Registro durante el proceso: cualquiera que capture por alguna área
    when 'ejecutar'  then uid is not distinct from v.responsable_ejecucion_id or public.prubind_tiene_autoridad(v.tipo, 'ejecutar')
                         or public.prubind_tiene_autoridad_prefijo(v.tipo, 'capturar_')
    -- Evaluación: el jefe de alguna de las áreas
    when 'evaluar'   then public.prubind_tiene_autoridad(v.tipo, 'evaluar') or public.prubind_tiene_autoridad_prefijo(v.tipo, 'evaluar_')
    when 'cancelar'  then uid is not distinct from v.registrado_por or uid is not distinct from v.responsable_inicial_id
                         or public.prubind_tiene_autoridad(v.tipo, 'cerrar') or public.prubind_tiene_autoridad(v.tipo, 'dictaminar')
    else public.prubind_tiene_autoridad(v.tipo, p_accion)
  end, false);
end $function$;

-- ¿Puede capturar o evaluar parámetros de esa área en esa prueba?
create or replace function public.prubind_puede_area(p_prueba uuid, p_rol text, p_area text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select public.prubind_tiene_autoridad(p.tipo, p_rol || '_' || p_area)
                   from public.pruebas_prubind p where p.id = p_prueba), false)
$$;

-- La captura se abre al registrar la prueba (sin preparación ni autorización previa)
create or replace function public.prubind_ejecucion_abierta(p_prueba uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.pruebas_prubind p join public.tipos_prueba_prubind t on t.codigo = p.tipo
    where p.id = p_prueba and (p.estado = 'en_ejecucion' or (p.estado in ('registrada', 'en_preparacion', 'preparada') and (not t.requiere_aut_ejecucion
      or exists (select 1 from public.autorizaciones_prubind a where a.prueba_id = p.id and a.ejecucion = p.ejecucion_actual and a.tipo = 'ejecucion')))))
$$;

-- Pasa a "En proceso" con el primer dato capturado (uso interno)
create or replace function public.prubind_iniciar_captura(p_prueba uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v public.pruebas_prubind%rowtype;
begin
  select * into v from public.pruebas_prubind where id = p_prueba;
  if v.estado in ('registrada', 'en_preparacion', 'preparada') then
    perform public.prubind_set_estado(p_prueba, 'en_ejecucion', 'Inició el registro durante el proceso (ejecución #' || v.ejecucion_actual || ').');
  end if;
end $$;

-- ---------- 9. Registro de la prueba (objetivo obligatorio) -------------
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
  if new.cantidad_evaluar is null then new.cantidad_unidad_id := null; end if;
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
    if new.objetivo_desc is null and new.objetivo_id is null then
      raise exception 'Escriba el objetivo de la prueba (qué se desea evaluar).' using errcode = 'P0001';
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
  if old.estado not in ('registrada', 'en_preparacion', 'preparada') then
    raise exception 'El registro solo se modifica antes de empezar a capturar datos del proceso.' using errcode = 'P0001';
  end if;
  if not public.prubind_puede(old.id, 'preparar') then
    raise exception 'Solo quien registró la prueba (o su responsable) puede modificar el registro.' using errcode = '42501';
  end if;
  return new;
end $function$;

-- ---------- 10. Registro durante el proceso ----------------------------
create or replace function public.prubind_validar_ejecucion()
 returns trigger language plpgsql security definer set search_path = '' as $function$
declare
  v     public.pruebas_prubind%rowtype;
  v_pid uuid;
  uid   uuid := public.prubind_usuario_actual_id();
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return coalesce(new, old); end if;
  if tg_table_name = 'batch_lotes_mp_prubind' then
    select b.prueba_id into v_pid from public.batches_prubind b where b.id = case when tg_op = 'DELETE' then old.batch_id else new.batch_id end;
  else
    v_pid := case when tg_op = 'DELETE' then old.prueba_id else new.prueba_id end;
  end if;
  select * into v from public.pruebas_prubind where id = v_pid;
  if v.id is null then return coalesce(new, old); end if;

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

  if not public.prubind_puede(v_pid, 'ejecutar') then
    raise exception 'No tiene autoridad para registrar datos durante el proceso.' using errcode = '42501';
  end if;
  if not public.prubind_ejecucion_abierta(v_pid) then
    raise exception 'El registro durante el proceso ya terminó para esta prueba.' using errcode = 'P0001';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  if tg_table_name <> 'batch_lotes_mp_prubind' then
    if tg_op = 'UPDATE' and ((to_jsonb(new) ->> 'prueba_id') is distinct from (to_jsonb(old) ->> 'prueba_id')
                             or (to_jsonb(new) ->> 'ejecucion') is distinct from (to_jsonb(old) ->> 'ejecucion')) then
      raise exception 'No se puede mover el registro a otra prueba o ejecución.' using errcode = 'P0001';
    end if;
    if tg_op = 'INSERT' then new := jsonb_populate_record(new, jsonb_build_object('ejecucion', v.ejecucion_actual)); end if;
  end if;

  if tg_table_name = 'lotes_diarios_prubind' then
    new := jsonb_populate_record(new, jsonb_build_object('codigo', upper(btrim(to_jsonb(new) ->> 'codigo'))));
    if tg_op = 'INSERT' then new := jsonb_populate_record(new, jsonb_build_object('created_by', uid)); end if;
  elsif tg_table_name = 'batches_prubind' then
    if not exists (select 1 from public.lotes_diarios_prubind l where l.id = (to_jsonb(new) ->> 'lote_diario_id')::uuid
                   and l.prueba_id = v_pid and l.ejecucion = (to_jsonb(new) ->> 'ejecucion')::int) then
      raise exception 'El batch debe pertenecer a un lote diario de esta prueba y ejecución.' using errcode = 'P0001';
    end if;
    if coalesce((to_jsonb(new) ->> 'numero')::int, 0) = 0 then
      new := jsonb_populate_record(new, jsonb_build_object('numero',
        (select coalesce(max(numero), 0) + 1 from public.batches_prubind where prueba_id = v_pid and ejecucion = (to_jsonb(new) ->> 'ejecucion')::int)));
    end if;
    if (to_jsonb(new) ->> 'fecha_hora')::timestamptz > now() + interval '15 minutes' then
      raise exception 'La fecha y hora de producción no puede ser futura.' using errcode = 'P0001';
    end if;
    new := jsonb_populate_record(new, jsonb_build_object(
      'identificador', nullif(upper(btrim(to_jsonb(new) ->> 'identificador')), ''),
      'incidencias', nullif(btrim(to_jsonb(new) ->> 'incidencias'), '')));
    if to_jsonb(new) ->> 'resultado_op' = 'no_conforme' and to_jsonb(new) ->> 'incidencias' is null then
      raise exception 'Describa la incidencia o desviación del batch.' using errcode = 'P0001';
    end if;
    if tg_op = 'INSERT' then
      new := jsonb_populate_record(new, jsonb_build_object('capturado_por', uid, 'responsable_id', coalesce((to_jsonb(new) ->> 'responsable_id')::uuid, uid)));
    end if;
  elsif tg_table_name = 'ejecucion_controles_prubind' then
    new := jsonb_populate_record(new, jsonb_build_object('nombre', btrim(to_jsonb(new) ->> 'nombre'),
      'valor', nullif(btrim(to_jsonb(new) ->> 'valor'), ''), 'observaciones', nullif(btrim(to_jsonb(new) ->> 'observaciones'), '')));
    if to_jsonb(new) ->> 'resultado' = 'no_conforme' and to_jsonb(new) ->> 'observaciones' is null then
      raise exception 'Justifique el resultado fuera de lo esperado en observaciones.' using errcode = 'P0001';
    end if;
    if to_jsonb(new) ->> 'resultado' <> 'pendiente' and to_jsonb(new) ->> 'fecha_hora' is null then
      new := jsonb_populate_record(new, jsonb_build_object('fecha_hora', now()));
    end if;
    if tg_op = 'INSERT' then new := jsonb_populate_record(new, jsonb_build_object('responsable_id', coalesce((to_jsonb(new) ->> 'responsable_id')::uuid, uid))); end if;
  elsif tg_table_name = 'batch_lotes_mp_prubind' then
    if not exists (select 1 from public.lotes_mp_prubind l where l.id = (to_jsonb(new) ->> 'lote_mp_id')::uuid and l.activo) then
      raise exception 'El lote de materia prima no existe o está inactivo.' using errcode = 'P0001';
    end if;
  end if;

  perform public.prubind_iniciar_captura(v_pid);
  return new;
end $function$;

create or replace function public.prubind_validar_muestra()
 returns trigger language plpgsql security definer set search_path = '' as $function$
declare
  v     public.pruebas_prubind%rowtype;
  v_pid uuid;
  v_n   integer;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return coalesce(new, old); end if;
  if tg_table_name = 'muestra_batches_prubind' then
    select m.prueba_id into v_pid from public.muestras_prubind m where m.id = case when tg_op = 'DELETE' then old.muestra_id else new.muestra_id end;
  else
    v_pid := case when tg_op = 'DELETE' then old.prueba_id else new.prueba_id end;
  end if;
  select * into v from public.pruebas_prubind where id = v_pid;
  if v.id is null then return coalesce(new, old); end if;
  if not (public.prubind_puede(v_pid, 'ejecutar') or public.prubind_puede(v_pid, 'evaluar')) then
    raise exception 'No tiene autoridad para registrar muestras.' using errcode = '42501';
  end if;
  if not (public.prubind_ejecucion_abierta(v_pid) or v.estado in ('en_evaluacion', 'pendiente_resultados')) then
    raise exception 'Las muestras se registran durante el proceso o mientras se completan resultados.' using errcode = 'P0001';
  end if;
  if tg_op = 'DELETE' then return old; end if;

  if tg_table_name = 'muestra_batches_prubind' then
    if not exists (select 1 from public.muestras_prubind m join public.batches_prubind b on b.prueba_id = m.prueba_id and b.ejecucion = m.ejecucion
                   where m.id = (to_jsonb(new) ->> 'muestra_id')::uuid and b.id = (to_jsonb(new) ->> 'batch_id')::uuid and m.nivel = 'compuesta') then
      raise exception 'Solo se componen muestras compuestas con batches de la misma prueba y ejecución.' using errcode = 'P0001';
    end if;
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.ejecucion := v.ejecucion_actual;
    new.tomada_por := coalesce(new.tomada_por, public.prubind_usuario_actual_id());
    if nullif(btrim(new.codigo), '') is null then
      select count(*) + 1 into v_n from public.muestras_prubind where prueba_id = v_pid and ejecucion = new.ejecucion;
      new.codigo := 'M' || new.ejecucion || '-' || lpad(v_n::text, 2, '0');
    end if;
  elsif new.prueba_id is distinct from old.prueba_id or new.ejecucion is distinct from old.ejecucion then
    raise exception 'No se puede mover la muestra.' using errcode = 'P0001';
  end if;
  new.codigo := upper(btrim(new.codigo));
  if new.batch_id is not null and not exists (select 1 from public.batches_prubind b where b.id = new.batch_id and b.prueba_id = v_pid and b.ejecucion = new.ejecucion) then
    raise exception 'El batch no pertenece a esta prueba y ejecución.' using errcode = 'P0001';
  end if;
  if new.lote_diario_id is not null and not exists (select 1 from public.lotes_diarios_prubind l where l.id = new.lote_diario_id and l.prueba_id = v_pid and l.ejecucion = new.ejecucion) then
    raise exception 'El lote diario no pertenece a esta prueba y ejecución.' using errcode = 'P0001';
  end if;
  if new.punto_id is not null and not exists (select 1 from public.puntos_muestreo_prubind p where p.id = new.punto_id and p.prueba_id = v_pid) then
    raise exception 'El punto de muestreo no pertenece a esta prueba.' using errcode = 'P0001';
  end if;
  if new.fecha_muestreo > public.prubind_hoy() then
    raise exception 'La fecha de muestreo no puede ser futura.' using errcode = 'P0001';
  end if;
  perform public.prubind_iniciar_captura(v_pid);
  return new;
end $function$;

-- Resultados: cada área captura sus parámetros; si un valor cambia, su evaluación se vuelve a hacer
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

  select * into pl from public.plan_evaluacion_prubind where id = case when tg_op = 'DELETE' then old.plan_id else new.plan_id end and prueba_id = v_pid;
  if not found or not pl.incluido then
    raise exception 'El parámetro no está en la lista de parámetros a evaluar de esta prueba.' using errcode = 'P0001';
  end if;
  select * into m from public.metodos_prubind where id = pl.metodo_id;
  if not (public.prubind_puede_area(v_pid, 'capturar', m.area) or public.prubind_puede_area(v_pid, 'evaluar', m.area)
          or uid is not distinct from v.responsable_ejecucion_id) then
    raise exception 'No tiene autoridad para registrar parámetros de %.', initcap(m.area) using errcode = '42501';
  end if;
  if not (public.prubind_ejecucion_abierta(v_pid) or v.estado in ('en_evaluacion', 'pendiente_resultados')) then
    raise exception 'Los resultados se registran durante el proceso o mientras se completan resultados.' using errcode = 'P0001';
  end if;

  -- Un valor nuevo o borrado invalida la evaluación hecha de ese parámetro
  if tg_op = 'DELETE' or (new.valor_num, new.valor_opcion, new.dilucion) is distinct from (old.valor_num, old.valor_opcion, old.dilucion) then
    perform set_config('prubind.rpc', '1', true);
    delete from public.evaluaciones_prubind e where e.plan_id = pl.id and e.ejecucion = v.ejecucion_actual;
    perform set_config('prubind.rpc', '', true);
  end if;
  if tg_op = 'DELETE' then return old; end if;

  if not exists (select 1 from public.muestras_prubind s where s.id = new.muestra_id and s.prueba_id = v_pid and s.ejecucion = v.ejecucion_actual) then
    raise exception 'La muestra no pertenece a la ejecución actual de esta prueba.' using errcode = 'P0001';
  end if;
  if tg_op = 'UPDATE' and (new.plan_id, new.muestra_id) is distinct from (old.plan_id, old.muestra_id) then
    raise exception 'No se puede mover el resultado a otro parámetro o muestra.' using errcode = 'P0001';
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
    if new.valor_num is not null and (pl.crit_minimo is not null or pl.crit_maximo is not null) then
      new.estado := case when (pl.crit_minimo is null or new.valor_num >= pl.crit_minimo)
                          and (pl.crit_maximo is null or new.valor_num <= pl.crit_maximo) then 'conforme' else 'no_conforme' end;
    elsif new.estado = 'no_conforme' then new.estado := 'pendiente';
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
    raise exception '% no cumple: escriba una explicación breve.', m.nombre using errcode = 'P0001';
  end if;
  if new.estado <> 'pendiente' and new.fecha_lectura is null then new.fecha_lectura := now(); end if;
  if tg_op = 'INSERT' then
    new.capturado_por := uid; new.revisado_por := null; new.revisado_at := null; new.resolucion := null;
  else
    new.capturado_por := old.capturado_por; new.modificado_por := uid;
    new.revisado_por := old.revisado_por; new.revisado_at := old.revisado_at;
  end if;
  perform public.prubind_iniciar_captura(v_pid);
  return new;
end $function$;

-- ---------- 11. Evaluación (Cumple / No cumple) y recomendaciones --------
create or replace function public.prubind_validar_evaluacion()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v     public.pruebas_prubind%rowtype;
  uid   uuid := public.prubind_usuario_actual_id();
  v_pid uuid;
  v_area text;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return coalesce(new, old); end if;
  if coalesce(current_setting('prubind.rpc', true), '') = '1' then return coalesce(new, old); end if;
  v_pid := case when tg_op = 'DELETE' then old.prueba_id else new.prueba_id end;
  select * into v from public.pruebas_prubind where id = v_pid;
  if v.id is null then return coalesce(new, old); end if;
  if v.estado not in ('en_evaluacion', 'pendiente_resultados') then
    raise exception 'Los resultados se evalúan después de terminar el registro durante el proceso y antes del dictamen.' using errcode = 'P0001';
  end if;
  if tg_op = 'DELETE' then
    if not public.prubind_puede_area(v_pid, 'evaluar', old.area) then
      raise exception 'No tiene autoridad para %.', public.prubind_accion_txt('evaluar_' || old.area) using errcode = '42501';
    end if;
    return old;
  end if;
  if tg_op = 'UPDATE' and (new.prueba_id, new.plan_id, new.prueba_parametro_id, new.ejecucion)
                          is distinct from (old.prueba_id, old.plan_id, old.prueba_parametro_id, old.ejecucion) then
    raise exception 'No se puede mover la evaluación a otro parámetro.' using errcode = 'P0001';
  end if;

  if new.plan_id is not null then
    select m.area into v_area from public.plan_evaluacion_prubind pl join public.metodos_prubind m on m.id = pl.metodo_id
     where pl.id = new.plan_id and pl.prueba_id = v_pid and pl.incluido;
    if v_area is null then raise exception 'El parámetro no pertenece a esta prueba.' using errcode = 'P0001'; end if;
    if not exists (select 1 from public.resultados_prubind r where r.plan_id = new.plan_id and r.ejecucion = v.ejecucion_actual
                   and (r.valor_num is not null or r.valor_opcion is not null)) then
      raise exception 'El parámetro aún no tiene resultado registrado.' using errcode = 'P0001';
    end if;
  else
    if not exists (select 1 from public.prueba_parametros_prubind x where x.id = new.prueba_parametro_id and x.prueba_id = v_pid) then
      raise exception 'El parámetro no pertenece a esta prueba.' using errcode = 'P0001';
    end if;
    v_area := 'produccion';
    if not exists (select 1 from public.ejecucion_controles_prubind c where c.prueba_parametro_id = new.prueba_parametro_id
                   and c.ejecucion = v.ejecucion_actual and c.valor is not null) then
      raise exception 'El parámetro aún no tiene valor registrado.' using errcode = 'P0001';
    end if;
  end if;
  if not public.prubind_puede_area(v_pid, 'evaluar', v_area) then
    raise exception 'No tiene autoridad para %.', public.prubind_accion_txt('evaluar_' || v_area) using errcode = '42501';
  end if;
  new.area := v_area;
  new.ejecucion := v.ejecucion_actual;
  new.observaciones := nullif(btrim(new.observaciones), '');
  if new.evaluacion = 'no_cumple' and (new.observaciones is null or lower(new.observaciones) = 'sin observaciones') then
    raise exception 'Explique por qué el parámetro no cumple.' using errcode = 'P0001';
  end if;
  new.observaciones := coalesce(new.observaciones, 'Sin observaciones');
  new.evaluado_por := uid;
  return new;
end $$;
drop trigger if exists evaluaciones_prubind_validar on public.evaluaciones_prubind;
create trigger evaluaciones_prubind_validar before insert or update or delete on public.evaluaciones_prubind
  for each row execute function public.prubind_validar_evaluacion();

-- Áreas que participan en la prueba (las de sus parámetros)
create or replace function public.prubind_areas_prueba(p_prueba uuid)
returns text[] language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(a order by array_position(array['calidad','produccion','seguridad','mantenimiento'], a)), '{}')
  from (select distinct m.area a from public.plan_evaluacion_prubind pl join public.metodos_prubind m on m.id = pl.metodo_id
         where pl.prueba_id = p_prueba and pl.incluido
        union
        select 'produccion' from public.prueba_parametros_prubind x where x.prueba_id = p_prueba) s
$$;

-- Parámetros de un área sin evaluar en la ejecución actual
create or replace function public.prubind_sin_evaluar(p_prueba uuid, p_area text default null)
returns integer language sql stable security definer set search_path = '' as $$
  select (select count(*) from public.plan_evaluacion_prubind pl join public.metodos_prubind m on m.id = pl.metodo_id
           join public.pruebas_prubind p on p.id = pl.prueba_id
          where pl.prueba_id = p_prueba and pl.incluido and (p_area is null or m.area = p_area)
            and not exists (select 1 from public.evaluaciones_prubind e where e.plan_id = pl.id and e.ejecucion = p.ejecucion_actual))::int
       + (select count(*) from public.prueba_parametros_prubind x join public.pruebas_prubind p on p.id = x.prueba_id
          where x.prueba_id = p_prueba and (p_area is null or p_area = 'produccion')
            and not exists (select 1 from public.evaluaciones_prubind e where e.prueba_parametro_id = x.id and e.ejecucion = p.ejecucion_actual))::int
$$;

create or replace function public.prubind_validar_recomendacion()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v     public.pruebas_prubind%rowtype;
  v_pid uuid;
  v_area text;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return coalesce(new, old); end if;
  if coalesce(current_setting('prubind.rpc', true), '') = '1' then return coalesce(new, old); end if;
  v_pid := case when tg_op = 'DELETE' then old.prueba_id else new.prueba_id end;
  v_area := case when tg_op = 'DELETE' then old.area else new.area end;
  select * into v from public.pruebas_prubind where id = v_pid;
  if v.id is null then return coalesce(new, old); end if;
  if v.estado not in ('en_evaluacion', 'pendiente_resultados') then
    raise exception 'Las recomendaciones se registran después de evaluar los resultados y antes del dictamen.' using errcode = 'P0001';
  end if;
  if not public.prubind_puede_area(v_pid, 'evaluar', v_area) then
    raise exception 'La recomendación de % la registra el responsable de esa área.', initcap(v_area) using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  if tg_op = 'UPDATE' and (new.prueba_id, new.ejecucion, new.area) is distinct from (old.prueba_id, old.ejecucion, old.area) then
    raise exception 'No se puede mover la recomendación.' using errcode = 'P0001';
  end if;
  if not (new.area = any (public.prubind_areas_prueba(v_pid))) then
    raise exception 'El área no participa en esta prueba.' using errcode = 'P0001';
  end if;
  if public.prubind_sin_evaluar(v_pid, new.area) > 0 then
    raise exception 'Evalúe primero todos los parámetros del área (Cumple / No cumple).' using errcode = 'P0001';
  end if;
  new.ejecucion := v.ejecucion_actual;
  new.recomendacion := btrim(new.recomendacion);
  new.emitido_por := public.prubind_usuario_actual_id();
  return new;
end $$;
drop trigger if exists recomendaciones_prubind_validar on public.recomendaciones_prubind;
create trigger recomendaciones_prubind_validar before insert or update or delete on public.recomendaciones_prubind
  for each row execute function public.prubind_validar_recomendacion();

-- ---------- 12. Indicadores de avance -----------------------------------
create or replace function public.prubind_eval_estado(p_prueba uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v public.pruebas_prubind%rowtype; r jsonb; v_areas text[];
begin
  select * into v from public.pruebas_prubind where id = p_prueba;
  if not found then return null; end if;
  v_areas := public.prubind_areas_prueba(v.id);
  select jsonb_build_object(
    'plan_incluidos', (select count(*) from public.plan_evaluacion_prubind pl where pl.prueba_id = v.id and pl.incluido),
    'obligatorios', (select count(*) from public.plan_evaluacion_prubind pl where pl.prueba_id = v.id and pl.incluido and pl.obligatorio),
    -- Parámetros sin ningún valor registrado en la ejecución actual
    'obligatorios_faltantes', (select count(*) from public.plan_evaluacion_prubind pl where pl.prueba_id = v.id and pl.incluido and pl.obligatorio
        and not exists (select 1 from public.resultados_prubind x where x.plan_id = pl.id and x.ejecucion = v.ejecucion_actual
                        and (x.valor_num is not null or x.valor_opcion is not null))),
    'resultados', (select count(*) from public.resultados_prubind x where x.prueba_id = v.id and x.ejecucion = v.ejecucion_actual),
    'pendientes', (select count(*) from public.resultados_prubind x where x.prueba_id = v.id and x.ejecucion = v.ejecucion_actual and x.estado = 'pendiente'),
    'conformes', (select count(*) from public.resultados_prubind x where x.prueba_id = v.id and x.ejecucion = v.ejecucion_actual and x.estado = 'conforme'),
    'no_conformes', (select count(*) from public.resultados_prubind x where x.prueba_id = v.id and x.ejecucion = v.ejecucion_actual and x.estado = 'no_conforme'),
    'nc_sin_resolver', 0,
    'revisiones_pendientes', 0,
    'batches', (select count(*) from public.batches_prubind b where b.prueba_id = v.id and b.ejecucion = v.ejecucion_actual),
    'batches_pendientes', (select count(*) from public.batches_prubind b where b.prueba_id = v.id and b.ejecucion = v.ejecucion_actual and b.resultado_op = 'pendiente'),
    'controles', (select count(*) from public.ejecucion_controles_prubind c where c.prueba_id = v.id and c.ejecucion = v.ejecucion_actual),
    'controles_pendientes', (select count(*) from public.ejecucion_controles_prubind c where c.prueba_id = v.id and c.ejecucion = v.ejecucion_actual and c.resultado = 'pendiente'),
    'aut_ejecucion', exists (select 1 from public.autorizaciones_prubind a where a.prueba_id = v.id and a.ejecucion = v.ejecucion_actual and a.tipo = 'ejecucion'),
    'areas', to_jsonb(v_areas),
    'eval_total', (select count(*) from public.plan_evaluacion_prubind pl where pl.prueba_id = v.id and pl.incluido)
                  + (select count(*) from public.prueba_parametros_prubind x where x.prueba_id = v.id),
    'eval_faltantes', public.prubind_sin_evaluar(v.id),
    'no_cumple', (select count(*) from public.evaluaciones_prubind e where e.prueba_id = v.id and e.ejecucion = v.ejecucion_actual and e.evaluacion = 'no_cumple'),
    'recom_faltantes', (select count(*) from unnest(v_areas) a
                        where not exists (select 1 from public.recomendaciones_prubind x where x.prueba_id = v.id and x.ejecucion = v.ejecucion_actual and x.area = a)),
    'impl_requeridas', (select count(*) from public.autoridades_prubind a where a.activo and a.accion = 'autorizar_implementacion' and (a.tipo is null or a.tipo = v.tipo)),
    'impl_obtenidas', (select count(*) from public.autoridades_prubind a where a.activo and a.accion = 'autorizar_implementacion' and (a.tipo is null or a.tipo = v.tipo)
        and exists (select 1 from public.autorizaciones_prubind z where z.prueba_id = v.id and z.tipo = 'implementacion'
                    and ((a.puesto_id is not null and z.puesto_id = a.puesto_id) or (a.usuario_id is not null and z.autorizado_por = a.usuario_id))))
  ) into r;
  return r;
end $$;

-- ---------- 13. Parámetros nuevos desde el registro --------------------
-- Cualquier usuario registra un parámetro que no exista; queda en el catálogo
-- y en la plantilla del tipo para que aparezca en las siguientes pruebas.
create or replace function public.prubind_nuevo_parametro(p_nombre text, p_area text, p_tipo_resultado text, p_unidad uuid default null, p_tipo_prueba text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_nom text := btrim(coalesce(p_nombre, ''));
  v_id  uuid;
  v_cod text;
  v_n   integer := 0;
  v_fab boolean;
begin
  if not public.prubind_es_miembro() then raise exception 'Usuario no autorizado.' using errcode = '42501'; end if;
  if char_length(v_nom) not between 2 and 150 then raise exception 'Escriba el nombre del parámetro (2 a 150 caracteres).' using errcode = 'P0001'; end if;
  if p_area not in ('calidad', 'produccion', 'seguridad', 'mantenimiento') then raise exception 'Área no válida.' using errcode = 'P0001'; end if;
  if p_tipo_resultado not in ('numerico', 'opcion') then raise exception 'Indique si el parámetro es cuantitativo o cualitativo.' using errcode = 'P0001'; end if;
  if p_unidad is not null and not exists (select 1 from public.unidades_prubind u where u.id = p_unidad and u.activo) then
    raise exception 'Unidad no válida.' using errcode = 'P0001';
  end if;
  select id into v_id from public.metodos_prubind where lower(btrim(nombre)) = lower(v_nom) and area = p_area order by activo desc limit 1;
  if v_id is null then
    loop
      v_n := v_n + 1;
      v_cod := case p_area when 'calidad' then 'CAL' when 'produccion' then 'PROD' when 'seguridad' then 'SEG' else 'MANT' end
               || '-U' || lpad(((select count(*) from public.metodos_prubind where area = p_area) + v_n)::text, 2, '0');
      exit when not exists (select 1 from public.metodos_prubind where codigo = v_cod);
    end loop;
    insert into public.metodos_prubind (codigo, nombre, categoria, area, tipo_resultado, unidad_id, opciones)
    values (v_cod, v_nom, case p_area when 'calidad' then 'general' when 'produccion' then 'proceso' when 'seguridad' then 'seguridad' else 'equipo' end,
            p_area, p_tipo_resultado, case when p_tipo_resultado = 'numerico' then p_unidad end,
            case when p_tipo_resultado = 'opcion' then '{conforme,no_conforme,no_aplica}'::text[] else '{}'::text[] end)
    returning id into v_id;
  end if;
  if p_tipo_prueba is not null then
    select ejecucion_form = 'fabricacion' into v_fab from public.tipos_prueba_prubind where codigo = p_tipo_prueba;
    insert into public.plantilla_evaluacion_prubind (tipo, metodo_id, obligatorio, nivel, orden)
    values (p_tipo_prueba, v_id, true, case when coalesce(v_fab, false) and p_area in ('calidad', 'produccion') then 'batch' else 'corrida' end, 900)
    on conflict (tipo, metodo_id) do update set activo = true;
  end if;
  return v_id;
end $$;

-- ---------- 14. Acciones del flujo --------------------------------------
create or replace function public.prubind_accion(p_prueba uuid, p_accion text, p_datos jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid   uuid := public.prubind_usuario_actual_id();
  v     public.pruebas_prubind%rowtype;
  t     public.tipos_prueba_prubind%rowtype;
  e     jsonb;
  d     jsonb := coalesce(p_datos, '{}'::jsonb);
  v_txt text := nullif(btrim(d ->> 'texto'), '');
  v_dic text;
  v_mot uuid;
  v_ver uuid;
  v_n   integer;
  v_met uuid;
  v_area text;
  v_abierta text[] := array['registrada', 'en_preparacion', 'preparada', 'en_ejecucion'];
begin
  if uid is null then raise exception 'Usuario no autorizado.' using errcode = '42501'; end if;
  if char_length(coalesce(v_txt, '')) > 1000 then raise exception 'El texto excede 1000 caracteres.' using errcode = 'P0001'; end if;
  select * into v from public.pruebas_prubind where id = p_prueba for update;
  if not found then raise exception 'La prueba no existe.' using errcode = 'P0001'; end if;
  select * into t from public.tipos_prueba_prubind where codigo = v.tipo;

  case p_accion
  -- ===== Parámetros a evaluar (registro y durante el proceso) =====
  when 'agregar_parametros' then
    if not (v.estado = any (v_abierta)) then
      raise exception 'Los parámetros se agregan al registrar la prueba o durante el proceso.' using errcode = 'P0001';
    end if;
    v_n := 0;
    for v_met in select (jsonb_array_elements_text(coalesce(d -> 'metodos', '[]'::jsonb)))::uuid loop
      select area into v_area from public.metodos_prubind where id = v_met and activo;
      if v_area is null then raise exception 'Parámetro no válido o inactivo.' using errcode = 'P0001'; end if;
      if not (public.prubind_puede(p_prueba, 'preparar') or public.prubind_puede_area(p_prueba, 'capturar', v_area)) then
        raise exception 'No tiene autoridad para agregar parámetros de %.', initcap(v_area) using errcode = '42501';
      end if;
      perform set_config('prubind.rpc', '1', true);
      insert into public.plan_evaluacion_prubind as x (prueba_id, metodo_id, incluido, obligatorio, nivel, especificacion_id,
                                                       crit_minimo, crit_maximo, crit_texto, crit_referencia, orden)
      select p_prueba, v_met, true, true,
             coalesce(pt.nivel, case when t.ejecucion_form = 'fabricacion' and v_area in ('calidad', 'produccion') then 'batch' else 'corrida' end),
             es.id, es.minimo, es.maximo, es.criterio_texto, es.referencia, coalesce(pt.orden, 900)
        from (select 1) one
        left join public.plantilla_evaluacion_prubind pt on pt.tipo = v.tipo and pt.metodo_id = v_met
        left join lateral (
          select s.* from public.especificaciones_prubind s
          where s.metodo_id = v_met and s.activo and s.vigente
            and (s.producto_id is null or s.producto_id = v.producto_id)
            and (s.materia_prima_id is null or s.materia_prima_id = v.materia_prima_id)
          order by (s.producto_id is not null) desc, (s.materia_prima_id is not null) desc, s.updated_at desc limit 1) es on true
      on conflict (prueba_id, metodo_id) do update set incluido = true, obligatorio = true;
      perform set_config('prubind.rpc', '', true);
      v_n := v_n + 1;
    end loop;
    if v_n > 0 then perform public.prubind_log(p_prueba, 'sistema', v_n || ' parámetro(s) a evaluar agregados.'); end if;

  when 'quitar_parametro' then
    if not (v.estado = any (v_abierta)) then
      raise exception 'Los parámetros se quitan al registrar la prueba o durante el proceso.' using errcode = 'P0001';
    end if;
    select m.area, m.nombre into v_area, v_txt from public.plan_evaluacion_prubind pl join public.metodos_prubind m on m.id = pl.metodo_id
     where pl.id = (d ->> 'plan_id')::uuid and pl.prueba_id = p_prueba;
    if v_area is null then raise exception 'El parámetro no pertenece a esta prueba.' using errcode = 'P0001'; end if;
    if not (public.prubind_puede(p_prueba, 'preparar') or public.prubind_puede_area(p_prueba, 'capturar', v_area)) then
      raise exception 'No tiene autoridad para quitar parámetros de %.', initcap(v_area) using errcode = '42501';
    end if;
    if exists (select 1 from public.resultados_prubind r where r.plan_id = (d ->> 'plan_id')::uuid) then
      raise exception 'El parámetro "%" ya tiene resultados registrados; bórrelos primero.', v_txt using errcode = 'P0001';
    end if;
    perform set_config('prubind.rpc', '1', true);
    delete from public.plan_evaluacion_prubind where id = (d ->> 'plan_id')::uuid;
    perform set_config('prubind.rpc', '', true);
    perform public.prubind_log(p_prueba, 'sistema', 'Se quitó el parámetro "' || v_txt || '".');
    v_txt := null;

  when 'cargar_equipo' then
    if not (v.estado = any (v_abierta)) then raise exception 'Acción no disponible en esta etapa.' using errcode = 'P0001'; end if;
    if not (public.prubind_puede(p_prueba, 'preparar') or public.prubind_puede_area(p_prueba, 'capturar', 'produccion')) then
      raise exception 'No tiene autoridad para cargar los parámetros del equipo.' using errcode = '42501';
    end if;
    if v.equipo_id is not null and not exists (select 1 from public.prueba_parametros_prubind where prueba_id = p_prueba) then
      perform set_config('prubind.rpc', '1', true);
      insert into public.prueba_parametros_prubind (prueba_id, equipo_id, parametro_id, nombre, unidad_id, minimo, maximo, referencia, orden)
      select p_prueba, x.equipo_id, x.id, x.nombre, x.unidad_id, x.minimo, x.maximo, x.referencia, row_number() over (order by x.nombre)
        from public.equipo_parametros_prubind x where x.equipo_id = v.equipo_id and x.activo;
      perform set_config('prubind.rpc', '', true);
    end if;

  -- ===== Preparación (se conserva para formulación e historial) =====
  when 'generar_plan' then
    perform public.prubind_req(p_prueba, 'preparar', array['registrada','en_preparacion']);
    perform set_config('prubind.rpc', '1', true);
    delete from public.plan_evaluacion_prubind where prueba_id = p_prueba
      and not exists (select 1 from public.resultados_prubind r where r.plan_id = plan_evaluacion_prubind.id);
    insert into public.plan_evaluacion_prubind (prueba_id, metodo_id, incluido, obligatorio, nivel, especificacion_id,
                                                crit_minimo, crit_maximo, crit_texto, crit_referencia, orden)
    select p_prueba, pt.metodo_id, true, true, pt.nivel, es.id, es.minimo, es.maximo, es.criterio_texto, es.referencia, pt.orden
      from public.plantilla_evaluacion_prubind pt
      join public.metodos_prubind m on m.id = pt.metodo_id and m.activo
      left join lateral (
        select s.* from public.especificaciones_prubind s
        where s.metodo_id = pt.metodo_id and s.activo and s.vigente
          and (s.producto_id is null or s.producto_id = v.producto_id)
          and (s.materia_prima_id is null or s.materia_prima_id = v.materia_prima_id)
        order by (s.producto_id is not null) desc, (s.materia_prima_id is not null) desc, s.updated_at desc limit 1) es on true
     where pt.tipo = v.tipo and pt.activo and pt.obligatorio and m.area in ('calidad', 'produccion')
    on conflict (prueba_id, metodo_id) do nothing;
    get diagnostics v_n = row_count;
    perform set_config('prubind.rpc', '', true);
    perform public.prubind_log(p_prueba, 'sistema', 'Parámetros sugeridos del tipo agregados (' || v_n || ').');

  when 'confirmar_plan' then
    perform public.prubind_req(p_prueba, 'preparar', array['registrada','en_preparacion']);
    perform set_config('prubind.rpc', '1', true);
    update public.pruebas_prubind set plan_confirmado_at = now(), plan_confirmado_por = uid where id = p_prueba;
    perform set_config('prubind.rpc', '', true);

  when 'copiar_receta' then
    perform public.prubind_req(p_prueba, 'preparar', array['registrada','en_preparacion']);
    if v.receta_version_id is null then raise exception 'La prueba no tiene receta seleccionada en el registro.' using errcode = 'P0001'; end if;
    perform set_config('prubind.rpc', '1', true);
    delete from public.prueba_formulacion_prubind where prueba_id = p_prueba;
    insert into public.prueba_formulacion_prubind (prueba_id, materia_prima_id, cantidad_original, cantidad_propuesta, unidad_id, accion, orden)
    select p_prueba, i.materia_prima_id, i.cantidad, i.cantidad, i.unidad_id, 'sin_cambio', i.orden
      from public.receta_ingredientes_prubind i where i.version_id = v.receta_version_id;
    get diagnostics v_n = row_count;
    perform set_config('prubind.rpc', '', true);
    perform public.prubind_log(p_prueba, 'sistema', 'Se copió la receta original (' || v_n || ' ingredientes) para registrar la formulación de la prueba. La receta oficial no se modifica.');

  when 'calcular_materiales' then
    perform public.prubind_req(p_prueba, 'preparar', array['registrada','en_preparacion']);
    if v.batches_planeados is null then raise exception 'Indique el número de batches.' using errcode = 'P0001'; end if;
    perform set_config('prubind.rpc', '1', true);
    insert into public.prueba_materiales_prubind as pm (prueba_id, materia_prima_id, cantidad, unidad_id, actualizado_por)
    select p_prueba, f.materia_prima_id, round(f.cantidad_propuesta * v.batches_planeados, 3), f.unidad_id, uid
      from public.prueba_formulacion_prubind f where f.prueba_id = p_prueba and coalesce(f.cantidad_propuesta, 0) > 0
    on conflict (prueba_id, materia_prima_id) do update set cantidad = excluded.cantidad, unidad_id = excluded.unidad_id, actualizado_por = uid;
    perform set_config('prubind.rpc', '', true);

  when 'marcar_preparada' then
    perform public.prubind_req(p_prueba, 'preparar', array['registrada','en_preparacion']);
    perform public.prubind_set_estado(p_prueba, 'preparada', 'Registro listo para capturar durante el proceso.');

  when 'regresar_preparacion' then
    perform public.prubind_req(p_prueba, 'preparar', array['preparada']);
    perform public.prubind_set_estado(p_prueba, 'en_preparacion', 'Regresó a registro' || coalesce(': ' || v_txt, '.'));

  when 'autorizar_ejecucion' then
    perform public.prubind_req(p_prueba, 'autorizar_ejecucion', array['preparada']);
    insert into public.autorizaciones_prubind (prueba_id, ejecucion, tipo, puesto_id, autorizado_por, comentario)
    values (p_prueba, v.ejecucion_actual, 'ejecucion', public.prubind_puesto_actual(), uid, v_txt)
    on conflict do nothing;
    perform public.prubind_log(p_prueba, 'estado', 'Ejecución #' || v.ejecucion_actual || ' autorizada' || coalesce(': ' || v_txt, '.'));

  -- ===== Registro durante el proceso → Resultados =====
  when 'terminar_ejecucion' then
    perform public.prubind_req(p_prueba, 'ejecutar', array['en_ejecucion']);
    e := public.prubind_eval_estado(p_prueba);
    if t.ejecucion_form = 'fabricacion' then
      if (e ->> 'batches')::int = 0 then raise exception 'Registre al menos un batch.' using errcode = 'P0001'; end if;
      if (e ->> 'batches_pendientes')::int > 0 then
        raise exception 'Hay % batch(es) sin indicar si se produjeron sin problemas.', e ->> 'batches_pendientes' using errcode = 'P0001';
      end if;
    elsif (e ->> 'resultados')::int = 0 and (e ->> 'controles')::int = 0 then
      raise exception 'Registre al menos un parámetro de la corrida.' using errcode = 'P0001';
    end if;
    perform public.prubind_set_estado(p_prueba, 'en_evaluacion', 'Terminó el registro durante el proceso (ejecución #' || v.ejecucion_actual || '); inicia la evaluación de resultados.');

  when 'enviar_dictamen' then
    perform public.prubind_req(p_prueba, 'evaluar', array['en_evaluacion','pendiente_resultados']);
    e := public.prubind_eval_estado(p_prueba);
    if (e ->> 'eval_faltantes')::int > 0 then
      raise exception 'Faltan % parámetro(s) por evaluar (Cumple / No cumple).', e ->> 'eval_faltantes' using errcode = 'P0001';
    end if;
    if (e ->> 'recom_faltantes')::int > 0 then
      raise exception 'Faltan las recomendaciones de % área(s).', e ->> 'recom_faltantes' using errcode = 'P0001';
    end if;
    perform public.prubind_set_estado(p_prueba, 'pendiente_dictamen', 'Resultados evaluados y recomendaciones registradas; pendiente del dictamen de Alta Dirección.');

  when 'revisar_resultado' then
    if not exists (select 1 from public.resultados_prubind x join public.metodos_prubind m on m.id = x.metodo_id
                   where x.id = (d ->> 'resultado_id')::uuid and x.prueba_id = p_prueba and m.revisa_puesto_id = public.prubind_puesto_actual()) then
      raise exception 'Este resultado no requiere su revisión o no existe.' using errcode = '42501';
    end if;
    if v.estado not in ('en_ejecucion','en_evaluacion','pendiente_resultados','pendiente_dictamen') then
      raise exception 'La revisión se registra antes del dictamen.' using errcode = 'P0001';
    end if;
    perform set_config('prubind.rpc', '1', true);
    update public.resultados_prubind set revisado_por = uid, revisado_at = now() where id = (d ->> 'resultado_id')::uuid;
    perform set_config('prubind.rpc', '', true);

  -- ===== Dictamen (Alta Dirección) =====
  when 'dictaminar' then
    perform public.prubind_req(p_prueba, 'dictaminar', array['pendiente_dictamen']);
    v_dic := d ->> 'dictamen';
    v_mot := nullif(d ->> 'motivo_id', '')::uuid;
    e := public.prubind_eval_estado(p_prueba);
    if v_dic = 'aprobada' then
      if (e ->> 'eval_faltantes')::int > 0 or (e ->> 'recom_faltantes')::int > 0 then
        raise exception 'No se puede aprobar: faltan evaluaciones o recomendaciones de las áreas.' using errcode = 'P0001';
      end if;
      if (e ->> 'no_cumple')::int > 0 and v_txt is null then
        raise exception 'Hay % parámetro(s) que no cumplen: explique en la conclusión por qué se aprueba.', e ->> 'no_cumple' using errcode = 'P0001';
      end if;
    elsif v_dic = 'rechazada' then
      if v_mot is null or not exists (select 1 from public.motivos_prubind where id = v_mot and tipo = 'rechazo') then
        raise exception 'Seleccione el motivo de rechazo.' using errcode = 'P0001';
      end if;
    elsif v_dic = 'requiere_repeticion' then
      if v_txt is null then raise exception 'Explique por qué se requiere repetir la prueba.' using errcode = 'P0001'; end if;
    elsif v_dic <> 'pendiente_resultados' then
      raise exception 'Dictamen no válido.' using errcode = 'P0001';
    end if;
    insert into public.dictamenes_prubind (prueba_id, ejecucion, dictamen, motivo_id, descripcion, emitido_por)
    values (p_prueba, v.ejecucion_actual, v_dic, case when v_dic = 'rechazada' then v_mot end, v_txt, uid);
    perform public.prubind_set_estado(p_prueba, v_dic,
      'Dictamen: ' || case v_dic when 'aprobada' then 'APROBADA' when 'rechazada' then 'RECHAZADA' when 'requiere_repeticion' then 'REQUIERE REPETICIÓN'
      else 'PENDIENTE DE RESULTADOS' end || coalesce('. ' || v_txt, '.'));

  when 'nueva_ejecucion' then
    if not (public.prubind_puede(p_prueba, 'preparar') or public.prubind_puede(p_prueba, 'dictaminar')) then
      raise exception 'No tiene autoridad para iniciar una nueva ejecución.' using errcode = '42501';
    end if;
    if v.estado <> 'requiere_repeticion' then raise exception 'Solo una prueba que requiere repetición inicia una nueva ejecución.' using errcode = 'P0001'; end if;
    perform set_config('prubind.rpc', '1', true);
    update public.pruebas_prubind set ejecucion_actual = ejecucion_actual + 1, estado = 'registrada' where id = p_prueba;
    perform set_config('prubind.rpc', '', true);
    perform public.prubind_log(p_prueba, 'estado', 'Se abrió la ejecución #' || (v.ejecucion_actual + 1) || ' vinculada al registro original. El historial anterior se conserva.');

  -- ===== Cierre =====
  when 'cerrar' then
    perform public.prubind_req(p_prueba, 'cerrar', array['aprobada','rechazada']);
    e := public.prubind_eval_estado(p_prueba);
    if v.estado = 'rechazada' and (e ->> 'obligatorios_faltantes')::int > 0 and v_txt is null then
      raise exception 'Hay parámetros sin resultado: registre la disposición formal para cerrar.' using errcode = 'P0001';
    end if;
    perform set_config('prubind.rpc', '1', true);
    update public.pruebas_prubind set estado = case when v.estado = 'aprobada' then 'cerrada_aprobada' else 'cerrada_rechazada' end,
           cerrada_por = uid, cerrada_at = now(), disposicion_cierre = v_txt where id = p_prueba;
    perform set_config('prubind.rpc', '', true);
    perform public.prubind_log(p_prueba, 'estado', 'Prueba cerrada (' || case when v.estado = 'aprobada' then 'aprobada' else 'rechazada' end || ').'
      || case when v.estado = 'aprobada' then ' La aprobación no libera producto ni autoriza por sí misma el cambio en producción.' else '' end);

  when 'autorizar_implementacion' then
    perform public.prubind_req(p_prueba, 'autorizar_implementacion', array['cerrada_aprobada']);
    insert into public.autorizaciones_prubind (prueba_id, ejecucion, tipo, puesto_id, autorizado_por, comentario)
    values (p_prueba, v.ejecucion_actual, 'implementacion', public.prubind_puesto_actual(), uid, v_txt)
    on conflict do nothing;
    perform public.prubind_log(p_prueba, 'estado', 'Autorización de implementación registrada' || coalesce(': ' || v_txt, '.'));

  when 'publicar_formulacion' then
    if not public.prubind_es_admin() then raise exception 'Solo los administradores publican versiones de receta.' using errcode = '42501'; end if;
    if v.estado <> 'cerrada_aprobada' then raise exception 'La prueba debe estar cerrada y aprobada.' using errcode = 'P0001'; end if;
    e := public.prubind_eval_estado(p_prueba);
    if (e ->> 'impl_requeridas')::int = 0 or (e ->> 'impl_obtenidas')::int < (e ->> 'impl_requeridas')::int then
      raise exception 'Faltan autorizaciones de implementación (% de %).', e ->> 'impl_obtenidas', e ->> 'impl_requeridas' using errcode = 'P0001';
    end if;
    if v.receta_version_id is null or not exists (select 1 from public.prueba_formulacion_prubind where prueba_id = p_prueba) then
      raise exception 'La prueba no tiene una formulación propuesta.' using errcode = 'P0001';
    end if;
    if nullif(btrim(d ->> 'version'), '') is null then raise exception 'Indique el nombre de la nueva versión.' using errcode = 'P0001'; end if;
    insert into public.receta_versiones_prubind (receta_id, version, estado, notas, origen_prueba_id)
    select r.receta_id, btrim(d ->> 'version'), 'borrador', 'Generada desde la prueba ' || v.folio, p_prueba
      from public.receta_versiones_prubind r where r.id = v.receta_version_id returning id into v_ver;
    perform set_config('prubind.rpc', '1', true);
    insert into public.receta_ingredientes_prubind (version_id, materia_prima_id, cantidad, unidad_id, orden)
    select v_ver, f.materia_prima_id, f.cantidad_propuesta, f.unidad_id, f.orden
      from public.prueba_formulacion_prubind f where f.prueba_id = p_prueba and coalesce(f.cantidad_propuesta, 0) > 0;
    perform set_config('prubind.rpc', '', true);
    update public.receta_versiones_prubind set estado = 'vigente' where id = v_ver;
    perform public.prubind_log(p_prueba, 'estado', 'Receta actualizada con la formulación aprobada. La versión anterior queda en el historial.');

  when 'cancelar' then
    perform public.prubind_req(p_prueba, 'cancelar', array['registrada','en_preparacion','preparada','en_ejecucion','en_evaluacion',
      'pendiente_resultados','pendiente_dictamen','requiere_repeticion']);
    if v_txt is null then raise exception 'Indique el motivo de la cancelación.' using errcode = 'P0001'; end if;
    perform set_config('prubind.rpc', '1', true);
    update public.pruebas_prubind set estado = 'cancelada', motivo_cancelacion = left(v_txt, 500), cancelado_por = uid, cancelado_at = now() where id = p_prueba;
    perform set_config('prubind.rpc', '', true);
    perform public.prubind_log(p_prueba, 'estado', 'Prueba cancelada: ' || v_txt);

  else
    raise exception 'Acción no válida.' using errcode = 'P0001';
  end case;

  select estado into v_dic from public.pruebas_prubind where id = p_prueba;
  return jsonb_build_object('estado', v_dic);
end $$;

-- ---------- 15. Pendientes por usuario ----------------------------------
create or replace function public.prubind_mis_pendientes()
 returns table (prueba_id uuid, folio text, cambio text, tipo_nombre text, estado text, accion text)
 language plpgsql stable security definer set search_path = '' as $function$
#variable_conflict use_column
declare uid uuid := public.prubind_usuario_actual_id();
begin
  if uid is null then raise exception 'Usuario no autorizado.' using errcode = '42501'; end if;
  return query
  with p as (
    select x.*, t.nombre as tnom, public.prubind_areas_prueba(x.id) as areas
    from public.pruebas_prubind x join public.tipos_prueba_prubind t on t.codigo = x.tipo
    where x.estado not in ('cerrada_rechazada', 'cancelada')
  )
  select p.id, p.folio, p.cambio, p.tnom, p.estado, a.accion
  from p cross join lateral (values ('capturar'), ('evaluar'), ('recomendar'), ('dictaminar'), ('cerrar'), ('autorizar_implementacion')) a(accion)
  where case a.accion
    -- Registrar durante el proceso: áreas de la prueba en las que el usuario captura
    when 'capturar' then p.estado in ('registrada', 'en_preparacion', 'preparada', 'en_ejecucion')
         and exists (select 1 from unnest(p.areas) ar where public.prubind_tiene_autoridad(p.tipo, 'capturar_' || ar))
    -- Evaluar Cumple / No cumple los parámetros de su área
    when 'evaluar' then p.estado in ('en_evaluacion', 'pendiente_resultados')
         and exists (select 1 from unnest(p.areas) ar where public.prubind_tiene_autoridad(p.tipo, 'evaluar_' || ar)
                     and public.prubind_sin_evaluar(p.id, ar) > 0)
    -- Registrar la recomendación de su área
    when 'recomendar' then p.estado in ('en_evaluacion', 'pendiente_resultados')
         and exists (select 1 from unnest(p.areas) ar where public.prubind_tiene_autoridad(p.tipo, 'evaluar_' || ar)
                     and public.prubind_sin_evaluar(p.id, ar) = 0
                     and not exists (select 1 from public.recomendaciones_prubind r where r.prueba_id = p.id and r.ejecucion = p.ejecucion_actual and r.area = ar))
    when 'dictaminar' then p.estado = 'pendiente_dictamen' and public.prubind_puede(p.id, 'dictaminar')
    when 'cerrar' then p.estado in ('aprobada', 'rechazada') and public.prubind_puede(p.id, 'cerrar')
    when 'autorizar_implementacion' then p.estado = 'cerrada_aprobada' and public.prubind_puede(p.id, 'autorizar_implementacion')
         and not exists (select 1 from public.autorizaciones_prubind z where z.prueba_id = p.id and z.tipo = 'implementacion'
                         and (z.autorizado_por = uid or (z.puesto_id is not null and z.puesto_id = public.prubind_puesto_actual())))
    else false end
  order by p.created_at;
end $function$;

-- ---------- 16. Vistas -------------------------------------------------
drop view if exists public.v_pruebas_prubind;
create view public.v_pruebas_prubind with (security_invoker = true) as
select p.*, t.nombre as tipo_nombre, t.campos_registro, t.secciones_prep, t.ejecucion_form, t.requiere_aut_ejecucion,
       o.nombre as objetivo_nombre, ar.nombre as area_nombre, pr.nombre as producto_nombre,
       rc.nombre as receta_nombre, rv.version as receta_version, mp.nombre as materia_prima_nombre, pv.nombre as proveedor_nombre,
       eq.nombre as equipo_nombre,
       ur.nombre as registrado_por_nombre, ur.foto_url as registrado_por_foto,
       ui.nombre as responsable_inicial_nombre, ue.nombre as responsable_ejecucion_nombre,
       uc.nombre as cerrada_por_nombre, ux.nombre as cancelado_por_nombre,
       (select jsonb_build_object('dictamen', d.dictamen, 'fecha', d.created_at, 'por', du.nombre, 'descripcion', d.descripcion, 'motivo', mo.nombre)
          from public.dictamenes_prubind d join public.usuarios_prubind du on du.id = d.emitido_por
          left join public.motivos_prubind mo on mo.id = d.motivo_id
         where d.prueba_id = p.id order by d.created_at desc limit 1) as ultimo_dictamen,
       cu.simbolo as cantidad_unidad
from public.pruebas_prubind p
join public.tipos_prueba_prubind t on t.codigo = p.tipo
join public.usuarios_prubind ur on ur.id = p.registrado_por
left join public.objetivos_prubind o on o.id = p.objetivo_id
left join public.areas_prubind ar on ar.id = p.area_id
left join public.productos_prubind pr on pr.id = p.producto_id
left join public.receta_versiones_prubind rv on rv.id = p.receta_version_id
left join public.recetas_prubind rc on rc.id = rv.receta_id
left join public.materias_primas_prubind mp on mp.id = p.materia_prima_id
left join public.proveedores_prubind pv on pv.id = p.proveedor_id
left join public.equipos_prubind eq on eq.id = p.equipo_id
left join public.usuarios_prubind ui on ui.id = p.responsable_inicial_id
left join public.usuarios_prubind ue on ue.id = p.responsable_ejecucion_id
left join public.usuarios_prubind uc on uc.id = p.cerrada_por
left join public.usuarios_prubind ux on ux.id = p.cancelado_por
left join public.unidades_prubind cu on cu.id = p.cantidad_unidad_id;
revoke all on public.v_pruebas_prubind from anon, public;
grant select on public.v_pruebas_prubind to authenticated;

create or replace view public.v_resultados_prubind with (security_invoker = true) as
select r.*, m.codigo as metodo_codigo, m.nombre as metodo_nombre, m.categoria, m.tipo_resultado, m.tecnica, m.horas_lectura,
       m.base_expresion, m.procedimiento_ref, m.revisa_puesto_id, un.simbolo as unidad,
       s.codigo as muestra_codigo, s.nivel as muestra_nivel, s.fecha_muestreo, b.numero as batch_numero, l.codigo as lote_codigo,
       pl.obligatorio, pl.crit_minimo, pl.crit_maximo, pl.crit_texto, pl.crit_referencia,
       uc.nombre as capturado_por_nombre, um.nombre as modificado_por_nombre, uv.nombre as revisado_por_nombre, mo.nombre as motivo_nombre,
       m.area
from public.resultados_prubind r
join public.metodos_prubind m on m.id = r.metodo_id
join public.muestras_prubind s on s.id = r.muestra_id
join public.plan_evaluacion_prubind pl on pl.id = r.plan_id
left join public.batches_prubind b on b.id = s.batch_id
left join public.lotes_diarios_prubind l on l.id = s.lote_diario_id
left join public.unidades_prubind un on un.id = r.unidad_id
join public.usuarios_prubind uc on uc.id = r.capturado_por
left join public.usuarios_prubind um on um.id = r.modificado_por
left join public.usuarios_prubind uv on uv.id = r.revisado_por
left join public.motivos_prubind mo on mo.id = r.motivo_desviacion_id;

-- ---------- 17. Privilegios de funciones -------------------------------
do $$
declare f text;
begin
  foreach f in array array['prubind_tiene_autoridad_prefijo(text,text)', 'prubind_puede_area(uuid,text,text)', 'prubind_areas_prueba(uuid)',
    'prubind_sin_evaluar(uuid,text)', 'prubind_nuevo_parametro(text,text,text,uuid,text)', 'prubind_puede(uuid,text)', 'prubind_eval_estado(uuid)',
    'prubind_accion(uuid,text,jsonb)', 'prubind_mis_pendientes()', 'prubind_ejecucion_abierta(uuid)', 'prubind_accion_txt(text)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
  foreach f in array array['prubind_iniciar_captura(uuid)', 'prubind_validar_prueba()', 'prubind_validar_ejecucion()', 'prubind_validar_muestra()',
    'prubind_validar_resultado()', 'prubind_validar_evaluacion()', 'prubind_validar_recomendacion()'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;
