// =====================================================================
// Etapa 2 · Registro durante el proceso y etapa 3 · Evaluaciones
// complementarias. No se planea el número de batches: cada parámetro se
// registra para TODA LA PRUEBA (registro general) o POR BATCH, y quien
// captura agrega los batches conforme se producen. Por lo general los
// inspectores registran por batch y los supervisores para toda la prueba.
// Cada área solo edita sus propios parámetros.
// =====================================================================
import {
  sb, state, esc, icon, toast, errMsg, confirmDialog, mustRow, getCat, fmtDateTime, pill, puedeEn, puedeArea,
  AREAS, AREAS_ORDEN, COMPLEMENTARIAS, TIPOS_COMPLEMENTARIAS, refreshIcons,
} from '../core.js';
import { cardHead, btn, iconBtn, aviso, vacio, checklist, accion, subirEvidencia } from './exp_comun.js';
import { capturaForm, itemsDe, ABIERTA } from './exp_captura.js';

const OP = { pendiente: ['Pendiente', 'warn'], conforme: ['Sin problemas', 'ok'], no_conforme: ['Con desviación', 'bad'] };
const COMPLETAR = ['en_evaluacion', 'pendiente_resultados'];
const NOM_CAT = { sensorial: 'Sensorial', microbiologia: 'Microbiología', bromatologia: 'Bromatológicos' };

async function cargarDatos(P, ej) {
  const [metodos, batches, plan, muestras, resultados] = await Promise.all([
    getCat('metodos'),
    sb.from('v_batches_prubind').select('*').eq('prueba_id', P.id).eq('ejecucion', ej).order('numero'),
    sb.from('plan_evaluacion_prubind').select('id, nivel, metodo_id').eq('prueba_id', P.id).eq('incluido', true),
    sb.from('muestras_prubind').select('id, nivel, batch_id, punto_id').eq('prueba_id', P.id).eq('ejecucion', ej),
    sb.from('resultados_prubind').select('id, plan_id, muestra_id, valor_num, valor_opcion').eq('prueba_id', P.id).eq('ejecucion', ej),
  ]);
  [batches, plan, muestras, resultados].forEach((r) => { if (r.error) throw r.error; });
  const met = (id) => metodos.find((m) => m.id === id);
  const conValor = (r) => r.valor_num != null || r.valor_opcion;
  // Resultados con valor de una unidad (muestra general o de un batch)
  const resDe = (pred) => { const m = muestras.data.find(pred); return m ? resultados.data.filter((r) => r.muestra_id === m.id && conValor(r)) : []; };
  return { met, resDe, B: batches.data, PL: plan.data, R: resultados.data.filter(conValor) };
}

