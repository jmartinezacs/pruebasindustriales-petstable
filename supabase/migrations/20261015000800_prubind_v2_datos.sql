-- =====================================================================
-- Pruebas industriales · v2 · Migración 8: datos maestros iniciales
-- Origen: requerimientos v2 del 15/10/2026. Todo es editable en el portal.
-- NO se cargan límites de aceptación ni rangos de máquina (los captura Calidad),
-- salvo el criterio de Salmonella que el documento indica explícitamente.
-- Las plantillas de proveedor, materia prima, proceso, equipo y vida útil
-- son PROPUESTA y deben validarse con Calidad.
-- =====================================================================

-- Administradores: solo el responsable del sistema y Nelisa (decisión del usuario)
update public.usuarios_prubind set rol = 'usuario' where email = 'camila@petstable.mx' and rol = 'admin';

insert into public.puestos_prubind (nombre) values
  ('Directora de Calidad'), ('Director de Producción'), ('Jefa de Calidad'), ('Gerente de Producción'), ('Gerente de Compras'),
  ('Coordinador de Almacén de Materia Prima'), ('Gerente de Procesos y Mejora Continua'), ('Jefe de Mantenimiento'),
  ('Inspector de Calidad'), ('Supervisor de Producción')
on conflict do nothing;

insert into public.unidades_prubind (simbolo, nombre) values
  ('kg', 'Kilogramo'), ('g', 'Gramo'), ('L', 'Litro'), ('mL', 'Mililitro'), ('°C', 'Grado Celsius'), ('cm/s', 'Centímetros por segundo'),
  ('%', 'Porcentaje'), ('pH', 'Unidades de pH'), ('UFC/g', 'Unidades formadoras de colonia por gramo'), ('h', 'Hora'), ('min', 'Minuto'),
  ('días', 'Días'), ('pzas', 'Piezas'), ('m', 'Metro'), ('mm', 'Milímetro'), ('bar', 'Bar'), ('N', 'Newton'), ('bolsas/min', 'Bolsas por minuto')
on conflict do nothing;

-- Los 10 tipos de prueba (se reutilizan los códigos existentes y se agregan los nuevos)
insert into public.tipos_prueba_prubind (codigo, nombre, descripcion, prefijo, orden) values
  ('cambio_receta', 'Cambio en la receta', 'Agregar, retirar o sustituir una materia prima.', null, 2),
  ('empaque_secundario', 'Cambio de empaque secundario', 'Caja, corrugado u otro empaque secundario.', null, 6),
  ('cambio_proceso', 'Cambio de proceso', 'Modificación de condiciones o etapas del proceso.', null, 7),
  ('cambio_equipo', 'Cambio de equipo o maquinaria', 'Equipo nuevo, modificado o reemplazado.', null, 8),
  ('cambio_especificacion_mp', 'Cambio de especificaciones de materia prima', 'Nueva especificación de una materia prima.', null, 9),
  ('vida_util', 'Cambio de vida útil', 'Determinación o confirmación de la vida útil.', null, 10)
on conflict (codigo) do nothing;
update public.tipos_prueba_prubind t set nombre = v.nombre, descripcion = v.descripcion, orden = v.orden, activo = true,
       campos_registro = v.campos, secciones_prep = v.prep, ejecucion_form = v.ejec
from (values
  ('producto_nuevo', 'Innovación de productos', 'Desarrollo de un producto o receta nueva.', 1,
     '{producto,receta}'::text[], '{batches,peso,formulacion,materiales,equipos,muestreo}'::text[], 'fabricacion'),
  ('cambio_receta', 'Cambio en la receta', 'Agregar, retirar o sustituir una materia prima.', 2,
     '{producto,receta,materia_prima}', '{batches,peso,formulacion,materiales,muestreo}', 'fabricacion'),
  ('cambio_formulacion', 'Cambio en la formulación', 'Modificar cantidades de ingredientes existentes.', 3,
     '{producto,receta}', '{batches,peso,formulacion,materiales,muestreo}', 'fabricacion'),
  ('cambio_proveedor', 'Cambio de proveedor', 'Evaluación de un proveedor alterno de materia prima.', 4,
     '{materia_prima,proveedor,producto}', '{batches,peso,materiales,muestreo}', 'fabricacion'),
  ('material_empaque', 'Cambio de empaque primario (film)', 'Film u otro empaque en contacto con el producto.', 5,
     '{empaque,producto,proveedor,equipo}', '{materiales,equipos,muestreo}', 'controles'),
  ('empaque_secundario', 'Cambio de empaque secundario', 'Caja, corrugado u otro empaque secundario.', 6,
     '{empaque,producto,proveedor}', '{materiales,muestreo}', 'controles'),
  ('cambio_proceso', 'Cambio de proceso', 'Modificación de condiciones o etapas del proceso.', 7,
     '{producto,proceso,equipo}', '{batches,peso,equipos,muestreo}', 'fabricacion'),
  ('cambio_equipo', 'Cambio de equipo o maquinaria', 'Equipo nuevo, modificado o reemplazado.', 8,
     '{equipo,producto}', '{batches,peso,equipos,muestreo}', 'fabricacion'),
  ('cambio_especificacion_mp', 'Cambio de especificaciones de materia prima', 'Nueva especificación de una materia prima.', 9,
     '{materia_prima,proveedor}', '{materiales,muestreo}', 'controles'),
  ('vida_util', 'Cambio de vida útil', 'Determinación o confirmación de la vida útil.', 10,
     '{producto,receta}', '{muestreo,vida_util}', 'controles')
) as v(codigo, nombre, descripcion, orden, campos, prep, ejec)
where t.codigo = v.codigo;

