// =====================================================================
// Etapa 2 · En proceso y etapa 3 · Evaluaciones complementarias.
// La prueba se registra solo después de que quien la registró la INICIA.
// Cada parámetro se registra para TODA LA PRUEBA (registro general) o POR
// BATCH; quien captura agrega los batches conforme se producen. Por lo
// general los inspectores registran por batch y los supervisores para toda
// la prueba. Cada área solo edita sus propios parámetros y participa si
// registra algún dato.
// =====================================================================
import {
  sb, state, esc, icon, toast, errMsg, confirmDialog, mustRow, getCat, fmtDateTime, fmtDate, todayISO, pill, puedeEn, puedeArea, misAreas,
  AREAS, AREAS_ORDEN, COMPLEMENTARIAS, TIPOS_COMPLEMENTARIAS, refreshIcons,
} from '../core.js';
import { iconBtn, aviso, vacio, subirEvidencia } from './exp_comun.js';
import { capturaForm, itemsDe } from './exp_captura.js';

const OP = { pendiente: ['Pendiente', 'warn'], conforme: ['Sin problemas', 'ok'], no_conforme: ['Con desviación', 'bad'] };
const COMPLETAR = ['en_evaluacion', 'pendiente_resultados'];
const ANTES = ['registrada', 'en_preparacion', 'preparada'];
const NOM_CAT = { sensorial: 'Sensorial', microbiologia: 'Microbiología', bromatologia: 'Bromatológicos' };
const ICO_CAT = { sensorial: 'eye', microbiologia: 'microscope', bromatologia: 'flask-round' };

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

// Avance de un grupo (área o categoría) dentro de una unidad: barra fina con su color
const barras = (grupos, items, R) => grupos.map(([k, label, pred]) => {
  const xs = items.filter(pred); if (!xs.length) return '';
  const n = conDato(xs, R);
  return `<div class="ut-bar g-${k}" title="${esc(label)}: ${n} de ${xs.length} con dato"><span>${esc(label)}</span><i><b style="width:${Math.round((n / xs.length) * 100)}%"></b></i><em>${n}/${xs.length}</em></div>`;
}).join('');

// Mosaico de una unidad de registro (toda la prueba o un batch)
function mosaico({ ico, titulo, sub, grupos, items, R, attrs, puede, cls = '', extra = '' }) {
  const n = conDato(items, R);
  return `<div class="unit-tile ${cls} ${n ? 'con-datos' : ''}">
    <button type="button" class="ut-main" ${attrs} aria-label="${puede ? 'Registrar en' : 'Ver'} ${esc(titulo)}">
      <span class="ut-ico">${icon(ico)}</span>
      <span class="ut-txt"><b>${esc(titulo)}</b><small>${sub}</small></span>
      <span class="ut-go">${icon(puede ? 'clipboard-pen' : 'eye')}<span>${puede ? 'Registrar' : 'Ver'}</span></span>
    </button>
    <div class="ut-bars">${barras(grupos, items, R)}</div>
    ${extra ? `<div class="ut-extra">${extra}</div>` : ''}
  </div>`;
}

// Situación de cada área en la prueba
function estadoAreas(P, E, items, D) {
  const sinPar = E.sin_parametros || [], part = E.participantes || [];
  const vencida = P.fecha_planeada && P.fecha_planeada < todayISO();
  return AREAS_ORDEN.map((a) => {
    const xs = items.filter((pl) => D.met(pl.metodo_id)?.area === a); const n = conDato(xs, D.R);
    let est;
    if (sinPar.includes(a)) est = [pill('Nada que evaluar', 'gray'), 'Indicó que no participa en esta prueba'];
    else if (part.includes(a) || n) est = [pill('Participa', 'ok'), `${n} de ${xs.length} parámetro(s) con dato`];
    else if (!xs.length) est = [pill('Sin parámetros', 'warn'), 'Puede agregarlos durante la prueba'];
    else est = [pill(vencida ? 'Sin registros' : 'Esperando datos', vencida ? 'gray' : 'warn'),
      vencida ? `No registró nada el ${fmtDate(P.fecha_planeada)}: se considera que no requirió participar` : `${xs.length} parámetro(s) por registrar`];
    return `<div class="area-row g-${a}"><span class="ar-ico">${icon(AREAS[a].ico)}</span><div class="li-main"><b>${esc(AREAS[a].label)}</b><span>${est[1]}</span></div>${est[0]}</div>`;
  }).join('');
}

