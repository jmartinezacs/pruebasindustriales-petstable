-- =====================================================================
-- Pruebas industriales · Pet's Table S.A. de C.V.
-- Migración 1/3: esquema, restricciones e índices.
-- Todos los objetos llevan el sufijo _prubind (o prefijo prubind_) para
-- aislarlos de las demás apps de esta instancia. No modifica objetos ajenos.
-- =====================================================================

-- ---------- Catálogo de áreas -----------------------------------------
create table if not exists public.areas_prubind (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null check (char_length(btrim(nombre)) between 2 and 80),
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists areas_prubind_nombre_uk on public.areas_prubind (lower(btrim(nombre)));

-- ---------- Usuarios autorizados --------------------------------------
-- Auth es compartido (misma contraseña que las demás apps). Esta tabla define
-- quién entra a ESTA app, su rol y sus funciones operativas.
--   rol:       admin (gestión completa) | usuario
--   funciones: calidad | produccion | compras | direccion
create table if not exists public.usuarios_prubind (
  id          uuid primary key default gen_random_uuid(),
  email       text not null check (email ~* '^[a-z0-9._%+-]+@petstable\.mx$'),
  nombre      text not null check (char_length(btrim(nombre)) between 2 and 120),
  puesto      text check (puesto is null or char_length(puesto) <= 100),
  foto_url    text check (foto_url is null or (char_length(foto_url) <= 500 and foto_url ~ '^https://')),
  area_id     uuid references public.areas_prubind(id) on delete restrict,
  rol         text not null default 'usuario' check (rol in ('admin', 'usuario')),
  funciones   text[] not null default '{}'
              check (funciones <@ array['calidad', 'produccion', 'compras', 'direccion']::text[]),
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists usuarios_prubind_email_uk on public.usuarios_prubind (lower(email));
create index if not exists usuarios_prubind_area_idx on public.usuarios_prubind (area_id);

-- ---------- Tipos de prueba -------------------------------------------
create table if not exists public.tipos_prueba_prubind (
  codigo          text primary key check (codigo ~ '^[a-z_]{3,40}$'),
  nombre          text not null check (char_length(btrim(nombre)) between 3 and 80),
  descripcion     text check (descripcion is null or char_length(descripcion) <= 300),
  prefijo         text not null check (prefijo ~ '^[A-Z]{2,4}$'),
  usa_proveedor   boolean not null default false,   -- captura proveedor actual / nuevo
  usa_empaque     boolean not null default false,   -- captura material actual / nuevo
  usa_envasadora  boolean not null default false,   -- sección de parámetros de envasadora
  orden           smallint not null default 0,
  activo          boolean not null default true,
  updated_at      timestamptz not null default now()
);
create unique index if not exists tipos_prueba_prubind_prefijo_uk on public.tipos_prueba_prubind (prefijo);

-- Quién puede detonar (registrar) cada tipo. Los administradores pueden registrar cualquiera.
create table if not exists public.tipo_responsables_prubind (
  tipo        text not null references public.tipos_prueba_prubind(codigo) on delete cascade,
  usuario_id  uuid not null references public.usuarios_prubind(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (tipo, usuario_id)
);
create index if not exists tipo_responsables_prubind_usuario_idx on public.tipo_responsables_prubind (usuario_id);

-- ---------- Pruebas ----------------------------------------------------
-- Estados: borrador → planeada → en_ejecucion → en_evaluacion → aprobada | rechazada
--          (cancelada desde cualquier estado abierto)
create table if not exists public.pruebas_prubind (
  id                    uuid primary key default gen_random_uuid(),
  folio                 bigint generated always as identity,
  tipo                  text not null references public.tipos_prueba_prubind(codigo) on delete restrict,
  titulo                text not null check (char_length(btrim(titulo)) between 3 and 150),
  producto              text check (producto is null or char_length(producto) <= 150),
  objetivo              text not null check (char_length(btrim(objetivo)) between 3 and 1000),
  descripcion           text check (descripcion is null or char_length(descripcion) <= 3000),
  num_batches           integer not null default 1 check (num_batches between 1 and 200),
  fecha_inicio          date,
  fecha_fin             date,
  -- Cambio de proveedor
  insumo_cambio         text check (insumo_cambio is null or char_length(insumo_cambio) <= 150),
  proveedor_actual      text check (proveedor_actual is null or char_length(proveedor_actual) <= 150),
  proveedor_nuevo       text check (proveedor_nuevo is null or char_length(proveedor_nuevo) <= 150),
  -- Cambio de material de empaque
  material_actual       text check (material_actual is null or char_length(material_actual) <= 150),
  material_nuevo        text check (material_nuevo is null or char_length(material_nuevo) <= 150),
  estado                text not null default 'borrador'
                        check (estado in ('borrador','planeada','en_ejecucion','en_evaluacion','aprobada','rechazada','cancelada')),
  creado_por            uuid not null references public.usuarios_prubind(id) on delete restrict,
  -- Dictamen técnico de Calidad
  dictamen_calidad      text check (dictamen_calidad in ('conforme','no_conforme')),
  dictamen_calidad_obs  text check (dictamen_calidad_obs is null or char_length(dictamen_calidad_obs) <= 2000),
  dictamen_calidad_por  uuid references public.usuarios_prubind(id) on delete restrict,
  dictamen_calidad_at   timestamptz,
  -- Dictamen final de Dirección
  dictamen_final        text check (dictamen_final in ('aprobada','rechazada')),
  dictamen_final_obs    text check (dictamen_final_obs is null or char_length(dictamen_final_obs) <= 2000),
  dictamen_final_por    uuid references public.usuarios_prubind(id) on delete restrict,
  dictamen_final_at     timestamptz,
  -- Cancelación
  motivo_cancelacion    text check (motivo_cancelacion is null or char_length(motivo_cancelacion) <= 500),
  cancelado_por         uuid references public.usuarios_prubind(id) on delete restrict,
  cancelado_at          timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint pruebas_prubind_fechas_ck check (fecha_fin is null or fecha_inicio is null or fecha_fin >= fecha_inicio),
  constraint pruebas_prubind_cancelacion_ck check (estado <> 'cancelada' or motivo_cancelacion is not null),
  constraint pruebas_prubind_final_ck check (estado not in ('aprobada','rechazada') or (dictamen_final = estado and dictamen_calidad is not null))
);
create unique index if not exists pruebas_prubind_folio_uk on public.pruebas_prubind (folio);
create index if not exists pruebas_prubind_estado_idx on public.pruebas_prubind (estado);
create index if not exists pruebas_prubind_tipo_idx on public.pruebas_prubind (tipo);
create index if not exists pruebas_prubind_creado_idx on public.pruebas_prubind (creado_por);
create index if not exists pruebas_prubind_created_at_idx on public.pruebas_prubind (created_at desc);
create index if not exists pruebas_prubind_dcp_idx on public.pruebas_prubind (dictamen_calidad_por);
create index if not exists pruebas_prubind_dfp_idx on public.pruebas_prubind (dictamen_final_por);
create index if not exists pruebas_prubind_canc_idx on public.pruebas_prubind (cancelado_por);

-- ---------- Batches ----------------------------------------------------
-- Se generan automáticamente a partir de num_batches de la prueba.
create table if not exists public.batches_prubind (
  id                  uuid primary key default gen_random_uuid(),
  prueba_id           uuid not null references public.pruebas_prubind(id) on delete cascade,
  numero              integer not null check (numero between 1 and 200),
  fecha_programada    date,
  fecha_real          date,
  lote                text check (lote is null or char_length(lote) <= 40),
  cantidad            numeric(14,3) check (cantidad is null or cantidad > 0),
  unidad              text check (unidad is null or char_length(unidad) <= 20),
  estado              text not null default 'programado' check (estado in ('programado','producido','cancelado')),
  observaciones       text check (observaciones is null or char_length(observaciones) <= 1000),
  motivo_cancelacion  text check (motivo_cancelacion is null or char_length(motivo_cancelacion) <= 300),
  registrado_por      uuid references public.usuarios_prubind(id) on delete restrict,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint batches_prubind_producido_ck check (estado <> 'producido' or fecha_real is not null),
  constraint batches_prubind_cancelado_ck check (estado <> 'cancelado' or motivo_cancelacion is not null)
);
create unique index if not exists batches_prubind_uk on public.batches_prubind (prueba_id, numero);
create index if not exists batches_prubind_fecha_idx on public.batches_prubind (fecha_programada) where estado = 'programado';
create index if not exists batches_prubind_reg_idx on public.batches_prubind (registrado_por);

-- ---------- Insumos requeridos (solicitud → validación → compra) -------
create table if not exists public.insumos_prubind (
  id                   uuid primary key default gen_random_uuid(),
  prueba_id            uuid not null references public.pruebas_prubind(id) on delete cascade,
  insumo               text not null check (char_length(btrim(insumo)) between 2 and 150),
  especificacion       text check (especificacion is null or char_length(especificacion) <= 300),
  proveedor            text check (proveedor is null or char_length(proveedor) <= 150),
  unidad               text not null check (char_length(btrim(unidad)) between 1 and 20),
  cantidad_por_batch   numeric(14,3) check (cantidad_por_batch is null or cantidad_por_batch > 0),
  cantidad_solicitada  numeric(14,3) not null check (cantidad_solicitada > 0),
  fecha_requerida      date,
  estado               text not null default 'solicitado'
                       check (estado in ('solicitado','validado','en_compra','recibido','cancelado')),
  cantidad_validada    numeric(14,3) check (cantidad_validada is null or cantidad_validada > 0),
  obs_validacion       text check (obs_validacion is null or char_length(obs_validacion) <= 300),
  validado_por         uuid references public.usuarios_prubind(id) on delete restrict,
  validado_at          timestamptz,
  orden_compra         text check (orden_compra is null or char_length(orden_compra) <= 40),
  obs_compras          text check (obs_compras is null or char_length(obs_compras) <= 300),
  cantidad_recibida    numeric(14,3) check (cantidad_recibida is null or cantidad_recibida > 0),
  fecha_recepcion      date,
  compras_por          uuid references public.usuarios_prubind(id) on delete restrict,
  motivo_cancelacion   text check (motivo_cancelacion is null or char_length(motivo_cancelacion) <= 300),
  solicitado_por       uuid not null references public.usuarios_prubind(id) on delete restrict,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint insumos_prubind_validado_ck check (estado in ('solicitado','cancelado') or cantidad_validada is not null),
  constraint insumos_prubind_recibido_ck check (estado <> 'recibido' or (cantidad_recibida is not null and fecha_recepcion is not null)),
  constraint insumos_prubind_cancelado_ck check (estado <> 'cancelado' or motivo_cancelacion is not null)
);
create index if not exists insumos_prubind_prueba_idx on public.insumos_prubind (prueba_id);
create index if not exists insumos_prubind_estado_idx on public.insumos_prubind (estado);
create index if not exists insumos_prubind_sol_idx on public.insumos_prubind (solicitado_por);
create index if not exists insumos_prubind_val_idx on public.insumos_prubind (validado_por);
create index if not exists insumos_prubind_com_idx on public.insumos_prubind (compras_por);

-- ---------- Resultados de calidad (captura libre por batch) ------------
create table if not exists public.resultados_prubind (
  id              uuid primary key default gen_random_uuid(),
  batch_id        uuid not null references public.batches_prubind(id) on delete restrict,
  prueba_id       uuid not null references public.pruebas_prubind(id) on delete cascade,
  tipo_analisis   text not null check (tipo_analisis in ('fisicoquimico','microbiologico','proceso','otro')),
  parametro       text not null check (char_length(btrim(parametro)) between 1 and 120),
  valor           text not null check (char_length(btrim(valor)) between 1 and 60),
  unidad          text check (unidad is null or char_length(unidad) <= 30),
  especificacion  text check (especificacion is null or char_length(especificacion) <= 120),
  resultado       text not null check (resultado in ('cumple','no_cumple','informativo')),
  observaciones   text check (observaciones is null or char_length(observaciones) <= 500),
  fecha_analisis  date not null,
  capturado_por   uuid not null references public.usuarios_prubind(id) on delete restrict,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists resultados_prubind_batch_idx on public.resultados_prubind (batch_id);
create index if not exists resultados_prubind_prueba_idx on public.resultados_prubind (prueba_id);
create index if not exists resultados_prubind_fecha_idx on public.resultados_prubind (fecha_analisis desc);
create index if not exists resultados_prubind_cap_idx on public.resultados_prubind (capturado_por);

-- ---------- Parámetros de envasadora (captura libre) -------------------
create table if not exists public.envasadora_prubind (
  id             uuid primary key default gen_random_uuid(),
  prueba_id      uuid not null references public.pruebas_prubind(id) on delete cascade,
  batch_id       uuid references public.batches_prubind(id) on delete set null,
  maquina        text check (maquina is null or char_length(maquina) <= 80),
  parametro      text not null check (char_length(btrim(parametro)) between 1 and 120),
  valor          text not null check (char_length(btrim(valor)) between 1 and 60),
  unidad         text check (unidad is null or char_length(unidad) <= 30),
  observaciones  text check (observaciones is null or char_length(observaciones) <= 500),
  capturado_por  uuid not null references public.usuarios_prubind(id) on delete restrict,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists envasadora_prubind_prueba_idx on public.envasadora_prubind (prueba_id);
create index if not exists envasadora_prubind_batch_idx on public.envasadora_prubind (batch_id);
create index if not exists envasadora_prubind_cap_idx on public.envasadora_prubind (capturado_por);

-- ---------- Seguimiento (notas y eventos; solo inserción) --------------
create table if not exists public.seguimiento_prubind (
  id          bigint generated always as identity primary key,
  prueba_id   uuid not null references public.pruebas_prubind(id) on delete cascade,
  tipo        text not null default 'nota' check (tipo in ('nota','estado','sistema')),
  texto       text not null check (char_length(btrim(texto)) between 1 and 2000),
  usuario_id  uuid references public.usuarios_prubind(id) on delete restrict,
  created_at  timestamptz not null default now()
);
create index if not exists seguimiento_prubind_prueba_idx on public.seguimiento_prubind (prueba_id, created_at desc);
create index if not exists seguimiento_prubind_fecha_idx on public.seguimiento_prubind (created_at desc);
create index if not exists seguimiento_prubind_usuario_idx on public.seguimiento_prubind (usuario_id);

-- ---------- Adjuntos (archivo en Storage, bucket privado) --------------
create table if not exists public.adjuntos_prubind (
  id           uuid primary key default gen_random_uuid(),
  prueba_id    uuid not null references public.pruebas_prubind(id) on delete restrict,
  nombre       text not null check (char_length(btrim(nombre)) between 1 and 200),
  ruta         text not null check (char_length(ruta) <= 300),
  mime         text check (mime is null or char_length(mime) <= 120),
  tamano       integer check (tamano is null or tamano between 0 and 20971520),
  descripcion  text check (descripcion is null or char_length(descripcion) <= 300),
  subido_por   uuid not null references public.usuarios_prubind(id) on delete restrict,
  created_at   timestamptz not null default now()
);
create unique index if not exists adjuntos_prubind_ruta_uk on public.adjuntos_prubind (ruta);
create index if not exists adjuntos_prubind_prueba_idx on public.adjuntos_prubind (prueba_id);
create index if not exists adjuntos_prubind_sub_idx on public.adjuntos_prubind (subido_por);

-- ---------- Bitácora de auditoría -------------------------------------
create table if not exists public.bitacora_prubind (
  id             bigint generated always as identity primary key,
  tabla          text not null,
  registro_id    text not null,
  accion         text not null check (accion in ('INSERT','UPDATE','DELETE')),
  cambios        jsonb,
  usuario_email  text,
  created_at     timestamptz not null default now()
);
create index if not exists bitacora_prubind_fecha_idx on public.bitacora_prubind (created_at desc);
create index if not exists bitacora_prubind_tabla_idx on public.bitacora_prubind (tabla, registro_id);

-- ---------- RLS activado desde la creación (políticas en migración 2) --
alter table public.areas_prubind             enable row level security;
alter table public.usuarios_prubind          enable row level security;
alter table public.tipos_prueba_prubind      enable row level security;
alter table public.tipo_responsables_prubind enable row level security;
alter table public.pruebas_prubind           enable row level security;
alter table public.batches_prubind           enable row level security;
alter table public.insumos_prubind           enable row level security;
alter table public.resultados_prubind        enable row level security;
alter table public.envasadora_prubind        enable row level security;
alter table public.seguimiento_prubind       enable row level security;
alter table public.adjuntos_prubind          enable row level security;
alter table public.bitacora_prubind          enable row level security;
