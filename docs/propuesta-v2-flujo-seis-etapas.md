# Propuesta v2 · Flujo de seis etapas

**Estado:** propuesta para revisión. Todavía no se ha modificado la base de datos.
**Fecha:** 14/10/2026

## 1. Viabilidad

**Sí es viable** con la arquitectura actual: Supabase con RLS, triggers y RPC, más el sitio de un solo archivo HTML. Es un cambio grande:

| Parte | Qué pasa |
|---|---|
| Se reutiliza sin cambios | Inicio de sesión, encabezado, menú, tema, modales, tablas, gráficas, alta de usuarios con búsqueda en Authentication, bitácora, perfil, adjuntos, seguimiento, generación del archivo único e íconos |
| Se adapta | Panel, lista de pruebas, expediente (ahora por etapas), usuarios (puestos y autoridades) |
| Se construye nuevo | Catálogos maestros (recetas y versiones, materias primas, proveedores, lotes de materia prima, equipos y parámetros, métodos, controles, especificaciones, unidades, motivos, evidencias, objetivos, puestos), plantillas configurables por tipo, preparación, lote diario y batches, muestras, evaluación por plantilla, dictamen, cierre y autorizaciones |

**Situación actual de los datos:** no hay pruebas registradas. Las tablas transaccionales de la v1 (`pruebas`, `batches`, `insumos`, `resultados`, `envasadora`, `seguimiento`, `adjuntos`) están **vacías**. Solo existen 7 usuarios, 5 áreas, 4 tipos de prueba con sus responsables y 25 registros de bitácora. Por eso el cambio no pone en riesgo información.

## 2. Estados

```
Registrada → En preparación → Preparada → En ejecución → En evaluación → Pendiente de dictamen → Cerrada (aprobada | rechazada)
Alternativos: Pendiente de resultados · Requiere repetición · Cancelada
```

