# Pruebas industriales · Pet's Table S.A. de C.V.

**Calidad de producto**: sistema web para registrar y dar seguimiento a las pruebas industriales: producto nuevo, cambio de formulación, cambio de proveedor y cambio de material de empaque.

- **Frontend:** HTML + CSS + JavaScript (módulos ES), sin compilación. Librerías por CDN con versión fija: supabase-js 2.45.4, Lucide 0.453.0 y Chart.js 4.4.4.
- **Backend:** Supabase (PostgreSQL, Auth, RLS, Storage, funciones `security definer` y una Edge Function).
- **Hosting:** Vercel, con despliegue automático desde GitHub.
- **Zona horaria:** `America/Mexico_City`.
- **Aislamiento:** todos los objetos llevan el sufijo `_prubind` o el prefijo `prubind_`. No se modificó ningún objeto de otras apps de la instancia (`_med`, `_calbas`, `brom_*`, EPP).

> **Versión 2.0.0 (15/10/2026): flujo de seis etapas.** Registro → Preparación → Ejecución → Evaluación → Dictamen → Cierre, con autoridad por puesto × tipo × acción (*Usuarios y autoridades*), catálogos, recetas versionadas, folio `PI-AAAA-NNN`. Detalle del diseño, implicaciones y datos pendientes: [docs/propuesta-v2-flujo-seis-etapas.md](docs/propuesta-v2-flujo-seis-etapas.md). Migraciones `20261015000600` a `001100` (la `001100` carga las recetas Chicken Chase, Meat Festival y Tasty Piggy v1 vigentes, las especificaciones del film y los parámetros de la ULMA, tomados de la hoja "Recetas, empaque y equipo"). Prueba SQL: `tests/sql/pruebas_flujo_v2.sql` (36 verificaciones). **Las secciones 1 a 5 y 9 de abajo describen la v1 y están pendientes de actualizar.**

> **Simplificación (15/10/2026, migraciones `001200` y `001300`):**
> - **Tipos y responsables:** "Cambio en la receta" se unificó en "Cambio de formulación" (el tipo anterior queda inactivo). "Producto nuevo" sigue siendo independiente. Responsables por etapa: registra Compras, prepara el Gerente de Producción, ejecutan el Jefe y los inspectores de Calidad, evalúa el Jefe de Calidad, dictamina Dirección y cierra el Gerente de Procesos y Mejora Continua.
> - **Ejecución:** se captura en un solo formulario por batch (proceso, fisicoquímicos, microbiológicos y bromatológicos) o por corrida (empaque: sellado, vacío, lotificado y parámetros de la ULMA).
> - **Recetas:** se muestran sin etiquetas de versión.
> - **Pruebas:** `tests/sql/pruebas_flujo_v3.sql` (16 verificaciones con los puestos reales).

---

## 0. Publicación (2 archivos)

La carpeta **`entrega/`** contiene todo lo que hay que subir:

| Archivo | Contenido |
|---|---|
| `index.html` | El sitio completo: estilos, código, logotipo, ícono del login, favicon, manifiesto (se genera en el navegador), configuración pública de Supabase y una Content-Security-Policy con hashes |
| `apple-touch-icon.png` | Ícono de 180×180 para iPhone/iPad. iOS exige que sea un archivo aparte |

1. Crea un repositorio **privado** en GitHub y sube **los dos archivos a la raíz** (no dentro de una carpeta): *Add file → Upload files*.
2. En Vercel: *Add New → Project →* elige el repositorio *→ Deploy*. No necesita variables de entorno, comando de compilación ni configuración.
3. Abre `https://TU-DOMINIO/apple-touch-icon.png` para confirmar que el ícono responde.
4. En Supabase, en *Authentication → URL Configuration → Redirect URLs*, agrega `https://TU-DOMINIO/**` para que funcione "¿Olvidaste tu contraseña?".

**Para modificar el sitio:** edita las fuentes en `public/` y regenera con el comando de abajo. Luego sube el nuevo `entrega/index.html`; Vercel lo publica solo con cada cambio.

```bash
powershell -ExecutionPolicy Bypass -File tools\build-single.ps1
```

**Diferencias con la publicación completa (sección 6):**
- Sin `vercel.json` no se envían los encabezados de seguridad del servidor (HSTS, `X-Frame-Options`, etc.). La CSP sí aplica, porque va dentro del HTML.
- En Android, el manifiesto se genera en el navegador con los íconos de 180 y 192 px. Instalar desde Chrome funciona, pero Chrome puede tratar la app como un acceso directo en lugar de una app completa. En iPhone no cambia nada.

---

## 1. Requisitos

