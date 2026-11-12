// =====================================================================
// Núcleo compartido: cliente Supabase, estado de sesión, catálogos y
// utilidades de interfaz (modales, tablas, validación, gráficas).
// =====================================================================
const cfg = window.PRUBIND_CONFIG || {};
export const TZ = 'America/Mexico_City';
export const APP_VERSION = cfg.APP_VERSION || '1.0.0';
// Dentro del Portal Pet's Table (theme-init.js lo detecta) la app vive en /pruebas-industriales/ y comparte
// con el portal la sesión, «Mantener sesión» y el tema; sola, en /, conserva sus llaves de siempre.
export const BASE = window.APP_BASE || '/';
export const EN_PORTAL = !!window.APP_PORTAL;
export const K_REMEMBER = EN_PORTAL ? 'portal.remember' : 'prubind.remember';
export const K_THEME = EN_PORTAL ? 'portal.theme' : 'prubind.theme';

// ---------- Almacenamiento de sesión ("Mantener sesión") ----------
function safe(fn, fallback) { try { return fn(); } catch { return fallback; } }
export const prefs = {
  get: (k) => safe(() => localStorage.getItem(k), null),
  set: (k, v) => safe(() => localStorage.setItem(k, v)),
  del: (k) => safe(() => localStorage.removeItem(k)),
};
const memory = new Map();
function activeStore() {
  const remember = prefs.get(K_REMEMBER) !== '0';
  return safe(() => (remember ? window.localStorage : window.sessionStorage), null);
}
const authStorage = {
  getItem: (k) => safe(() => activeStore()?.getItem(k), null) ?? memory.get(k) ?? null,
  setItem: (k, v) => { if (safe(() => (activeStore()?.setItem(k, v), true), false) !== true) memory.set(k, v); },
  removeItem: (k) => { memory.delete(k); safe(() => localStorage.removeItem(k)); safe(() => sessionStorage.removeItem(k)); },
};

if (!window.supabase || !cfg.SUPABASE_URL || !cfg.SUPABASE_ANON_KEY) {
  throw new Error('Configuración de Supabase no disponible.');
}
export const sb = window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, storage: authStorage, storageKey: EN_PORTAL ? 'portal-auth' : 'prubind-auth' },
});

// ---------- Sesión y permisos (ayuda visual; el servidor valida todo) ----------
// El administrador gestiona catálogos y usuarios, pero NO tiene autoridad técnica:
// la autoridad viene de la matriz puesto × tipo de prueba × acción.
export const state = { session: null, profile: null, isAdmin: false };
// El administrador puede hacer todo lo que hacen los responsables (igual que en el servidor)
export const autoridad = (tipo, accion) => state.isAdmin || (state.profile?.autoridades || [])
  .some((a) => a.accion === accion && (!a.tipo || a.tipo === tipo));
export const autoridadAlguna = (accion) => state.isAdmin || (state.profile?.autoridades || []).some((a) => a.accion === accion);
const yo = () => state.profile?.id;
// Espejo de prubind_puede (servidor)
export function puedeEn(p, accion) {
  if (!p || !yo()) return false;
  const persona = [p.registrado_por, p.responsable_inicial_id, p.responsable_ejecucion_id].includes(yo());
  const prefijo = (pre) => state.isAdmin || (state.profile?.autoridades || []).some((a) => a.accion.startsWith(pre) && (!a.tipo || a.tipo === p.tipo));
  switch (accion) {
    // Inicia y termina la prueba: su responsable (o un administrador)
    case 'responsable': return state.isAdmin || (p.responsable_inicial_id || p.registrado_por) === yo();
    case 'preparar': return persona || autoridad(p.tipo, 'preparar');
    case 'abastecer': return autoridad(p.tipo, 'abastecer') || puedeEn(p, 'preparar');
    case 'ejecutar': return p.responsable_ejecucion_id === yo() || autoridad(p.tipo, 'ejecutar') || prefijo('capturar_');
    case 'evaluar': return autoridad(p.tipo, 'evaluar') || prefijo('evaluar_');
    case 'cancelar': return [p.registrado_por, p.responsable_inicial_id].includes(yo()) || autoridad(p.tipo, 'cerrar') || autoridad(p.tipo, 'dictaminar');
    default: return autoridad(p.tipo, accion);
  }
}
// ¿Captura (rol 'capturar') o evalúa (rol 'evaluar') parámetros de esa área?
export const puedeArea = (p, rol, area) => !!p && autoridad(p.tipo, `${rol}_${area}`);
// Áreas que la persona atiende en una prueba (registra o evalúa). El administrador y quien no
// atiende ningún área (solo consulta) ven todas; los demás ven abiertas solo las suyas.
export function misAreas(p) {
  const todas = ['calidad', 'produccion', 'seguridad', 'mantenimiento'];
  if (!p || state.isAdmin) return todas;
  const mias = todas.filter((a) => puedeArea(p, 'capturar', a) || puedeArea(p, 'evaluar', a));
  return mias.length ? mias : todas;
}

