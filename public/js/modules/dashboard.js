// =====================================================================
// Panel: qué me toca (pendientes según mi autoridad), indicadores reales,
// gráficas y actividad reciente. Cifras desde prubind_dashboard y
// prubind_mis_pendientes.
// =====================================================================
import {
  sb, state, esc, icon, refreshIcons, todayISO, addDays, fmtDate, fmtDateTime, fmtNum, pill, makeChart, destroyCharts, toast, errMsg,
  emptyState, errorState, navigate, monthShort, prefs, must, avatarHTML, estadoPill, prioPill, ESTADOS_PRUEBA, ABIERTAS, ACCIONES, AREAS,
  temaOscuro, colorCategoria, push,
} from '../core.js';
import { openRegistro, etapasMini } from './pruebas.js';

let root, token = 0;
export const TAB_ACCION = { iniciar: 'proceso', definir: 'registro', capturar: 'proceso', evaluar: 'resultados', recomendar: 'recomendaciones', dictaminar: 'dictamen', cerrar: 'cierre', autorizar_implementacion: 'cierre' };
export const ACC = {
  iniciar: ['Iniciar la prueba', 'play', 'Iniciar'], definir: ['Definir parámetros', 'list-plus', 'Definir'], capturar: ['Registrar parámetros', 'clipboard-pen', 'Registrar'],
  evaluar: ['Evaluar resultados', 'list-checks', 'Evaluar'], recomendar: ['Dar veredicto y recomendación', 'thumbs-up', 'Veredicto'],
  dictaminar: ['Emitir dictamen', 'gavel', 'Dictamen'], cerrar: ['Cerrar la prueba', 'archive', 'Cerrar'], autorizar_implementacion: ['Autorizar implementación', 'stamp', 'Autorizar'],
};
const PRIO_ORDEN = { urgente: 0, alta: 1, normal: 2 };
const MESES = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];

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

let filtroPend = 'todas', verTodas = false, PEND = [];
// Si en la campana se marca algo como hecho, el panel se actualiza
document.addEventListener('prubind:pendientes', () => { if (root) load(); });

export default {
  async render(el) {
    root = el; filtroPend = 'todas'; verTodas = false;
    const per = prefs.get('prubind.dash.period') || 'anio';
    el.innerHTML = `
      <section class="page-intro">
        <div><span class="eyebrow">Panel general</span>
          <h1 class="hello">Hola, ${esc(state.profile.nombre.split(' ')[0])} <span class="paws" aria-hidden="true">${icon('paw-print')}${icon('paw-print')}</span></h1>
          <p class="hello-sub">Aquí se registran y siguen las pruebas industriales de Pet's Table: nuevos productos, cambios de formulación, proveedor, empaque o proceso. Cada área define y evalúa sus parámetros, y Alta Dirección emite el dictamen.</p></div>
        <div class="toolbar" style="margin:0">
          <select id="dash-period" aria-label="Periodo"><option value="mes">Mes en curso</option><option value="90">Últimos 90 días</option>
            <option value="anio">Año en curso</option><option value="12m">Últimos 12 meses</option><option value="custom">Personalizado</option></select>
          <span class="date-range hidden" id="dash-custom"><input type="date" id="dash-desde" aria-label="Desde"> a <input type="date" id="dash-hasta" aria-label="Hasta"></span>
        </div>
      </section>
      <div id="dash-notif"></div>
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
      const act = a.dataset.dash;
      if (act === 'retry') return load();
      if (act === 'nueva') { const id = await openRegistro(); if (id) navigate(`#/pruebas?id=${id}`); return; }
      if (act === 'filtro') { filtroPend = a.dataset.f; verTodas = false; pintarPendientes(); return; }
      if (act === 'mas') { verTodas = !verTodas; pintarPendientes(); return; }
      if (act === 'notif-on') {
        a.disabled = true;
        try { await push.activar(); toast('Notificaciones activadas en este dispositivo.', 'success'); a.closest('.notif-banner')?.remove(); }
        catch (err) { toast(errMsg(err), 'error'); a.disabled = false; }
        return;
      }
      if (act === 'notif-x') { prefs.set('prubind.notif.omitir', '1'); a.closest('.notif-banner')?.remove(); return; }
      navigate(act);
    });
    el.addEventListener('keydown', (e) => { if ((e.key === 'Enter' || e.key === ' ') && e.target.matches('[data-dash][role="link"]')) { e.preventDefault(); e.target.click(); } });
    notifHTML().then((h) => { const n = root?.querySelector('#dash-notif'); if (n) { n.innerHTML = h; refreshIcons(); } });
    await load();
  },
  destroy() { token++; root = null; },
};

