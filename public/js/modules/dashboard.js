// =====================================================================
// Panel: qué me toca (pendientes según mi autoridad), indicadores reales
// y gráficas. Cifras desde prubind_dashboard y prubind_mis_pendientes.
// =====================================================================
import {
  sb, state, esc, icon, refreshIcons, todayISO, addDays, fmtDateTime, fmtNum, pill, makeChart, destroyCharts,
  emptyState, errorState, navigate, monthShort, prefs, must, avatarHTML, estadoPill, ESTADOS_PRUEBA, ABIERTAS, CATEGORIAS, ACCIONES,
} from '../core.js';
import { openRegistro } from './pruebas.js';

let root, token = 0;
const TAB_ACCION = { definir: 'registro', capturar: 'proceso', evaluar: 'resultados', recomendar: 'recomendaciones', dictaminar: 'dictamen', cerrar: 'cierre', autorizar_implementacion: 'cierre' };
const ACC_TXT = { ...ACCIONES, definir: 'Definir parámetros de su área', capturar: 'Registrar durante el proceso', evaluar: 'Evaluar resultados (Cumple / No cumple)', recomendar: 'Registrar recomendación', dictaminar: 'Emitir dictamen' };
const ACC_ICO = { definir: 'list-plus', capturar: 'factory', evaluar: 'list-checks', recomendar: 'lightbulb', dictaminar: 'gavel', cerrar: 'archive', autorizar_implementacion: 'stamp' };

function periodRange(p, desde, hasta) {
  const hoy = todayISO();
  switch (p) {
    case '90': return [addDays(hoy, -89), hoy];
    case 'anio': return [`${hoy.slice(0, 4)}-01-01`, `${hoy.slice(0, 4)}-12-31`];
    case '12m': return [addDays(hoy, -364), hoy];
    case 'custom': return [desde, hasta];
    default: { const y = Number(hoy.slice(0, 4)), m = Number(hoy.slice(5, 7)); const last = new Date(Date.UTC(y, m, 0)).getUTCDate();
      return [`${hoy.slice(0, 7)}-01`, `${hoy.slice(0, 7)}-${String(last).padStart(2, '0')}`]; }
  }
}

export default {
  async render(el) {
    root = el;
    const per = prefs.get('prubind.dash.period') || 'anio';
    el.innerHTML = `
      <section class="page-intro">
        <div><span class="eyebrow">Panel general</span>
          <h1 class="hello">Hola, ${esc(state.profile.nombre.split(' ')[0])} <span class="paws" aria-hidden="true">${icon('paw-print')}${icon('paw-print')}</span></h1>
          <p>${state.isAdmin ? 'Administrador' : 'Usuario'} · lo que requiere tu intervención y el estado de las pruebas.</p></div>
        <div class="toolbar" style="margin:0">
          <select id="dash-period" aria-label="Periodo"><option value="mes">Mes en curso</option><option value="90">Últimos 90 días</option>
            <option value="anio">Año en curso</option><option value="12m">Últimos 12 meses</option><option value="custom">Personalizado</option></select>
          <span class="date-range hidden" id="dash-custom"><input type="date" id="dash-desde" aria-label="Desde"> a <input type="date" id="dash-hasta" aria-label="Hasta"></span>
        </div>
      </section>
      <div id="dash-body" class="dash"></div>`;
    const sel = el.querySelector('#dash-period'); sel.value = per;
    const [d0, d1] = periodRange('mes');
    el.querySelector('#dash-desde').value = d0; el.querySelector('#dash-hasta').value = d1;
    el.querySelector('#dash-custom').classList.toggle('hidden', per !== 'custom');
    sel.addEventListener('change', () => { prefs.set('prubind.dash.period', sel.value); el.querySelector('#dash-custom').classList.toggle('hidden', sel.value !== 'custom'); load(); });
    el.querySelectorAll('#dash-desde, #dash-hasta').forEach((i) => i.addEventListener('change', load));
    el.addEventListener('click', async (e) => {
      const a = e.target.closest('[data-dash]');
      if (!a) return;
      if (a.dataset.dash === 'retry') return load();
      if (a.dataset.dash === 'nueva') { const id = await openRegistro(); if (id) navigate(`#/pruebas?id=${id}`); return; }
      navigate(a.dataset.dash);
    });
    el.addEventListener('keydown', (e) => { if ((e.key === 'Enter' || e.key === ' ') && e.target.matches('[data-dash][role="link"]')) { e.preventDefault(); e.target.click(); } });
    await load();
  },
  destroy() { token++; root = null; },
};