// Parámetros (de la lista dada) con al menos un valor en esos resultados
const conDato = (items, R) => items.filter((pl) => R.some((r) => r.plan_id === pl.id)).length;
const puedeCapturarAlgo = (P, areas) => areas.some((a) => puedeArea(P, 'capturar', a) || puedeArea(P, 'evaluar', a)) || P.responsable_ejecucion_id === state.profile.id;
const selEjecucion = (P, ej) => (P.ejecucion_actual > 1 ? `<label class="inline-sel">Ejecución <select id="ej-sel" data-native>${Array.from({ length: P.ejecucion_actual }, (_, i) => i + 1)
  .map((n) => `<option value="${n}" ${n === ej ? 'selected' : ''}>#${n}${n === P.ejecucion_actual ? ' (actual)' : ''}</option>`).join('')}</select></label>` : '');

// Fila de una unidad de registro con el avance por grupo (área o categoría)
function filaUnidad({ ico, titulo, sub, grupos, items, R, attrs, puede, extra = '' }) {
  return `<div class="unit-row">
    <span class="pend-ico">${icon(ico)}</span>
    <div class="li-main"><b>${titulo}</b><span>${sub}</span>
      <div class="unit-chips">${grupos.map(([k, label, pred]) => { const xs = items.filter(pred); const n = conDato(xs, R);
        return xs.length ? `<span class="chip ${n ? 'on' : ''}">${esc(label)} <b>${n}</b>/${xs.length}</span>` : ''; }).join('')}</div></div>
    <div class="row-actions">${btn(attrs, puede ? 'clipboard-pen' : 'eye', puede ? 'Registrar' : 'Ver', puede ? 'primary sm' : 'secondary sm')}${extra}</div></div>`;
}

// ============================== REGISTRO EN PROCESO ==============================
export async function etapaProceso(pane, ctx) {
  const { P } = ctx;
  const ej = ctx.ejecucion || P.ejecucion_actual;
  const actual = ej === P.ejecucion_actual;
  const fab = P.ejecucion_form === 'fabricacion';
  const noun = fab ? 'batch' : 'corrida';
  const D = await cargarDatos(P, ej);
  const abierta = actual && ABIERTA.includes(P.estado);
  const enCaptura = actual && (abierta || COMPLETAR.includes(P.estado));
  const altaBatch = abierta && puedeEn(P, 'ejecutar');
  const items = itemsDe(D.PL, D.met, { seccion: 'proceso' });
  const areas = AREAS_ORDEN.filter((a) => items.some((pl) => D.met(pl.metodo_id)?.area === a));
  const grupos = areas.map((a) => [a, AREAS[a].label, (pl) => D.met(pl.metodo_id)?.area === a]);
  const puede = enCaptura && puedeCapturarAlgo(P, areas);

  const Rgen = D.resDe((m) => m.nivel === 'corrida');
  const filas = [filaUnidad({ ico: 'layers', titulo: 'Toda la prueba', sub: 'Registro general: lo que se mide una sola vez (por ejemplo, merma total, seguridad, mantenimiento)',
    grupos, items, R: Rgen, attrs: 'data-ej="general"', puede })]
    .concat(D.B.map((b) => filaUnidad({ ico: 'package', titulo: `${fab ? 'Batch' : 'Corrida'} #${b.numero}`,
      sub: `${fmtDateTime(b.fecha_hora)} · ${pill(...OP[b.resultado_op])}${b.incidencias ? ` · ${esc(b.incidencias)}` : ''}`,
      grupos, items, R: D.resDe((m) => m.nivel === 'batch' && m.batch_id === b.id), attrs: `data-ej="b-cap" data-id="${esc(b.id)}"`, puede,
      extra: `${iconBtn(`data-ej="b-evi" data-id="${esc(b.id)}"`, 'paperclip', 'Adjuntar evidencia')}${altaBatch ? iconBtn(`data-ej="b-del" data-id="${esc(b.id)}"`, 'trash-2', `Eliminar ${noun}`, 'bad') : ''}` })));

  // Avance por área: parámetros con al menos un valor (en cualquier registro)
  const avance = areas.map((a) => { const xs = items.filter((pl) => D.met(pl.metodo_id)?.area === a); const n = conDato(xs, D.R);
    return `<div class="av-row"><span>${icon(AREAS[a].ico)} ${esc(AREAS[a].label)}</span><div class="av-bar"><i style="width:${xs.length ? Math.round((n / xs.length) * 100) : 0}%"></i></div><b>${n}/${xs.length}</b></div>`; }).join('');

  const reqs = [[D.R.length > 0 || D.B.length > 0, 'Al menos un dato registrado']];
  let estadoHTML = '';
  if (!actual) estadoHTML = aviso(`Consulta de la ejecución #${ej}.`);
  else if (COMPLETAR.includes(P.estado)) estadoHTML = aviso('El registro durante el proceso terminó. Los valores que falten (por ejemplo, resultados de laboratorio) aún se pueden completar.', '', 'info');
  else if (abierta && !puedeEn(P, 'ejecutar')) estadoHTML = aviso('El registro lo hace cada área: Calidad, Producción, Seguridad y Mantenimiento.');

  pane.innerHTML = `${estadoHTML}
    <div class="grid grid-main mt-s">
      <div><div class="card">
        ${cardHead('Registros de la prueba', `Registre cada parámetro para toda la prueba o por ${noun}. Agregue un ${noun} cada vez que se produzca uno.`,
          `${selEjecucion(P, ej)}${altaBatch ? btn('data-ej="b-nuevo"', 'plus', `Agregar ${noun}`, 'primary') : ''}`)}
        ${items.length ? `<div class="unit-list">${filas.join('')}</div>` : vacio('Aún no hay parámetros definidos. Cada área los define en la pestaña Registro.')}
        ${abierta && (puedeEn(P, 'preparar') || puedeEn(P, 'ejecutar')) ? `<p class="hint mt-s">¿Falta un parámetro? <button class="link-btn" data-tab="registro">${icon('plus')} Agréguelo en Registro → Parámetros a evaluar</button></p>` : ''}
      </div></div>
      <div class="card"><div class="card-head"><div><h3>Avance por área</h3><p>Parámetros con al menos un valor</p></div></div>
        <div class="av-list">${avance || vacio('Sin parámetros.')}</div>
        ${abierta ? `${checklist(reqs)}
          ${P.estado === 'en_ejecucion' && puedeEn(P, 'ejecutar') ? `<button class="btn primary block mt" data-ej="terminar" ${reqs.every(([ok]) => ok) ? '' : 'disabled'}>${icon('flag')} Terminar y pasar a resultados</button>` : ''}
          <p class="hint mt-s">${P.estado === 'en_ejecucion' ? 'Lo que falte de laboratorio se puede completar después.' : 'El registro empieza con el primer dato capturado.'}</p>` : ''}
      </div>
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
        case 'general': if (!await capturaForm(P, { unidad: 'corrida', seccion: 'proceso' })) return; break;
        case 'b-cap': if (!await capturaForm(P, { unidad: 'batch', seccion: 'proceso', batch: D.B.find((x) => x.id === id) })) return; break;
        case 'b-del':
          if (!await confirmDialog({ title: `Eliminar ${noun}`, message: `Se eliminará el ${noun}. Si ya tiene parámetros registrados, bórrelos primero.`, confirmText: 'Eliminar', danger: true })) return;
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
  const fab = P.ejecucion_form === 'fabricacion';
  const D = await cargarDatos(P, P.ejecucion_actual);
  const items = itemsDe(D.PL, D.met, { seccion: 'complementarias' });
  const enCaptura = ABIERTA.includes(P.estado) || COMPLETAR.includes(P.estado);
  const puede = enCaptura && puedeCapturarAlgo(P, ['calidad']);
  const cats = COMPLEMENTARIAS.filter((c) => items.some((pl) => D.met(pl.metodo_id)?.categoria === c));
  const grupos = cats.map((c) => [c, NOM_CAT[c], (pl) => D.met(pl.metodo_id)?.categoria === c]);
  const filas = [filaUnidad({ ico: 'layers', titulo: 'Toda la prueba', sub: 'Una muestra representativa de la prueba', grupos, items, R: D.resDe((m) => m.nivel === 'corrida'), attrs: 'data-co="general"', puede })]
    .concat(D.B.map((b) => filaUnidad({ ico: 'package', titulo: `${fab ? 'Batch' : 'Corrida'} #${b.numero}`, sub: fmtDateTime(b.fecha_hora),
      grupos, items, R: D.resDe((m) => m.nivel === 'batch' && m.batch_id === b.id), attrs: `data-co="cap" data-id="${esc(b.id)}"`, puede })));
  pane.innerHTML = `<div class="card">
    ${cardHead('Evaluaciones complementarias', 'Evaluación sensorial (olor, color, sabor, textura), microbiología y análisis bromatológicos (proteínas, grasas, humedad, cenizas). Forman parte de los parámetros de Calidad; se registran para toda la prueba o por batch.')}
    ${!items.length ? vacio('Esta prueba no tiene evaluaciones complementarias en sus parámetros a evaluar.') : `<div class="unit-list">${filas.join('')}</div>`}
    ${items.length && !D.B.length ? '<p class="hint mt-s">Los batches se agregan en «Registro en proceso».</p>' : ''}
    ${enCaptura && !puede ? aviso('Las registra Calidad.') : ''}
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