### 1.1 Definidos por el usuario (implementados)
| Requisito | Implementación |
|---|---|
| 4 tipos de prueba, cada uno con quien lo detona | Catálogo `tipos_prueba_prubind` y responsables en `tipo_responsables_prubind`. Producto nuevo y Formulación: Camila. Proveedor: Laura. Empaque: Rafa. |
| Solo el responsable del tipo (o un administrador) registra pruebas de ese tipo | Decisión del usuario. Se valida con la política RLS y el trigger. Los responsables se editan en *Usuarios y catálogos → Tipos de prueba*. |
| Cada prueba indica cuántos batches, qué días, qué se ocupa, descripción y qué se busca | Campos `num_batches`, fechas planeadas, `objetivo` y `descripcion`. Los batches se generan solos y cada uno tiene su fecha programada. |
| Calidad (Abigail) registra análisis fisicoquímicos, microbiológicos y parámetros de proceso por batch | `resultados_prubind`. Captura libre (decisión del usuario): parámetro, valor, unidad, especificación como texto libre y resultado (cumple / no cumple / informativo). |
| Insumos: los solicita Producción o el responsable; Juan valida las cantidades por batch; Compras los adquiere | `insumos_prubind`. Flujo *solicitado → validado (Producción) → en compra → recibido (Compras)*. Se puede cancelar con motivo. |
| Empaque: qué material, qué día, parámetros de la envasadora y cuántos batches | Material actual y nuevo, fechas, número de batches y pestaña **Envasadora** de captura libre (máquina, parámetro, valor, unidad, batch). |
| Todo es un seguimiento | Pestaña **Seguimiento**: notas del equipo y eventos automáticos (cambios de estado, insumos, batches). |
| Dictamen | Decisión del usuario: Calidad emite el dictamen técnico (conforme / no conforme) y Dirección o un administrador emite el final (aprobada / rechazada). |
| Alta de usuarios desde el portal con búsqueda en Authentication (como Servicio Médico) | *Usuarios → Nuevo usuario*: busca la cuenta y llena nombre, correo y foto. Si el correo no tiene cuenta, la Edge Function la crea con contraseña temporal. |

### 1.2 Supuestos documentados (ajustables)
| Supuesto | Valor | Dónde cambiarlo |
|---|---|---|
| Estados de la prueba | borrador → planeada → en ejecución → en evaluación → aprobada / rechazada. Cancelada desde cualquier estado abierto | Trigger y `prubind_cambiar_estado` |
| Para planear se requiere la fecha de inicio | Sí | `prubind_cambiar_estado` |
| Para enviar a evaluación, todos los batches deben estar producidos o cancelados, y al menos uno producido | Sí | `prubind_cambiar_estado` |
| Iniciar la ejecución con insumos sin recibir | **Se permite**, con una advertencia en pantalla (no se dio esa regla) | Interfaz |
| Funciones operativas por persona | Abigail: Calidad. Juan: Producción. Laura: Compras. Camila: Dirección. Editables por un administrador | *Usuarios y catálogos* |
| Los administradores (Javier, Nelisa, Camila) pueden ejercer todas las funciones | Sí | `prubind_tiene_funcion` |
| Todos los usuarios activos **consultan** todas las pruebas | Sí (trabajo colaborativo) | Políticas `*_sel` |
| Las pruebas solo se eliminan en borrador; las demás se cancelan con motivo | Sí | Trigger `prubind_validar_prueba` |
| Una prueba cerrada (aprobada, rechazada o cancelada) ya no se modifica | Sí | Triggers |
| Un administrador puede **reabrir** una prueba en evaluación, con motivo; se retira el dictamen de Calidad | Sí | `prubind_cambiar_estado('reabrir')` |
| Se registran resultados con la prueba en ejecución o en evaluación, en batches no cancelados | Sí | `prubind_validar_resultado` |
| La envasadora solo aplica a tipos con "Parámetros de envasadora" (empaque) | Sí, configurable por tipo | *Tipos de prueba → Editar* |
| Adjuntos | PDF, imágenes, Excel, Word, CSV o texto, máx. 10 MB, en el bucket privado `adjuntos_prubind` | Migración 2 |
| Área de Rafa | "Material de empaque" | *Usuarios → Editar* |
| Nombres de Camila y Rafa | "Camila" y "Rafa": no se proporcionaron los apellidos | *Usuarios → Editar* |

### 1.3 Pendientes de aclarar (no se inventaron)
- **Laura Vásquez no tiene cuenta en Supabase Auth.** Está registrada en la app y aparece como "Sin cuenta de acceso". Créala con el botón de llave en *Usuarios*, o confirma si su correo es otro.
- **Límites de aceptación:** la captura es libre, como se decidió. Si después se quieren especificaciones por parámetro con evaluación automática, se agrega un catálogo.
- **Notificaciones** (push o correo) cuando alguien tiene un pendiente: no se solicitaron. Por ahora el **Panel → Mis pendientes** muestra a cada persona lo que le toca.
- Si se necesita **exportar** a Excel o PDF, o un reporte imprimible de la prueba.

---

## 2. Roles y permisos

| Acción | Admin | Responsable de la prueba | Producción | Calidad | Compras | Dirección | Otro usuario |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| Consultar pruebas, panel, programa e insumos | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| Registrar prueba (solo tipos asignados) | ✔ todos | ✔ | | | | | |
| Editar datos (borrador / planeada) · planear · cancelar · eliminar borrador | ✔ | ✔ | | | | | |
| Solicitar insumos | ✔ | ✔ | ✔ | | | | |
| Validar cantidades de insumos | ✔ | | ✔ | | | | |
| Registrar compra y recepción de insumos | ✔ | | | | ✔ | | |
| Iniciar ejecución · registrar producción de batches · envasadora | ✔ | ✔ | ✔ | | | | |
| Enviar a evaluación | ✔ | ✔ | ✔ | ✔ | | | |
| Resultados de calidad · dictamen técnico | ✔ | | | ✔ | | | |
| Dictamen final (aprobada / rechazada) | ✔ | | | | | ✔ | |
| Reabrir prueba en evaluación | ✔ | | | | | | |
| Notas de seguimiento y adjuntos | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| Usuarios, tipos de prueba, áreas y bitácora | ✔ | | | | | | |

