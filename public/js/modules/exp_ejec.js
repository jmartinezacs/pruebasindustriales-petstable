// =====================================================================
// Etapa 2 · Registro durante el proceso y etapa 3 · Evaluaciones
// complementarias. Cada área registra sus parámetros:
//   Calidad → Inspectores · Producción → Supervisores ·
//   Seguridad → Supervisor de Seguridad, Salud y Ambiente ·
//   Mantenimiento → Jefe de Mantenimiento.
// Fabricación: por batch (agrupados por lote diario). Empaque: por corrida.
// Seguridad y Mantenimiento: un registro general por prueba.
// =====================================================================
import {
  sb, state, esc, icon, toast, errMsg, confirmDialog, mustRow, getCat, fmtDate, fmtDateTime, pill, puedeEn, puedeArea,
  AREAS, COMPLEMENTARIAS, TIPOS_COMPLEMENTARIAS, refreshIcons,
} from '../core.js';
import { cardHead, btn, iconBtn, aviso, vacio, checklist, accion, subirEvidencia } from './exp_comun.js';
import { capturaForm, avanceUnidad, itemsDe, areasDe, conEquipo, ABIERTA } from './exp_captura.js';

const OP = { pendiente: ['Pendiente', 'warn'], conforme: ['Sin problemas', 'ok'], no_conforme: ['Con desviación', 'bad'] };
const COMPLETAR = ['en_evaluacion', 'pendiente_resultados'];

async function cargarDatos(P, ej) {
  const [metodos, lotes, batches, controles, pars, plan, muestras, resultados] = await Promise.all([
    getCat('metodos'),
    sb.from('lotes_diarios_prubind').select('*').eq('prueba_id', P.id).eq('ejecucion', ej).order('fecha'),
    sb.from('v_batches_prubind').select('*').eq('prueba_id', P.id).eq('ejecucion', ej).order('numero'),
    sb.from('ejecucion_controles_prubind').select('*').eq('prueba_id', P.id).eq('ejecucion', ej).order('created_at'),
    sb.from('prueba_parametros_prubind').select('*').eq('prueba_id', P.id).order('orden'),
    sb.from('plan_evaluacion_prubind').select('id, nivel, metodo_id').eq('prueba_id', P.id).eq('incluido', true),
    sb.from('muestras_prubind').select('id, nivel, batch_id, punto_id').eq('prueba_id', P.id).eq('ejecucion', ej),
    sb.from('resultados_prubind').select('id, plan_id, muestra_id, valor_num, valor_opcion, estado').eq('prueba_id', P.id).eq('ejecucion', ej),
  ]);
  [lotes, batches, controles, pars, plan, muestras, resultados].forEach((r) => { if (r.error) throw r.error; });
  const met = (id) => metodos.find((m) => m.id === id);
  const resDe = (pred) => { const m = muestras.data.find(pred); return m ? resultados.data.filter((r) => r.muestra_id === m.id) : []; };
  return { met, resDe, L: lotes.data, B: batches.data, C: controles.data, PR: pars.data, PL: plan.data, R: resultados.data };
}

// "3 de 4" con color según avance
const avanceTxt = ([h, t]) => (t ? `<span class="${h === t ? 'ok-txt' : h ? '' : 'cell-sub'}">${h} de ${t}</span>` : '<span class="cell-sub">—</span>');
const puedeCapturarAlgo = (P, areas) => areas.some((a) => puedeArea(P, 'capturar', a) || puedeArea(P, 'evaluar', a)) || P.responsable_ejecucion_id === state.profile.id;