insert into public.objetivos_prubind (nombre, orden) values
  ('Validar un producto o receta nueva', 1), ('Mejorar la calidad del producto', 2), ('Reducir costos', 3),
  ('Asegurar el abasto o un proveedor alterno', 4), ('Cumplir un requisito de cliente o regulatorio', 5),
  ('Mejorar el desempeño del proceso o equipo', 6), ('Determinar o confirmar la vida útil', 7), ('Otro (describir)', 99)
on conflict do nothing;

insert into public.motivos_prubind (tipo, nombre) values
  ('rechazo', 'Incumplimiento fisicoquímico'), ('rechazo', 'Incumplimiento microbiológico'), ('rechazo', 'Incumplimiento sensorial'),
  ('rechazo', 'Incumplimiento de proceso'), ('rechazo', 'Incumplimiento de empaque'), ('rechazo', 'Evidencia insuficiente'),
  ('rechazo', 'Otro motivo justificado'),
  ('desviacion', 'Fuera de especificación'), ('desviacion', 'Falla de equipo'), ('desviacion', 'Desviación de proceso'),
  ('desviacion', 'Materia prima no conforme'), ('desviacion', 'Error de muestreo o análisis'), ('desviacion', 'Otro')
on conflict do nothing;

insert into public.tipos_evidencia_prubind (nombre) values
  ('Reporte de laboratorio'), ('Fotografía'), ('Ficha técnica'), ('Certificado de análisis'), ('Registro de producción'), ('Otro')
on conflict do nothing;

