-- =====================================================================
-- Pruebas industriales · v2 · Migración 6
-- Flujo de seis etapas: Registro, Preparación, Ejecución, Evaluación,
-- Dictamen y Cierre. Catálogos maestros separados de los registros.
--
-- Retira las tablas transaccionales de la v1 (autorizado por el usuario el
-- 15/10/2026; estaban VACÍAS) y crea el esquema nuevo. Se conservan:
-- usuarios, áreas, tipos de prueba (se amplía), bitácora, buckets de Storage
-- y la Edge Function. No toca objetos de otras apps.
-- =====================================================================

-- ---------- 1. Retiro de la v1 (tablas vacías) -------------------------
drop view if exists public.v_pruebas_prubind, public.v_batches_prubind, public.v_insumos_prubind, public.v_seguimiento_prubind;
drop table if exists public.adjuntos_prubind, public.seguimiento_prubind, public.resultados_prubind, public.envasadora_prubind,
                     public.insumos_prubind, public.batches_prubind, public.pruebas_prubind cascade;
drop function if exists public.prubind_validar_insumo(), public.prubind_despues_insumo(), public.prubind_validar_resultado(),
  public.prubind_validar_envasadora(), public.prubind_validar_batch(), public.prubind_despues_batch(),
  public.prubind_sincronizar_batches(uuid, integer, date), public.prubind_validar_prueba(), public.prubind_despues_prueba(),
  public.prubind_cambiar_estado(uuid, text, text), public.prubind_dictamen_calidad(uuid, text, text),
  public.prubind_dictamen_final(uuid, text, text), public.prubind_dashboard(date, date), public.prubind_validar_adjunto();