Todas las reglas se aplican **en la base de datos** (RLS, triggers y RPC). Ocultar botones en la interfaz es solo una ayuda visual.

---

## 3. Módulos

| Módulo | Contenido |
|---|---|
| **Panel** | Indicadores (activas, en ejecución, en evaluación, aprobadas), alertas (batches atrasados o próximos, insumos pendientes), **Mis pendientes** según la función de cada quien, 4 gráficas, próximos batches, actividad reciente y accesos rápidos |
| **Pruebas** | Lista con búsqueda (folio, título o producto) y filtros por tipo, estado y "mías". **Expediente** con avance por estados, siguiente paso, acciones según el rol y pestañas: Resumen, Batches, Insumos, Calidad, Envasadora, Seguimiento y Adjuntos |
| **Programa de batches** | Todos los batches: programados, atrasados, próximos 7 días o producidos sin resultados. Producción registra aquí su avance |
| **Insumos** | Bandeja de solicitudes de todas las pruebas. Abre en "Por validar" para Producción y en "Por comprar" para Compras |
| **Usuarios y catálogos** | Usuarios (rol, funciones, foto, cuenta de acceso), tipos de prueba con sus responsables, y áreas |
| **Bitácora** | Auditoría automática de altas, cambios y bajas |
| **Mi perfil** | Datos, funciones, cambio de contraseña, tema claro u oscuro e instrucciones de instalación |

**Folios:** prefijo del tipo + consecutivo global (`PN-0001`, `CF-0002`, `CP-0003`, `ME-0004`).

---

## 4. Modelo de datos (sufijo `_prubind`)

| Tabla | Propósito | Reglas principales |
|---|---|---|
| `areas_prubind` | Catálogo de áreas | Nombre único |
| `usuarios_prubind` | Usuarios autorizados: rol `admin`/`usuario` y `funciones[]` (`calidad`, `produccion`, `compras`, `direccion`) | Correo `@petstable.mx` único. Siempre al menos un admin activo. Nadie cambia su propio rol ni estado |
| `tipos_prueba_prubind` | Tipos de prueba y qué secciones usan | Prefijo único |
| `tipo_responsables_prubind` | Quién detona cada tipo | PK (tipo, usuario) |
| `pruebas_prubind` | Prueba, sus estados y sus dictámenes | El estado y los dictámenes solo cambian por RPC. Cancelar requiere motivo. Cerrada = inmutable |
| `batches_prubind` | Batches generados desde `num_batches` | Sin alta manual. Producido requiere fecha real (no futura). Cancelado requiere motivo |
| `insumos_prubind` | Solicitud → validación → compra → recepción | Cada etapa solo la ejecuta su función. Los autores y fechas los asigna el servidor |
| `resultados_prubind` | Resultados de calidad por batch | Solo Calidad o admin. Fecha no futura |
| `envasadora_prubind` | Parámetros de la máquina | Solo tipos con envasadora |
| `seguimiento_prubind` | Notas y eventos | Solo inserción (no se editan ni se borran) |
| `adjuntos_prubind` | Metadatos de archivos | Archivos en el bucket privado `adjuntos_prubind`, con URL firmada |
| `bitacora_prubind` | Auditoría | Escritura solo por triggers |

**Vistas** (`security_invoker`): `v_pruebas_prubind`, `v_batches_prubind`, `v_insumos_prubind`, `v_seguimiento_prubind`.

**RPC:** `prubind_mi_perfil`, `prubind_cambiar_estado`, `prubind_dictamen_calidad`, `prubind_dictamen_final`, `prubind_dashboard`, `prubind_estado_cuentas`, `prubind_correo_tiene_cuenta`, `prubind_buscar_cuentas`.

**Storage:** `avatares_prubind` (fotos, lectura pública, escritura de admins) y `adjuntos_prubind` (privado). El bucket `avatares` de otras apps solo se **lee**.

**Criterios del tablero:** los indicadores de "hoy" usan el estado actual de todas las pruebas. Las gráficas usan las pruebas **registradas** en el periodo. Las aprobadas o rechazadas se cuentan por la fecha del dictamen final, y los resultados por su fecha de análisis.

---

## 5. Estructura

```
├── public/                       ← raíz publicada por Vercel
│   ├── index.html
│   ├── manifest.webmanifest
│   ├── apple-touch-icon.png      (180×180, ícono oficial)
│   ├── favicon.ico               (16/32/48)
│   ├── icons/  icon-192.png · icon-512.png · icon-maskable-512.png · favicon-32.png
│   ├── img/    logo-petstable.webp (oficial, sin modificar) · app-icon-128.png
│   ├── css/    app.css (base compartida con Servicio Médico) · prubind.css
│   └── js/     config.js · theme-init.js · core.js · app.js
│               modules/ dashboard · pruebas · acciones · programa · insumos · usuarios · bitacora · perfil
├── supabase/migrations/          ← 5 migraciones (ya aplicadas en domumnsezocubigfqwry)
├── supabase/functions/gestionar_usuarios_prubind/   (desplegada)
├── tests/sql/pruebas_reglas_negocio.sql
├── fuentes/                      ← ícono y logotipo originales
├── scripts/generate-config.mjs   ← genera config.js con variables de entorno en Vercel
├── entrega/  index.html · apple-touch-icon.png   ← los 2 archivos a publicar (generados)
├── tools/  build-single.ps1 · make-icons.ps1 · serve.ps1
└── vercel.json · package.json · .env.example · .gitignore
```