const selEjecucion = (P, ej) => (P.ejecucion_actual > 1 ? `<label class="inline-sel">Ejecución <select id="ej-sel" data-native>${Array.from({ length: P.ejecucion_actual }, (_, i) => i + 1)
  .map((n) => `<option value="${n}" ${n === ej ? 'selected' : ''}>#${n}${n === P.ejecucion_actual ? ' (actual)' : ''}</option>`).join('')}</select></label>` : '');

// ============================== REGISTRO EN PROCESO ==============================
export async function etapaProceso(pane, ctx) {
  const { P, E } = ctx;
  const ej = ctx.ejecucion || P.ejecucion_actual;
  const actual = ej === P.ejecucion_actual;
  const fab = P.ejecucion_form === 'fabricacion';
  const D = await cargarDatos(P, ej);
  const abierta = actual && ABIERTA.includes(P.estado);
  const enCaptura = actual && (abierta || COMPLETAR.includes(P.estado));
  const altaBatch = abierta && puedeEn(P, 'ejecutar');

  const itemsProc = itemsDe(D.PL, D.met, { unidad: fab ? 'batch' : 'corrida', seccion: 'proceso', fab });
  const itemsGen = itemsDe(D.PL, D.met, { unidad: 'corrida', seccion: 'general', fab });
  const parsGen = conEquipo({ unidad: 'corrida', seccion: 'general', fab }) ? D.PR : [];
  const parsProc = conEquipo({ unidad: 'corrida', seccion: 'proceso', fab }) ? D.PR : [];
  const areasProc = areasDe(itemsProc, D.met);
  const areasGen = [...new Set([...areasDe(itemsGen, D.met), ...(parsGen.length ? ['produccion'] : [])])];
  const capProc = enCaptura && puedeCapturarAlgo(P, areasProc.length ? areasProc : ['produccion']);
  const capGen = enCaptura && puedeCapturarAlgo(P, areasGen);

  const avArea = (items, R, area) => avanceUnidad(items.filter((pl) => D.met(pl.metodo_id)?.area === area), R);
  const avEquipo = (pars) => [pars.filter((x) => D.C.some((c) => c.prueba_parametro_id === x.id && c.valor != null)).length, pars.length];

  // ---------- Fabricación: batches ----------
  const batchRow = (b) => {
    const R = D.resDe((m) => m.nivel === 'batch' && m.batch_id === b.id);
    return `<tr class="${b.resultado_op === 'no_conforme' ? 'row-bad' : ''}">
    <td data-label="Batch"><div class="td-in"><b>#${b.numero}</b><div class="cell-sub">${fmtDateTime(b.fecha_hora)}</div></div></td>
    ${areasProc.map((a) => `<td data-label="${esc(AREAS[a].label)}"><div class="td-in">${avanceTxt(avArea(itemsProc, R, a))}</div></td>`).join('')}
    <td data-label="¿Sin problemas?"><div class="td-in">${pill(...OP[b.resultado_op])}${b.incidencias ? `<div class="cell-sub">${esc(b.incidencias)}</div>` : ''}</div></td>
    <td class="actions" data-label=""><div class="td-in"><div class="row-actions">
      ${capProc ? `<button class="btn secondary sm" data-ej="b-cap" data-id="${esc(b.id)}">${icon('clipboard-pen')} Registrar</button>` : iconBtn(`data-ej="b-cap" data-id="${esc(b.id)}"`, 'eye', 'Ver registro')}
      ${iconBtn(`data-ej="b-evi" data-id="${esc(b.id)}"`, 'paperclip', 'Adjuntar evidencia')}
      ${altaBatch ? iconBtn(`data-ej="b-del" data-id="${esc(b.id)}"`, 'trash-2', 'Eliminar batch', 'bad') : ''}</div></div></td></tr>`;
  };
  const fabHTML = `<div class="card">
    ${cardHead('Batches', `Por cada batch, cada área registra sus parámetros: ${areasProc.map((a) => `<b>${esc(AREAS[a].label)}</b>`).join(', ') || 'sin parámetros definidos aún'}.`,
      `${selEjecucion(P, ej)}${altaBatch ? btn('data-ej="b-nuevo"', 'plus', 'Nuevo batch', 'primary') : ''}`)}
    ${P.batches_planeados ? `<p class="hint">Batches de la prueba: <b>${P.batches_planeados}</b> · registrados: <b>${D.B.length}</b>.</p>` : ''}
    ${D.L.length ? D.L.map((l) => {
      const bs = D.B.filter((b) => b.lote_diario_id === l.id);
      return `<div class="lote-card"><div class="lote-head"><span class="pend-ico">${icon('package')}</span><div><b>Lote diario ${esc(l.codigo)}</b><span>${fmtDate(l.fecha)} · ${bs.length} batch(es)</span></div>
        ${altaBatch && !bs.length ? iconBtn(`data-ej="lote-del" data-id="${esc(l.id)}"`, 'trash-2', 'Eliminar lote diario', 'bad') : ''}</div>
        ${bs.length ? `<div class="table-wrap responsive"><table class="table"><thead><tr><th>Batch</th>${areasProc.map((a) => `<th>${esc(AREAS[a].label)}</th>`).join('')}<th>¿Sin problemas?</th><th class="actions"></th></tr></thead>
          <tbody>${bs.map(batchRow).join('')}</tbody></table></div>` : vacio('Sin batches en este lote.')}</div>`;
    }).join('') : vacio(altaBatch ? 'Pulse “Nuevo batch” para registrar el primero. El lote diario se crea solo.' : 'Sin batches registrados.')}
  </div>`;

  // ---------- Corrida (empaque) ----------
  const Rcor = D.resDe((m) => m.nivel === 'corrida');
  const tarjetaUnidad = (titulo, sub, items, pars, areas, seccion, puede) => `<div class="card ${seccion === 'general' && fab ? 'mt' : ''}">
    ${cardHead(titulo, sub, `${seccion === 'proceso' ? selEjecucion(P, ej) : ''}${btn(`data-ej="corrida" data-sec="${seccion}"`, puede ? 'clipboard-pen' : 'eye', puede ? 'Registrar' : 'Ver registro', puede ? 'primary' : 'secondary')}`)}
    <div class="area-avance">${areas.map((a) => {
      const av = a === 'produccion' && pars.length ? (([h, t], [h2, t2]) => [h + h2, t + t2])(avArea(items, Rcor, a), avEquipo(pars)) : avArea(items, Rcor, a);
      return `<div class="list-item"><span class="pend-ico">${icon(AREAS[a].ico)}</span><div class="li-main"><b>${esc(AREAS[a].label)}</b><span>${avanceTxt(av)} parámetros con valor</span></div></div>`;
    }).join('') || vacio('Sin parámetros.')}</div></div>`;

  const genHTML = itemsGen.length || parsGen.length
    ? tarjetaUnidad('Registro general de la prueba', 'Una sola vez por prueba: seguridad, mantenimiento y otros parámetros generales.', itemsGen, parsGen, areasGen, 'general', capGen) : '';
  const procHTML = fab ? fabHTML
    : tarjetaUnidad('Corrida de prueba', 'Pruebas del material y parámetros del equipo durante la corrida.', itemsProc, parsProc, [...new Set([...areasProc, ...(parsProc.length ? ['produccion'] : [])])], 'proceso', capProc);

  // ---------- Para terminar ----------
  const reqs = fab ? [[D.B.length > 0, 'Al menos un batch registrado']]
    : [[D.R.length > 0 || D.C.length > 0, 'Al menos un parámetro de la corrida registrado']];
  const conValor = E.obligatorios - E.obligatorios_faltantes;
  let estadoHTML = '';
  if (!actual) estadoHTML = aviso(`Consulta de la ejecución #${ej}.`);
  else if (COMPLETAR.includes(P.estado)) estadoHTML = aviso('El registro durante el proceso terminó. Los valores que falten (por ejemplo, resultados de laboratorio) aún se pueden completar.', '', 'info');
  else if (abierta && !puedeEn(P, 'ejecutar')) estadoHTML = aviso('El registro lo hacen las áreas: inspectores de Calidad, supervisores de Producción y, si aplica, Seguridad y Mantenimiento.');

  pane.innerHTML = `${estadoHTML}
    <div class="${abierta ? 'grid grid-main ' : ''}mt-s">
      <div>${procHTML}${genHTML}
        ${abierta && (puedeEn(P, 'preparar') || puedeEn(P, 'ejecutar')) ? `<p class="hint mt-s">¿Falta un parámetro? <button class="link-btn" data-tab="registro">${icon('plus')} Agréguelo en Registro → Parámetros a evaluar</button></p>` : ''}</div>
      ${abierta ? `<div class="card"><div class="card-head"><div><h3>Para terminar el registro en proceso</h3></div></div>${checklist(reqs)}
        <p class="hint">Parámetros con al menos un valor: <b>${conValor} de ${E.obligatorios}</b>.${TIPOS_COMPLEMENTARIAS.includes(P.tipo) ? ' Las evaluaciones complementarias (laboratorio) se pueden completar después.' : ''}</p>
        ${P.estado === 'en_ejecucion' && puedeEn(P, 'ejecutar') ? `<button class="btn primary block mt" data-ej="terminar" ${reqs.every(([ok]) => ok) ? '' : 'disabled'}>${icon('flag')} Terminar y pasar a resultados</button>` : ''}
        ${P.estado !== 'en_ejecucion' ? '<p class="hint">El registro empieza con el primer dato capturado.</p>' : ''}
      </div>` : ''}
    </div>`;
  refreshIcons();

  const recargar = () => ctx.refrescar('proceso', ej);
  pane.querySelector('#ej-sel')?.addEventListener('change', (e) => ctx.refrescar('proceso', Number(e.target.value)));
  pane.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-ej]');
    if (!b) return;
    const id = b.dataset.id;
    try {
      switch (b.dataset.ej) {
        case 'b-nuevo': {
          let r = await capturaForm(P, { unidad: 'batch', seccion: 'proceso' });
          while (r?.siguiente) r = await capturaForm({ ...P, estado: 'en_ejecucion' }, { unidad: 'batch', seccion: 'proceso', previo: r.previo });
          ctx.refrescar('proceso', ej); return;
        }
        case 'b-cap': if (!await capturaForm(P, { unidad: 'batch', seccion: 'proceso', batch: D.B.find((x) => x.id === id) })) return; break;
        case 'corrida': if (!await capturaForm(P, { unidad: 'corrida', seccion: b.dataset.sec })) return; break;
        case 'lote-del': mustRow(await sb.from('lotes_diarios_prubind').delete().eq('id', id).select('id')); break;
        case 'b-del':
          if (!await confirmDialog({ title: 'Eliminar batch', message: 'Se eliminará el batch con sus lotes de materia prima vinculados. Si ya tiene parámetros registrados, bórrelos primero.', confirmText: 'Eliminar', danger: true })) return;
          mustRow(await sb.from('batches_prubind').delete().eq('id', id).select('id')); break;
        case 'b-evi': if (!await subirEvidencia(P, { batch_id: id, etapa: 'ejecucion' })) return; break;
        case 'terminar':
          if (!await confirmDialog({ title: 'Terminar registro en proceso', message: 'La prueba pasará a resultados: cada área evaluará sus parámetros (Cumple / No cumple). Los valores pendientes de laboratorio aún se podrán completar.', confirmText: 'Terminar' })) return;
          await accion(P.id, 'terminar_ejecucion'); toast('Registro en proceso terminado; inicia la evaluación de resultados.', 'success'); ctx.refrescar('resultados'); return;
        default: return;
      }
      recargar();
    } catch (err) { toast(errMsg(err), 'error'); recargar(); }
  });
}