// ---------- Formato y fechas ----------
export const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
export function todayISO() {
  return new Intl.DateTimeFormat('en-CA', { timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
}
export function addDays(iso, n) {
  const d = new Date(iso + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10);
}
export const fmtDate = (iso) => (iso ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}` : '—');
export function fmtDateTime(ts) {
  if (!ts) return '—';
  return new Intl.DateTimeFormat('es-MX', { timeZone: TZ, day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(new Date(ts));
}
export function fmtLongDate(iso) {
  return new Intl.DateTimeFormat('es-MX', { timeZone: 'UTC', weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }).format(new Date(iso + 'T12:00:00Z'));
}
export function monthShort(iso) {
  return new Intl.DateTimeFormat('es-MX', { timeZone: 'UTC', month: 'short' }).format(new Date(iso + 'T12:00:00Z')).replace('.', '');
}
export const fmtNum = (n) => new Intl.NumberFormat('es-MX').format(Number(n || 0));
// Cantidades con hasta 3 decimales (insumos, batches)
export const fmtQty = (n, unidad = '') => (n === null || n === undefined || n === '' ? '—'
  : `${new Intl.NumberFormat('es-MX', { maximumFractionDigits: 3 }).format(Number(n))}${unidad ? ` ${unidad}` : ''}`);
export function initials(name) {
  return String(name || '?').trim().split(/\s+/).slice(0, 2).map((p) => p[0]).join('').toUpperCase();
}
// Inicio del día (MX, UTC-6 sin horario de verano desde 2022) en ISO para filtrar timestamps
export const dayStartTs = (iso) => `${iso}T00:00:00-06:00`;
export const dayEndTs = (iso) => `${addDays(iso, 1)}T00:00:00-06:00`;

// ---------- Catálogos de negocio ----------
// etapa: posición en ETAPAS (1 Registro … 7 Cierre); 8 = concluida
export const ESTADOS_PRUEBA = {
  registrada:           { label: 'Registrada',               cls: 'gray',   etapa: 2 },
  en_preparacion:       { label: 'Registrada',               cls: 'gray',   etapa: 2 },
  preparada:            { label: 'Registrada',               cls: 'gray',   etapa: 2 },
  en_ejecucion:         { label: 'En proceso',               cls: 'orange', etapa: 2 },
  en_evaluacion:        { label: 'Evaluación de resultados', cls: 'violet', etapa: 4 },
  pendiente_resultados: { label: 'Pendiente de resultados',  cls: 'warn',   etapa: 4 },
  pendiente_dictamen:   { label: 'Pendiente de dictamen',    cls: 'warn',   etapa: 6 },
  aprobada:             { label: 'Aprobada · por cerrar',    cls: 'ok',     etapa: 7 },
  rechazada:            { label: 'Rechazada · por cerrar',   cls: 'bad',    etapa: 7 },
  requiere_repeticion:  { label: 'Requiere repetición',      cls: 'warn',   etapa: 6 },
  cerrada_aprobada:     { label: 'Cerrada y aprobada',       cls: 'ok',     etapa: 8 },
  cerrada_rechazada:    { label: 'Cerrada y rechazada',      cls: 'bad',    etapa: 8 },
  cancelada:            { label: 'Cancelada',                cls: 'bad',    etapa: 0 },
};
// Etapas según el flujo de información acordado (narración del 20/10/2026). Desde v5.6 los análisis de
// laboratorio y sensoriales (antes "Evaluaciones complementarias") se registran En proceso, para toda la prueba.
export const ETAPAS = [['registro', 'Registro', 'clipboard-pen'], ['proceso', 'En proceso', 'factory'],
  ['resultados', 'Evaluación', 'list-checks'], ['recomendaciones', 'Recomendaciones', 'lightbulb'],
  ['dictamen', 'Dictamen y aprobación', 'gavel'], ['cierre', 'Cierre', 'archive']];
// Los análisis de laboratorio y sensoriales solo aplican a materia prima, reformulación y producto nuevo
export const TIPOS_COMPLEMENTARIAS = ['producto_nuevo', 'cambio_formulacion', 'cambio_proveedor'];
export const etapasDe = () => ETAPAS;
// Fecha de ejecución: un día o un rango
export const fechaEjecTxt = (p) => (!p?.fecha_planeada ? '' : p.fecha_fin && p.fecha_fin !== p.fecha_planeada
  ? `${fmtDate(p.fecha_planeada)} al ${fmtDate(p.fecha_fin)}` : fmtDate(p.fecha_planeada));
export const fechaFinDe = (p) => p?.fecha_fin || p?.fecha_planeada || null;
export const COMPLEMENTARIAS = ['sensorial', 'microbiologia', 'bromatologia'];
// Áreas que registran y evalúan parámetros
export const AREAS = {
  calidad:       { label: 'Calidad',       desc: 'Calidad del producto: proceso, inocuidad y análisis de laboratorio', captura: 'Inspectores o Jefe de Calidad',                       evalua: 'Jefe de Calidad',                            ico: 'flask-conical' },
  produccion:    { label: 'Producción',    desc: 'Rendimiento y condiciones de fabricación', captura: 'Supervisores o Gerente de Producción',               evalua: 'Gerente de Producción',                      ico: 'hard-hat' },
  seguridad:     { label: 'Seguridad',     desc: 'Seguridad del personal y del área de trabajo', captura: 'Supervisor o Ingeniero de Seguridad',            evalua: 'Supervisor de Seguridad, Salud y Ambiente', ico: 'shield-check' },
  mantenimiento: { label: 'Mantenimiento', desc: 'Funcionamiento de máquinas y equipos', captura: 'Jefe o técnicos de Mantenimiento',                   evalua: 'Jefe de Mantenimiento',                      ico: 'wrench' },
};
export const AREAS_ORDEN = ['calidad', 'produccion', 'seguridad', 'mantenimiento'];
// Evaluación de cada parámetro: [texto, clase, ícono]
export const EVALUACION = {
  cumple: ['Cumple', 'ok', 'check'], no_cumple: ['No cumple', 'bad', 'x'], no_determinado: ['No se pudo determinar', 'warn', 'circle-help'],
};
// Veredicto de cada área sobre la prueba (recomendaciones_prubind.sentido)
export const VEREDICTO = {
  favorable: ['Satisfactoria', 'ok', 'thumbs-up', 'Por parte del área, la prueba es satisfactoria'],
  no_favorable: ['No satisfactoria', 'bad', 'thumbs-down', 'Por parte del área, la prueba no es satisfactoria'],
  repetir: ['Repetir prueba', 'warn', 'repeat', 'Recomienda repetir o ajustar la prueba'],
};
export const CERRADAS = ['cerrada_aprobada', 'cerrada_rechazada', 'cancelada'];
export const ABIERTAS = Object.keys(ESTADOS_PRUEBA).filter((e) => !CERRADAS.includes(e));
export const ESTADO_RES = {
  pendiente:   { label: 'Pendiente',   cls: 'warn' },
  conforme:    { label: 'Conforme',    cls: 'ok' },
  no_conforme: { label: 'No conforme', cls: 'bad' },
  no_aplica:   { label: 'No aplica',   cls: 'gray' },
};
export const OPCIONES_TXT = { conforme: 'Conforme', no_conforme: 'No conforme', no_aplica: 'No aplica', no_evaluado: 'No evaluado', pendiente: 'Pendiente', ausencia: 'Ausencia', presencia: 'Presencia' };
export const DISPONIBILIDAD = {
  pendiente:     { label: 'Por confirmar', cls: 'warn' },
  disponible:    { label: 'Disponible',    cls: 'ok' },
  en_compra:     { label: 'En compra',     cls: 'orange' },
  no_disponible: { label: 'No disponible', cls: 'bad' },
};
export const PRIORIDADES = { normal: { label: 'Normal', cls: 'blue' }, alta: { label: 'Alta', cls: 'warn' }, urgente: { label: 'Urgente', cls: 'bad' } };
export const NIVELES = { batch: 'Por batch', compuesta: 'Muestra compuesta', lote_diario: 'Por lote diario', corrida: 'Corrida / general', punto: 'Punto de muestreo' };
export const CATEGORIAS = {
  fisicoquimica: 'Fisicoquímica', sensorial: 'Sensorial', microbiologia: 'Microbiología', bromatologia: 'Bromatología',
  empaque_primario: 'Empaque primario', empaque_secundario: 'Empaque secundario', proceso: 'Proceso', equipo: 'Equipo',
  materia_prima: 'Materia prima / proveedor', vida_util: 'Vida útil', seguridad: 'Seguridad', general: 'Otros parámetros',
};
export const ACCIONES = {
  capturar_calidad: 'Registrar parámetros de Calidad', capturar_produccion: 'Registrar parámetros de Producción',
  capturar_seguridad: 'Registrar parámetros de Seguridad', capturar_mantenimiento: 'Registrar parámetros de Mantenimiento',
  evaluar_calidad: 'Evaluar y recomendar · Calidad', evaluar_produccion: 'Evaluar y recomendar · Producción',
  evaluar_seguridad: 'Evaluar y recomendar · Seguridad', evaluar_mantenimiento: 'Evaluar y recomendar · Mantenimiento',
  dictaminar: 'Dictaminar (Alta Dirección)', cerrar: 'Cerrar',
};
export const CAMPOS_REGISTRO = { producto: 'Receta', receta: 'Receta', materia_prima: 'Materia prima', proveedor: 'Proveedor', empaque: 'Empaque', proceso: 'Proceso', equipo: 'Equipo' };
export const SECCIONES_PREP = { batches: 'Batches planeados', peso: 'Peso objetivo', formulacion: 'Formulación', materiales: 'Materiales', equipos: 'Equipos y parámetros', muestreo: 'Plan de muestreo', vida_util: 'Puntos de vida útil' };
export const pill = (text, cls = 'gray') => `<span class="pill ${cls}">${esc(text)}</span>`;
const catPill = (cat) => (e) => pill(cat[e]?.label || e, cat[e]?.cls || 'gray');
export const estadoPill = catPill(ESTADOS_PRUEBA);
export const resPill = catPill(ESTADO_RES);
export const dispPill = catPill(DISPONIBILIDAD);
export const prioPill = catPill(PRIORIDADES);
export const icon = (name, cls = '') => `<i data-lucide="${name}"${cls ? ` class="${cls}"` : ''}></i>`;
// Ayuda contextual: ícono con explicación breve (al pasar el cursor o al tocarlo)
export const ayuda = (texto) => `<span class="help" tabindex="0" role="note" aria-label="${esc(texto)}" data-tip="${esc(texto)}">${icon('circle-help')}</span>`;
export function refreshIcons() { try { window.lucide?.createIcons(); } catch { /* sin íconos */ } }

// ---------- Ilustraciones propias (public/emoji, generadas desde fuentes/ilustraciones.src) ----------
// Ruta relativa: funciona sola en / y dentro del Portal en /pruebas-industriales/. Decorativas (alt vacío).
export const emoji = (slug, cls = '') => `<img class="emoji ${cls}" src="emoji/${slug}.svg" alt="" aria-hidden="true" loading="lazy" decoding="async">`;
// Ilustración de cada estado de la prueba y de cada etapa del expediente
export const ILUS_ESTADO = {
  registrada: 'calendario', en_preparacion: 'calendario', preparada: 'calendario', en_ejecucion: 'en_curso',
  en_evaluacion: 'evaluacion', pendiente_resultados: 'evaluacion', pendiente_dictamen: 'dictamen', requiere_repeticion: 'evaluacion',
  aprobada: 'aprobada', rechazada: 'rechazada', cerrada_aprobada: 'aprobada', cerrada_rechazada: 'rechazada', cancelada: 'cancelada',
};
export const ILUS_ETAPA = { registro: 'registro', proceso: 'cocimiento', resultados: 'evaluacion', recomendaciones: 'criterios', dictamen: 'dictamen', cierre: 'folio' };

// ---------- Indicadores (.kx) ----------
// tono: orange, green, red, blue o violet. ilus: ilustración (si no, ícono lucide ico).
// texto: el valor es una palabra. barra: porcentaje 0 a 100. go: ruta al pulsar (data-dash en el Panel).
export function kpiHTML({ tono, ico = 'circle', ilus = '', label, valor, desc = '', go = '', texto = false, barra = null, attr = 'data-go' }) {
  const link = go ? ` ${attr}="${esc(go)}" role="link" tabindex="0"` : '';
  return `<div class="kx t-${tono}${texto ? ' texto' : ''}${go ? ' go' : ''}"${link}>
    <span class="kx-ico${ilus ? ' ilus-box' : ''}" aria-hidden="true">${ilus ? emoji(ilus) : icon(ico)}</span>
    <div class="kx-top"><small>${esc(label)}</small></div>
    <strong${texto ? '' : ' data-cifra'} title="${esc(valor)}">${esc(valor)}</strong>${desc ? `<span class="kx-desc">${esc(desc)}</span>` : ''}
    ${barra !== null ? `<span class="kx-barra" aria-hidden="true"><i style="width:${Math.max(0, Math.min(100, barra))}%"></i></span>` : ''}
    ${go ? `<span class="kx-go">Ver detalle ${icon('arrow-right')}</span>` : ''}</div>`;
}
// Las cifras cuentan desde 0 (1,832 · 95.0% · 6.4%), en formato es-MX. Sin animación si el usuario la reduce.
export function animarCifras(raiz) {
  if (!raiz || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  raiz.querySelectorAll('[data-cifra]').forEach((el) => {
    const m = el.textContent.trim().match(/^([\d,]+)(\.\d+)?(%?)$/);
    if (!m) return;
    const fin = Number(`${m[1].replace(/,/g, '')}${m[2] || ''}`), dec = m[2] ? m[2].length - 1 : 0, suf = m[3];
    if (!fin) return;
    const fmt = new Intl.NumberFormat('es-MX', { minimumFractionDigits: dec, maximumFractionDigits: dec });
    const t0 = performance.now(), dur = 900;
    const paso = (t) => {
      const k = Math.min(1, (t - t0) / dur), e = 1 - (1 - k) ** 3;
      el.textContent = `${fmt.format(fin * e)}${suf}`;
      if (k < 1 && el.isConnected) requestAnimationFrame(paso);
    };
    requestAnimationFrame(paso);
  });
}

export function sanitizeSearch(q) { return String(q || '').replace(/[%,()*\\"'`;:]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 60); }
export function debounce(fn, ms = 300) { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; }

// ---------- Errores ----------
const CONSTRAINT_MSG = {
  areas_prubind_nombre_uk: 'Ya existe un área con ese nombre.',
  usuarios_prubind_email_uk: 'Ese correo ya está registrado.',
  usuarios_prubind_email_check: 'El correo debe ser del dominio @petstable.mx.',
  pruebas_prubind_fechas_ck: 'La fecha de fin debe ser igual o posterior a la de inicio.',
  tipo_responsables_prubind_pkey: 'Esa persona ya es responsable de este tipo de prueba.',
  tipos_prueba_prubind_prefijo_uk: 'Ese prefijo ya lo usa otro tipo de prueba.',
};
export function errMsg(err) {
  if (!err) return 'Ocurrió un error inesperado.';
  const msg = err.message || String(err);
  for (const [k, v] of Object.entries(CONSTRAINT_MSG)) if (msg.includes(k) || err.details?.includes?.(k)) return v;
  if (err.code === '23505') return 'El registro ya existe (dato duplicado).';
  if (err.code === '23503') return 'No se puede eliminar porque tiene registros relacionados. Puede desactivarlo en su lugar.';
  if (err.code === '23514') return 'Algún dato no cumple las reglas de validación.';
  if (err.code === '42501') return msg.includes('permission denied') || msg.includes('row-level security') ? 'No tiene permiso para realizar esta acción.' : msg;
  if (err.code === 'P0001') return msg;
  if (/row-level security|permission denied|Unauthorized/i.test(msg)) return 'No tiene permiso para realizar esta acción.';
  if (/exceeded the maximum allowed size|Payload too large/i.test(msg)) return 'El archivo es demasiado grande.';
  if (/mime type|invalid_mime/i.test(msg)) return 'Tipo de archivo no permitido.';
  if (err.code === 'PGRST301' || /JWT expired|invalid JWT/i.test(msg)) return 'Su sesión expiró. Vuelva a iniciar sesión.';
  if (/Failed to fetch|NetworkError|Load failed|network/i.test(msg)) return 'No hay conexión con el servidor. Verifique su red e intente de nuevo.';
  return msg;
}
// Lanza el error de una respuesta de Supabase
export function must(res) { if (res.error) throw res.error; return res; }
// Una actualización que no afectó filas (RLS) se reporta como falta de permiso
export function mustRow(res) {
  must(res);
  if (Array.isArray(res.data) ? !res.data.length : !res.data) throw Object.assign(new Error('No tiene permiso para modificar este registro o ya no existe.'), { code: '42501' });
  return res;
}