---

## 6. Despliegue: GitHub + Vercel

### 6.1 Subir a GitHub
Este equipo no tiene `git` instalado.
- **Web:** crea un repositorio **privado** → *Add file → Upload files* → arrastra el **contenido** de esta carpeta (las carpetas conservan su estructura).
- **Con Git** (si lo instalas), desde esta carpeta:

```bash
git init -b main
```
```bash
git add . && git commit -m "Pruebas industriales v1.0.0"
```
```bash
git remote add origin https://github.com/ORG/pruebas-industriales.git && git push -u origin main
```

### 6.2 Conectar Vercel
1. *Vercel → Add New → Project →* importa el repositorio.
2. **Framework Preset:** *Other*. `vercel.json` ya define `buildCommand` (`node scripts/generate-config.mjs`) y `outputDirectory` (`public`).
3. **Environment Variables** (opcional; si no existen se usa `public/js/config.js`):
   - `SUPABASE_URL` = `https://domumnsezocubigfqwry.supabase.co`
   - `SUPABASE_ANON_KEY` = la llave **publishable** (`sb_publishable_…`). El script **rechaza** las llaves `service_role` y `sb_secret_`.
4. *Deploy.* Cada `push` a `main` despliega a producción.

### 6.3 Comprobar que el despliegue terminó bien
1. *Vercel → Deployments:* el último debe estar en **Ready** y ligado al commit correcto. En *Build Logs* debe aparecer `[config] …`.
2. Abre estas URLs y confirma que responden `200` con el tipo correcto:
   - `/apple-touch-icon.png` → `image/png`
   - `/manifest.webmanifest` → `application/manifest+json`
   - `/icons/icon-192.png`, `/icons/icon-512.png`, `/icons/icon-maskable-512.png`, `/favicon.ico`
3. Chrome de escritorio: *DevTools → Application → Manifest*, sin errores y con los 3 íconos.
4. *DevTools → Console* sin errores. Si aparece "Refused to connect", revisa la CSP en `vercel.json`.

### 6.4 Revertir a una versión estable
- **Inmediato:** *Vercel → Deployments →* elige el último estable → **⋯ → Promote to Production** (Instant Rollback).
- **Definitivo:** revierte el commit en GitHub y haz `push`.
- **Base de datos:** las migraciones son aditivas. Para revertir se necesita una migración nueva y explícita. **Nunca** ejecutes `drop` sobre objetos sin el sufijo `_prubind`.

### 6.5 Configuración de Auth recomendada (panel de Supabase)
1. **Authentication → URL Configuration → Redirect URLs:** agrega `https://TU-DOMINIO.vercel.app/**` para que funcione "¿Olvidaste tu contraseña?".
2. **Authentication → Providers → Email → Leaked password protection:** actívala (aviso del asesor de seguridad, a nivel de toda la instancia).

---

## 7. Instalación en la pantalla de inicio

- **iPhone / iPad (Safari):** *Compartir → Agregar a pantalla de inicio*. Nombre: "Pruebas industriales". Ícono: `apple-touch-icon.png` (180×180).
- **Android (Chrome):** *menú ⋮ → Instalar aplicación*. Usa el manifiesto (192, 512 y *maskable*).

**Si iOS conserva un ícono anterior:** borra el acceso directo, cierra Safari por completo, ve a *Ajustes → Safari → Avanzado → Datos de sitios web* y elimina el dominio. Después vuelve a abrir el sitio y agrégalo de nuevo. Si en el futuro cambias el ícono, sube el número `?v=1` de los `<link>` en `index.html`.

**Nota sobre los íconos:** el ícono oficial mide **180×180 px**. `apple-touch-icon.png` sale de él, aplanado sobre el naranja de su borde, porque iOS rellena de negro las esquinas transparentes. Las versiones de 192 y 512 px se **ampliaron** desde ese original, así que en Android pueden verse algo suaves. Para máxima nitidez, entrega el original en 1024×1024 y ejecuta:

```bash
powershell -ExecutionPolicy Bypass -File tools\make-icons.ps1 -Src fuentes\icono-1024.png -Logo fuentes\logo-oficial.webp -Out public
```

No hay *service worker* ni modo sin conexión, porque no se solicitaron. La app necesita conexión.

---

## 8. Pruebas locales

```bash
powershell -ExecutionPolicy Bypass -File tools\serve.ps1 -Port 5174
```
Abre `http://localhost:5174`. Usa la base de datos **real**: lo que registres queda guardado.

Para validar las reglas del servidor, ejecuta `tests/sql/pruebas_reglas_negocio.sql` en el *SQL Editor* de Supabase. Revierte todos sus cambios y muestra el resultado como mensaje de error (es intencional). Postgres no regresa los consecutivos, así que cada ejecución consume números de folio. Si la tabla `pruebas_prubind` sigue vacía, puedes reiniciarlos con `alter table public.pruebas_prubind alter column folio restart with 1;`.

---

## 9. Registro de pruebas (14/10/2026)