// Invitación a activar las notificaciones (como en Servicio Médico)
async function notifHTML() {
  if (prefs.get('prubind.notif.omitir') === '1') return '';
  const est = await push.estado().catch(() => 'no-soportado');
  if (est === 'inactivo') {
    return `<div class="notif-banner"><span class="nb-ico">${icon('bell-ring')}</span><div class="nb-txt"><b>Activa las notificaciones</b>
      <span>Recibe un aviso en este dispositivo cuando se registre o inicie una prueba en la que participa tu área, y cuando esté lista para dictamen.</span></div>
      <button class="btn primary" data-dash="notif-on">${icon('bell')} Activar</button><button class="icon-btn" data-dash="notif-x" aria-label="Ocultar aviso">${icon('x')}</button></div>`;
  }
  if (est === 'instalar') {
    return `<div class="notif-banner"><span class="nb-ico">${icon('smartphone')}</span><div class="nb-txt"><b>Instala la app para recibir avisos</b>
      <span>En iPhone: toca Compartir → “Agregar a pantalla de inicio”, abre la app desde ahí y activa las notificaciones.</span></div>
      <button class="icon-btn" data-dash="notif-x" aria-label="Ocultar aviso">${icon('x')}</button></div>`;
  }
  return '';
}

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
      sb.from('v_seguimiento_prubind').select('id, prueba_id, tipo, texto, created_at, usuario, foto_url, folio, cambio').order('created_at', { ascending: false }).order('id', { ascending: false }).limit(12),
    ]);
    res.forEach(must);
    if (t !== token) return;
    const [k, pend, act] = res.map((r) => r.data);
    PEND = pend;
    destroyCharts();
    body.innerHTML = kpisHTML(k) + '<section class="card mt pend-card" id="dash-pend"></section>' + chartsHTML(k) + actividadHTML(act) + accesoHTML();
    pintarPendientes();
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
  return `<div class="grid grid-4">
    ${kpi('k-green i-green', 'flask-conical', 'Pruebas abiertas', abiertas, 'Sin cerrar ni cancelar', '#/pruebas?estado=abiertas')}
    ${kpi('k-yellow i-yellow', 'factory', 'En proceso', a.en_ejecucion || 0, 'Iniciadas, con registro de las áreas', '#/pruebas?estado=en_ejecucion')}
    ${kpi('k-orange i-orange', 'gavel', 'Pendientes de dictamen', a.pendiente_dictamen || 0, 'Las áreas ya dieron su veredicto', '#/pruebas?estado=pendiente_dictamen')}
    ${kpi('k-blue i-blue', 'archive', 'Pruebas cerradas', (a.cerrada_aprobada || 0) + (a.cerrada_rechazada || 0), `${a.cerrada_aprobada || 0} aprobada(s) · ${a.cerrada_rechazada || 0} rechazada(s)`, '#/pruebas?estado=cerradas')}
  </div>`;
}