// ---------- Toasts ----------
export function toast(message, type = 'info', ms = 4200) {
  const root = document.getElementById('toasts');
  const el = document.createElement('div');
  const ic = { success: 'check-circle-2', error: 'alert-octagon', warning: 'alert-triangle', info: 'info' }[type] || 'info';
  el.className = `toast ${type}`;
  el.setAttribute('role', type === 'error' ? 'alert' : 'status');
  el.innerHTML = `${icon(ic)}<div class="t-body">${esc(message)}</div><button type="button" aria-label="Cerrar">${icon('x')}</button>`;
  el.querySelector('button').addEventListener('click', () => el.remove());
  root.appendChild(el); refreshIcons();
  setTimeout(() => el.remove(), type === 'error' ? Math.max(ms, 7000) : ms);
}

// ---------- Modales ----------
let modalDepth = 0;
export function openModal({ title, subtitle = '', body = '', submitText = 'Guardar', onSubmit = null, size = '', danger = false, onOpen = null, confirmDiscard = true }) {
  return new Promise((resolve) => {
    const root = document.getElementById('modal-root');
    const wrap = document.createElement('div');
    wrap.className = 'modal';
    wrap.innerHTML = `
      <form class="modal-box ${size}" role="dialog" aria-modal="true" aria-labelledby="mt-${modalDepth}" novalidate>
        <header class="modal-head">
          <div><h3 id="mt-${modalDepth}">${esc(title)}</h3>${subtitle ? `<p>${esc(subtitle)}</p>` : ''}</div>
          <button type="button" class="icon-btn" data-close aria-label="Cerrar">${icon('x')}</button>
        </header>
        <div class="modal-body">${body}</div>
        <footer class="modal-foot">
          ${onSubmit
            ? `<div class="form-error" role="alert"></div>
               <button type="button" class="btn secondary" data-close>Cancelar</button>
               <button type="submit" class="btn ${danger ? 'danger' : 'primary'}" data-submit>${esc(submitText)}</button>`
            : `<button type="button" class="btn secondary" data-close>Cerrar</button>`}
        </footer>
      </form>`;
    modalDepth++;
    root.appendChild(wrap);
    document.body.classList.add('modal-open');
    const form = wrap.querySelector('form');
    const errBox = wrap.querySelector('.form-error');
    let dirty = false, busy = false, result;
    form.addEventListener('input', () => { dirty = true; });

    const finish = () => {
      wrap.remove(); modalDepth--;
      document.removeEventListener('keydown', onKey);
      if (!root.children.length) document.body.classList.remove('modal-open');
      resolve(result);
    };
    const close = async (force = false) => {
      if (busy) return;
      if (!force && dirty && onSubmit && confirmDiscard) {
        const ok = await confirmDialog({ title: '¿Descartar cambios?', message: 'Hay información capturada que no se ha guardado.', confirmText: 'Descartar', danger: true });
        if (!ok) return;
      }
      finish();
    };
    const onKey = (e) => { if (e.key === 'Escape' && root.lastElementChild === wrap) { e.preventDefault(); close(); } };
    document.addEventListener('keydown', onKey);
    wrap.addEventListener('click', (e) => { if (e.target.closest('[data-close]')) close(); });

    const ctx = {
      form, wrap,
      setError: (m) => { if (errBox) errBox.textContent = m || ''; },
      close: (value) => { result = value; finish(); },
    };
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      if (!onSubmit || busy) return;
      ctx.setError('');
      const btn = form.querySelector('[data-submit]');
      busy = true; btn.disabled = true;
      const label = btn.innerHTML; btn.innerHTML = `<span class="spinner sm"></span> Guardando…`;
      try {
        const r = await onSubmit(ctx);
        if (r !== false) { result = r === undefined ? true : r; busy = false; finish(); return; }
      } catch (err) {
        console.error(err);
        ctx.setError(errMsg(err));
      }
      busy = false; btn.disabled = false; btn.innerHTML = label; refreshIcons();
    });
    refreshIcons();
    onOpen?.(ctx);
    setTimeout(() => form.querySelector('input:not([type=hidden]):not([disabled]):not([type=checkbox]), select, textarea')?.focus({ preventScroll: true }), 30);
  });
}

// Confirmación (opcionalmente con texto obligatorio, p. ej. motivo de cancelación)
// html: contenido ya escapado por quien llama (en lugar de message)
export function confirmDialog({ title, message = '', html = '', confirmText = 'Confirmar', danger = false, input = null }) {
  const body = `${html || `<p style="margin:0 0 6px">${esc(message)}</p>`}
    ${input ? `<div class="field"><label for="cd-input">${esc(input.label)} ${input.required ? '<span class="req">*</span>' : ''}</label>
      ${input.type ? `<input id="cd-input" name="value" type="${esc(input.type)}" value="${esc(input.value || '')}" ${input.min ? `min="${esc(input.min)}"` : ''} ${input.required ? 'required' : ''}>`
        : `<textarea id="cd-input" name="value" maxlength="${input.maxlength || 300}" ${input.required ? 'required' : ''} placeholder="${esc(input.placeholder || '')}">${esc(input.value || '')}</textarea>`}</div>` : ''}`;
  return openModal({
    title, body, submitText: confirmText, danger, size: 'sm', confirmDiscard: false,
    onSubmit: ({ form }) => {
      if (input) {
        if (!checkForm(form)) return false;
        return { value: form.elements.value.value.trim() };
      }
      return true;
    },
  }).then((r) => r || false);
}

// ---------- Validación de formularios ----------
function validityMessage(el) {
  const v = el.validity;
  if (v.valueMissing) return 'Campo obligatorio.';
  if (v.typeMismatch) return el.type === 'email' ? 'Correo electrónico inválido.' : 'Formato inválido.';
  if (v.patternMismatch) return el.dataset.patternMsg || 'Formato inválido.';
  if (v.tooShort) return `Mínimo ${el.minLength} caracteres.`;
  if (v.tooLong) return `Máximo ${el.maxLength} caracteres.`;
  if (v.rangeUnderflow) return `El valor mínimo es ${el.min}.`;
  if (v.rangeOverflow) return `El valor máximo es ${el.max}.`;
  if (v.stepMismatch) return el.step === '1' ? 'Use un número entero.' : 'Use como máximo 3 decimales.';
  if (v.badInput) return 'Valor inválido.';
  return 'Valor inválido.';
}
export function fieldError(el, msg) {
  const field = el.closest('.field') || el.parentElement;
  field.classList.add('invalid');
  const s = document.createElement('small'); s.className = 'field-error'; s.textContent = msg;
  field.appendChild(s);
}
export function clearErrors(form) {
  form.querySelectorAll('.field-error').forEach((e) => e.remove());
  form.querySelectorAll('.invalid').forEach((e) => e.classList.remove('invalid'));
}
export function checkForm(form, custom = {}) {
  clearErrors(form);
  let first = null;
  for (const el of form.elements) {
    if (!el.name || el.disabled || el.type === 'button' || el.type === 'submit') continue;
    let msg = '';
    if (el.required && typeof el.value === 'string' && el.type !== 'radio' && el.type !== 'checkbox' && !el.value.trim()) msg = 'Campo obligatorio.';
    else if (el.willValidate && !el.checkValidity()) msg = validityMessage(el);
    if (!msg && custom[el.name]) msg = custom[el.name](el.value, form) || '';
    if (msg && !el.closest('.field')?.classList.contains('invalid')) { fieldError(el, msg); first ??= el; }
  }
  if (first) (first._cs?.btn || first).focus();
  return !first;
}
export function formValues(form) {
  const o = {};
  for (const [k, v] of new FormData(form).entries()) o[k] = typeof v === 'string' ? v.trim() : v;
  return o;
}
export const nullIfEmpty = (v) => (v === '' || v === undefined ? null : v);
export const numOrNull = (v) => (v === '' || v === undefined || v === null ? null : Number(v));

// Contadores de caracteres en textareas con data-counter
export function bindCounters(root) {
  root.querySelectorAll('textarea[maxlength][data-counter]').forEach((ta) => {
    const lab = root.querySelector(`label[for="${ta.id}"]`);
    if (!lab) return;
    const c = document.createElement('span'); c.className = 'counter'; lab.appendChild(c);
    const upd = () => { c.textContent = `${ta.value.length}/${ta.maxLength}`; };
    ta.addEventListener('input', upd); upd();
  });
}

// ---------- Estados vacíos ----------
// Ilustración de los estados vacíos según el ícono pedido (los demás conservan su ícono lucide)
const ILUS_VACIO = {
  'book-open': 'libro', 'calendar-x': 'calendario', history: 'n_bitacora', 'list-checks': 'criterios', 'search-x': 'buscar_vacio', 'wifi-off': 'sin_conexion',
  inbox: 'paquete', 'bar-chart-3': 'n_panel', 'check-circle-2': 'activo', users: 'personas', 'flask-conical': 'pruebas', package: 'paquete', factory: 'cocimiento',
};
export function emptyState({ ico = 'inbox', title, text = '', action = '' }) {
  const ilus = ILUS_VACIO[ico];
  return `<div class="empty"><div class="empty-ico${ilus ? ' ilus' : ''}">${ilus ? emoji(ilus) : icon(ico)}</div><b>${esc(title)}</b>${text ? `<p>${esc(text)}</p>` : ''}${action}</div>`;
}
export function errorState(err, retryAction = 'retry') {
  return `<div class="empty error"><div class="empty-ico ilus">${emoji('sin_conexion')}</div><b>No se pudo cargar la información</b><p>${esc(errMsg(err))}</p>
    <button class="btn secondary" data-action="${retryAction}">${icon('refresh-cw')} Reintentar</button></div>`;
}