async function load() {
  const t = ++token;
  const body = root?.querySelector('#dash-body');
  if (!body) return;
  const [desde, hasta] = periodRange(root.querySelector('#dash-period').value, root.querySelector('#dash-desde').value, root.querySelector('#dash-hasta').value);
  if (!desde || !hasta || hasta < desde) { body.innerHTML = emptyState({ ico: 'calendar-x', title: 'Periodo inválido', text: 'La fecha final debe ser igual o posterior a la inicial.' }); refreshIcons(); return; }
  if (!body.children.length) body.innerHTML = `<div class="grid grid-4">${'<div class="kpi"><div class="skeleton" style="width:60%"></div><div class="skeleton" style="height:30px;width:40%"></div></div>'.repeat(4)}</div>`;
  try {
    const res = await Promise.all([
      sb.rpc('prubind_dashboard', { p_desde: desde, p_hasta: hasta }),
      sb.rpc('prubind_mis_pendientes'),
      sb.from('v_seguimiento_prubind').select('id, prueba_id, tipo, texto, created_at, usuario, foto_url, folio').order('created_at', { ascending: false }).order('id', { ascending: false }).limit(8),
    ]);
    res.forEach(must);
    if (t !== token) return;
    const [k, pend, act] = res.map((r) => r.data);
    destroyCharts();
    body.innerHTML = kpisHTML(k) + pendientesHTML(pend) + chartsHTML(k) + actividadHTML(act) + accesoHTML();
    refreshIcons();
    drawCharts(k);
  } catch (err) {
    if (t !== token) return;
    console.error(err);
    body.innerHTML = errorState(err).replace('data-action="retry"', 'data-dash="retry"'); refreshIcons();
  }
}

const kpi = (cls, ico, label, value, desc, go = '') => `<div class="kpi ${cls} ${go ? 'clickable' : ''}" ${go ? `data-dash="${go}" role="link" tabindex="0"` : ''}>
  <div class="kpi-head"><span class="kpi-ico">${icon(ico)}</span><small>${esc(label)}</small></div><strong>${fmtNum(value)}</strong><span class="desc">${esc(desc)}</span></div>`;

function kpisHTML(k) {
  const a = k.actual || {};
  const abiertas = ABIERTAS.reduce((s, e) => s + (a[e] || 0), 0);
  const cerradas = k.cerradas_aprobadas + k.cerradas_rechazadas;
  return `<div class="grid grid-4">
    ${kpi('i-blue', 'flask-conical', 'Pruebas abiertas', abiertas, 'Sin cerrar ni cancelar (hoy)', '#/pruebas?estado=abiertas')}
    ${kpi('c2 i-amber', 'factory', 'En ejecución', a.en_ejecucion || 0, 'Produciendo o corriendo (hoy)', '#/pruebas?estado=en_ejecucion')}
    ${kpi('c3 i-violet', 'gavel', 'Pendientes de dictamen', a.pendiente_dictamen || 0, 'Evaluación completa (hoy)', '#/pruebas?estado=pendiente_dictamen')}
    ${kpi(k.urgentes_abiertas ? 'danger i-pink' : 'c4 i-pink', 'siren', 'Urgentes abiertas', k.urgentes_abiertas, cerradas ? `${k.cerradas_aprobadas} aprobada(s) y ${k.cerradas_rechazadas} rechazada(s) cerradas en el periodo` : 'Ninguna cerrada en el periodo')}
  </div>`;
}