// ---------- Requieren tu intervención: una tarjeta por prueba con lo que te toca ----------
function cuando(f) {
  if (!f) return '';
  const hoy = todayISO();
  const cls = f < hoy ? 'late' : f === hoy ? 'today' : '';
  return `<span class="pc-fecha ${cls}">${icon('calendar')} ${f === hoy ? 'Hoy' : f === addDays(hoy, 1) ? 'Mañana' : fmtDate(f)}${f < hoy ? ' · vencida' : ''}</span>`;
}
function pintarPendientes() {
  const cont = root?.querySelector('#dash-pend');
  if (!cont) return;
  const porPrueba = new Map();
  PEND.forEach((p) => { if (!porPrueba.has(p.prueba_id)) porPrueba.set(p.prueba_id, { ...p, acciones: [] }); porPrueba.get(p.prueba_id).acciones.push(p); });
  let pruebas = [...porPrueba.values()].sort((a, b) => (PRIO_ORDEN[a.prioridad] ?? 3) - (PRIO_ORDEN[b.prioridad] ?? 3)
    || String(a.fecha_planeada || '9999').localeCompare(String(b.fecha_planeada || '9999')) || String(a.folio).localeCompare(String(b.folio)));
  const conteo = {}; PEND.forEach((p) => { conteo[p.accion] = (conteo[p.accion] || 0) + 1; });
  if (filtroPend !== 'todas') pruebas = pruebas.filter((p) => p.acciones.some((x) => x.accion === filtroPend));
  const visibles = verTodas ? pruebas : pruebas.slice(0, 6);
  const tarjeta = (p) => {
    const principal = p.acciones[0];
    const go = `#/pruebas?id=${p.prueba_id}&tab=${TAB_ACCION[principal.accion] || ''}`;
    return `<article class="pend-tile prio-${esc(p.prioridad || 'normal')}">
      <div class="pc-top"><span class="pc-folio mono">${esc(p.folio)}</span><span class="pc-tipo">${esc(p.tipo_nombre)}</span>${p.prioridad !== 'normal' ? prioPill(p.prioridad) : ''}</div>
      <h4 class="pc-title" title="${esc(p.cambio)}">${esc(p.cambio)}</h4>
      <div class="pc-stage">${etapasMini({ tipo: p.tipo, estado: p.estado })}<span>${esc(ESTADOS_PRUEBA[p.estado]?.label || p.estado)}</span></div>
      <ul class="pc-acts">${p.acciones.map((x) => `<li><button type="button" class="pc-act acc-${x.accion}" data-dash="#/pruebas?id=${esc(p.prueba_id)}&tab=${TAB_ACCION[x.accion] || ''}">
        <span class="pa-ico">${icon(ACC[x.accion]?.[1] || 'dot')}</span><span class="pa-txt">${esc(ACC[x.accion]?.[0] || x.accion)}${x.area ? ` <em>· ${esc(AREAS[x.area]?.label || x.area)}</em>` : ''}</span>${icon('chevron-right')}</button></li>`).join('')}</ul>
      <div class="pc-foot">${cuando(p.fecha_planeada)}<button type="button" class="btn primary sm" data-dash="${go}">${esc(ACC[principal.accion]?.[2] || 'Atender')} ${icon('arrow-right')}</button></div>
    </article>`;
  };
  const filtros = Object.keys(ACC).filter((k) => conteo[k]);
  cont.innerHTML = `<div class="card-head center"><div><h3>${icon('hand')} Requieren tu intervención</h3><p>${porPrueba.size ? `${PEND.length} acción(es) en ${porPrueba.size} prueba(s), según tu puesto y tu participación` : 'Según tu puesto y tu participación en cada prueba'}</p></div>
      <button class="btn primary" data-dash="nueva">${icon('flask-conical')} Nueva prueba</button></div>
    ${filtros.length > 1 ? `<div class="pend-filtros" role="tablist">${[['todas', 'Todas', PEND.length], ...filtros.map((k) => [k, ACC[k][2], conteo[k]])]
      .map(([k, l, n]) => `<button type="button" role="tab" class="pf ${filtroPend === k ? 'on' : ''}" data-dash="filtro" data-f="${k}" aria-selected="${filtroPend === k}">${k !== 'todas' ? icon(ACC[k][1]) : ''}${esc(l)} <b>${n}</b></button>`).join('')}</div>` : ''}
    ${porPrueba.size ? `<div class="pend-tiles">${visibles.map(tarjeta).join('')}</div>
      ${pruebas.length > 6 ? `<div class="pend-more"><button class="btn ghost" data-dash="mas">${verTodas ? `${icon('chevron-up')} Ver menos` : `${icon('chevron-down')} Ver las ${pruebas.length} pruebas`}</button></div>` : ''}`
      : emptyState({ ico: 'check-circle-2', title: 'Todo al día', text: state.profile.puesto_id ? 'No tienes acciones pendientes en este momento.' : 'Tu usuario no tiene puesto asignado: solo verás pendientes de las pruebas que registres.' })}`;
  refreshIcons();
}