// ---------- Tabla con paginación y orden en servidor ----------
export class DataTable {
  /**
   * @param {HTMLElement} el contenedor
   * @param {{columns: Array, fetch: Function, pageSize?: number, sort?: {key:string, asc:boolean}, empty?: object, rowKey?: string, rowClass?: Function}} opts
   * columns: [{ key, label, sort?: 'columna', cls?, render(row) }]
   * fetch({ from, to, sort, filters }) => Promise<{ rows, count }>
   */
  constructor(el, opts) {
    this.el = el; this.o = opts;
    this.page = 1; this.size = opts.pageSize || prefsNum('prubind.pagesize', 10);
    this.sort = opts.sort || null; this.filters = {};
    this.rows = []; this.count = 0; this.token = 0;
    el.addEventListener('click', (e) => this.onClick(e));
    el.addEventListener('change', (e) => {
      if (e.target.matches('[data-pagesize]')) { this.size = Number(e.target.value); prefs.set('prubind.pagesize', String(this.size)); this.page = 1; this.load(); }
    });
  }
  setFilters(f) { this.filters = { ...this.filters, ...f }; this.page = 1; return this.load(); }
  row(id) { return this.rows.find((r) => String(r[this.o.rowKey || 'id']) === String(id)); }
  onClick(e) {
    const th = e.target.closest('th[data-sort]');
    if (th) {
      const key = th.dataset.sort;
      this.sort = this.sort?.key === key ? { key, asc: !this.sort.asc } : { key, asc: true };
      this.page = 1; this.load(); return;
    }
    const pg = e.target.closest('[data-page]');
    if (pg && !pg.disabled) { this.page = Number(pg.dataset.page); this.load(); return; }
    if (e.target.closest('[data-action="retry"]')) this.load();
  }
  async load() {
    const t = ++this.token;
    const from = (this.page - 1) * this.size, to = from + this.size - 1;
    if (!this.rendered) this.el.innerHTML = this.skeleton();
    else this.el.querySelector('.table-wrap')?.classList.add('table-loading');
    try {
      const { rows, count } = await this.o.fetch({ from, to, sort: this.sort, filters: this.filters });
      if (t !== this.token) return;
      this.rows = rows || []; this.count = count ?? this.rows.length;
      const pages = Math.max(1, Math.ceil(this.count / this.size));
      if (this.page > pages && this.count > 0) { this.page = pages; return this.load(); }
      this.render();
    } catch (err) {
      if (t !== this.token) return;
      console.error(err);
      this.rendered = false;
      this.el.innerHTML = errorState(err);
      refreshIcons();
    }
  }
  skeleton() {
    return `<div class="table-wrap"><table class="table"><tbody>${Array.from({ length: 5 }, () => `<tr>${this.o.columns.map(() => '<td><div class="skeleton"></div></td>').join('')}</tr>`).join('')}</tbody></table></div>`;
  }
  render() {
    const { columns, empty } = this.o;
    if (!this.rows.length) {
      const filtered = Object.entries(this.filters).some(([k, v]) => !(this.o.baseFilters || []).includes(k) && v !== '' && v != null && v !== false);
      this.el.innerHTML = emptyState(filtered
        ? { ico: 'search-x', title: 'Sin resultados', text: 'No hay registros que coincidan con los filtros aplicados.' }
        : (empty || { title: 'Sin registros' }));
      this.rendered = false; refreshIcons(); return;
    }
    const head = columns.map((c) => {
      const sorted = c.sort && this.sort?.key === c.sort;
      const ind = c.sort ? `<span class="sort-ind">${sorted ? (this.sort.asc ? '▲' : '▼') : '↕'}</span>` : '';
      return `<th class="${c.cls || ''} ${c.sort ? 'sortable' : ''} ${sorted ? 'sorted' : ''}" ${c.sort ? `data-sort="${c.sort}" aria-sort="${sorted ? (this.sort.asc ? 'ascending' : 'descending') : 'none'}"` : ''}>${esc(c.label)}${ind}</th>`;
    }).join('');
    const body = this.rows.map((r) => `<tr data-id="${esc(r[this.o.rowKey || 'id'])}" class="${this.o.rowClass ? this.o.rowClass(r) : ''}">${columns.map((c) =>
      `<td class="${c.cls || ''}" data-label="${esc(c.label)}"><div class="td-in">${c.render ? c.render(r) : esc(r[c.key])}</div></td>`).join('')}</tr>`).join('');
    const pages = Math.max(1, Math.ceil(this.count / this.size));
    const from = (this.page - 1) * this.size + 1, to = Math.min(this.count, this.page * this.size);
    this.el.innerHTML = `
      <div class="table-wrap responsive"><table class="table"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table></div>
      <div class="pager">
        <span>Mostrando <b>${fmtNum(from)}–${fmtNum(to)}</b> de <b>${fmtNum(this.count)}</b></span>
        <div class="pager-ctrl">
          <label class="sr-only" for="ps-${this.token}">Registros por página</label>
          <select id="ps-${this.token}" data-pagesize>${[10, 25, 50].map((n) => `<option value="${n}" ${n === this.size ? 'selected' : ''}>${n} por página</option>`).join('')}</select>
          <button class="icon-btn" data-page="1" ${this.page <= 1 ? 'disabled' : ''} aria-label="Primera página">${icon('chevrons-left')}</button>
          <button class="icon-btn" data-page="${this.page - 1}" ${this.page <= 1 ? 'disabled' : ''} aria-label="Página anterior">${icon('chevron-left')}</button>
          <span>Pág. ${this.page} / ${pages}</span>
          <button class="icon-btn" data-page="${this.page + 1}" ${this.page >= pages ? 'disabled' : ''} aria-label="Página siguiente">${icon('chevron-right')}</button>
          <button class="icon-btn" data-page="${pages}" ${this.page >= pages ? 'disabled' : ''} aria-label="Última página">${icon('chevrons-right')}</button>
        </div>
      </div>`;
    this.rendered = true;
    refreshIcons();
  }
}
function prefsNum(k, d) { const n = Number(prefs.get(k)); return [10, 25, 50].includes(n) ? n : d; }

// Aplica orden y rango a una consulta de Supabase
export function paged(q, { from, to, sort }, extraOrder = []) {
  if (sort) q = q.order(sort.key, { ascending: sort.asc, nullsFirst: false });
  for (const [k, asc] of extraOrder) q = q.order(k, { ascending: asc });
  return q.range(from, to);
}

// ---------- Gráficas ----------
// Sistema visual de Ruta de calidad: barras con degradado, dona con cifra al centro,
// etiquetas dentro de la barra (o en píldora si no caben), tooltip oscuro y gráfica ampliada.
const charts = new Set();
const chartConfigs = new WeakMap();
export function cssVar(name) { return getComputedStyle(document.documentElement).getPropertyValue(name).trim(); }
// ¿Tema oscuro? (para elegir los tonos validados de cada modo)
export const temaOscuro = () => { const t = document.documentElement.dataset.theme; return t ? t === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches; };
const fmtEtiqueta = (v) => new Intl.NumberFormat('es-MX', { maximumFractionDigits: 1 }).format(v);
// Paleta categórica validada (daltonismo y contraste) para claro y oscuro: un color por
// categoría, siempre en el mismo orden; máximo 8 categorías por gráfica (el resto, «Otros»).
const PALETA_CAT = {
  claro: ['#2A78D6', '#EB6834', '#1BAF7A', '#EDA100', '#E87BA4', '#008300', '#6250D6', '#E34948'],
  oscuro: ['#3987E5', '#D95926', '#199E70', '#C98500', '#D55181', '#008300', '#9085E9', '#E66767'],
};
export const paletaCat = () => PALETA_CAT[temaOscuro() ? 'oscuro' : 'claro'];
export const colorCategoria = (i) => paletaCat()[i % 8];