### Ejecutadas ✔
**Base de datos** (sesiones simuladas de cada usuario con el rol `authenticated`, más una cuenta sin acceso y el rol anónimo; todo revertido). **27 de 27** verificaciones correctas:
- Al registrar una prueba se generan sus batches y se fuerza "borrador". Laura no puede registrar "producto nuevo", pero sí "cambio de proveedor".
- El estado no cambia por edición directa, solo por RPC. Abigail no puede editar una prueba ajena.
- Insumos: Compras no valida, Producción sí. La recepción exige cantidad y fecha. La validación queda congelada y los autores los asigna el servidor.
- No se inicia desde borrador. "Producido" exige fecha real. No se pasa a evaluación con batches programados. Calidad no modifica batches.
- Resultados: Producción no los captura. `prueba_id` lo fuerza el servidor. Un batch con resultados no se revierte.
- El dictamen final exige antes el dictamen de Calidad. Calidad no emite el dictamen final. El rechazo exige motivo. Una prueba aprobada ya no se edita.
- Seguimiento automático (12 eventos en el flujo). El tablero responde. Cancelar exige motivo. La envasadora solo aplica a su tipo. Una prueba no borrador no se elimina.
- Una cuenta sin acceso no ve pruebas, y el rol anónimo no tiene acceso.

**Pruebas adicionales en base de datos:**
- Flujo completo con 4 pruebas realistas (insumos, batches, resultados, envasadora, dictamen), revertido.
- Al eliminar un borrador con insumo validado se borra todo en cascada, pero un insumo validado no se puede borrar suelto.

**Asesores de Supabase:** sin hallazgos de seguridad para `_prubind`, salvo el aviso esperado de funciones `security definer` ejecutables por usuarios autenticados (validan el rol internamente). En rendimiento solo aparecen "índices sin uso", porque las tablas están vacías.

**Navegador** (panel integrado de Claude, Chromium):
- **Servidor local real (`tools/serve.ps1`):**
  - Carga sin errores de consola.
  - `apple-touch-icon.png` es PNG 180×180. Los íconos 192, 512 y maskable son PNG, `favicon.ico` responde y el manifiesto es válido.
  - Los metadatos de `<head>` son correctos.
  - Con la llave pública, el rol anónimo recibe `permission denied` en tablas y RPC.
- **Arnés local con respuestas simuladas** (fuera del proyecto; no hubo inicio de sesión real), con sesiones de Javier (admin), Juan (Producción), Laura (Compras) y Abigail (Calidad):
  - El panel muestra indicadores, 4 gráficas, "Mis pendientes" según la función, próximos batches y actividad.
  - Lista de pruebas y expediente con sus 7 pestañas. Los botones de acción corresponden a cada rol.
  - Formularios: nueva prueba (solo tipos permitidos, secciones según el tipo, validación de fechas), resultado de calidad (validación y "capturar otro"), producción de batch, envasadora, validación y compra de insumos, dictamen de Calidad y dictamen final (motivo obligatorio al rechazar), y alta de usuario con búsqueda de cuenta existente y su foto.
  - Programa de batches (vistas atrasados y sin resultados), bandeja de insumos, bitácora y perfil.
  - Modo claro y oscuro. A **375 px** no hay desbordamiento horizontal: tablas como tarjetas y acciones apiladas.
  - Inicio de sesión: rechaza correos fuera de `@petstable.mx` y muestra "Correo o contraseña incorrectos". Cierre de sesión correcto.
- **Recursos:** comprobados por HTTP local, **no** por HTTPS.

### Pendientes ⏳ (requieren despliegue o credenciales reales)
- Inicio de sesión real con cada usuario. No se ingresaron contraseñas reales.
- Flujo completo desde la interfaz contra la base real: crear, planear, ejecutar, evaluar y dictaminar.
- Subida y apertura real de adjuntos (Storage), y creación de cuenta con la Edge Function (desplegada, pero no invocada con un usuario real).
- Restablecimiento de contraseña por correo (requiere configurar Redirect URLs).
- Recursos por **HTTPS** en Vercel y encabezados CSP en producción.
- **iPhone real con Safari** y "Agregar a pantalla de inicio" (no se ha probado en un dispositivo iOS).
- Android real (instalación y apariencia del ícono *maskable*), tableta física y tablas con muchos registros reales.

## v4 · Flujo por áreas (20/10/2026)

Según la narración del usuario: **Registro → Registro en proceso → Evaluaciones complementarias → Resultados → Recomendaciones → Dictamen → Cierre**.

- **Registro**: cualquier persona registra la prueba (fecha de ejecución, nombre, objetivo obligatorio, tipo, batches y cantidad a evaluar) y marca los **parámetros a evaluar por área**. Calidad y Producción siempre; Seguridad y Mantenimiento cuando la prueba los involucra. Se pueden agregar parámetros nuevos (cuantitativos con unidad o cualitativos conforme/no conforme), que quedan en el catálogo y en la plantilla del tipo. Ya no hay etapa de preparación ni autorización de ejecución.
- **Registro en proceso**: Calidad → Inspectores; Producción → Supervisores; Seguridad → Supervisor de Seguridad, Salud y Ambiente (puesto nuevo); Mantenimiento → Jefe de Mantenimiento. Cada área edita solo lo suyo (autoridades `capturar_<área>`).
- **Evaluaciones complementarias** (sensorial, microbiología, bromatología): solo nuevo producto, cambio en la formulación y cambio de proveedor.
- **Resultados**: tabla Parámetro / Resultado / Criterio / Cumple–No cumple / Observaciones (`evaluaciones_prubind`). "Cumple" queda "Sin observaciones"; "No cumple" exige explicación. Evalúa el jefe de cada área (`evaluar_<área>`). Si cambia un valor, su evaluación se vuelve a hacer.
- **Recomendaciones** por área (`recomendaciones_prubind`); con todas registradas pasa sola al dictamen de Alta Dirección. Aprobar con parámetros que no cumplen exige conclusión.
- Tipos activos: Nuevo producto, Cambio en la formulación, Cambio de proveedor, Material de empaque y Cambio en el proceso (los demás se desactivaron, no se borraron).
- Migraciones `20261020001400` y `20261020001500`; prueba de flujo `tests/sql/pruebas_flujo_v4.sql` (23/23).