// ============================== EVALUACIONES COMPLEMENTARIAS ==============================
export async function etapaComplementarias(pane, ctx) {
  const { P } = ctx;
  if (!TIPOS_COMPLEMENTARIAS.includes(P.tipo)) {
    pane.innerHTML = aviso('Las evaluaciones complementarias solo aplican a materia prima, reformulaciones y productos nuevos. Esta prueba pasa directo a resultados.');
    refreshIcons(); return;
  }
  const ej = P.ejecucion_actual;
  const fab = P.ejecucion_form === 'fabricacion';
  const D = await cargarDatos(P, ej);
  const unidad = fab ? 'batch' : 'corrida';
  const items = itemsDe(D.PL, D.met, { unidad, seccion: 'complementarias', fab });
  const enCaptura = ABIERTA.includes(P.estado) || COMPLETAR.includes(P.estado);
  const puede = enCaptura && puedeCapturarAlgo(P, ['calidad']);
  const cats = COMPLEMENTARIAS.filter((c) => items.some((pl) => D.met(pl.metodo_id)?.categoria === c));
  const NOM = { sensorial: 'Sensorial', microbiologia: 'Microbiología', bromatologia: 'Bromatológicos' };
  const av = (R, cat) => avanceUnidad(items.filter((pl) => D.met(pl.metodo_id)?.categoria === cat), R);

  const filas = fab ? D.B.map((b) => {
    const R = D.resDe((m) => m.nivel === 'batch' && m.batch_id === b.id);
    return `<tr><td data-label="Batch"><div class="td-in"><b>#${b.numero}</b><div class="cell-sub">${esc(b.lote_codigo || '')} · ${fmtDateTime(b.fecha_hora)}</div></div></td>
      ${cats.map((c) => `<td data-label="${esc(NOM[c])}"><div class="td-in">${avanceTxt(av(R, c))}</div></td>`).join('')}
      <td class="actions" data-label=""><div class="td-in">${puede ? `<button class="btn secondary sm" data-co="cap" data-id="${esc(b.id)}">${icon('clipboard-pen')} Registrar</button>` : iconBtn(`data-co="cap" data-id="${esc(b.id)}"`, 'eye', 'Ver')}</div></td></tr>`;
  }).join('') : '';

  pane.innerHTML = `<div class="card">
    ${cardHead('Evaluaciones complementarias', `Evaluación sensorial (olor, color, sabor, textura), microbiología y análisis bromatológicos (proteínas, grasas, humedad, cenizas). Forman parte de los parámetros de Calidad.`)}
    ${!items.length ? vacio('Esta prueba no tiene evaluaciones complementarias en sus parámetros a evaluar.')
      : fab ? (D.B.length ? `<div class="table-wrap responsive"><table class="table"><thead><tr><th>Batch</th>${cats.map((c) => `<th>${esc(NOM[c])}</th>`).join('')}<th class="actions"></th></tr></thead><tbody>${filas}</tbody></table></div>`
          : aviso('Se registran por batch. Primero registre un batch en «Registro en proceso».'))
        : `<div class="list-item"><div class="li-main"><b>Corrida de prueba</b><span>${cats.map((c) => `${NOM[c]} ${avanceTxt(av(D.resDe((m) => m.nivel === 'corrida'), c))}`).join(' · ')}</span></div>${btn('data-co="corrida"', puede ? 'clipboard-pen' : 'eye', puede ? 'Registrar' : 'Ver')}</div>`}
    ${enCaptura && !puede ? aviso('Las registran los inspectores de Calidad.') : ''}
  </div>`;
  refreshIcons();
  pane.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-co]');
    if (!b) return;
    try {
      const r = b.dataset.co === 'cap' ? await capturaForm(P, { unidad: 'batch', seccion: 'complementarias', batch: D.B.find((x) => x.id === b.dataset.id) })
        : await capturaForm(P, { unidad: 'corrida', seccion: 'complementarias' });
      if (r) ctx.refrescar('complementarias');
    } catch (err) { toast(errMsg(err), 'error'); }
  });
}