-- Métodos y controles (tiempos y diluciones según el documento; editables)
insert into public.metodos_prubind (codigo, nombre, categoria, tipo_resultado, unidad_id, diluciones, horas_lectura, tecnica, base_expresion, opciones, revisa_puesto_id)
select v.codigo, v.nombre, v.cat, v.tr, u.id, v.dil, v.horas, v.tec, v.base, v.opc, p.id
from (values
  ('FQ-PH', 'pH', 'fisicoquimica', 'numerico', 'pH', '{}'::text[], null::int, null, null, '{}'::text[], null),
  ('FQ-HUM', 'Humedad', 'fisicoquimica', 'numerico', '%', '{}', null, null, null, '{}', null),
  ('SEN-COLOR', 'Color', 'sensorial', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_evaluado}', null),
  ('SEN-OLOR', 'Olor', 'sensorial', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_evaluado}', null),
  ('SEN-SABOR', 'Sabor', 'sensorial', 'opcion', null, '{}', null, 'Solo conforme al protocolo autorizado y en condiciones de inocuidad', null, '{conforme,no_conforme,no_evaluado}', null),
  ('SEN-TEXTURA', 'Textura', 'sensorial', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_evaluado}', null),
  ('MIC-MESO', 'Mesófilos aerobios', 'microbiologia', 'diluciones', 'UFC/g', '{10⁻¹,10⁻²}', 24, null, null, '{}', null),
  ('MIC-COLI', 'Coliformes totales', 'microbiologia', 'diluciones', 'UFC/g', '{10⁻¹,10⁻²}', 24, null, null, '{}', null),
  ('MIC-ECOLI', 'Escherichia coli', 'microbiologia', 'numerico', 'UFC/g', '{}', null, 'Compact Dry', null, '{}', null),
  ('MIC-HONGOS', 'Hongos', 'microbiologia', 'diluciones', 'UFC/g', '{10⁻¹,10⁻²,10⁻³}', 60, null, null, '{}', null),
  ('MIC-LEV', 'Levaduras', 'microbiologia', 'diluciones', 'UFC/g', '{10⁻¹,10⁻²,10⁻³}', 60, null, null, '{}', null),
  ('MIC-SALM', 'Salmonella', 'microbiologia', 'presencia', null, '{}', null, 'PCR', 'en 25 g', '{}', null),
  ('MIC-O157', 'E. coli O157', 'microbiologia', 'presencia', null, '{}', null, 'PCR', null, '{}', null),
  ('BRO-CEN', 'Cenizas', 'bromatologia', 'numerico', '%', '{}', null, null, null, '{}', 'Directora de Calidad'),
  ('BRO-GRA', 'Grasas', 'bromatologia', 'numerico', '%', '{}', null, null, null, '{}', 'Directora de Calidad'),
  ('BRO-HUM', 'Humedad (bromatológico)', 'bromatologia', 'numerico', '%', '{}', null, null, null, '{}', 'Directora de Calidad'),
  ('BRO-PRO', 'Proteínas', 'bromatologia', 'numerico', '%', '{}', null, null, null, '{}', 'Directora de Calidad'),
  ('EP-PARAM', 'Parámetros de operación utilizados', 'empaque_primario', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_aplica,pendiente}', null),
  ('EP-TSELL', 'Temperatura de sellado', 'empaque_primario', 'numerico', '°C', '{}', null, null, null, '{}', null),
  ('EP-VEL', 'Velocidad de operación', 'empaque_primario', 'numerico', 'bolsas/min', '{}', null, null, null, '{}', null),
  ('EP-SELLO', 'Calidad y uniformidad del sellado', 'empaque_primario', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_aplica,pendiente}', null),
  ('EP-ABRE', 'Prueba de abre fácil', 'empaque_primario', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_aplica,pendiente}', null),
  ('EP-HERM', 'Hermeticidad o vacío', 'empaque_primario', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_aplica,pendiente}', null),
  ('EP-COD', 'Codificado o impresión correcta', 'empaque_primario', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_aplica,pendiente}', null),
  ('EP-COMPAT', 'Compatibilidad del film con la máquina', 'empaque_primario', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_aplica,pendiente}', null),
  ('EP-COMPORT', 'Comportamiento del material durante el proceso', 'empaque_primario', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_aplica,pendiente}', null),
  ('ES-RES', 'Resistencia y protección', 'empaque_secundario', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_aplica,pendiente}', null),
  ('ES-DIM', 'Dimensiones y ajuste', 'empaque_secundario', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_aplica,pendiente}', null),
  ('ES-ID', 'Identificación y etiquetado', 'empaque_secundario', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_aplica,pendiente}', null),
  ('ES-ARM', 'Facilidad de armado', 'empaque_secundario', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_aplica,pendiente}', null),
  ('ES-MAN', 'Manejo y almacenamiento', 'empaque_secundario', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_aplica,pendiente}', null),
  ('MP-COA', 'Certificado de análisis del proveedor', 'materia_prima', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_aplica,pendiente}', null),
  ('MP-FT', 'Ficha técnica conforme', 'materia_prima', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_aplica,pendiente}', null),
  ('MP-INSP', 'Inspección de recepción', 'materia_prima', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_aplica,pendiente}', null),
  ('MP-ESPEC', 'Cumplimiento de la especificación de materia prima', 'materia_prima', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_aplica,pendiente}', null),
  ('PR-PARAM', 'Parámetros de proceso conforme a lo planeado', 'proceso', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_aplica,pendiente}', null),
  ('PR-REND', 'Rendimiento del proceso', 'proceso', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_aplica,pendiente}', null),
  ('EQ-FUNC', 'Funcionamiento del equipo', 'equipo', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_aplica,pendiente}', null),
  ('EQ-PARAM', 'Parámetros de operación del equipo', 'equipo', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_aplica,pendiente}', null),
  ('EQ-INST', 'Condición de instalación y seguridad', 'equipo', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_aplica,pendiente}', null),
  ('EQ-LIMP', 'Limpieza y sanitización', 'equipo', 'opcion', null, '{}', null, null, null, '{conforme,no_conforme,no_aplica,pendiente}', null)
) as v(codigo, nombre, cat, tr, unidad, dil, horas, tec, base, opc, puesto)
left join public.unidades_prubind u on u.simbolo = v.unidad
left join public.puestos_prubind p on p.nombre = v.puesto
on conflict (codigo) do nothing;