// ============================== EN PROCESO ==============================
export async function etapaProceso(pane, ctx) {
  const { P, E } = ctx;
  const ej = ctx.ejecucion || P.ejecucion_actual;
  const actual = ej === P.ejecucion_actual;
  const fab = P.ejecucion_form === 'fabricacion';
  const noun = fab ? 'batch' : 'corrida', Noun = fab ? 'Batch' : 'Corrida';

  // Antes de iniciar: no se registra nada todavía
  if (actual && ANTES.includes(P.estado)) {
    const inicia = puedeEn(P, 'preparar');
    pane.innerHTML = `<div class="card start-card">
      <span class="start-ico">${icon('circle-play')}</span>
      <h3>La prueba aún no inicia</h3>
      <p>${inicia ? 'Iníciela cuando esté lista; se avisará a las áreas.'
        : `${esc(P.registrado_por_nombre || 'Quien registró la prueba')} la iniciará.`}</p>
      ${inicia ? `<button class="btn primary lg" data-pa="iniciar">${icon('play')} Iniciar prueba</button>` : `<button class="btn secondary" data-tab="registro">${icon('list-checks')} Ver parámetros a evaluar</button>`}
    </div>`;
    refreshIcons(); return;
  }

  const D = await cargarDatos(P, ej);
  const enProceso = actual && P.estado === 'en_ejecucion';
  const enCaptura = actual && (enProceso || COMPLETAR.includes(P.estado));
  const altaBatch = enProceso && puedeEn(P, 'ejecutar');
  const items = itemsDe(D.PL, D.met, { seccion: 'proceso' });
  const areas = AREAS_ORDEN.filter((a) => items.some((pl) => D.met(pl.metodo_id)?.area === a));
  // Las barras de cada registro muestran solo las áreas de quien consulta; la participación de todas va aparte
  const vis = misAreas(P);
  const grupos = areas.filter((a) => vis.includes(a)).map((a) => [a, AREAS[a].label, (pl) => D.met(pl.metodo_id)?.area === a]);
  const puede = enCaptura && puedeCapturarAlgo(P, areas);
  const Rgen = D.resDe((m) => m.nivel === 'corrida');

  const general = mosaico({ ico: 'layers', titulo: 'Toda la prueba', cls: 'ut-general',
    sub: 'Lo que se mide una sola vez',
    grupos, items, R: Rgen, attrs: 'data-ej="general"', puede });
  const lotes = D.B.map((b) => mosaico({ ico: 'package', titulo: `${Noun} #${b.numero}`,
    sub: `${fmtDateTime(b.fecha_hora)} · ${pill(...OP[b.resultado_op])}${b.incidencias ? ` · ${esc(b.incidencias)}` : ''}`,
    grupos, items, R: D.resDe((m) => m.nivel === 'batch' && m.batch_id === b.id), attrs: `data-ej="b-cap" data-id="${esc(b.id)}"`, puede,
    extra: `${iconBtn(`data-ej="b-evi" data-id="${esc(b.id)}"`, 'paperclip', 'Adjuntar evidencia')}${altaBatch ? iconBtn(`data-ej="b-del" data-id="${esc(b.id)}"`, 'trash-2', `Eliminar ${noun}`, 'bad') : ''}` }));

  let estadoHTML = '';
  if (!actual) estadoHTML = aviso(`Consulta de la ejecución #${ej}.`);
  else if (COMPLETAR.includes(P.estado)) estadoHTML = aviso('La prueba terminó; aún se pueden completar valores pendientes.', '', 'info');
  else if (enProceso && !puede) estadoHTML = aviso('Cada área registra sus parámetros.');

  pane.innerHTML = `${estadoHTML}
    <div class="grid grid-main mt-s">
      <div>
        <div class="card">
          <div class="card-head"><div><h3>¿Dónde va a registrar?</h3><p>Toda la prueba o por ${noun}.</p></div>${selEjecucion(P, ej)}</div>
          ${items.length ? `<div class="unit-choice">
              ${general}
              <div class="unit-tile ut-batches">
                <div class="ut-main as-head"><span class="ut-ico">${icon('package')}</span><span class="ut-txt"><b>Por ${noun}</b>
                  <small>${D.B.length ? `${D.B.length} ${noun}(es) registrado(s)` : `Agregue uno por cada ${noun} producido`}</small></span></div>
                ${altaBatch ? `<button type="button" class="btn primary block" data-ej="b-nuevo">${icon('plus')} Nuevo ${noun}</button>` : `<p class="hint" style="margin:6px 2px 0">${enProceso ? `Los agrega quien registra.` : `Ya no se agregan ${noun}es.`}</p>`}
              </div>
            </div>
            ${lotes.length ? `<div class="section-title mt">${icon('package')} ${Noun}es de la prueba</div><div class="unit-grid">${lotes.join('')}</div>` : ''}`
            : vacio('Aún no hay parámetros definidos (pestaña Registro).')}
          ${enProceso && areas.length < 4 ? `<p class="hint mt-s">¿Falta un parámetro? <button class="link-btn" data-tab="registro">${icon('plus')} Agregar en Registro</button></p>` : ''}
        </div>
      </div>
      <div class="card">
        <div class="card-head"><div><h3>Participación por área</h3><p>Quién ya registró datos</p></div></div>
        <div class="area-rows">${estadoAreas(P, E, items, D)}</div>
        ${enProceso && (puedeEn(P, 'preparar') || puedeEn(P, 'ejecutar')) ? `<button class="btn primary block mt" data-pa="terminar" ${D.R.length || D.B.length ? '' : 'disabled'}>${icon('flag')} Terminar prueba</button>
          <p class="hint mt-s">${D.R.length || D.B.length ? 'Lo pendiente de laboratorio se completa después.' : 'Requiere al menos un dato registrado.'}</p>` : ''}
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
          while (r?.siguiente) r = await capturaForm(P, { unidad: 'batch', seccion: 'proceso', previo: r.previo });
          recargar(); return;
        }
        case 'general': if (!await capturaForm(P, { unidad: 'corrida', seccion: 'proceso' })) return; break;
        case 'b-cap': if (!await capturaForm(P, { unidad: 'batch', seccion: 'proceso', batch: D.B.find((x) => x.id === id) })) return; break;
        case 'b-del':
          if (!await confirmDialog({ title: `Eliminar ${noun}`, message: `Se eliminará el ${noun}. Si ya tiene parámetros registrados, bórrelos primero.`, confirmText: 'Eliminar', danger: true })) return;
          mustRow(await sb.from('batches_prubind').delete().eq('id', id).select('id')); break;
        case 'b-evi': if (!await subirEvidencia(P, { batch_id: id, etapa: 'ejecucion' })) return; break;
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
  if (ANTES.includes(P.estado)) {
    pane.innerHTML = aviso('Las evaluaciones complementarias se registran cuando la prueba ya inició.', '', 'circle-play');
    refreshIcons(); return;
  }
  const fab = P.ejecucion_form === 'fabricacion';
  const D = await cargarDatos(P, P.ejecucion_actual);
  const items = itemsDe(D.PL, D.met, { seccion: 'complementarias' });
  const enCaptura = P.estado === 'en_ejecucion' || COMPLETAR.includes(P.estado);
  const puede = enCaptura && puedeCapturarAlgo(P, ['calidad']);
  const cats = COMPLEMENTARIAS.filter((c) => items.some((pl) => D.met(pl.metodo_id)?.categoria === c));
  const grupos = cats.map((c) => [c, NOM_CAT[c], (pl) => D.met(pl.metodo_id)?.categoria === c]);
  const tiles = [mosaico({ ico: 'layers', titulo: 'Toda la prueba', cls: 'ut-general', sub: 'Una muestra representativa de la prueba', grupos, items, R: D.resDe((m) => m.nivel === 'corrida'), attrs: 'data-co="general"', puede })]
    .concat(D.B.map((b) => mosaico({ ico: 'package', titulo: `${fab ? 'Batch' : 'Corrida'} #${b.numero}`, sub: fmtDateTime(b.fecha_hora),
      grupos, items, R: D.resDe((m) => m.nivel === 'batch' && m.batch_id === b.id), attrs: `data-co="cap" data-id="${esc(b.id)}"`, puede })));
  // Son parámetros de Calidad: para las demás áreas el apartado aparece contraído (se puede abrir)
  pane.innerHTML = `<div class="card plegable ${misAreas(P).includes('calidad') ? '' : 'colapsada'}">
    <div class="card-head"><div><h3>Evaluaciones complementarias</h3><p>Sensorial, microbiología y bromatológicos (Calidad).</p></div><span class="pleg-ico">${icon('chevron-down')}</span></div>
    <div class="compl-cats">${cats.map((c) => `<span class="chip on">${icon(ICO_CAT[c])} ${esc(NOM_CAT[c])}</span>`).join('')}</div>
    ${cats.includes('bromatologia') ? `<div class="notice info mt-s">${icon('hourglass')}<span>Los bromatológicos pueden quedar <b>pendientes de laboratorio</b> sin detener la evaluación.</span></div>` : ''}
    ${!items.length ? vacio('Sin evaluaciones complementarias.') : `<div class="unit-grid mt-s">${tiles.join('')}</div>`}
    ${items.length && !D.B.length ? '<p class="hint mt-s">Los batches se agregan en «En proceso».</p>' : ''}
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