function pendientesHTML(pend) {
  const porAccion = {};
  pend.forEach((p) => (porAccion[p.accion] ||= []).push(p));
  return `<section class="card mt"><div class="card-head center"><div><h3>Requieren tu intervención</h3><p>${pend.length ? `${pend.length} pendiente(s) según tu puesto y tu participación en cada prueba` : 'Según tu puesto y tu participación en cada prueba'}</p></div>
      <button class="btn primary" data-dash="nueva">${icon('flask-conical')} Nueva prueba</button></div>
    ${pend.length ? `<div class="pend-grid">${Object.entries(porAccion).map(([acc, items]) => `<div class="pend-col"><div class="pend-col-head"><span class="pend-ico">${icon(ACC_ICO[acc] || 'dot')}</span><b>${esc(ACC_TXT[acc] || acc)}</b><span class="pend-n">${items.length}</span></div>
      ${items.slice(0, 6).map((p) => `<button class="pend-row" data-dash="#/pruebas?id=${esc(p.prueba_id)}&tab=${TAB_ACCION[acc] || ''}"><b class="mono">${esc(p.folio)}</b><span>${esc(p.cambio)}</span><small>${esc(p.tipo_nombre)} · ${esc(ESTADOS_PRUEBA[p.estado]?.label || p.estado)}</small></button>`).join('')}
      ${items.length > 6 ? `<small class="hint">y ${items.length - 6} más…</small>` : ''}</div>`).join('')}</div>`
      : emptyState({ ico: 'check-circle-2', title: 'Sin pendientes', text: state.profile.puesto_id ? 'No tienes acciones pendientes en este momento.' : 'Tu usuario no tiene puesto asignado: solo verás pendientes de las pruebas que registres o en las que seas responsable.' })}
  </section>`;
}

const chartCard = (id, title, sub, cls = '') => `<div class="card"><div class="card-head center"><div><h3>${esc(title)}</h3>${sub ? `<p>${esc(sub)}</p>` : ''}</div></div><div class="chart-box ${cls}"><canvas id="${id}" role="img" aria-label="${esc(title)}"></canvas></div></div>`;
function chartsHTML(k) {
  const hayActual = Object.values(k.actual || {}).some((n) => n > 0);
  if (!k.registradas && !hayActual) return `<div class="card mt">${emptyState({ ico: 'bar-chart-3', title: 'Aún no hay pruebas', text: 'Las gráficas aparecerán al registrar pruebas.' })}</div>`;
  return `<div class="section-label">Indicadores</div>
    <div class="grid grid-main">${chartCard('ch-serie', 'Pruebas registradas y cerradas', k.por_mes ? 'Por mes, en el periodo' : 'Por día, en el periodo')}${chartCard('ch-estado', 'Estado actual de todas las pruebas', '')}</div>
    <div class="grid grid-2 mt">${chartCard('ch-tipo', 'Pruebas registradas por tipo', 'En el periodo', 'sm')}${(k.resultados_por_categoria || []).length ? chartCard('ch-res', 'Resultados por categoría', 'Capturados en el periodo', 'sm') : `<div class="card">${emptyState({ ico: 'microscope', title: 'Sin resultados en el periodo' })}</div>`}</div>`;
}

function actividadHTML(act) {
  const SEG = { nota: 'message-square', estado: 'flag', sistema: 'cpu' };
  return `<section class="card mt"><div class="card-head center"><div><h3>Actividad reciente</h3><p>Notas y eventos de seguimiento</p></div></div>
    ${act.length ? `<div class="list">${act.map((s) => `<button class="list-item" data-dash="#/pruebas?id=${esc(s.prueba_id)}&tab=seguimiento" style="text-align:left;cursor:pointer;color:inherit">
      ${s.tipo === 'nota' ? avatarHTML(s.usuario, s.foto_url, 'sm') : `<span class="tl-ico sm">${icon(SEG[s.tipo] || 'dot')}</span>`}
      <div class="li-main"><b>${esc(s.folio)} · ${esc(s.texto)}</b><span>${esc(s.usuario || 'Sistema')} · ${fmtDateTime(s.created_at)}</span></div></button>`).join('')}</div>`
      : emptyState({ ico: 'history', title: 'Sin actividad' })}</section>`;
}