// Etiqueta de datos: el valor dentro de cada barra o segmento (en píldora si no cabe).
// Se dibuja en el canvas, así que también aparece al guardar la gráfica como imagen.
const etiquetasDatos = {
  id: 'prubindEtiquetas',
  afterDatasetsDraw(chart) {
    const tipo = chart.config.type;
    if (!['bar', 'doughnut', 'pie'].includes(tipo)) return;
    const { ctx } = chart;
    const horiz = chart.options.indexAxis === 'y';
    ctx.save();
    ctx.font = `800 ${chart.canvas.dataset.zoom ? 15 : 11}px Inter, Segoe UI, system-ui, sans-serif`;
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    chart.data.datasets.forEach((ds, di) => {
      const meta = chart.getDatasetMeta(di);
      if (meta.hidden || meta.type === 'line') return;
      meta.data.forEach((el, i) => {
        const v = Number(ds.data[i]);
        if (!v || el.hidden || (tipo !== 'bar' && !chart.getDataVisibility(i))) return;
        // _porcentaje: el segmento muestra su proporción del total (pastel y dona)
        const total = ds._porcentaje ? ds.data.reduce((s, n) => s + Number(n || 0), 0) : 0;
        const label = ds._porcentaje ? `${fmtEtiqueta((v / total) * 100)} %` : `${fmtEtiqueta(v)}${ds._sufijo || ''}`;
        let x, y, dentro = true;
        if (tipo === 'bar') {
          const p = el.getProps(['x', 'y', 'base'], true);
          const largo = horiz ? Math.abs(p.x - p.base) : Math.abs(p.base - p.y);
          const ancho = ctx.measureText(label).width + 6;
          dentro = largo >= (horiz ? ancho : 16);
          // Barras apiladas: si no cabe, no se repite fuera (se lee en el recuadro de información)
          if (!dentro && ds.stack !== undefined) return;
          if (!dentro && chart.options.scales?.x?.stacked) return;
          if (dentro) { x = horiz ? (p.x + p.base) / 2 : p.x; y = horiz ? p.y : (p.y + p.base) / 2; }
          else { x = horiz ? p.x + ancho / 2 + 8 : p.x; y = horiz ? p.y : p.y - 13; }
        } else {
          if (el.circumference < 0.12) return;
          // Dona con cifra al centro: el segmento dominante no repite la cifra
          if (ds._centro && el.circumference > Math.PI * 1.6) return;
          ({ x, y } = el.tooltipPosition(true));
        }
        if (dentro) {
          if (ds.etiquetaColor) ctx.fillStyle = ds.etiquetaColor;
          else { ctx.shadowColor = 'rgba(9, 13, 18, .45)'; ctx.shadowBlur = 4; ctx.shadowOffsetY = 1; ctx.fillStyle = '#FFFFFF'; }
          ctx.fillText(label, x, y);
          ctx.shadowColor = 'transparent'; ctx.shadowBlur = 0; ctx.shadowOffsetY = 0;
        } else {
          // Fuera de la barra: píldora con el color de la tarjeta y borde del color de la barra
          const w = ctx.measureText(label).width + 12, h = chart.canvas.dataset.zoom ? 22 : 18;
          const col = colorDe(ds._color, i) || cssVar('--muted');
          ctx.beginPath(); ctx.roundRect(x - w / 2, y - h / 2, w, h, h / 2);
          ctx.fillStyle = cssVar('--card') || '#fff'; ctx.fill();
          ctx.lineWidth = 1.5; ctx.strokeStyle = typeof col === 'string' ? col : '#94A3B8'; ctx.stroke();
          ctx.fillStyle = cssVar('--text') || '#172431';
          ctx.fillText(label, x, y + .5);
        }
      });
    });
    ctx.restore();
  },
};
// Color hexadecimal → rgba (para degradados); otros formatos se devuelven igual
export function rgba(hex, a = 1) {
  const m = /^#?([0-9a-f]{6})$/i.exec(String(hex || '').trim());
  if (!m) return hex;
  const n = parseInt(m[1], 16);
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${a})`;
}
// Mezcla con blanco (0–1): tono claro del mismo color para el degradado de las barras
function aclarar(hex, k) {
  const m = /^#?([0-9a-f]{6})$/i.exec(String(hex || '').trim());
  if (!m) return hex;
  const n = parseInt(m[1], 16), f = (c) => Math.round(c + (255 - c) * k);
  return `rgb(${f((n >> 16) & 255)}, ${f((n >> 8) & 255)}, ${f(n & 255)})`;
}
const colorDe = (col, i) => (Array.isArray(col) ? col[i % col.length] : col);
// Barras: degradado del color pleno (extremo de la barra) a un tono más claro (base)
function degradadoBarra(c, col, horiz) {
  const base = colorDe(col, c.dataIndex);
  const area = c.chart.chartArea;
  if (!area || typeof base !== 'string' || !base.startsWith('#')) return base;
  const g = horiz ? c.chart.ctx.createLinearGradient(area.left, 0, area.right, 0) : c.chart.ctx.createLinearGradient(0, area.bottom, 0, area.top);
  g.addColorStop(0, aclarar(base, 0.4));
  g.addColorStop(1, base);
  return g;
}
// Líneas: área bajo la curva que se desvanece hacia abajo
function degradadoArea(c, col) {
  const area = c.chart.chartArea;
  if (!area || typeof col !== 'string') return rgba(col, 0.12);
  const g = c.chart.ctx.createLinearGradient(0, area.top, 0, area.bottom);
  g.addColorStop(0, rgba(col, 0.26));
  g.addColorStop(1, rgba(col, 0));
  return g;
}
// Dona: cifra principal al centro (dataset._centro = { valor, etiqueta, color })
const centroDona = {
  id: 'prubindCentro',
  afterDatasetsDraw(chart) {
    const ds = chart.data.datasets[0];
    if (chart.config.type !== 'doughnut' || !ds?._centro) return;
    const arco = chart.getDatasetMeta(0).data.find((a) => a && !a.hidden);
    if (!arco) return;
    const { x, y, innerRadius } = arco.getProps(['x', 'y', 'innerRadius'], true);
    const zoom = !!chart.canvas.dataset.zoom;
    const t = Math.max(14, Math.min(innerRadius * 0.42, zoom ? 46 : 30));
    const { ctx } = chart;
    ctx.save();
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.font = `900 ${t}px Inter, Segoe UI, system-ui, sans-serif`;
    ctx.fillStyle = ds._centro.color || cssVar('--text') || '#172431';
    ctx.fillText(ds._centro.valor, x, y - (ds._centro.etiqueta ? t * 0.3 : 0));
    if (ds._centro.etiqueta) {
      ctx.font = `700 ${Math.max(10, t * 0.38)}px Inter, Segoe UI, system-ui, sans-serif`;
      ctx.fillStyle = cssVar('--muted') || '#687B8C';
      ctx.fillText(ds._centro.etiqueta, x, y + t * 0.6);
    }
    ctx.restore();
  },
};
// Aplica el color del tema a cada serie: _colores() devuelve los colores del tema activo
function aplicarColores(d) {
  if (typeof d._colores !== 'function') return;
  const col = d._colores();
  d._color = col;
  if (!d._grad) d.backgroundColor = col;
}

export function makeChart(canvas, config) {
  if (!window.Chart || !canvas) return null;
  const muted = cssVar('--muted') || '#687B8C', line = cssVar('--line') || '#E3EAEF', text = cssVar('--text') || '#172431';
  window.Chart.defaults.font.family = 'Inter, Segoe UI, system-ui, sans-serif';
  window.Chart.defaults.color = muted;
  const horiz = config.options?.indexAxis === 'y';
  const tipo = config.type;
  const apilada = !!(config.options?.scales?.x?.stacked || config.options?.scales?.y?.stacked);
  config.data.datasets.forEach((d) => {
    aplicarColores(d);
    // Pastel y dona: la separación entre segmentos toma el color de la tarjeta (sin bordes blancos en modo oscuro)
    if (['pie', 'doughnut'].includes(tipo)) {
      d.borderColor = cssVar('--card') || '#fff'; d._bordeTarjeta = true;
      d.borderWidth = 3; d.hoverOffset = 8;
      if (tipo === 'doughnut') d.borderRadius = 6;
      return;
    }
    // Barras con degradado (el color base se guarda en _color: la gráfica ampliada copia los datos como JSON)
    if ((d.type || tipo) === 'bar') {
      if (d._color === undefined) d._color = d.backgroundColor;
      d._grad = true;
      d.backgroundColor = (c) => degradadoBarra(c, d._color, horiz);
      d.hoverBackgroundColor = (c) => colorDe(d._color, c.dataIndex);
      d.borderRadius = apilada ? 4 : 8;
      d.borderSkipped = apilada ? 'middle' : 'start';
      return;
    }
    // Línea principal: área sombreada bajo la curva y puntos con aro del color de la tarjeta
    if ((d.type || tipo) === 'line' && d._area) {
      if (d._color === undefined) d._color = d.borderColor;
      const col = d._color;
      d.fill = 'start';
      d.backgroundColor = (c) => degradadoArea(c, col);
      d.pointBorderColor = cssVar('--card') || '#fff'; d._bordeTarjeta = true;
      d.pointBorderWidth = 2;
    }
  });
  const chico = (canvas.parentElement?.clientWidth || canvas.clientWidth || 600) < 420; // celular: menos marcas y letra compacta
  const ejes = { grid: { color: line, drawTicks: false, lineWidth: 1 }, ticks: { color: muted, precision: 0, padding: chico ? 6 : 8, maxTicksLimit: chico ? 5 : 8, font: { size: chico ? 10.5 : 11, weight: '500' } }, border: { display: false } };
  const ox = config.options?.scales?.x || {}, oy = config.options?.scales?.y || {};
  const c = new window.Chart(canvas, {
    ...config,
    plugins: [...(config.plugins || []), etiquetasDatos, centroDona],
    options: {
      responsive: true, maintainAspectRatio: false,
      animation: { duration: 750, easing: 'easeOutCubic' },
      transitions: { active: { animation: { duration: 160 } } },
      interaction: config.options?.interaction || (['doughnut', 'pie'].includes(tipo) ? { mode: 'nearest', intersect: true } : { mode: 'index', intersect: false }),
      layout: config.options?.layout || { padding: { top: 12, right: 10, bottom: 2, left: 4 } },
      plugins: {
        legend: { labels: { color: text, boxWidth: 8, boxHeight: 8, usePointStyle: true, pointStyle: 'circle', padding: chico ? 12 : 16, font: { size: chico ? 11 : 12, weight: '600' } }, ...(config.options?.plugins?.legend || {}) },
        tooltip: {
          backgroundColor: 'rgba(10, 26, 39, .96)', titleColor: '#FFFFFF', bodyColor: '#D7E1EA', footerColor: '#93A5B3',
          titleFont: { size: 12, weight: '700' }, bodyFont: { size: 12, weight: '500' }, titleMarginBottom: 6, bodySpacing: 4,
          padding: { x: 12, y: 10 }, cornerRadius: 10, caretSize: 5, caretPadding: 8, boxPadding: 5, usePointStyle: true, animation: { duration: 140 },
          borderColor: 'rgba(255, 255, 255, .14)', borderWidth: 1,
          ...(['doughnut', 'pie'].includes(tipo) ? { callbacks: { label: (it) => { const t = it.dataset.data.reduce((s, v) => s + (Number(v) || 0), 0); return ` ${it.label}: ${fmtEtiqueta(it.parsed)} (${t ? Math.round((it.parsed / t) * 100) : 0} %)`; } } } : {}),
          ...(config.options?.plugins?.tooltip || {}),
        },
      },
      scales: ['doughnut', 'pie'].includes(tipo) ? {} : {
        x: { ...ejes, beginAtZero: horiz, ...ox, grid: { ...ejes.grid, display: horiz, ...(ox.grid || {}) }, ticks: { ...ejes.ticks, ...(ox.ticks || {}) } },
        y: { ...ejes, beginAtZero: !horiz, ...oy, grid: { ...ejes.grid, display: !horiz, ...(oy.grid || {}) }, ticks: { ...ejes.ticks, ...(oy.ticks || {}) } },
      },
      ...(horiz ? { indexAxis: 'y' } : {}),
      ...(tipo === 'doughnut' ? { cutout: '66%' } : {}),
    },
  });
  charts.add(c);
  chartConfigs.set(c, config);
  // El recuadro de información se oculta al salir de la gráfica (no se queda fijo)
  const ocultar = () => { try { c.setActiveElements([]); c.tooltip?.setActiveElements([], { x: 0, y: 0 }); c.update('none'); } catch { /* gráfica destruida */ } };
  canvas.addEventListener('mouseleave', ocultar);
  canvas.addEventListener('pointerleave', ocultar);
  canvas.addEventListener('blur', ocultar);
  return c;
}
// Cambio de tema inmediato: re-colorea las gráficas sin volver a consultar datos
export function restyleCharts() {
  const muted = cssVar('--muted'), line = cssVar('--line'), text = cssVar('--text'), card = cssVar('--card') || '#ffffff';
  charts.forEach((c) => {
    try {
      const o = c.options;
      if (o.plugins?.legend?.labels) o.plugins.legend.labels.color = text;
      c.data.datasets.forEach((d) => {
        aplicarColores(d);
        if (!d._bordeTarjeta) return;
        if (['pie', 'doughnut'].includes(c.config.type)) d.borderColor = card; else d.pointBorderColor = card;
      });
      for (const s of Object.values(o.scales || {})) {
        if (s.ticks) s.ticks.color = muted;
        if (s.grid) s.grid.color = line;
      }
      c.update('none');
    } catch { /* gráfica ya destruida */ }
  });
}
export function destroyCharts() { charts.forEach((c) => { try { c.destroy(); } catch { /* ya destruida */ } }); charts.clear(); }

// ---------- Gráfica ampliada ----------
// Al tocar o hacer clic en una gráfica se abre sola, en grande, sobre un fondo
// limpio (útil para tomar captura) y con la opción de guardarla como imagen.
let zoomAbierto = null;
export function ampliarGrafica(canvas) {
  const orig = window.Chart?.getChart(canvas);
  const config = orig && chartConfigs.get(orig);
  if (!config || zoomAbierto) return;
  const card = canvas.closest('.card');
  const titulo = card?.querySelector('.chart-head h3, .card-head h3')?.textContent.trim() || canvas.getAttribute('aria-label') || 'Gráfica';
  const sub = card?.querySelector('.chart-head p, .card-head p')?.textContent.trim() || '';
  const total = card?.querySelector('.chart-total')?.textContent.replace(/\s+/g, ' ').trim() || '';
  const ov = document.createElement('div');
  ov.className = 'chart-zoom';
  ov.setAttribute('role', 'dialog');
  ov.setAttribute('aria-modal', 'true');
  ov.setAttribute('aria-label', titulo);
  ov.innerHTML = `
    <div class="cz-card">
      <div class="cz-head">
        <div class="cz-tit"><h2>${esc(titulo)}</h2>${sub ? `<p>${esc(sub)}</p>` : ''}${total ? `<span class="chart-total">${esc(total)}</span>` : ''}</div>
        <div class="cz-acts">
          <button type="button" class="btn secondary" data-cz="png">${icon('image-down')} <span>Guardar imagen</span></button>
          <button type="button" class="icon-btn" data-cz="cerrar" aria-label="Cerrar" title="Cerrar (Esc)">${icon('x')}</button>
        </div>
      </div>
      <div class="cz-body"><canvas data-zoom="1" role="img" aria-label="${esc(titulo)}"></canvas></div>
      <div class="cz-pie"><span>Pruebas industriales · Pet's Table</span><span class="cz-girar">${icon('smartphone')} Gira el teléfono para verla más grande</span></div>
    </div>`;
  document.body.appendChild(ov);
  document.body.classList.add('modal-open');
  refreshIcons();
  const cfg = { ...config, data: JSON.parse(JSON.stringify(config.data)) };
  cfg.data.datasets?.forEach((d, i) => {
    const o = config.data.datasets[i];
    if (o?._colores) d._colores = o._colores;
    if (d.maxBarThickness) d.maxBarThickness = Math.round(d.maxBarThickness * 1.8);
  });
  const zc = makeChart(ov.querySelector('canvas'), cfg);
  charts.delete(zc);
  // Letras más grandes en la vista ampliada
  try {
    for (const s of Object.values(zc.options.scales || {})) if (s.ticks) s.ticks.font = { size: 14, weight: '600' };
    if (zc.options.plugins?.legend?.labels) zc.options.plugins.legend.labels.font = { size: 14 };
    zc.update('none');
  } catch { /* opciones no disponibles */ }
  const cerrar = () => {
    document.removeEventListener('keydown', onKey);
    try { zc.destroy(); } catch { /* ya destruida */ }
    ov.remove();
    if (!document.querySelector('.modal')) document.body.classList.remove('modal-open');
    zoomAbierto = null;
    canvas.focus?.();
  };
  const onKey = (e) => { if (e.key === 'Escape') cerrar(); };
  document.addEventListener('keydown', onKey);
  ov.addEventListener('click', (e) => {
    if (e.target === ov || e.target.closest('[data-cz="cerrar"]')) cerrar();
    else if (e.target.closest('[data-cz="png"]')) guardarGrafica(zc, titulo, [sub, total].filter(Boolean).join(' · '));
  });
  zoomAbierto = cerrar;
  ov.querySelector('[data-cz="cerrar"]').focus();
}
window.addEventListener('hashchange', () => zoomAbierto?.());

// Imagen PNG con título, subtítulo y la gráfica sobre fondo sólido
async function guardarGrafica(chart, titulo, sub) {
  const src = chart.canvas, k = 2;
  const w = src.width, h = src.height, pad = 24 * k, top = (sub ? 78 : 56) * k;
  const c = document.createElement('canvas');
  c.width = w + pad * 2; c.height = h + top + pad;
  const ctx = c.getContext('2d');
  ctx.fillStyle = cssVar('--card') || '#FFFFFF';
  ctx.fillRect(0, 0, c.width, c.height);
  ctx.fillStyle = cssVar('--text') || '#172431';
  ctx.font = `800 ${22 * k}px Inter, Segoe UI, system-ui, sans-serif`;
  ctx.textBaseline = 'top';
  ctx.fillText(titulo, pad, pad);
  if (sub) {
    ctx.fillStyle = cssVar('--muted') || '#687B8C';
    ctx.font = `500 ${14 * k}px Inter, Segoe UI, system-ui, sans-serif`;
    ctx.fillText(sub, pad, pad + 32 * k);
  }
  ctx.drawImage(src, pad, top);
  const nombre = `${titulo.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/gi, '-').replace(/^-|-$/g, '').toLowerCase() || 'grafica'}.png`;
  const blob = await new Promise((r) => c.toBlob(r, 'image/png'));
  if (!blob) { toast('No se pudo generar la imagen.', 'error'); return; }
  const file = new File([blob], nombre, { type: 'image/png' });
  // En celulares: compartir o guardar en fotos; en computadora: descarga directa
  if (matchMedia('(pointer: coarse)').matches && navigator.canShare?.({ files: [file] })) {
    try { await navigator.share({ files: [file], title: titulo }); return; } catch (err) { if (err?.name === 'AbortError') return; }
  }
  const url = URL.createObjectURL(blob);
  const a = Object.assign(document.createElement('a'), { href: url, download: nombre });
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 4000);
  toast('Imagen de la gráfica guardada.', 'success');
}
// Clic o Enter sobre una gráfica: se abre ampliada
document.addEventListener('click', (e) => {
  const cv = e.target.closest('.chart-box')?.querySelector('canvas');
  if (cv && !e.target.closest('.chart-zoom')) ampliarGrafica(cv);
});
document.addEventListener('keydown', (e) => {
  if (e.key !== 'Enter' || !e.target.matches?.('.chart-box')) return;
  const cv = e.target.querySelector('canvas');
  if (cv) ampliarGrafica(cv);
});

// ---------- Catálogos en caché ligera ----------
// Definición de lectura de cada catálogo (tabla, columnas y orden)
const CATS = {
  areas: ['areas_prubind', 'id, nombre, activo', 'nombre'],
  puestos: ['puestos_prubind', 'id, nombre, activo', 'nombre'],
  unidades: ['unidades_prubind', 'id, simbolo, nombre, activo', 'simbolo'],
  tipos: ['tipos_prueba_prubind', 'codigo, nombre, descripcion, orden, activo, campos_registro, secciones_prep, ejecucion_form, requiere_aut_ejecucion, equipo_id', 'orden'],
  objetivos: ['objetivos_prubind', 'id, tipo, nombre, orden, activo', 'orden'],
  productos: ['productos_prubind', 'id, codigo, nombre, activo', 'nombre'],
  materias: ['materias_primas_prubind', 'id, codigo, nombre, categoria, unidad_id, activo', 'nombre'],
  proveedores: ['proveedores_prubind', 'id, nombre, contacto, activo', 'nombre'],
  equipos: ['equipos_prubind', 'id, codigo, nombre, area_id, activo', 'nombre'],
  parametros: ['equipo_parametros_prubind', 'id, equipo_id, nombre, unidad_id, minimo, maximo, referencia, activo', 'nombre'],
  metodos: ['metodos_prubind', 'id, codigo, nombre, categoria, area, tipo_resultado, unidad_id, diluciones, horas_lectura, tecnica, base_expresion, procedimiento_ref, opciones, revisa_puesto_id, activo', 'codigo'],
  motivos: ['motivos_prubind', 'id, tipo, nombre, activo', 'nombre'],
  evidencias: ['tipos_evidencia_prubind', 'id, nombre, activo', 'nombre'],
  usuarios: ['usuarios_prubind', 'id, nombre, email, puesto_id, foto_url, activo', 'nombre'],
  versiones: ['receta_versiones_prubind', 'id, receta_id, version, estado, receta:recetas_prubind(nombre, producto_id)', 'version'],
};
const catCache = new Map();
export async function getCat(nombre, { force = false, activos = false } = {}) {
  if (!catCache.has(nombre) || force) {
    const [t, cols, ord] = CATS[nombre];
    const { data, error } = await sb.from(t).select(cols).order(ord);
    if (error) throw error;
    catCache.set(nombre, data);
  }
  const rows = catCache.get(nombre);
  return activos ? rows.filter((r) => r.activo !== false) : rows;
}
export function invalidateCat(...nombres) { (nombres.length ? nombres : [...catCache.keys()]).forEach((n) => catCache.delete(n)); }
export const getAreas = ({ force = false, soloActivas = false } = {}) => getCat('areas', { force, activos: soloActivas });
export const invalidateAreas = () => invalidateCat('areas');
export const getTipos = ({ force = false } = {}) => getCat('tipos', { force });
export const invalidateTipos = () => invalidateCat('tipos');
// <option>s de un catálogo, conservando el valor actual aunque esté inactivo
export function opciones(rows, actual, { label = (r) => r.nombre, value = (r) => r.id, vacio = 'Selecciona…' } = {}) {
  return (vacio !== null ? `<option value="">${esc(vacio)}</option>` : '') + rows
    .filter((r) => r.activo !== false || value(r) === actual)
    .map((r) => `<option value="${esc(value(r))}" ${value(r) === actual ? 'selected' : ''}>${esc(label(r))}</option>`).join('');
}
export const unidadTxt = (uns, id) => uns.find((u) => u.id === id)?.simbolo || '';

// ---------- Fotos de usuario ----------
// Avatar con foto (si existe) y respaldo de iniciales cuando la imagen no carga
export function avatarHTML(nombre, fotoUrl, cls = '') {
  const ini = esc(initials(nombre));
  if (fotoUrl && /^https:\/\//.test(fotoUrl)) {
    return `<span class="avatar has-img ${cls}" data-ini="${ini}"><img src="${esc(fotoUrl)}" alt="" loading="lazy" referrerpolicy="no-referrer"></span>`;
  }
  return `<span class="avatar ${cls}">${ini}</span>`;
}
document.addEventListener('error', (e) => {
  const img = e.target;
  if (img?.tagName === 'IMG' && img.parentElement?.classList.contains('avatar')) {
    const span = img.parentElement; span.classList.remove('has-img'); span.textContent = span.dataset.ini || '?';
  }
}, true);

export const FOTO_MAX_MB = 5;
// Recorta al centro, reduce a 320×320 y convierte a JPEG antes de subir (fotos ligeras)
export async function prepararFoto(file) {
  if (!/^image\/(jpeg|png|webp)$/.test(file.type)) throw new Error('La foto debe ser JPG, PNG o WEBP.');
  if (file.size > FOTO_MAX_MB * 1024 * 1024) throw new Error(`La foto no debe superar ${FOTO_MAX_MB} MB.`);
  const url = URL.createObjectURL(file);
  try {
    const img = await new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = () => rej(new Error('No se pudo leer la imagen.')); i.src = url; });
    const s = Math.min(img.naturalWidth, img.naturalHeight), size = 320;
    const c = document.createElement('canvas'); c.width = size; c.height = size;
    const ctx = c.getContext('2d'); ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, size, size);
    ctx.drawImage(img, (img.naturalWidth - s) / 2, (img.naturalHeight - s) / 2, s, s, 0, 0, size, size);
    return await new Promise((res, rej) => c.toBlob((b) => (b ? res(b) : rej(new Error('No se pudo procesar la imagen.'))), 'image/jpeg', 0.86));
  } finally { URL.revokeObjectURL(url); }
}
const uid = () => (crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`);
export async function subirFoto(blob) {
  const path = `${uid()}.jpg`;
  const { error } = await sb.storage.from('avatares_prubind').upload(path, blob, { contentType: 'image/jpeg', upsert: false, cacheControl: '31536000' });
  if (error) throw error;
  return sb.storage.from('avatares_prubind').getPublicUrl(path).data.publicUrl;
}
// Borra una foto anterior solo si pertenece al bucket propio (nunca toca "avatares")
export async function borrarFotoPropia(url) {
  const m = /\/storage\/v1\/object\/public\/avatares_prubind\/(.+)$/.exec(url || '');
  if (m) await sb.storage.from('avatares_prubind').remove([decodeURIComponent(m[1])]).catch(() => {});
}