// ---------- Gráficas ----------
const chartCard = (id, title, sub, cls = '', total = '') => `<div class="card chart-card"><div class="chart-head"><h3>${esc(title)}</h3>${sub ? `<p>${esc(sub)}</p>` : ''}${total !== '' ? `<span class="chart-total">${total}</span>` : ''}</div><div class="chart-box ${cls}"><canvas id="${id}" role="img" aria-label="${esc(title)}"></canvas></div></div>`;
function chartsHTML(k) {
  const hayActual = Object.values(k.actual || {}).some((n) => n > 0);
  if (!k.registradas && !hayActual) return `<div class="card mt">${emptyState({ ico: 'bar-chart-3', title: 'Aún no hay pruebas', text: 'Las gráficas aparecerán al registrar pruebas.' })}</div>`;
  const ev = (k.evaluaciones_por_area || []).some((x) => x.cumple || x.no_cumple || x.no_determinado);
  const total = Object.values(k.actual || {}).reduce((s, n) => s + n, 0);
  const curso = ABIERTAS.reduce((s, e) => s + ((k.actual || {})[e] || 0), 0);
  return `<div class="section-label">Indicadores</div>
    <div class="grid grid-main">${chartCard('ch-serie', 'Pruebas registradas y cerradas', k.por_mes ? 'Por mes, en el periodo' : 'Por día, en el periodo', '', `${fmtNum(k.registradas)} <small>Registradas</small>`)}${chartCard('ch-estado', 'Situación de todas las pruebas', 'Todas las pruebas registradas', '', `${fmtNum(total)} <small>Total</small>`)}</div>
    <div class="grid grid-2 mt">${chartCard('ch-etapa', 'Pruebas en curso por etapa', 'Dónde están las pruebas que no se han cerrado', 'sm', `${fmtNum(curso)} <small>En curso</small>`)}${chartCard('ch-tipo', 'Pruebas registradas por tipo', 'En el periodo', 'sm', `${fmtNum(k.registradas)} <small>En el periodo</small>`)}</div>
    <div class="mt">${ev ? chartCard('ch-areas', 'Evaluación de parámetros por área', 'Cumple / No cumple / No se pudo determinar, evaluados en el periodo', 'sm') : `<div class="card">${emptyState({ ico: 'list-checks', title: 'Sin parámetros evaluados en el periodo' })}</div>`}</div>`;
}