## v4.1 · Ajustes del registro y publicación en GitHub (20/10/2026)

- **Publicación:** repo `https://github.com/jmartinezacs/pruebasindustriales-petstable` (rama `main`). En la raíz quedan los archivos que publica Vercel: `index.html` (generado), `apple-touch-icon.png` y `version.json`. La app consulta `version.json` cada 10 minutos y muestra **"Hay una nueva versión disponible · Actualizar"** cuando difiere de `APP_VERSION`.
- **Flujo de publicación:** editar `public/` → subir `APP_VERSION` en `public/js/config.js` → `powershell -ExecutionPolicy Bypass -File tools\build-single.ps1` → commit y push a `main`.
- **Registro:** sin "Cantidad a evaluar", sin "Más datos" (área que coordina y responsable de seguimiento ya no se piden); "Número de batches para la prueba"; prioridad con tarjetas Normal / Alta / Urgente y motivo obligatorio para Alta o Urgente. Nuevo producto ya no pide receta base.
- **Parámetros por área:** cada responsable define los de su área (autoridad `evaluar_<área>`): Jefe de Calidad → Calidad, Gerente de Producción → Producción, Supervisor de SSA → Seguridad, Jefe de Mantenimiento → Mantenimiento. Quien registra solo marca los de su propia área (si tiene una) e indica si la prueba involucra Seguridad o Mantenimiento (`pruebas_prubind.areas_involucradas`). RPC `prubind_definir_parametros` y `prubind_areas_involucradas`; pendiente nuevo "Definir parámetros de su área".
- **Seguridad y Mantenimiento no detienen la prueba:** para pasar a dictamen y aprobar solo se exigen las evaluaciones y recomendaciones de Calidad y Producción; lo que falte de las áreas opcionales queda señalado en el dictamen.
- **Alta rápida** de receta, materia prima y proveedor desde los menús del registro (`prubind_alta_rapida`).
- **Salmonella 25 g (PCR)** y **E. coli O157 (PCR)**: ausencia / presencia.
- Migración `20261020001600_prubind_v41_areas_y_catalogos.sql`.

## v4.2 · Registro flexible y panel (20/10/2026)

- **Registro:** objetivo desde el catálogo de objetivos (con «Otro (describir)»); sin número de batches; sin campo de equipo; ejemplo de empaque «Film Chicken Chase formato 4x2»; encabezados numerados y prioridad en control segmentado.
- **Seguridad y Mantenimiento participan siempre**, con parámetros propios (EPP, riesgos, condiciones seguras, incidentes, LOTO, señalización, ergonomía, orden y limpieza, residuos; funcionamiento del equipo, paros no programados, ruidos/vibraciones, tiempo de ajuste, desgaste, fugas). Para avanzar a dictamen siguen bastando Calidad y Producción.
- **ULMA** (termoformado 95–100 °C, termosellado 135–145 °C, avance ref. 299.8 mm) pasa a parámetros de Mantenimiento en «Material de empaque».
- **Registro durante el proceso flexible:** cada parámetro se registra para *toda la prueba* o *por batch/corrida*; los batches se agregan conforme se producen (el lote del día se asigna solo). Terminar exige al menos un dato, no un batch.
- **Vistas retiradas del menú:** «Batches ejecutados»; en Catálogos: Lotes de materia prima, Equipos y maquinaria, Parámetros de operación (los datos se conservan).
- **Panel:** indicadores sin «(hoy)» y con colores nuevos; gráficas con etiquetas de datos (situación, etapas, tipos, Cumple/No cumple por área). Título de la pestaña fijo: «Pruebas industriales».
- Migración `20261020001700_prubind_v42_areas_fijas_y_registro_flexible.sql`.

## v5.0 · Inicio de la prueba, áreas independientes y notificaciones (20/10/2026)

Migración `20261020001800_prubind_v5_inicio_areas_avisos.sql`; prueba SQL `tests/sql/pruebas_flujo_v5.sql` (15 verificaciones).