// ---------- Adjuntos de pruebas (bucket privado) ----------
export const ADJ_MAX_MB = 10;
export const ADJ_ACCEPT = '.pdf,.jpg,.jpeg,.png,.webp,.csv,.txt,.xlsx,.xls,.docx,.doc';
export function nombreSeguro(n) {
  const base = String(n || 'archivo').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^A-Za-z0-9._-]+/g, '_').replace(/^_+|_+$/g, '');
  return (base || 'archivo').slice(-80);
}
export function rutaAdjunto(pruebaId, nombre) { return `${pruebaId}/${uid().slice(0, 8)}-${nombreSeguro(nombre)}`; }
export const fmtBytes = (b) => (b == null ? '—' : b < 1024 ? `${b} B` : b < 1048576 ? `${(b / 1024).toFixed(0)} KB` : `${(b / 1048576).toFixed(1)} MB`);

// ---------- Menús desplegables con el estilo del sistema ----------
// Reemplaza visualmente <select> y <input list> por un menú propio. El control
// original se conserva (oculto) para validación, FormData y eventos "change".
const CHEVRON = '<svg class="cs-chev" viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>';
const CHECK = '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 6 9 17l-5-5"/></svg>';
let csAbierto = null;
function csCerrar(enfocar = false) {
  if (!csAbierto) return;
  const { panel, anchor } = csAbierto;
  panel.remove(); anchor.setAttribute('aria-expanded', 'false');
  csAbierto = null;
  if (enfocar) anchor.focus();
}
function csUbicar(panel, anchor) {
  const r = anchor.getBoundingClientRect();
  const alto = Math.min(panel.scrollHeight, 300);
  const vh = window.visualViewport?.height || innerHeight;   // sin contar el teclado del celular
  const abajo = vh - r.bottom;
  panel.style.width = `${Math.max(r.width, 200)}px`;
  panel.style.left = `${Math.max(8, Math.min(r.left, innerWidth - 8 - Math.max(r.width, 200)))}px`;
  if (abajo < alto + 12 && r.top > abajo) { panel.style.top = ''; panel.style.bottom = `${innerHeight - r.top + 6}px`; }
  else { panel.style.bottom = ''; panel.style.top = `${r.bottom + 6}px`; }
}
// items: [{ value, label, disabled, selected }]; onPick(value)
function csAbrir(anchor, items, onPick) {
  csCerrar();
  if (!items.length) return;
  const panel = document.createElement('div');
  panel.className = 'cs-panel'; panel.setAttribute('role', 'listbox');
  // Menús largos: cuadro de búsqueda para filtrar opciones
  const conBusqueda = anchor.tagName !== 'INPUT' && items.length > 8;
  panel.innerHTML = (conBusqueda ? '<div class="cs-search"><input type="search" placeholder="Buscar…" aria-label="Buscar opción" autocomplete="off"></div>' : '')
    + items.map((it, i) => `<div class="cs-opt ${it.selected ? 'sel' : ''} ${it.disabled ? 'dis' : ''} ${it.ph ? 'ph' : ''}" role="option" data-i="${i}" aria-selected="${it.selected ? 'true' : 'false'}" ${it.disabled ? 'aria-disabled="true"' : ''}>
      <span>${esc(it.label)}</span>${it.selected ? CHECK : ''}</div>`).join('');
  document.body.appendChild(panel);
  csUbicar(panel, anchor);
  anchor.setAttribute('aria-expanded', 'true');
  let hl = Math.max(0, items.findIndex((x) => x.selected));
  const visibles = () => [...panel.querySelectorAll('.cs-opt')].filter((o) => !o.classList.contains('hidden')).map((o) => Number(o.dataset.i));
  const pintar = () => {
    panel.querySelectorAll('.cs-opt').forEach((o) => o.classList.toggle('hl', Number(o.dataset.i) === hl));
    panel.querySelector('.cs-opt.hl')?.scrollIntoView({ block: 'nearest' });
  };
  pintar();
  const elegir = (i) => { const it = items[i]; if (!it || it.disabled) return; csCerrar(true); onPick(it.value); };
  panel.addEventListener('mousedown', (e) => { if (!e.target.closest('.cs-search')) e.preventDefault(); });
  panel.addEventListener('click', (e) => { const o = e.target.closest('.cs-opt'); if (o) elegir(Number(o.dataset.i)); });
  const buscador = panel.querySelector('.cs-search input');
  if (buscador) {
    const norm = (s) => s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
    buscador.addEventListener('input', () => {
      const q = norm(buscador.value.trim());
      panel.querySelectorAll('.cs-opt').forEach((o) => o.classList.toggle('hidden', !!q && !norm(items[Number(o.dataset.i)].label).includes(q)));
      const v = visibles(); hl = v.includes(hl) ? hl : (v[0] ?? -1); pintar();
    });
    buscador.addEventListener('keydown', (e) => csAbierto?.key(e));
    // En celular y tableta no se enfoca solo: abrir el teclado redimensiona la pantalla y cerraba el menú
    if (!tactil()) setTimeout(() => buscador.focus(), 0);
  }
  csAbierto = {
    panel, anchor,
    key: (e) => {
      if (buscador && ['ArrowDown', 'ArrowUp'].includes(e.key)) {
        e.preventDefault();
        const v = visibles(); if (!v.length) return;
        const pos = v.indexOf(hl);
        hl = e.key === 'ArrowDown' ? v[Math.min(v.length - 1, pos + 1)] : v[Math.max(0, pos - 1)];
        pintar(); return;
      }
      if (buscador && e.key.length === 1) { if (e.target !== buscador) buscador.focus(); return; }
      if (e.key === 'ArrowDown') { e.preventDefault(); do { hl = Math.min(items.length - 1, hl + 1); } while (items[hl]?.disabled && hl < items.length - 1); pintar(); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); do { hl = Math.max(0, hl - 1); } while (items[hl]?.disabled && hl > 0); pintar(); }
      else if (e.key === 'Enter') { e.preventDefault(); elegir(hl); }
      else if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); csCerrar(true); }
      else if (e.key === 'Tab') csCerrar();
      else if (e.key.length === 1 && /\S/.test(e.key) && anchor.tagName !== 'INPUT') {
        const k = e.key.toLowerCase();
        const j = items.findIndex((it, i) => i > hl && !it.disabled && it.label.toLowerCase().startsWith(k));
        const j2 = j >= 0 ? j : items.findIndex((it) => !it.disabled && it.label.toLowerCase().startsWith(k));
        if (j2 >= 0) { hl = j2; pintar(); }
      }
    },
  };
}
document.addEventListener('mousedown', (e) => {
  if (csAbierto && !csAbierto.panel.contains(e.target) && !csAbierto.anchor.contains(e.target)) csCerrar();
}, true);
// Mientras se escribe en el menú (o en un campo con sugerencias) el teclado del celular desplaza y
// redimensiona la pantalla: en ese caso el menú se reacomoda en lugar de cerrarse
const tactil = () => matchMedia('(pointer: coarse)').matches;
const csEscribiendo = () => csAbierto && (csAbierto.panel.contains(document.activeElement) || document.activeElement === csAbierto.anchor);
document.addEventListener('scroll', (e) => {
  if (!csAbierto || csAbierto.panel.contains(e.target)) return;
  if (csEscribiendo()) csUbicar(csAbierto.panel, csAbierto.anchor); else csCerrar();
}, true);
window.addEventListener('resize', () => { if (csEscribiendo()) csUbicar(csAbierto.panel, csAbierto.anchor); else csCerrar(); });
window.visualViewport?.addEventListener('resize', () => { if (csEscribiendo()) csUbicar(csAbierto.panel, csAbierto.anchor); });
document.addEventListener('keydown', (e) => { if (csAbierto && (e.target === csAbierto.anchor)) csAbierto.key(e); }, true);