-- ---------- 2. Catálogos maestros --------------------------------------
create table if not exists public.puestos_prubind (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null check (char_length(btrim(nombre)) between 2 and 80),
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists puestos_prubind_nombre_uk on public.puestos_prubind (lower(btrim(nombre)));

alter table public.usuarios_prubind add column if not exists puesto_id uuid references public.puestos_prubind(id) on delete restrict;
create index if not exists usuarios_prubind_puesto_idx on public.usuarios_prubind (puesto_id);

-- Tipos de prueba: plantilla configurable
alter table public.tipos_prueba_prubind
  add column if not exists campos_registro text[] not null default '{}'
    check (campos_registro <@ array['producto','receta','materia_prima','proveedor','empaque','proceso','equipo']::text[]),
  add column if not exists secciones_prep text[] not null default '{}'
    check (secciones_prep <@ array['batches','peso','formulacion','materiales','equipos','muestreo','vida_util']::text[]),
  add column if not exists ejecucion_form text not null default 'controles' check (ejecucion_form in ('fabricacion','controles')),
  add column if not exists requiere_aut_ejecucion boolean not null default true;
alter table public.tipos_prueba_prubind alter column prefijo drop not null;

create table if not exists public.unidades_prubind (
  id          uuid primary key default gen_random_uuid(),
  simbolo     text not null check (char_length(btrim(simbolo)) between 1 and 20),
  nombre      text not null check (char_length(btrim(nombre)) between 1 and 60),
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists unidades_prubind_simbolo_uk on public.unidades_prubind (simbolo);

create table if not exists public.objetivos_prubind (
  id          uuid primary key default gen_random_uuid(),
  tipo        text references public.tipos_prueba_prubind(codigo) on delete restrict,  -- null = aplica a todos
  nombre      text not null check (char_length(btrim(nombre)) between 2 and 120),
  orden       smallint not null default 0,
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists objetivos_prubind_tipo_idx on public.objetivos_prubind (tipo);

create table if not exists public.productos_prubind (
  id          uuid primary key default gen_random_uuid(),
  codigo      text check (codigo is null or char_length(btrim(codigo)) between 1 and 30),
  nombre      text not null check (char_length(btrim(nombre)) between 2 and 150),
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists productos_prubind_nombre_uk on public.productos_prubind (lower(btrim(nombre)));

create table if not exists public.materias_primas_prubind (
  id          uuid primary key default gen_random_uuid(),
  codigo      text check (codigo is null or char_length(btrim(codigo)) between 1 and 30),
  nombre      text not null check (char_length(btrim(nombre)) between 2 and 150),
  categoria   text not null default 'ingrediente' check (categoria in ('ingrediente','empaque_primario','empaque_secundario','otro')),
  unidad_id   uuid references public.unidades_prubind(id) on delete restrict,
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists materias_primas_prubind_nombre_uk on public.materias_primas_prubind (lower(btrim(nombre)));
create index if not exists materias_primas_prubind_unidad_idx on public.materias_primas_prubind (unidad_id);

create table if not exists public.proveedores_prubind (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null check (char_length(btrim(nombre)) between 2 and 150),
  contacto    text check (contacto is null or char_length(contacto) <= 200),
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists proveedores_prubind_nombre_uk on public.proveedores_prubind (lower(btrim(nombre)));

-- Catálogo de trazabilidad: lotes de materia prima (Almacén)
create table if not exists public.lotes_mp_prubind (
  id               uuid primary key default gen_random_uuid(),
  materia_prima_id uuid not null references public.materias_primas_prubind(id) on delete restrict,
  proveedor_id     uuid references public.proveedores_prubind(id) on delete restrict,
  lote             text not null check (char_length(btrim(lote)) between 1 and 60),
  fecha_recepcion  date,
  caducidad        date,
  activo           boolean not null default true,
  created_by       uuid references public.usuarios_prubind(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create unique index if not exists lotes_mp_prubind_uk on public.lotes_mp_prubind (materia_prima_id, lower(btrim(lote)));
create index if not exists lotes_mp_prubind_prov_idx on public.lotes_mp_prubind (proveedor_id);
create index if not exists lotes_mp_prubind_cb_idx on public.lotes_mp_prubind (created_by);

create table if not exists public.equipos_prubind (
  id          uuid primary key default gen_random_uuid(),
  codigo      text check (codigo is null or char_length(btrim(codigo)) between 1 and 30),
  nombre      text not null check (char_length(btrim(nombre)) between 2 and 150),
  area_id     uuid references public.areas_prubind(id) on delete restrict,
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists equipos_prubind_nombre_uk on public.equipos_prubind (lower(btrim(nombre)));
create index if not exists equipos_prubind_area_idx on public.equipos_prubind (area_id);

-- Parámetros de operación por equipo; el rango es OPCIONAL y debe citar su referencia
create table if not exists public.equipo_parametros_prubind (
  id          uuid primary key default gen_random_uuid(),
  equipo_id   uuid not null references public.equipos_prubind(id) on delete restrict,
  nombre      text not null check (char_length(btrim(nombre)) between 2 and 120),
  unidad_id   uuid references public.unidades_prubind(id) on delete restrict,
  minimo      numeric,
  maximo      numeric,
  referencia  text check (referencia is null or char_length(referencia) <= 200),
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint equipo_parametros_prubind_rango_ck check (minimo is null or maximo is null or maximo >= minimo),
  constraint equipo_parametros_prubind_ref_ck check ((minimo is null and maximo is null) or referencia is not null)
);
create index if not exists equipo_parametros_prubind_eq_idx on public.equipo_parametros_prubind (equipo_id);
create index if not exists equipo_parametros_prubind_un_idx on public.equipo_parametros_prubind (unidad_id);

-- Productos y recetas con versiones
create table if not exists public.recetas_prubind (
  id          uuid primary key default gen_random_uuid(),
  producto_id uuid references public.productos_prubind(id) on delete restrict,
  nombre      text not null check (char_length(btrim(nombre)) between 2 and 150),
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists recetas_prubind_nombre_uk on public.recetas_prubind (lower(btrim(nombre)));
create index if not exists recetas_prubind_prod_idx on public.recetas_prubind (producto_id);

create table if not exists public.receta_versiones_prubind (
  id              uuid primary key default gen_random_uuid(),
  receta_id       uuid not null references public.recetas_prubind(id) on delete restrict,
  version         text not null check (char_length(btrim(version)) between 1 and 20),
  estado          text not null default 'borrador' check (estado in ('borrador','vigente','historica')),
  vigente_desde   date,
  notas           text check (notas is null or char_length(notas) <= 500),
  origen_prueba_id uuid,   -- FK se agrega tras crear pruebas_prubind
  created_by      uuid references public.usuarios_prubind(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create unique index if not exists receta_versiones_prubind_uk on public.receta_versiones_prubind (receta_id, lower(btrim(version)));
create unique index if not exists receta_versiones_prubind_vigente_uk on public.receta_versiones_prubind (receta_id) where estado = 'vigente';
create index if not exists receta_versiones_prubind_cb_idx on public.receta_versiones_prubind (created_by);

create table if not exists public.receta_ingredientes_prubind (
  id               uuid primary key default gen_random_uuid(),
  version_id       uuid not null references public.receta_versiones_prubind(id) on delete cascade,
  materia_prima_id uuid not null references public.materias_primas_prubind(id) on delete restrict,
  cantidad         numeric(14,4) not null check (cantidad > 0),
  unidad_id        uuid not null references public.unidades_prubind(id) on delete restrict,
  orden            smallint not null default 0
);
create unique index if not exists receta_ingredientes_prubind_uk on public.receta_ingredientes_prubind (version_id, materia_prima_id);
create index if not exists receta_ingredientes_prubind_mp_idx on public.receta_ingredientes_prubind (materia_prima_id);
create index if not exists receta_ingredientes_prubind_un_idx on public.receta_ingredientes_prubind (unidad_id);

-- Métodos de análisis y controles de evaluación
create table if not exists public.metodos_prubind (
  id               uuid primary key default gen_random_uuid(),
  codigo           text not null check (codigo ~ '^[A-Z0-9_-]{2,30}$'),
  nombre           text not null check (char_length(btrim(nombre)) between 2 and 150),
  categoria        text not null check (categoria in ('fisicoquimica','sensorial','microbiologia','bromatologia','empaque_primario',
                                                      'empaque_secundario','proceso','equipo','materia_prima','vida_util')),
  tipo_resultado   text not null check (tipo_resultado in ('numerico','opcion','diluciones','presencia')),
  unidad_id        uuid references public.unidades_prubind(id) on delete restrict,
  diluciones       text[] not null default '{}',
  horas_lectura    integer check (horas_lectura is null or horas_lectura between 1 and 2000),
  tecnica          text check (tecnica is null or char_length(tecnica) <= 120),
  base_expresion   text check (base_expresion is null or char_length(base_expresion) <= 60),
  procedimiento_ref text check (procedimiento_ref is null or char_length(procedimiento_ref) <= 200),
  opciones         text[] not null default '{}',
  revisa_puesto_id uuid references public.puestos_prubind(id) on delete restrict,
  activo           boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create unique index if not exists metodos_prubind_codigo_uk on public.metodos_prubind (codigo);
create index if not exists metodos_prubind_un_idx on public.metodos_prubind (unidad_id);
create index if not exists metodos_prubind_rev_idx on public.metodos_prubind (revisa_puesto_id);

-- Especificaciones / criterios de aceptación (siempre con referencia)
create table if not exists public.especificaciones_prubind (
  id               uuid primary key default gen_random_uuid(),
  metodo_id        uuid not null references public.metodos_prubind(id) on delete restrict,
  producto_id      uuid references public.productos_prubind(id) on delete restrict,
  materia_prima_id uuid references public.materias_primas_prubind(id) on delete restrict,
  minimo           numeric,
  maximo           numeric,
  criterio_texto   text check (criterio_texto is null or char_length(criterio_texto) <= 200),
  referencia       text not null check (char_length(btrim(referencia)) between 2 and 200),
  version          text not null default '1' check (char_length(version) <= 20),
  vigente          boolean not null default true,
  activo           boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint especificaciones_prubind_rango_ck check (minimo is null or maximo is null or maximo >= minimo),
  constraint especificaciones_prubind_criterio_ck check (minimo is not null or maximo is not null or criterio_texto is not null)
);
create index if not exists especificaciones_prubind_met_idx on public.especificaciones_prubind (metodo_id);
create index if not exists especificaciones_prubind_prod_idx on public.especificaciones_prubind (producto_id);
create index if not exists especificaciones_prubind_mp_idx on public.especificaciones_prubind (materia_prima_id);

-- Plantilla de evaluación por tipo de prueba
create table if not exists public.plantilla_evaluacion_prubind (
  id          uuid primary key default gen_random_uuid(),
  tipo        text not null references public.tipos_prueba_prubind(codigo) on delete restrict,
  metodo_id   uuid not null references public.metodos_prubind(id) on delete restrict,
  obligatorio boolean not null default true,
  nivel       text not null default 'batch' check (nivel in ('batch','compuesta','lote_diario','corrida','punto')),
  orden       smallint not null default 0,
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists plantilla_evaluacion_prubind_uk on public.plantilla_evaluacion_prubind (tipo, metodo_id);
create index if not exists plantilla_evaluacion_prubind_met_idx on public.plantilla_evaluacion_prubind (metodo_id);

create table if not exists public.motivos_prubind (
  id          uuid primary key default gen_random_uuid(),
  tipo        text not null check (tipo in ('rechazo','desviacion')),
  nombre      text not null check (char_length(btrim(nombre)) between 2 and 120),
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists motivos_prubind_uk on public.motivos_prubind (tipo, lower(btrim(nombre)));

create table if not exists public.tipos_evidencia_prubind (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null check (char_length(btrim(nombre)) between 2 and 80),
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists tipos_evidencia_prubind_uk on public.tipos_evidencia_prubind (lower(btrim(nombre)));

-- Matriz de autoridades: tipo (null = todos) × acción × puesto o usuario
create table if not exists public.autoridades_prubind (
  id          uuid primary key default gen_random_uuid(),
  tipo        text references public.tipos_prueba_prubind(codigo) on delete restrict,
  accion      text not null check (accion in ('preparar','abastecer','autorizar_ejecucion','ejecutar','evaluar','dictaminar','cerrar','autorizar_implementacion')),
  puesto_id   uuid references public.puestos_prubind(id) on delete restrict,
  usuario_id  uuid references public.usuarios_prubind(id) on delete restrict,
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  constraint autoridades_prubind_quien_ck check ((puesto_id is null) <> (usuario_id is null))
);
create unique index if not exists autoridades_prubind_uk on public.autoridades_prubind (coalesce(tipo, '*'), accion, coalesce(puesto_id, usuario_id));
create index if not exists autoridades_prubind_puesto_idx on public.autoridades_prubind (puesto_id);
create index if not exists autoridades_prubind_usuario_idx on public.autoridades_prubind (usuario_id);

-- Consecutivo de folio por año (PI-AAAA-NNN)
create table if not exists public.folios_prubind (
  anio    integer primary key,
  ultimo  integer not null default 0
);

-- ---------- 3. Registros transaccionales -------------------------------
create table public.pruebas_prubind (
  id                   uuid primary key default gen_random_uuid(),
  folio                text not null,
  anio                 integer not null,
  consecutivo          integer not null,
  tipo                 text not null references public.tipos_prueba_prubind(codigo) on delete restrict,
  -- Etapa 1 · Registro
  objetivo_id          uuid references public.objetivos_prubind(id) on delete restrict,
  objetivo_desc        text check (objetivo_desc is null or char_length(objetivo_desc) <= 500),
  cambio               text not null check (char_length(btrim(cambio)) between 3 and 500),
  area_id              uuid references public.areas_prubind(id) on delete restrict,
  prioridad            text not null default 'normal' check (prioridad in ('normal','alta','urgente')),
  prioridad_just       text check (prioridad_just is null or char_length(prioridad_just) <= 300),
  producto_id          uuid references public.productos_prubind(id) on delete restrict,
  receta_version_id    uuid references public.receta_versiones_prubind(id) on delete restrict,
  materia_prima_id     uuid references public.materias_primas_prubind(id) on delete restrict,
  proveedor_id         uuid references public.proveedores_prubind(id) on delete restrict,
  equipo_id            uuid references public.equipos_prubind(id) on delete restrict,
  proceso              text check (proceso is null or char_length(proceso) <= 200),
  empaque              text check (empaque is null or char_length(empaque) <= 200),
  registrado_por       uuid not null references public.usuarios_prubind(id) on delete restrict,
  responsable_inicial_id uuid references public.usuarios_prubind(id) on delete restrict,
  -- Etapa 2 · Preparación
  fecha_planeada       date,
  batches_planeados    integer check (batches_planeados is null or batches_planeados between 1 and 500),
  peso_objetivo_kg     numeric(10,3) check (peso_objetivo_kg is null or peso_objetivo_kg > 0),
  responsable_ejecucion_id uuid references public.usuarios_prubind(id) on delete restrict,
  plan_muestreo        text check (plan_muestreo is null or char_length(plan_muestreo) <= 1000),
  plan_confirmado_at   timestamptz,
  plan_confirmado_por  uuid references public.usuarios_prubind(id) on delete restrict,
  -- Control
  estado               text not null default 'registrada' check (estado in ('registrada','en_preparacion','preparada','en_ejecucion',
                         'en_evaluacion','pendiente_resultados','pendiente_dictamen','aprobada','rechazada','requiere_repeticion',
                         'cerrada_aprobada','cerrada_rechazada','cancelada')),
  ejecucion_actual     integer not null default 1 check (ejecucion_actual between 1 and 50),
  motivo_cancelacion   text check (motivo_cancelacion is null or char_length(motivo_cancelacion) <= 500),
  cancelado_por        uuid references public.usuarios_prubind(id) on delete restrict,
  cancelado_at         timestamptz,
  disposicion_cierre   text check (disposicion_cierre is null or char_length(disposicion_cierre) <= 1000),
  cerrada_por          uuid references public.usuarios_prubind(id) on delete restrict,
  cerrada_at           timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint pruebas_prubind_prioridad_ck check (prioridad = 'normal' or prioridad_just is not null),
  constraint pruebas_prubind_cancel_ck check (estado <> 'cancelada' or motivo_cancelacion is not null)
);
create unique index pruebas_prubind_folio_uk on public.pruebas_prubind (folio);
create unique index pruebas_prubind_consec_uk on public.pruebas_prubind (anio, consecutivo);
create index pruebas_prubind_estado_idx on public.pruebas_prubind (estado);
create index pruebas_prubind_tipo_idx on public.pruebas_prubind (tipo);
create index pruebas_prubind_created_idx on public.pruebas_prubind (created_at desc);
do $$
declare c text;
begin
  foreach c in array array['objetivo_id','area_id','producto_id','receta_version_id','materia_prima_id','proveedor_id','equipo_id',
                           'registrado_por','responsable_inicial_id','responsable_ejecucion_id','plan_confirmado_por','cancelado_por','cerrada_por'] loop
    execute format('create index if not exists %I on public.pruebas_prubind (%I)', 'pruebas_prubind_' || c || '_idx', c);
  end loop;
end $$;
alter table public.receta_versiones_prubind drop constraint if exists receta_versiones_prubind_origen_fk;
alter table public.receta_versiones_prubind add constraint receta_versiones_prubind_origen_fk
  foreign key (origen_prueba_id) references public.pruebas_prubind(id) on delete restrict;
create index if not exists receta_versiones_prubind_origen_idx on public.receta_versiones_prubind (origen_prueba_id);

-- Formulación: copia de la receta original + propuesta (la receta oficial no se toca)
create table public.prueba_formulacion_prubind (
  id                 uuid primary key default gen_random_uuid(),
  prueba_id          uuid not null references public.pruebas_prubind(id) on delete cascade,
  materia_prima_id   uuid not null references public.materias_primas_prubind(id) on delete restrict,
  cantidad_original  numeric(14,4) check (cantidad_original is null or cantidad_original > 0),
  cantidad_propuesta numeric(14,4) check (cantidad_propuesta is null or cantidad_propuesta >= 0),
  unidad_id          uuid not null references public.unidades_prubind(id) on delete restrict,
  accion             text not null default 'sin_cambio' check (accion in ('sin_cambio','modificar','agregar','retirar','sustituir')),
  sustituye_a_id     uuid references public.materias_primas_prubind(id) on delete restrict,
  orden              smallint not null default 0
);
create unique index prueba_formulacion_prubind_uk on public.prueba_formulacion_prubind (prueba_id, materia_prima_id);
create index prueba_formulacion_prubind_mp_idx on public.prueba_formulacion_prubind (materia_prima_id);
create index prueba_formulacion_prubind_un_idx on public.prueba_formulacion_prubind (unidad_id);
create index prueba_formulacion_prubind_sus_idx on public.prueba_formulacion_prubind (sustituye_a_id);

-- Materiales previstos, compra y disponibilidad (Compras / Almacén)
create table public.prueba_materiales_prubind (
  id               uuid primary key default gen_random_uuid(),
  prueba_id        uuid not null references public.pruebas_prubind(id) on delete cascade,
  materia_prima_id uuid not null references public.materias_primas_prubind(id) on delete restrict,
  cantidad         numeric(14,3) check (cantidad is null or cantidad > 0),
  unidad_id        uuid references public.unidades_prubind(id) on delete restrict,
  requiere_compra  boolean not null default false,
  disponibilidad   text not null default 'pendiente' check (disponibilidad in ('pendiente','disponible','en_compra','no_disponible')),
  observaciones    text check (observaciones is null or char_length(observaciones) <= 300),
  actualizado_por  uuid references public.usuarios_prubind(id) on delete restrict,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create unique index prueba_materiales_prubind_uk on public.prueba_materiales_prubind (prueba_id, materia_prima_id);
create index prueba_materiales_prubind_mp_idx on public.prueba_materiales_prubind (materia_prima_id);
create index prueba_materiales_prubind_un_idx on public.prueba_materiales_prubind (unidad_id);
create index prueba_materiales_prubind_act_idx on public.prueba_materiales_prubind (actualizado_por);

-- Equipos y parámetros de operación planeados
create table public.prueba_parametros_prubind (
  id             uuid primary key default gen_random_uuid(),
  prueba_id      uuid not null references public.pruebas_prubind(id) on delete cascade,
  equipo_id      uuid not null references public.equipos_prubind(id) on delete restrict,
  parametro_id   uuid references public.equipo_parametros_prubind(id) on delete restrict,
  nombre         text not null check (char_length(btrim(nombre)) between 1 and 120),
  valor_objetivo text check (valor_objetivo is null or char_length(valor_objetivo) <= 60),
  unidad_id      uuid references public.unidades_prubind(id) on delete restrict,
  minimo         numeric,
  maximo         numeric,
  referencia     text check (referencia is null or char_length(referencia) <= 200),
  orden          smallint not null default 0
);
create index prueba_parametros_prubind_prueba_idx on public.prueba_parametros_prubind (prueba_id);
create index prueba_parametros_prubind_eq_idx on public.prueba_parametros_prubind (equipo_id);
create index prueba_parametros_prubind_par_idx on public.prueba_parametros_prubind (parametro_id);
create index prueba_parametros_prubind_un_idx on public.prueba_parametros_prubind (unidad_id);

-- Plan de evaluación: copia de la plantilla y del criterio vigente al prepararse
create table public.plan_evaluacion_prubind (
  id               uuid primary key default gen_random_uuid(),
  prueba_id        uuid not null references public.pruebas_prubind(id) on delete cascade,
  metodo_id        uuid not null references public.metodos_prubind(id) on delete restrict,
  incluido         boolean not null default true,
  obligatorio      boolean not null default true,
  nivel            text not null default 'batch' check (nivel in ('batch','compuesta','lote_diario','corrida','punto')),
  especificacion_id uuid references public.especificaciones_prubind(id) on delete restrict,
  crit_minimo      numeric,
  crit_maximo      numeric,
  crit_texto       text check (crit_texto is null or char_length(crit_texto) <= 200),
  crit_referencia  text check (crit_referencia is null or char_length(crit_referencia) <= 200),
  orden            smallint not null default 0
);
create unique index plan_evaluacion_prubind_uk on public.plan_evaluacion_prubind (prueba_id, metodo_id);
create index plan_evaluacion_prubind_met_idx on public.plan_evaluacion_prubind (metodo_id);
create index plan_evaluacion_prubind_esp_idx on public.plan_evaluacion_prubind (especificacion_id);

-- Puntos de muestreo programados (vida útil)
create table public.puntos_muestreo_prubind (
  id               uuid primary key default gen_random_uuid(),
  prueba_id        uuid not null references public.pruebas_prubind(id) on delete cascade,
  nombre           text not null check (char_length(btrim(nombre)) between 1 and 60),
  fecha_programada date,
  orden            smallint not null default 0
);
create index puntos_muestreo_prubind_prueba_idx on public.puntos_muestreo_prubind (prueba_id);

-- Etapa 3 · Ejecución
create table public.lotes_diarios_prubind (
  id          uuid primary key default gen_random_uuid(),
  prueba_id   uuid not null references public.pruebas_prubind(id) on delete restrict,
  ejecucion   integer not null default 1,
  codigo      text not null check (char_length(btrim(codigo)) between 1 and 40),
  fecha       date not null,
  created_by  uuid references public.usuarios_prubind(id) on delete restrict,
  created_at  timestamptz not null default now()
);
create unique index lotes_diarios_prubind_uk on public.lotes_diarios_prubind (prueba_id, ejecucion, lower(btrim(codigo)));
create index lotes_diarios_prubind_cb_idx on public.lotes_diarios_prubind (created_by);

create table public.batches_prubind (
  id                uuid primary key default gen_random_uuid(),
  prueba_id         uuid not null references public.pruebas_prubind(id) on delete restrict,
  ejecucion         integer not null default 1,
  lote_diario_id    uuid not null references public.lotes_diarios_prubind(id) on delete restrict,
  numero            integer not null check (numero between 1 and 999),
  identificador     text check (identificador is null or char_length(identificador) <= 40),
  fecha_hora        timestamptz not null,
  receta_version_id uuid references public.receta_versiones_prubind(id) on delete restrict,
  peso_real_kg      numeric(10,3) check (peso_real_kg is null or peso_real_kg > 0),
  temp_coccion_c    numeric(6,2),
  consistencia_cm_s numeric(8,3) check (consistencia_cm_s is null or consistencia_cm_s >= 0),
  responsable_id    uuid references public.usuarios_prubind(id) on delete restrict,
  incidencias       text check (incidencias is null or char_length(incidencias) <= 1000),
  motivo_desviacion_id uuid references public.motivos_prubind(id) on delete restrict,
  resultado_op      text not null default 'pendiente' check (resultado_op in ('pendiente','conforme','no_conforme')),
  resolucion        text check (resolucion is null or char_length(resolucion) <= 500),
  capturado_por     uuid references public.usuarios_prubind(id) on delete restrict,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint batches_prubind_nc_ck check (resultado_op <> 'no_conforme' or incidencias is not null)
);
create unique index batches_prubind_uk on public.batches_prubind (prueba_id, ejecucion, numero);
do $$
declare c text;
begin
  foreach c in array array['lote_diario_id','receta_version_id','responsable_id','motivo_desviacion_id','capturado_por'] loop
    execute format('create index if not exists %I on public.batches_prubind (%I)', 'batches_prubind_' || c || '_idx', c);
  end loop;
end $$;

create table public.batch_lotes_mp_prubind (
  batch_id    uuid not null references public.batches_prubind(id) on delete cascade,
  lote_mp_id  uuid not null references public.lotes_mp_prubind(id) on delete restrict,
  cantidad    numeric(14,3) check (cantidad is null or cantidad > 0),
  primary key (batch_id, lote_mp_id)
);
create index batch_lotes_mp_prubind_lote_idx on public.batch_lotes_mp_prubind (lote_mp_id);

-- Ejecución de pruebas que no son de fabricación (empaque, equipo, etc.)
create table public.ejecucion_controles_prubind (
  id               uuid primary key default gen_random_uuid(),
  prueba_id        uuid not null references public.pruebas_prubind(id) on delete restrict,
  ejecucion        integer not null default 1,
  prueba_parametro_id uuid references public.prueba_parametros_prubind(id) on delete set null,
  nombre           text not null check (char_length(btrim(nombre)) between 1 and 120),
  valor            text check (valor is null or char_length(valor) <= 60),
  unidad_id        uuid references public.unidades_prubind(id) on delete restrict,
  resultado        text not null default 'pendiente' check (resultado in ('pendiente','conforme','no_conforme','no_aplica')),
  fecha_hora       timestamptz,
  observaciones    text check (observaciones is null or char_length(observaciones) <= 500),
  resolucion       text check (resolucion is null or char_length(resolucion) <= 500),
  responsable_id   uuid references public.usuarios_prubind(id) on delete restrict,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint ejecucion_controles_prubind_nc_ck check (resultado <> 'no_conforme' or observaciones is not null)
);
create index ejecucion_controles_prubind_prueba_idx on public.ejecucion_controles_prubind (prueba_id, ejecucion);
create index ejecucion_controles_prubind_par_idx on public.ejecucion_controles_prubind (prueba_parametro_id);
create index ejecucion_controles_prubind_un_idx on public.ejecucion_controles_prubind (unidad_id);
create index ejecucion_controles_prubind_resp_idx on public.ejecucion_controles_prubind (responsable_id);

-- Etapa 4 · Muestras y resultados
create table public.muestras_prubind (
  id               uuid primary key default gen_random_uuid(),
  prueba_id        uuid not null references public.pruebas_prubind(id) on delete restrict,
  ejecucion        integer not null default 1,
  codigo           text not null check (char_length(btrim(codigo)) between 1 and 40),
  nivel            text not null check (nivel in ('batch','compuesta','lote_diario','corrida','punto')),
  batch_id         uuid references public.batches_prubind(id) on delete restrict,
  lote_diario_id   uuid references public.lotes_diarios_prubind(id) on delete restrict,
  punto_id         uuid references public.puntos_muestreo_prubind(id) on delete restrict,
  fecha_muestreo   date,
  tomada_por       uuid references public.usuarios_prubind(id) on delete restrict,
  created_at       timestamptz not null default now(),
  constraint muestras_prubind_nivel_ck check (
    (nivel = 'batch' and batch_id is not null) or (nivel = 'lote_diario' and lote_diario_id is not null) or
    (nivel = 'punto' and punto_id is not null) or nivel in ('compuesta','corrida'))
);
create unique index muestras_prubind_uk on public.muestras_prubind (prueba_id, ejecucion, lower(codigo));
do $$
declare c text;
begin
  foreach c in array array['batch_id','lote_diario_id','punto_id','tomada_por'] loop
    execute format('create index if not exists %I on public.muestras_prubind (%I)', 'muestras_prubind_' || c || '_idx', c);
  end loop;
end $$;

create table public.muestra_batches_prubind (   -- composición de muestras compuestas
  muestra_id uuid not null references public.muestras_prubind(id) on delete cascade,
  batch_id   uuid not null references public.batches_prubind(id) on delete restrict,
  primary key (muestra_id, batch_id)
);
create index muestra_batches_prubind_batch_idx on public.muestra_batches_prubind (batch_id);

create table public.resultados_prubind (
  id                 uuid primary key default gen_random_uuid(),
  prueba_id          uuid not null references public.pruebas_prubind(id) on delete restrict,
  ejecucion          integer not null default 1,
  plan_id            uuid not null references public.plan_evaluacion_prubind(id) on delete restrict,
  muestra_id         uuid not null references public.muestras_prubind(id) on delete restrict,
  metodo_id          uuid not null references public.metodos_prubind(id) on delete restrict,
  dilucion           text check (dilucion is null or char_length(dilucion) <= 20),
  valor_num          numeric,
  valor_opcion       text check (valor_opcion is null or char_length(valor_opcion) <= 40),
  unidad_id          uuid references public.unidades_prubind(id) on delete restrict,
  fecha_lectura      timestamptz,
  estado             text not null default 'pendiente' check (estado in ('pendiente','conforme','no_conforme','no_aplica')),
  justificacion      text check (justificacion is null or char_length(justificacion) <= 500),
  motivo_desviacion_id uuid references public.motivos_prubind(id) on delete restrict,
  resolucion         text check (resolucion is null or char_length(resolucion) <= 500),
  capturado_por      uuid not null references public.usuarios_prubind(id) on delete restrict,
  modificado_por     uuid references public.usuarios_prubind(id) on delete restrict,
  revisado_por       uuid references public.usuarios_prubind(id) on delete restrict,
  revisado_at        timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint resultados_prubind_nc_ck check (estado <> 'no_conforme' or justificacion is not null)
);
create unique index resultados_prubind_uk on public.resultados_prubind (plan_id, muestra_id, coalesce(dilucion, ''));
create index resultados_prubind_prueba_idx on public.resultados_prubind (prueba_id, ejecucion);
do $$
declare c text;
begin
  foreach c in array array['muestra_id','metodo_id','unidad_id','motivo_desviacion_id','capturado_por','modificado_por','revisado_por'] loop
    execute format('create index if not exists %I on public.resultados_prubind (%I)', 'resultados_prubind_' || c || '_idx', c);
  end loop;
end $$;

-- Etapas 5 y 6 · Dictámenes y autorizaciones (historial; solo inserción)
create table public.dictamenes_prubind (
  id          uuid primary key default gen_random_uuid(),
  prueba_id   uuid not null references public.pruebas_prubind(id) on delete restrict,
  ejecucion   integer not null,
  dictamen    text not null check (dictamen in ('aprobada','rechazada','requiere_repeticion','pendiente_resultados')),
  motivo_id   uuid references public.motivos_prubind(id) on delete restrict,
  descripcion text check (descripcion is null or char_length(descripcion) <= 1000),
  emitido_por uuid not null references public.usuarios_prubind(id) on delete restrict,
  created_at  timestamptz not null default now(),
  constraint dictamenes_prubind_rech_ck check (dictamen <> 'rechazada' or motivo_id is not null)
);
create index dictamenes_prubind_prueba_idx on public.dictamenes_prubind (prueba_id, created_at desc);
create index dictamenes_prubind_motivo_idx on public.dictamenes_prubind (motivo_id);
create index dictamenes_prubind_emitido_idx on public.dictamenes_prubind (emitido_por);

create table public.autorizaciones_prubind (
  id             uuid primary key default gen_random_uuid(),
  prueba_id      uuid not null references public.pruebas_prubind(id) on delete restrict,
  ejecucion      integer not null,
  tipo           text not null check (tipo in ('ejecucion','implementacion')),
  puesto_id      uuid references public.puestos_prubind(id) on delete restrict,
  autorizado_por uuid not null references public.usuarios_prubind(id) on delete restrict,
  comentario     text check (comentario is null or char_length(comentario) <= 500),
  created_at     timestamptz not null default now()
);
create unique index autorizaciones_prubind_uk on public.autorizaciones_prubind (prueba_id, ejecucion, tipo, coalesce(puesto_id, autorizado_por));
create index autorizaciones_prubind_puesto_idx on public.autorizaciones_prubind (puesto_id);
create index autorizaciones_prubind_por_idx on public.autorizaciones_prubind (autorizado_por);

-- Seguimiento y evidencia (se recrean con los vínculos nuevos)
create table public.seguimiento_prubind (
  id          bigint generated always as identity primary key,
  prueba_id   uuid not null references public.pruebas_prubind(id) on delete cascade,
  tipo        text not null default 'nota' check (tipo in ('nota','estado','sistema')),
  texto       text not null check (char_length(btrim(texto)) between 1 and 2000),
  usuario_id  uuid references public.usuarios_prubind(id) on delete restrict,
  created_at  timestamptz not null default now()
);
create index seguimiento_prubind_prueba_idx on public.seguimiento_prubind (prueba_id, created_at desc);
create index seguimiento_prubind_fecha_idx on public.seguimiento_prubind (created_at desc);
create index seguimiento_prubind_usuario_idx on public.seguimiento_prubind (usuario_id);

create table public.adjuntos_prubind (
  id               uuid primary key default gen_random_uuid(),
  prueba_id        uuid not null references public.pruebas_prubind(id) on delete restrict,
  tipo_evidencia_id uuid references public.tipos_evidencia_prubind(id) on delete restrict,
  resultado_id     uuid references public.resultados_prubind(id) on delete set null,
  batch_id         uuid references public.batches_prubind(id) on delete set null,
  etapa            text check (etapa in ('registro','preparacion','ejecucion','evaluacion','dictamen','cierre')),
  nombre           text not null check (char_length(btrim(nombre)) between 1 and 200),
  ruta             text not null check (char_length(ruta) <= 300),
  mime             text check (mime is null or char_length(mime) <= 120),
  tamano           integer check (tamano is null or tamano between 0 and 20971520),
  descripcion      text check (descripcion is null or char_length(descripcion) <= 300),
  subido_por       uuid not null references public.usuarios_prubind(id) on delete restrict,
  created_at       timestamptz not null default now()
);
create unique index adjuntos_prubind_ruta_uk on public.adjuntos_prubind (ruta);
create index adjuntos_prubind_prueba_idx on public.adjuntos_prubind (prueba_id);
create index adjuntos_prubind_tipo_idx on public.adjuntos_prubind (tipo_evidencia_id);
create index adjuntos_prubind_res_idx on public.adjuntos_prubind (resultado_id);
create index adjuntos_prubind_batch_idx on public.adjuntos_prubind (batch_id);
create index adjuntos_prubind_sub_idx on public.adjuntos_prubind (subido_por);

-- ---------- 4. RLS activado desde la creación (políticas en migración 7)
do $$
declare t text;
begin
  foreach t in array array['puestos_prubind','unidades_prubind','objetivos_prubind','productos_prubind','materias_primas_prubind',
    'proveedores_prubind','lotes_mp_prubind','equipos_prubind','equipo_parametros_prubind','recetas_prubind','receta_versiones_prubind',
    'receta_ingredientes_prubind','metodos_prubind','especificaciones_prubind','plantilla_evaluacion_prubind','motivos_prubind',
    'tipos_evidencia_prubind','autoridades_prubind','folios_prubind','pruebas_prubind','prueba_formulacion_prubind',
    'prueba_materiales_prubind','prueba_parametros_prubind','plan_evaluacion_prubind','puntos_muestreo_prubind','lotes_diarios_prubind',
    'batches_prubind','batch_lotes_mp_prubind','ejecucion_controles_prubind','muestras_prubind','muestra_batches_prubind',
    'resultados_prubind','dictamenes_prubind','autorizaciones_prubind','seguimiento_prubind','adjuntos_prubind'] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;
