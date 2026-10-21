// =====================================================================
// Campana de pendientes (encabezado): cuántas acciones te tocan y acceso
// directo a cada una, pensado sobre todo para el celular. Si el dispositivo
// no tiene activadas las notificaciones, ofrece activarlas ahí mismo.
// También pone el número en el ícono de la app instalada (si el sistema lo admite).
// =====================================================================
import { sb, state, esc, icon, refreshIcons, toast, errMsg, navigate, push, prioPill, AREAS, debounce } from '../core.js';
import { ACC, TAB_ACCION } from './dashboard.js';

let PEND = [], abierta = false, cargando = false;

export function montarCampana() {
  if (document.getElementById('bell-btn')) { actualizarCampana(); return; }
  const acciones = document.querySelector('.header-actions');
  acciones.insertAdjacentHTML('afterbegin', `<button class="bell-btn" id="bell-btn" aria-label="Tus pendientes" aria-haspopup="dialog" aria-expanded="false">${icon('bell')}<span class="bell-n hidden" id="bell-n"></span></button>`);
  document.body.insertAdjacentHTML('beforeend', `<div class="bell-backdrop hidden" id="bell-bd"></div>
    <section class="bell-panel hidden" id="bell-panel" role="dialog" aria-label="Tus pendientes"></section>`);
  refreshIcons();
  document.getElementById('bell-btn').addEventListener('click', () => (abierta ? cerrar() : abrir()));
  document.getElementById('bell-bd').addEventListener('click', cerrar);
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && abierta) cerrar(); });
  document.getElementById('bell-panel').addEventListener('click', async (e) => {
    const go = e.target.closest('[data-go]');
    if (go) { cerrar(); navigate(go.dataset.go); return; }
    const b = e.target.closest('[data-bell="notif"]');
    if (b) {
      b.disabled = true;
      try { await push.activar(); toast('Notificaciones activadas en este dispositivo.', 'success'); pintar(); }
      catch (err) { toast(errMsg(err), 'error'); b.disabled = false; }
    }
  });
  const refrescar = debounce(actualizarCampana, 600);
  window.addEventListener('hashchange', refrescar);
  document.addEventListener('prubind:cambio', refrescar);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) refrescar(); });
  setInterval(actualizarCampana, 2 * 60 * 1000);
  actualizarCampana();
}

export async function actualizarCampana() {
  if (!state.profile || cargando) return;
  cargando = true;
  try {
    const { data, error } = await sb.rpc('prubind_mis_pendientes');
    if (error) throw error;
    PEND = data || [];
    const n = PEND.length, el = document.getElementById('bell-n');
    if (el) { el.textContent = n > 99 ? '99+' : String(n); el.classList.toggle('hidden', !n); }
    document.getElementById('bell-btn')?.classList.toggle('has', n > 0);
    try { if ('setAppBadge' in navigator) (n ? navigator.setAppBadge(n) : navigator.clearAppBadge()).catch(() => {}); } catch { /* no disponible */ }
    if (abierta) pintar();
  } catch { /* sin conexión: se reintenta en el siguiente ciclo */ } finally { cargando = false; }
}

function abrir() {
  abierta = true;
  document.getElementById('bell-panel').classList.remove('hidden');
  document.getElementById('bell-bd').classList.remove('hidden');
  document.getElementById('bell-btn').setAttribute('aria-expanded', 'true');
  document.body.classList.add('bell-open');
  pintar(); actualizarCampana();
}
function cerrar() {
  abierta = false;
  document.getElementById('bell-panel')?.classList.add('hidden');
  document.getElementById('bell-bd')?.classList.add('hidden');
  document.getElementById('bell-btn')?.setAttribute('aria-expanded', 'false');
  document.body.classList.remove('bell-open');
}

async function pintar() {
  const panel = document.getElementById('bell-panel');
  if (!panel) return;
  const porPrueba = new Map();
  PEND.forEach((p) => { if (!porPrueba.has(p.prueba_id)) porPrueba.set(p.prueba_id, { ...p, acciones: [] }); porPrueba.get(p.prueba_id).acciones.push(p); });
  const orden = { urgente: 0, alta: 1, normal: 2 };
  const pruebas = [...porPrueba.values()].sort((a, b) => (orden[a.prioridad] ?? 3) - (orden[b.prioridad] ?? 3) || String(a.folio).localeCompare(String(b.folio)));
  const est = await push.estado().catch(() => 'no-soportado');
  const notif = est === 'inactivo'
    ? `<div class="bell-notif">${icon('bell-ring')}<span><b>Activa las notificaciones</b>Te avisaremos cuando te toque hacer algo.</span><button class="btn primary sm" data-bell="notif">Activar</button></div>`
    : est === 'instalar' ? `<div class="bell-notif">${icon('smartphone')}<span><b>Instala la app para recibir avisos</b>En iPhone: Compartir → “Agregar a pantalla de inicio”.</span></div>` : '';
  panel.innerHTML = `<div class="bell-head"><div><b>Tus pendientes</b><span>${PEND.length ? `${PEND.length} acción(es) en ${porPrueba.size} prueba(s)` : 'Nada pendiente por ahora'}</span></div>
      <button class="icon-btn" data-go="#/panel" aria-label="Ir al panel">${icon('layout-dashboard')}</button></div>
    ${notif}
    <div class="bell-list">${pruebas.length ? pruebas.map((p) => `<article class="bell-item prio-${esc(p.prioridad || 'normal')}">
        <div class="bi-top"><span class="pc-folio mono">${esc(p.folio)}</span>${p.prioridad !== 'normal' ? prioPill(p.prioridad) : ''}</div>
        <b class="bi-title">${esc(p.cambio)}</b>
        ${p.acciones.map((x) => `<button type="button" class="pc-act acc-${x.accion}" data-go="#/pruebas?id=${esc(p.prueba_id)}&tab=${TAB_ACCION[x.accion] || ''}">
          <span class="pa-ico">${icon(ACC[x.accion]?.[1] || 'dot')}</span><span class="pa-txt">${esc(ACC[x.accion]?.[0] || x.accion)}${x.area ? ` <em>· ${esc(AREAS[x.area]?.label || x.area)}</em>` : ''}</span>${icon('chevron-right')}</button>`).join('')}
      </article>`).join('')
      : `<div class="bell-empty">${icon('check-circle-2')}<b>Todo al día</b><span>Cuando una prueba requiera algo de ti, aparecerá aquí.</span></div>`}</div>`;
  refreshIcons();
}