-- Criterio indicado explícitamente en el documento (validar la referencia con Calidad)
insert into public.especificaciones_prubind (metodo_id, criterio_texto, referencia, version)
select m.id, 'Ausencia en 25 g', 'Requerimientos del sistema v2 (15/10/2026) — sustituir por el documento aprobado de Calidad', '1'
from public.metodos_prubind m where m.codigo = 'MIC-SALM'
  and not exists (select 1 from public.especificaciones_prubind e where e.metodo_id = m.id);

-- Plantillas de evaluación por tipo
insert into public.plantilla_evaluacion_prubind (tipo, metodo_id, obligatorio, nivel, orden)
select v.tipo, m.id, true, v.nivel, v.orden
from (values
  -- A. Innovación, receta y formulación
  ('producto_nuevo','FQ-PH','batch',1),('producto_nuevo','FQ-HUM','batch',2),('producto_nuevo','SEN-COLOR','lote_diario',3),
  ('producto_nuevo','SEN-OLOR','lote_diario',4),('producto_nuevo','SEN-SABOR','lote_diario',5),('producto_nuevo','SEN-TEXTURA','lote_diario',6),
  ('producto_nuevo','MIC-MESO','lote_diario',7),('producto_nuevo','MIC-COLI','lote_diario',8),('producto_nuevo','MIC-ECOLI','lote_diario',9),
  ('producto_nuevo','MIC-HONGOS','lote_diario',10),('producto_nuevo','MIC-LEV','lote_diario',11),('producto_nuevo','MIC-SALM','lote_diario',12),
  ('producto_nuevo','MIC-O157','lote_diario',13),('producto_nuevo','BRO-CEN','compuesta',14),('producto_nuevo','BRO-GRA','compuesta',15),
  ('producto_nuevo','BRO-HUM','compuesta',16),('producto_nuevo','BRO-PRO','compuesta',17),
  ('cambio_receta','FQ-PH','batch',1),('cambio_receta','FQ-HUM','batch',2),('cambio_receta','SEN-COLOR','lote_diario',3),
  ('cambio_receta','SEN-OLOR','lote_diario',4),('cambio_receta','SEN-SABOR','lote_diario',5),('cambio_receta','SEN-TEXTURA','lote_diario',6),
  ('cambio_receta','MIC-MESO','lote_diario',7),('cambio_receta','MIC-COLI','lote_diario',8),('cambio_receta','MIC-ECOLI','lote_diario',9),
  ('cambio_receta','MIC-HONGOS','lote_diario',10),('cambio_receta','MIC-LEV','lote_diario',11),('cambio_receta','MIC-SALM','lote_diario',12),
  ('cambio_receta','MIC-O157','lote_diario',13),('cambio_receta','BRO-CEN','compuesta',14),('cambio_receta','BRO-GRA','compuesta',15),
  ('cambio_receta','BRO-HUM','compuesta',16),('cambio_receta','BRO-PRO','compuesta',17),
  ('cambio_formulacion','FQ-PH','batch',1),('cambio_formulacion','FQ-HUM','batch',2),('cambio_formulacion','SEN-COLOR','lote_diario',3),
  ('cambio_formulacion','SEN-OLOR','lote_diario',4),('cambio_formulacion','SEN-SABOR','lote_diario',5),('cambio_formulacion','SEN-TEXTURA','lote_diario',6),
  ('cambio_formulacion','MIC-MESO','lote_diario',7),('cambio_formulacion','MIC-COLI','lote_diario',8),('cambio_formulacion','MIC-ECOLI','lote_diario',9),
  ('cambio_formulacion','MIC-HONGOS','lote_diario',10),('cambio_formulacion','MIC-LEV','lote_diario',11),('cambio_formulacion','MIC-SALM','lote_diario',12),
  ('cambio_formulacion','MIC-O157','lote_diario',13),('cambio_formulacion','BRO-CEN','compuesta',14),('cambio_formulacion','BRO-GRA','compuesta',15),
  ('cambio_formulacion','BRO-HUM','compuesta',16),('cambio_formulacion','BRO-PRO','compuesta',17),
  -- B. Empaque primario (film): solo controles de empaque y máquina
  ('material_empaque','EP-PARAM','corrida',1),('material_empaque','EP-TSELL','corrida',2),('material_empaque','EP-VEL','corrida',3),
  ('material_empaque','EP-SELLO','corrida',4),('material_empaque','EP-ABRE','corrida',5),('material_empaque','EP-HERM','corrida',6),
  ('material_empaque','EP-COD','corrida',7),('material_empaque','EP-COMPAT','corrida',8),('material_empaque','EP-COMPORT','corrida',9),
  -- C. Empaque secundario
  ('empaque_secundario','ES-RES','corrida',1),('empaque_secundario','ES-DIM','corrida',2),('empaque_secundario','ES-ID','corrida',3),
  ('empaque_secundario','ES-ARM','corrida',4),('empaque_secundario','ES-MAN','corrida',5),
  -- D. Propuestas (validar con Calidad)
  ('cambio_proveedor','MP-COA','corrida',1),('cambio_proveedor','MP-FT','corrida',2),('cambio_proveedor','MP-INSP','corrida',3),
  ('cambio_proveedor','FQ-PH','batch',4),('cambio_proveedor','FQ-HUM','batch',5),('cambio_proveedor','SEN-COLOR','lote_diario',6),
  ('cambio_proveedor','SEN-OLOR','lote_diario',7),('cambio_proveedor','SEN-TEXTURA','lote_diario',8),('cambio_proveedor','MIC-MESO','lote_diario',9),
  ('cambio_proveedor','MIC-COLI','lote_diario',10),('cambio_proveedor','MIC-SALM','lote_diario',11),
  ('cambio_especificacion_mp','MP-ESPEC','corrida',1),('cambio_especificacion_mp','MP-COA','corrida',2),('cambio_especificacion_mp','MP-FT','corrida',3),
  ('cambio_especificacion_mp','MP-INSP','corrida',4),
  ('cambio_proceso','PR-PARAM','corrida',1),('cambio_proceso','PR-REND','corrida',2),('cambio_proceso','FQ-PH','batch',3),
  ('cambio_proceso','FQ-HUM','batch',4),('cambio_proceso','SEN-COLOR','lote_diario',5),('cambio_proceso','SEN-TEXTURA','lote_diario',6),
  ('cambio_proceso','MIC-MESO','lote_diario',7),('cambio_proceso','MIC-COLI','lote_diario',8),
  ('cambio_equipo','EQ-FUNC','corrida',1),('cambio_equipo','EQ-PARAM','corrida',2),('cambio_equipo','EQ-INST','corrida',3),
  ('cambio_equipo','EQ-LIMP','corrida',4),('cambio_equipo','FQ-HUM','batch',5),('cambio_equipo','SEN-TEXTURA','lote_diario',6),
  ('vida_util','FQ-PH','punto',1),('vida_util','FQ-HUM','punto',2),('vida_util','SEN-COLOR','punto',3),('vida_util','SEN-OLOR','punto',4),
  ('vida_util','SEN-TEXTURA','punto',5),('vida_util','MIC-MESO','punto',6),('vida_util','MIC-HONGOS','punto',7),('vida_util','MIC-LEV','punto',8)
) as v(tipo, metodo, nivel, orden)
join public.metodos_prubind m on m.codigo = v.metodo
on conflict (tipo, metodo_id) do nothing;