function accesoHTML() {
  const p = state.profile, u = state.session?.user;
  const acc = [...new Set((p.autoridades || []).map((a) => ACCIONES[a.accion]).filter(Boolean))];
  return `<section class="access-card mt" aria-label="Acceso autorizado">
    <div class="access-photo">${avatarHTML(p.nombre, p.foto_url, 'xl')}<span class="access-check">${icon('badge-check')}</span></div>
    <div class="access-info"><span class="access-badge">${icon('shield-check')} Acceso autorizado</span><h2>${esc(p.nombre)}</h2>
      <p class="access-puesto">${esc(p.puesto || 'Puesto no asignado')}</p>
      <div class="access-tags"><span>${icon(state.isAdmin ? 'crown' : 'user')} ${state.isAdmin ? 'Administrador del portal' : 'Usuario'}</span>
        ${acc.map((a) => `<span>${icon('key-round')} ${esc(a)}</span>`).join('')}
        <span>${icon('building-2')} ${esc(p.area || 'Sin área')}</span><span>${icon('clock')} Último acceso: ${fmtDateTime(u?.last_sign_in_at)}</span></div>
      <p class="access-foot">${icon('lock')} ${state.isAdmin ? 'La administración del portal no otorga autoridad de aprobación técnica.' : 'Sesión verificada con tu cuenta corporativa Pet\'s Table.'}</p></div></section>`;
}

const ESTADO_COLOR = { registrada: '#94A3B8', en_preparacion: '#38BDF8', preparada: '#0891B2', en_ejecucion: '#F58020', en_evaluacion: '#7C3AED', pendiente_resultados: '#E8890C',
  pendiente_dictamen: '#F59E0B', aprobada: '#22C55E', rechazada: '#EF4444', requiere_repeticion: '#D97706', cerrada_aprobada: '#16A34A', cerrada_rechazada: '#DC2626', cancelada: '#64748B' };
const TIPO_COLOR = ['#F58020', '#1BC7C7', '#7C3AED', '#2563EB', '#DB2777', '#16A34A', '#E8890C', '#0891B2', '#65A30D', '#9333EA'];
function drawCharts(k) {
  const fmtP = (p) => (k.por_mes ? `${monthShort(p + '-15')} ${p.slice(2, 4)}` : `${p.slice(8, 10)}/${p.slice(5, 7)}`);
  const s = k.serie || [];
  makeChart(document.getElementById('ch-serie'), { type: 'bar', data: { labels: s.map((x) => fmtP(x.periodo)), datasets: [
    { label: 'Registradas', data: s.map((x) => x.registradas), backgroundColor: 'rgba(245,128,32,.85)', borderRadius: 6, maxBarThickness: 28 },
    { label: 'Cerradas', data: s.map((x) => x.cerradas), type: 'line', borderColor: '#1BC7C7', backgroundColor: '#1BC7C7', tension: .35, pointRadius: 3 }] } });
  const pe = Object.entries(k.actual || {}).sort((a, b) => Object.keys(ESTADOS_PRUEBA).indexOf(a[0]) - Object.keys(ESTADOS_PRUEBA).indexOf(b[0]));
  makeChart(document.getElementById('ch-estado'), { type: 'doughnut', data: { labels: pe.map(([e]) => ESTADOS_PRUEBA[e]?.label || e),
    datasets: [{ data: pe.map(([, n]) => n), backgroundColor: pe.map(([e]) => ESTADO_COLOR[e] || '#999'), borderWidth: 0 }] }, options: { plugins: { legend: { position: 'bottom' } } } });
  const pt = (k.por_tipo || []).filter((x) => x.n > 0);
  makeChart(document.getElementById('ch-tipo'), { type: 'bar', data: { labels: pt.map((x) => x.tipo), datasets: [{ label: 'Pruebas', data: pt.map((x) => x.n),
    backgroundColor: pt.map((_, i) => TIPO_COLOR[i % TIPO_COLOR.length]), borderRadius: 6, maxBarThickness: 24 }] }, options: { indexAxis: 'y', plugins: { legend: { display: false } } } });
  const rc = k.resultados_por_categoria || [];
  makeChart(document.getElementById('ch-res'), { type: 'bar', data: { labels: rc.map((x) => CATEGORIAS[x.categoria] || x.categoria), datasets: [
    { label: 'Conforme', data: rc.map((x) => x.conforme), backgroundColor: '#16A34A', borderRadius: 4 },
    { label: 'No conforme', data: rc.map((x) => x.no_conforme), backgroundColor: '#DC2626', borderRadius: 4 },
    { label: 'Pendiente', data: rc.map((x) => x.pendiente), backgroundColor: '#E8890C', borderRadius: 4 },
    { label: 'No aplica', data: rc.map((x) => x.no_aplica), backgroundColor: '#94A3B8', borderRadius: 4 }] }, options: { scales: { x: { stacked: true }, y: { stacked: true } } } });
}