// ---------- Actividad reciente: línea de tiempo agrupada por día ----------
function hace(ts) {
  const s = Math.max(0, (Date.now() - new Date(ts).getTime()) / 1000);
  if (s < 60) return 'Hace un momento';
  if (s < 3600) return `Hace ${Math.floor(s / 60)} min`;
  if (s < 86400) return `Hace ${Math.floor(s / 3600)} h`;
  return fmtDateTime(ts).slice(-5);
}
function diaDe(ts) {
  const d = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Mexico_City' }).format(new Date(ts));
  const hoy = todayISO();
  return d === hoy ? 'Hoy' : d === addDays(hoy, -1) ? 'Ayer' : fmtDate(d);
}
function actividadHTML(act) {
  const SEG = { nota: ['message-square', 'Nota'], estado: ['flag', 'Cambio de etapa'], sistema: ['cpu', 'Sistema'] };
  const grupos = [];
  act.forEach((s) => { const d = diaDe(s.created_at); if (!grupos.length || grupos[grupos.length - 1][0] !== d) grupos.push([d, []]); grupos[grupos.length - 1][1].push(s); });
  return `<section class="card mt"><div class="card-head center"><div><h3>${icon('activity')} Actividad reciente</h3><p>Notas del equipo y avances de las pruebas</p></div></div>
    ${act.length ? `<div class="feed">${grupos.map(([d, xs]) => `<div class="feed-day"><span>${esc(d)}</span></div>
      <ol class="feed-list">${xs.map((s) => `<li><button type="button" class="feed-item t-${esc(s.tipo)}" data-dash="#/pruebas?id=${esc(s.prueba_id)}&tab=seguimiento">
        <span class="feed-av">${s.usuario ? avatarHTML(s.usuario, s.foto_url, 'sm') : `<span class="feed-sys">${icon('cpu')}</span>`}<span class="feed-badge">${icon(SEG[s.tipo]?.[0] || 'dot')}</span></span>
        <span class="feed-body"><span class="feed-head"><b>${esc(s.usuario || 'Sistema')}</b><span class="feed-folio mono">${esc(s.folio)}</span><time datetime="${esc(s.created_at)}" title="${esc(fmtDateTime(s.created_at))}">${esc(hace(s.created_at))}</time></span>
          <span class="feed-txt">${esc(s.texto)}</span>${s.cambio ? `<span class="feed-sub">${esc(s.cambio)}</span>` : ''}</span></button></li>`).join('')}</ol>`).join('')}</div>`
      : emptyState({ ico: 'history', title: 'Sin actividad', text: 'Aquí aparecerán las notas y los avances de las pruebas.' })}</section>`;
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
      <p class="access-foot">${icon('lock')} ${state.isAdmin ? 'Como administrador puedes realizar cualquier acción de las autoridades.' : 'Sesión verificada con tu cuenta corporativa Pet\'s Table.'}</p></div></section>`;
}

// Estados (fijos, con etiqueta): cumple / no cumple / no determinado; situación de las pruebas
const ESTADO_COL = {
  cumple: ['#0ca30c', '#0ca30c'], no_cumple: ['#d03b3b', '#d03b3b'], no_determinado: ['#eda100', '#c98500'], curso: ['#2a78d6', '#3987e5'], gris: ['#94A3B8', '#64748B'],
};
const SITUACION = [['En curso', (e) => !['cerrada_aprobada', 'cerrada_rechazada', 'cancelada'].includes(e), 'curso'],
  ['Cerradas y aprobadas', (e) => e === 'cerrada_aprobada', 'cumple'], ['Cerradas y rechazadas', (e) => e === 'cerrada_rechazada', 'no_cumple'],
  ['Canceladas', (e) => e === 'cancelada', 'gris']];
const ETAPA_DE = [['Registradas', ['registrada', 'en_preparacion', 'preparada']], ['En proceso', ['en_ejecucion']],
  ['En evaluación', ['en_evaluacion', 'pendiente_resultados']], ['Pendientes de dictamen', ['pendiente_dictamen', 'requiere_repeticion']], ['Por cerrar', ['aprobada', 'rechazada']]];
function drawCharts(k) {
  const o = temaOscuro() ? 1 : 0;
  const ce = (n) => ESTADO_COL[n][o];
  // Sin abreviaturas: "Octubre 2026" por mes; "20/10/2026" por día
  const fmtP = (p) => (k.por_mes ? `${MESES[Number(p.slice(5, 7)) - 1]} ${p.slice(0, 4)}` : `${p.slice(8, 10)}/${p.slice(5, 7)}/${p.slice(0, 4)}`);
  const s = k.serie || [];
  // Dos series: un color categórico por serie
  makeChart(document.getElementById('ch-serie'), { type: 'bar', data: { labels: s.map((x) => fmtP(x.periodo)), datasets: [
    { label: 'Registradas', data: s.map((x) => x.registradas), backgroundColor: colorCategoria(0), maxBarThickness: 34, categoryPercentage: 0.72, barPercentage: 0.92 },
    { label: 'Cerradas', data: s.map((x) => x.cerradas), backgroundColor: colorCategoria(1), maxBarThickness: 34, categoryPercentage: 0.72, barPercentage: 0.92 }] },
    options: { plugins: { legend: { position: 'top', align: 'center' } } } });
  const a = k.actual || {};
  const sit = SITUACION.map(([l, f, col]) => [l, Object.entries(a).filter(([e]) => f(e)).reduce((t, [, n]) => t + n, 0), col]).filter(([, n]) => n > 0);
  makeChart(document.getElementById('ch-estado'), { type: 'doughnut', data: { labels: sit.map(([l]) => l),
    datasets: [{ data: sit.map(([, n]) => n), backgroundColor: sit.map(([, , col]) => ce(col)) }] },
    options: { plugins: { legend: { position: 'bottom' }, etiquetas: { centro: 'Pruebas' } } } });
  // Una barra por categoría: cada una con su color (en orden fijo de la paleta)
  const et = ETAPA_DE.map(([l, es]) => [l, es.reduce((t, e) => t + (a[e] || 0), 0)]);
  makeChart(document.getElementById('ch-etapa'), { type: 'bar', data: { labels: et.map(([l]) => l), datasets: [{ label: 'Pruebas', data: et.map(([, n]) => n),
    backgroundColor: et.map((_, i) => colorCategoria(i)), maxBarThickness: 24 }] }, options: { indexAxis: 'y', plugins: { legend: { display: false } } } });
  const pt = (k.por_tipo || []).filter((x) => x.n > 0);
  makeChart(document.getElementById('ch-tipo'), { type: 'bar', data: { labels: pt.map((x) => x.tipo), datasets: [{ label: 'Pruebas', data: pt.map((x) => x.n),
    backgroundColor: pt.map((_, i) => colorCategoria(i)), maxBarThickness: 24 }] }, options: { indexAxis: 'y', plugins: { legend: { display: false } } } });
  const ea = (k.evaluaciones_por_area || []).filter((x) => x.cumple || x.no_cumple || x.no_determinado);
  makeChart(document.getElementById('ch-areas'), { type: 'bar', data: { labels: ea.map((x) => AREAS[x.area]?.label || x.area), datasets: [
    { label: 'Cumple', data: ea.map((x) => x.cumple), backgroundColor: ce('cumple'), maxBarThickness: 28 },
    { label: 'No cumple', data: ea.map((x) => x.no_cumple), backgroundColor: ce('no_cumple'), maxBarThickness: 28 },
    { label: 'No se pudo determinar', data: ea.map((x) => x.no_determinado || 0), backgroundColor: ce('no_determinado'), etiquetaColor: '#1f1a0a', maxBarThickness: 28 }] },
    options: { indexAxis: 'y', scales: { x: { stacked: true }, y: { stacked: true } }, plugins: { legend: { position: 'top', align: 'center' } } } });
}