const valueDesc = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value');
const indexDesc = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'selectedIndex');
function mejorarSelect(sel) {
  if (sel._cs || sel.multiple || sel.size > 1 || 'native' in sel.dataset) return;
  const wrap = document.createElement('div');
  wrap.className = 'cs';
  if (sel.style.cssText) { wrap.style.cssText = sel.style.cssText; sel.style.cssText = ''; }
  sel.parentNode.insertBefore(wrap, sel);
  wrap.appendChild(sel);
  sel.classList.add('cs-native'); sel.tabIndex = -1; sel.setAttribute('aria-hidden', 'true');
  const btn = document.createElement('button');
  btn.type = 'button'; btn.className = 'cs-btn';
  btn.setAttribute('aria-haspopup', 'listbox'); btn.setAttribute('aria-expanded', 'false');
  const lab = sel.id ? document.querySelector(`label[for="${CSS.escape(sel.id)}"]`) : null;
  btn.setAttribute('aria-label', sel.getAttribute('aria-label') || lab?.textContent.replace('*', '').trim() || 'Seleccionar');
  wrap.appendChild(btn);
  const sync = () => {
    const o = sel.options[sel.selectedIndex];
    btn.innerHTML = `<span class="cs-val ${!sel.value ? 'ph' : ''}">${esc(o ? o.textContent : '—')}</span>${CHEVRON}`;
    btn.disabled = sel.disabled;
  };
  // Reflejar cambios hechos por código (value / selectedIndex / opciones / disabled)
  Object.defineProperty(sel, 'value', { configurable: true, get() { return valueDesc.get.call(this); }, set(v) { valueDesc.set.call(this, v); sync(); } });
  Object.defineProperty(sel, 'selectedIndex', { configurable: true, get() { return indexDesc.get.call(this); }, set(v) { indexDesc.set.call(this, v); sync(); } });
  new MutationObserver(sync).observe(sel, { childList: true, subtree: true, attributes: true, attributeFilter: ['disabled', 'selected'] });
  sel.addEventListener('change', sync);
  btn.addEventListener('click', () => {
    if (csAbierto?.anchor === btn) { csCerrar(); return; }
    const items = [...sel.options].filter((o) => !o.hidden).map((o) => ({
      value: o.value, label: o.textContent, disabled: o.disabled, selected: o.index === sel.selectedIndex, ph: o.value === '',
    }));
    csAbrir(btn, items, (v) => {
      valueDesc.set.call(sel, v); sync();
      sel.dispatchEvent(new Event('input', { bubbles: true }));
      sel.dispatchEvent(new Event('change', { bubbles: true }));
    });
  });
  btn.addEventListener('keydown', (e) => {
    if (!csAbierto && ['ArrowDown', 'ArrowUp', 'Enter', ' '].includes(e.key)) { e.preventDefault(); btn.click(); }
  });
  sel._cs = { btn, sync };
  sync();
}
function mejorarDatalist(inp) {
  if (inp._cs) return;
  const dl = document.getElementById(inp.getAttribute('list'));
  if (!dl) return;
  inp.removeAttribute('list');
  inp.setAttribute('autocomplete', 'off');
  inp.setAttribute('aria-autocomplete', 'list'); inp.setAttribute('aria-expanded', 'false');
  inp.parentElement.classList.add('cs-dl');
  const mostrar = () => {
    const q = inp.value.trim().toLowerCase();
    const items = [...dl.options].map((o) => ({ value: o.value, label: o.label && o.label !== o.value ? `${o.value} · ${o.label}` : o.value }))
      .filter((it) => !q || it.label.toLowerCase().includes(q));
    if (!items.length || (items.length === 1 && items[0].value.toLowerCase() === q)) { if (csAbierto?.anchor === inp) csCerrar(); return; }
    csAbrir(inp, items.slice(0, 50), (v) => {
      inp.value = v;
      inp.dispatchEvent(new Event('input', { bubbles: true }));
      inp.dispatchEvent(new Event('change', { bubbles: true }));
      setTimeout(() => csCerrar(), 0);
    });
  };
  inp.addEventListener('focus', mostrar);
  inp.addEventListener('input', (e) => { if (e.isTrusted) mostrar(); });
  inp.addEventListener('keydown', (e) => { if (!csAbierto && e.key === 'ArrowDown') { e.preventDefault(); mostrar(); } });
  inp._cs = { mostrar };
}
export function mejorarControles(root = document) {
  root.querySelectorAll?.('select').forEach(mejorarSelect);
  root.querySelectorAll?.('input[list]').forEach(mejorarDatalist);
}
new MutationObserver((muts) => {
  for (const m of muts) for (const n of m.addedNodes) {
    if (n.nodeType !== 1) continue;
    if (n.tagName === 'SELECT') mejorarSelect(n);
    else if (n.tagName === 'INPUT' && n.hasAttribute('list')) mejorarDatalist(n);
    else mejorarControles(n);
  }
}).observe(document.documentElement, { childList: true, subtree: true });
// Un clic en la etiqueta de un select mejorado enfoca su botón
document.addEventListener('click', (e) => {
  const lab = e.target.closest('label[for]');
  const c = lab && document.getElementById(lab.htmlFor);
  if (c?._cs?.btn) { e.preventDefault(); c._cs.btn.focus(); }
});