| Transición | Condición que valida el servidor |
|---|---|
| Registrada → En preparación | Al guardar el primer dato de preparación |
| En preparación → Preparada | Plan de evaluación confirmado. Responsable de ejecución asignado. Si aplica, batches y materiales previstos. **Autorización para ejecutar** por quien tenga esa autoridad para el tipo |
| Preparada → En ejecución | Al registrar el primer batch o dato de ejecución |
| En ejecución → En evaluación | Todos los batches o registros de ejecución con resultado operativo, y ninguno "pendiente" |
| En evaluación → Pendiente de dictamen | Todos los resultados **obligatorios** del plan capturados. Cada no conformidad con justificación |
| Dictamen *Aprobada* | Sin obligatorios pendientes ni incumplimientos sin resolver. Solo quien tenga **autoridad de dictamen** para el tipo |
| Dictamen *Rechazada* | Motivo del catálogo obligatorio, con descripción opcional |
| Dictamen *Requiere repetición* | Permite crear una **nueva ejecución vinculada** (la misma prueba con ejecución #2). Conserva el historial de la anterior |
| Dictamen *Pendiente de resultados* | Regresa a evaluación; no cierra |
| Cierre | Fecha y usuario de cierre. Consolida el expediente. La **autorización de implementación** es un registro aparte, opcional y de otra autoridad |

## 3. Cambios de esquema

### 3.1 Datos maestros (nuevos; con activo/inactivo; nunca se borran si tienen historial)
| Tabla | Contenido |
|---|---|
| `puestos_prubind` | Los 10 puestos de la organización. El usuario tiene un puesto |
| `autoridades_prubind` | **Matriz configurable**: tipo de prueba × etapa o acción × puesto (o usuario). Acciones: registrar, preparar, autorizar ejecución, ejecutar, capturar evaluación, dictaminar, cerrar, autorizar implementación |
| `tipos_prueba_prubind` (se amplía) | Los 10 tipos y su **plantilla**: campos de registro, secciones de preparación y formulario de ejecución (fabricación, empaque primario, empaque secundario, proceso, equipo, vida útil o genérico) |
| `objetivos_prubind` | Objetivos predefinidos por tipo |
| `productos_prubind`, `recetas_prubind`, `receta_versiones_prubind`, `receta_ingredientes_prubind` | Productos y recetas, versiones (vigente, histórica o propuesta) e ingredientes con cantidad estándar por batch y unidad |
| `materias_primas_prubind`, `proveedores_prubind` | Catálogos |
| `lotes_mp_prubind` | **Catálogo de trazabilidad**: lote de materia prima, proveedor, fecha de recepción y caducidad (lo alimenta Almacén) |
| `equipos_prubind`, `equipo_parametros_prubind` | Equipos y sus parámetros: unidad, rango de aceptación **opcional** y referencia a la especificación |
| `unidades_prubind` | Unidades de medida |
| `metodos_prubind` | Métodos y controles: categoría (fisicoquímica, sensorial, microbiología, bromatología, empaque primario o secundario, proceso, equipo, vida útil, proveedor), **tipo de resultado** (numérico, opción, conteo por diluciones o presencia/ausencia), unidad, diluciones, horas de lectura, técnica, base de expresión, procedimiento de referencia y opciones de resultado |
| `especificaciones_prubind` | Criterio de aceptación: método, ámbito (producto, receta, material o equipo), mínimo, máximo o texto, **referencia del documento aprobado**, versión y vigencia |
| `plantilla_evaluacion_prubind` | Por tipo: qué métodos o controles se proponen, si son obligatorios y el nivel de muestreo sugerido (batch, compuesta o lote diario) |
| `motivos_prubind` | Motivos de rechazo y de desviación |
| `tipos_evidencia_prubind` | Tipos de evidencia (reporte de laboratorio, fotografía, ficha técnica…) |

### 3.2 Registros transaccionales (se rediseñan; están vacíos)
| Tabla | Contenido |
|---|---|
| `pruebas_prubind` | Folio **PI-AAAA-NNN** (consecutivo por año, único), tipo, objeto involucrado según el tipo, objetivo, cambio a evaluar, área, prioridad (con justificación solo si es alta o urgente), quién registra, responsable inicial, estado y ejecución actual. Además, los datos de preparación: fecha planeada, batches planeados, peso objetivo, responsable de ejecución y plan de muestreo |
| `prueba_formulacion_prubind` | **Copia de la receta original** (versión y cantidades) y la formulación **propuesta** por separado (agregar, retirar, sustituir o modificar). La receta oficial no se toca |
| `prueba_materiales_prubind` | Materias primas y cantidades previstas, necesidad de compra y disponibilidad (Compras y Almacén). **Sustituye a `insumos_prubind`** |
| `prueba_parametros_prubind` | Equipos y parámetros de operación planeados |
| `plan_evaluacion_prubind` | **Copia** de la plantilla al preparar la prueba: método, obligatorio, nivel de muestreo y criterio vigente en ese momento. Así una prueba antigua conserva el criterio con el que se evaluó |
| `ejecuciones_prubind` | Ejecución #1, #2… (repeticiones vinculadas) |
| `lotes_diarios_prubind` | Lote diario de producción, ligado a la ejecución |
| `batches_prubind` | Cada batch pertenece a un lote diario. Fecha y hora, versión de receta, peso real en kg (sin valor fijo), temperatura de cocimiento en °C, consistencia en cm/s, responsable, incidencias y resultado operativo |
| `batch_lotes_mp_prubind` | Lotes de materia prima usados en cada batch |
| `ejecucion_controles_prubind` | Formulario de ejecución de pruebas que **no** son de fabricación (empaque, proceso, equipo): parámetro o control, valor y resultado |
| `muestras_prubind` | Muestra ligada a un batch, a una compuesta (varios batches) o al lote diario, con su fecha de muestreo |
| `resultados_prubind` | Plan, muestra, método, **dilución** (un renglón por dilución cuando aplica), valor numérico u opción, unidad, fechas de muestreo y lectura, responsable, estado (pendiente, conforme, no conforme o no aplica) y justificación de la desviación |
| `dictamenes_prubind` | Historial de dictámenes: tipo, motivo, descripción, quién y cuándo |
| `autorizaciones_prubind` | Autorización para ejecutar y autorización de implementación, cada una con quién y cuándo |
| `seguimiento_prubind`, `adjuntos_prubind`, `bitacora_prubind` | Se conservan. Los adjuntos se ligan opcionalmente a un resultado, batch o dictamen, con su tipo de evidencia |

### 3.3 Implicaciones
1. **Se eliminan y recrean** las tablas transaccionales vacías de la v1: `pruebas`, `batches`, `insumos`, `resultados`, `envasadora`, `seguimiento` y `adjuntos`, con sus vistas y funciones. No se pierde ningún dato. Requiere tu autorización explícita.
2. **Se conservan** `usuarios`, `areas`, `tipos_prueba` (se amplía), `bitacora`, los buckets de Storage y la función de crear cuentas.
3. **Administrador ≠ autoridad técnica.** Hoy un administrador puede hacer todo. En la v2, un administrador solo gestiona catálogos, usuarios y plantillas. Para dictaminar, autorizar o capturar evaluaciones se necesita estar en la matriz de autoridades.
4. Las funciones actuales (calidad, producción, compras, dirección) se sustituyen por **puesto + matriz de autoridades**.
5. Los 4 tipos actuales se reemplazan por los 10 nuevos.
6. Todo sigue en el sufijo `_prubind`; no se toca ninguna otra app.

## 4. Lo que el sistema NO inventa
Los catálogos se cargan solo con lo que está en el documento: los 10 tipos, los métodos y controles con sus diluciones y horas de lectura, y las unidades. **Quedan vacíos para que Calidad los capture:**
- Límites y criterios de aceptación (fisicoquímicos, microbiológicos, bromatológicos y de máquina) con su documento de referencia.
- Rangos de los parámetros de equipo.
- Protocolos de vida útil (tiempos de muestreo).

Si un resultado obligatorio no tiene criterio cargado, el evaluador marca conforme o no conforme de forma manual y debe citar la referencia. El sistema avisa que falta el criterio.

## 5. Datos que necesito de ustedes
1. **Las 3 recetas actuales:** nombre, producto, ingredientes, cantidad estándar por batch, unidad y versión vigente. Si no las tienen a la mano, se pueden capturar después desde el portal.
2. **Quién ocupa cada puesto** (Directora de Calidad, Director de Producción, Jefa de Calidad, etc.) y su correo.
3. **Matriz de autoridades:** quién autoriza la ejecución, quién dictamina y quién autoriza la implementación, por tipo de prueba.
4. Confirmar que "Notificado o impresión correcta" se refiere a **"Codificado o impresión correcta"**.
5. Si Almacén ya tiene un sistema de lotes de materia prima, o si los lotes se capturarán en este portal.