- **Iniciar prueba:** quien registra la prueba la inicia con un botón; antes de iniciar no se registran datos. Puede iniciarla aunque alguna área no haya definido sus parámetros (se pueden agregar durante la prueba). Estado "En proceso" (antes "Registro en proceso"). Quien la registró también la termina.
- **Nada que evaluar por mi área:** cada responsable puede indicarlo en Registro → Parámetros a evaluar (tabla `areas_sin_parametros_prubind`, RPC `prubind_area_sin_parametros`); puede retomarla mientras la prueba no termine.
- **Áreas independientes:** participa el área que registra algún dato. Cada una evalúa (✓ Cumple, ✗ No cumple, ? No se pudo determinar) y da su veredicto (Satisfactoria / No satisfactoria) con su recomendación, incluso con la prueba en proceso. El dictamen espera solo a las áreas que participaron; si al terminar ya todas dieron su veredicto, pasa sola a dictamen.
- **Laboratorio pendiente:** los parámetros sin resultado (p. ej. bromatológicos) no detienen la evaluación ni el veredicto; se pueden marcar "No se pudo determinar" con explicación.
- **Notificaciones push** (mismo diseño que Servicio Médico: foto de quien genera el aviso con la insignia de la app): Edge Function `notificar_prubind`, `public/sw.js`, tablas `push_subs_prubind` y `avisos_prubind`, claves VAPID en `prubind_private.config_push`. Eventos: prueba registrada, prueba iniciada (áreas con autoridad de registrar o evaluar), lista para dictamen (Alta Dirección) y dictamen emitido (quien registró y las áreas). Se activan en Mi perfil o en el aviso del Panel; en iPhone requiere la app instalada.
- **Publicación:** además de `index.html`, la raíz publica `sw.js`, `manifest.webmanifest`, `icon-512.png`, `notif-icon.png` y `notif-badge.png`.
- **Panel:** "Requieren tu intervención" en tarjetas por prueba con lo que te toca (filtrables), gráficas con un color por barra o porción y etiquetas de datos, y actividad reciente como línea de tiempo por día.

## v5.1 · Administrador, dictamen y aprobación, objetivos por tipo (20/10/2026)

Migración `20261020001900_prubind_v51_admin_dictamen_objetivos.sql`.

- **Administrador:** puede hacer todo lo que hacen los responsables de Autoridades (definir, registrar, evaluar y dar veredicto por cualquier área, dictaminar y cerrar). Los avisos push siguen llegando solo a los responsables asignados.
- **Dictamen y aprobación en un solo paso:** el dictamen "Aprobada" de Alta Dirección autoriza implementar el cambio; después la Gerencia de Procesos y Mejora Continua cierra. La autorización de implementación separada se desactivó (los registros anteriores se conservan).
- **Objetivos por tipo de prueba** (más "Cumplir un requisito de cliente o regulatorio" y "Otro"); los objetivos generales anteriores quedan inactivos.
- Sin formulación en el Registro; prioridad solo "Normal / Alta / Urgente" (Normal en azul); "Cancelada" en rojo.
- Gráficas: encabezados y totales centrados, meses sin abreviar y etapas Registradas, En proceso, En evaluación, Pendientes de dictamen y Por cerrar.

## v5.2 · Ícono nuevo, campana de pendientes y más avisos (20/10/2026)

Migración `20261020002000_prubind_v52_avisos_pendientes.sql`; Edge Functions `notificar_prubind` (v2) y `recordatorios_prubind`.

- **Ícono verde** (fuente: `fuentes/icono-verde.png`) en favicon, pantalla de inicio de iPhone y Android, manifiesto, inicio de sesión y avisos. Ícono de 512 px para que no se vea borroso al abrir la app instalada.
- **Campana de pendientes** en el encabezado: número de acciones que te tocan y acceso directo a cada una; si el dispositivo no tiene avisos activos, permite activarlos ahí. El número también aparece en el ícono de la app instalada cuando el sistema lo admite.
- **Avisos:** nuevo aviso "prueba terminada" a quienes evalúan en las áreas que participaron, y recordatorio diario (lunes a sábado, 08:00) a cada persona con pendientes (pg_cron → `recordatorios_prubind`, protegido con secreto en `prubind_private.cron`).
- **Registro de la prueba:** ficha compacta (nombre, objetivo y datos en mosaicos) y tarjeta de quien la registró con foto, puesto, fecha y hora.

- **v5.2.1:** el ícono es la imagen original completa (esquinas redondeadas, sin recortes ni bordes) en iPhone, Android, computadora y avisos; la campana de pendientes pasó a ser un botón flotante junto a "Nueva prueba" e "Inicio".
- **v5.2.2:** campana dorada en vector como botón flotante; nombre corto "Pruebas" al instalar (Android/iPhone) y en el encabezado del celular; identidad nueva de la app (`id: /pruebas`) para que la instalación en computadora tome el ícono verde; cerrar sesión ya no da de baja las notificaciones del dispositivo (migración `20261021002100_prubind_v522_vincular_push.sql`).

## v5.3 · Pendientes "hechos", vista por área y número de batch (21/10/2026)

Migración `20261021002200_prubind_v53_pendientes_hechos.sql`.

- **Marcar como hecho** en la campana: quita el pendiente solo de la lista de esa persona (p. ej. si otro inspector ya registró los datos); se puede volver a mostrar. También se refleja en el panel y en el recordatorio diario.
- **Vista por área:** al registrar durante el proceso solo aparecen los parámetros de las áreas de la persona; en Resultados, Recomendaciones y Evaluaciones complementarias las demás áreas aparecen contraídas (se abren al tocarlas). Participación por área la ven todos; el administrador ve todo.
- **Número de batch** escrito por quien registra (p. ej. 29, 30, 31), sin repetir dentro de la prueba.
- KPI "Pruebas cerradas" en lugar de "Urgentes abiertas"; filtro "Cerradas" en Pruebas.
- Borde de la gráfica de pastel blanco al cambiar a modo claro; título completo "Pruebas industriales" en el celular (el botón Salir queda en el menú); subtítulo "Calidad de proceso".
- Íconos de 48, 96, 144 y 256 px en el manifiesto (acceso directo de Windows).
- **v5.3.1:** la campana flotante es solo la campana dorada con el número de pendientes (sin fondo). Se borró la prueba de prueba PI-2026-001 (folio reiniciado).