-- Matriz de autoridades inicial (propuesta aceptada; editable en el portal)
insert into public.autoridades_prubind (tipo, accion, puesto_id)
select v.tipo, v.accion, p.id
from (values
  (null, 'preparar', 'Gerente de Procesos y Mejora Continua'), (null, 'preparar', 'Gerente de Producción'), (null, 'preparar', 'Jefa de Calidad'),
  (null, 'abastecer', 'Gerente de Compras'), (null, 'abastecer', 'Coordinador de Almacén de Materia Prima'),
  (null, 'autorizar_ejecucion', 'Gerente de Producción'), (null, 'autorizar_ejecucion', 'Director de Producción'),
  (null, 'ejecutar', 'Supervisor de Producción'), (null, 'ejecutar', 'Gerente de Producción'),
  ('cambio_equipo', 'ejecutar', 'Jefe de Mantenimiento'), ('cambio_proceso', 'ejecutar', 'Jefe de Mantenimiento'),
  (null, 'evaluar', 'Directora de Calidad'), (null, 'evaluar', 'Jefa de Calidad'), (null, 'evaluar', 'Inspector de Calidad'),
  (null, 'dictaminar', 'Directora de Calidad'),
  (null, 'cerrar', 'Directora de Calidad'), (null, 'cerrar', 'Gerente de Procesos y Mejora Continua'),
  (null, 'autorizar_implementacion', 'Director de Producción'), (null, 'autorizar_implementacion', 'Directora de Calidad')
) as v(tipo, accion, puesto)
join public.puestos_prubind p on p.nombre = v.puesto
on conflict do nothing;

-- Áreas adicionales para los puestos contemplados
insert into public.areas_prubind (nombre) values ('Calidad'), ('Almacén de materia prima'), ('Mantenimiento')
on conflict do nothing;