// ---------- Apartados contraíbles (.plegable): tocar el encabezado abre o cierra ----------
document.addEventListener('click', (e) => {
  const head = e.target.closest('.plegable > .card-head');
  if (!head || e.target.closest('button, a, input, select, textarea, label')) return;
  const card = head.parentElement;
  card.classList.toggle('colapsada');
  head.setAttribute('aria-expanded', String(!card.classList.contains('colapsada')));
});

// ---------- Avisos (notificaciones push) ----------
// Se envían en segundo plano; si fallan no afectan la operación de la prueba.
// La Edge Function valida que el evento sea real y elige a quién avisar.
export function avisar(evento, pruebaId, extra = {}) {
  try { sb.functions.invoke('notificar_prubind', { body: { ...extra, accion: 'aviso', evento, prueba_id: pruebaId } }).catch(() => {}); } catch { /* sin conexión */ }
}
function b64uToUint8(s) {
  const pad = '='.repeat((4 - (s.length % 4)) % 4);
  const raw = atob((s + pad).replace(/-/g, '+').replace(/_/g, '/'));
  return Uint8Array.from(raw, (c) => c.charCodeAt(0));
}
// Registro del service worker de esta app (alcance / sola, /pruebas-industriales/ en el portal). getRegistration
// devolvería el del portal si el de la app aún no existe, por eso se compara el alcance.
export async function registroPropio() {
  const reg = await navigator.serviceWorker.getRegistration(BASE);
  return reg && reg.scope === location.origin + BASE ? reg : null;
}
export const push = {
  soportado: () => 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window && window.isSecureContext,
  esIOS: () => /iphone|ipad|ipod/i.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1),
  // App instalada: ventana propia, pantalla completa o sin barra de título (computadora)
  instalada: () => window.matchMedia('(display-mode: standalone), (display-mode: fullscreen), (display-mode: window-controls-overlay)').matches || window.navigator.standalone === true,
  async suscripcion() {
    if (!push.soportado()) return null;
    const reg = await registroPropio();
    return reg ? reg.pushManager.getSubscription() : null;
  },
  // 'no-soportado' | 'instalar' (iOS sin instalar) | 'bloqueado' | 'activo' | 'inactivo'
  async estado() {
    if (push.esIOS() && !push.instalada()) return 'instalar';
    if (!push.soportado()) return 'no-soportado';
    if (Notification.permission === 'denied') return 'bloqueado';
    return (await push.suscripcion()) && Notification.permission === 'granted' ? 'activo' : 'inactivo';
  },
  // Vincula la suscripción de este dispositivo a quien tiene la sesión (aunque antes fuera de otra persona)
  async guardar(sub) {
    const j = sub.toJSON();
    const { error } = await sb.rpc('prubind_vincular_push', {
      p_endpoint: j.endpoint, p_p256dh: j.keys.p256dh, p_auth: j.keys.auth, p_dispositivo: navigator.userAgent.slice(0, 200),
    });
    if (error) throw error;
  },
  async activar() {
    if (!push.soportado()) throw new Error('Este navegador no admite notificaciones.');
    const perm = await Notification.requestPermission();
    if (perm !== 'granted') throw new Error('No se concedió el permiso de notificaciones.');
    const reg = await navigator.serviceWorker.register('sw.js', { scope: './' });
    await navigator.serviceWorker.ready;
    let { data: pub } = await sb.rpc('prubind_vapid_publica');
    if (!pub) {
      const r = await sb.functions.invoke('notificar_prubind', { body: { accion: 'init' } });
      pub = r.data?.publica;
    }
    if (!pub) throw new Error('No se pudo obtener la clave de notificaciones. Intenta más tarde.');
    let sub = await reg.pushManager.getSubscription();
    if (!sub) sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: b64uToUint8(pub) });
    await push.guardar(sub);
  },
  async desactivar() {
    const sub = await push.suscripcion();
    if (sub) {
      await sb.from('push_subs_prubind').delete().eq('endpoint', sub.endpoint);
      await sub.unsubscribe().catch(() => {});
    }
  },
  // Al cerrar sesión: el dispositivo deja de recibir avisos de esa persona, pero conserva
  // el permiso y la suscripción para no volver a pedirlos al siguiente inicio de sesión
  async desvincular() {
    const sub = await push.suscripcion();
    if (sub) await sb.from('push_subs_prubind').delete().eq('endpoint', sub.endpoint);
  },
  // Al iniciar sesión: si el dispositivo ya dio permiso, vincula (o recrea) la suscripción sin preguntar de nuevo
  async sincronizar() {
    try {
      if (!push.soportado() || Notification.permission !== 'granted') return;
      const sub = await push.suscripcion();
      if (sub) await push.guardar(sub); else await push.activar();
    } catch { /* silencioso */ }
  },
};

export function navigate(hash) { if (location.hash !== hash) location.hash = hash; else window.dispatchEvent(new HashChangeEvent('hashchange')); }