## v5.4 · Usuarios en consulta y barra turquesa (21/10/2026)

- Todos los usuarios pueden ver Usuarios y Autoridades (solo consulta); solo los administradores modifican (también lo impone RLS).
- Barra de la app instalada (theme_color) en turquesa #1BC7C7.
- Catálogo "Materias primas" (antes "Materias primas y materiales").
- Panel: texto de bienvenida que explica para qué es el sitio.

## v5.5 · Pantalla completa y textos breves (21/10/2026)

- App instalada: `display: fullscreen` con `display_override` [window-controls-overlay, fullscreen, standalone]. Android abre en pantalla completa; en computadora la barra de título se oculta (solo quedan los botones de ventana sobre el encabezado, que sirve para mover la ventana). iOS no permite ocultar la barra de estado.
- Barra de color de nuevo en naranja (#F58020).
- Textos de la app más breves (saludo, pasos siguientes, avisos y ayudas).

## v5.6 · Permisos por puesto, pendientes, evidencia y expediente (21/10/2026)
- **Permisos:** los parámetros a evaluar los define solo el responsable de cada área (Gerente de Producción, Jefe de Calidad, Jefe de Mantenimiento, Supervisor de SSA), que también es el único que crea parámetros nuevos. Durante la prueba registran: Calidad → inspectores o Jefe; Producción → supervisores o Gerente; Seguridad → Supervisor o Ingeniero de Seguridad; Mantenimiento → Jefe o técnicos (puesto nuevo "Técnico de Mantenimiento"). Se corrigió que el Ingeniero de Seguridad tenía permisos de Calidad.
- **Sin "Evaluaciones complementarias":** bromatológicos, microbiología y sensorial se registran en *En proceso*, en "Toda la prueba".
- **Pendiente:** cada valor puede marcarse "Pendiente"; el responsable lo completa al evaluar o lo marca "No se pudo determinar", y quien dictamina puede completarlo y evaluarlo en la pestaña del dictamen.
- **Evaluar durante el proceso:** los responsables ven "Evaluar" en sus pendientes desde que hay datos, sin esperar a que termine la prueba.
- **Terminar:** botón destacado para quien registró; la fecha de ejecución puede ser un día o un rango, y la prueba se termina sola al acabar el último día (pg_cron `prubind_autoterminar`, 00:05 hora de México).
- **Evidencia:** se adjunta en cada parámetro al registrar y en el dictamen (ya no hay pestaña Evidencia aparte).
- **Seguimiento** con la foto de cada persona; **expediente** con logo, solo las secciones con datos y firmas de quien dictaminó y quien cerró.
- **Agregar parámetro:** formulario directo (nombre, cuantitativo o cualitativo y unidad); si el nombre ya existe en el catálogo se usa ese. Catálogo depurado (5 parámetros vagos o duplicados desactivados).
- Migraciones `20261021002300_prubind_v56_roles_pendientes_evidencias.sql` y `20261021002400_prubind_v56_muestras_dictamen.sql`; pruebas `tests/sql/pruebas_flujo_v56.sql` (13/13).

## v5.7 · Registro de datos unificado y Evaluación al terminar (22/10/2026)
- **Un solo formulario "Registrar datos"** en *En proceso*: cada parámetro se registra para toda la prueba (un valor) o, al elegir **Por batch**, con un renglón por batch (número y valor) y "Agregar batch". Los batches se crean solos con su número y se comparten entre parámetros; los que quedan sin datos se quitan.
- La etapa **Resultados** se llama **Evaluación**, y la evaluación y el veredicto de las áreas solo se registran con la prueba **terminada** (servidor y pendientes).
- Migración `20261022002500_prubind_v57_evaluar_al_terminar.sql`; pruebas `tests/sql/pruebas_flujo_v57.sql` (6/6).

## v5.8 · Responsable, catálogo de parámetros simplificado y colores (22/10/2026)
- **Responsable de la prueba:** se asigna en el registro (por omisión, quien registra) y es el único que la **inicia** y la **termina** (o un administrador).
- **Catálogos retirados de la app:** especificaciones y criterios, plantillas de evaluación y motivos de rechazo y desviación (las tablas se conservan). Al rechazar, el dictamen pide la explicación en la conclusión.
- **Parámetros a evaluar:** la tabla muestra código, parámetro, área, si es cuantitativo o cualitativo y unidad; el formulario (nombre, área, cómo se cuantifica y unidad) es el mismo que usan los jefes al agregar un parámetro en una prueba. Solo cuatro categorías: las áreas.
- **Código automático** de cada parámetro: área + palabras del nombre (p. ej. `CAL-TEMP-COCC`, `SEG-EQUI-PROT`); se recalcularon todos. La humedad bromatológica se renombró "Humedad (laboratorio)".
- Botones de acción con más colores (turquesa, verde, azul y violeta; naranja para lo principal). En *En proceso* se quitaron "Batches registrados" y "¿Falta un parámetro?".
- Migraciones `20261022002600`–`20261022002900`; pruebas `tests/sql/pruebas_flujo_v58.sql` (10/10).
