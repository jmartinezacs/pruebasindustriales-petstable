// =====================================================================
// Etapa 2 · En proceso.
// La prueba se registra solo después de que quien la registró la INICIA.
// Cada parámetro se registra para TODA LA PRUEBA (registro general, donde
// también van los análisis de laboratorio y sensoriales) o POR BATCH;
// quien captura agrega los batches conforme se producen. Cada área solo
// edita sus propios parámetros y participa si registra algún dato. Los
// responsables pueden evaluar lo ya registrado sin esperar a que termine.
// La prueba termina con el botón "Terminar prueba" o sola al concluir su
// fecha de ejecución.
// =====================================================================
import {
  sb, state, esc, icon, toast, errMsg, confirmDialog, mustRow, must, getCat, fmtDateTime, fmtDate, todayISO, pill, puedeEn, puedeArea, misAreas,
  AREAS, AREAS_ORDEN, COMPLEMENTARIAS, refreshIcons, fechaEjecTxt, fechaFinDe,
} from '../core.js';
import { iconBtn, aviso, vacio } from './exp_comun.js';
import { capturaForm, itemsDe, esLab } from './exp_captura.js';

const OP = { pendiente: ['Pendiente', 'warn'], conforme: ['Sin problemas', 'ok'], no_conforme: ['Con desviación', 'bad'] };
const COMPLETAR = ['en_evaluacion', 'pendiente_resultados'];
const ANTES = ['registrada', 'en_preparacion', 'preparada'];
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
  // Parámetros marcados "Pendiente" (resultado sin valor y sin ningún valor registrado)
  const pendientes = plan.data.filter((pl) => resultados.data.some((r) => r.plan_id === pl.id) && !resultados.data.some((r) => r.plan_id === pl.id && conValor(r)));
  return { met, resDe, B: batches.data, PL: plan.data, R: resultados.data.filter(conValor), pendientes };
}

// Parámetros (de la lista dada) con al menos un valor en esos resultados
const conDato = (items, R) => items.filter((pl) => R.some((r) => r.plan_id === pl.id)).length;
const puedeCapturarAlgo = (P, areas) => areas.some((a) => puedeArea(P, 'capturar', a) || puedeArea(P, 'evaluar', a));
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
  const fin = fechaFinDe(P);
  const vencida = fin && fin < todayISO();
  return AREAS_ORDEN.map((a) => {
    const xs = items.filter((pl) => D.met(pl.metodo_id)?.area === a); const n = conDato(xs, D.R);
    const pend = D.pendientes.filter((pl) => D.met(pl.metodo_id)?.area === a).length;
    let est;
    if (sinPar.includes(a)) est = [pill('Nada que evaluar', 'gray'), 'Indicó que no participa en esta prueba'];
    else if (part.includes(a) || n) est = [pill('Participa', 'ok'), `${n} de ${xs.length} parámetro(s) con dato${pend ? ` · ${pend} pendiente(s)` : ''}`];
    else if (!xs.length) est = [pill('Sin parámetros', 'warn'), 'Puede agregarlos durante la prueba'];
    else est = [pill(vencida ? 'Sin registros' : 'Esperando datos', vencida ? 'gray' : 'warn'),
      vencida ? `No registró nada en la fecha de ejecución: se considera que no requirió participar` : `${xs.length} parámetro(s) por registrar`];
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
  const items = itemsDe(D.PL, D.met, { unidad: 'corrida' });
  const itemsBatch = itemsDe(D.PL, D.met, { unidad: 'batch' });
  const areas = AREAS_ORDEN.filter((a) => items.some((pl) => D.met(pl.metodo_id)?.area === a));
  // Las barras de cada registro muestran solo las áreas de quien consulta; la participación de todas va aparte
  const vis = misAreas(P);
  const grupoArea = (a) => [a, AREAS[a].label, (pl) => D.met(pl.metodo_id)?.area === a && !esLab(D.met(pl.metodo_id))];
  const cats = COMPLEMENTARIAS.filter((c) => items.some((pl) => D.met(pl.metodo_id)?.categoria === c));
  const gruposGen = [...areas.filter((a) => vis.includes(a)).map(grupoArea),
    ...(vis.includes('calidad') ? cats.map((c) => [c, NOM_CAT[c], (pl) => D.met(pl.metodo_id)?.categoria === c]) : [])];
  const gruposBatch = areas.filter((a) => vis.includes(a)).map(grupoArea);
  const puede = enCaptura && puedeCapturarAlgo(P, areas);
  const Rgen = D.resDe((m) => m.nivel === 'corrida');
  const terminador = enProceso && (puedeEn(P, 'preparar') || puedeEn(P, 'ejecutar'));
  const fin = fechaFinDe(P);

  const general = mosaico({ ico: 'layers', titulo: 'Toda la prueba', cls: 'ut-general',
    sub: cats.length ? 'Una vez por prueba · incluye laboratorio y sensorial' : 'Lo que se mide una sola vez',
    grupos: gruposGen, items, R: Rgen, attrs: 'data-ej="general"', puede });
  const lotes = D.B.map((b) => mosaico({ ico: 'package', titulo: `${Noun} #${b.numero}`,
    sub: `${fmtDateTime(b.fecha_hora)} · ${pill(...OP[b.resultado_op])}${b.incidencias ? ` · ${esc(b.incidencias)}` : ''}`,
    grupos: gruposBatch, items: itemsBatch, R: D.resDe((m) => m.nivel === 'batch' && m.batch_id === b.id), attrs: `data-ej="b-cap" data-id="${esc(b.id)}"`, puede,
    extra: altaBatch ? iconBtn(`data-ej="b-del" data-id="${esc(b.id)}"`, 'trash-2', `Eliminar ${noun}`, 'bad') : '' }));

  // Evaluación durante el proceso: lo ya registrado de las áreas que la persona evalúa
  const misEval = AREAS_ORDEN.filter((a) => puedeArea(P, 'evaluar', a));
  const porEvaluar = actual && (enProceso || COMPLETAR.includes(P.estado)) && misEval.length ? (E.eval_faltantes || 0) : 0;

  let estadoHTML = '';
  if (!actual) estadoHTML = aviso(`Consulta de la ejecución #${ej}.`);
  else if (COMPLETAR.includes(P.estado)) estadoHTML = aviso('La prueba terminó; aún se pueden completar los valores pendientes.', '', 'info');
  else if (enProceso && !puede) estadoHTML = aviso('Cada área registra sus parámetros.');

  pane.innerHTML = `${estadoHTML}
    ${porEvaluar ? `<div class="notice info mt-s eval-cta">${icon('list-checks')}<span><b>${porEvaluar} parámetro(s) registrados por evaluar.</b> Puede evaluarlos sin esperar a que termine la prueba.</span>
      <button class="btn primary sm" data-tab="resultados">${icon('check-check')} Evaluar</button></div>` : ''}
    <div class="grid grid-main mt-s">
      <div>
        <div class="card">
          <div class="card-head"><div><h3>¿Dónde va a registrar?</h3><p>Toda la prueba o por ${noun}.</p></div>${selEjecucion(P, ej)}</div>
          ${items.length ? `<div class="unit-choice">
              ${general}
              <div class="unit-tile ut-batches">
                <div class="ut-main as-head"><span class="ut-ico">${icon('package')}</span><span class="ut-txt"><b>Por ${noun}</b>
                  <small>${D.B.length ? `${D.B.length} ${noun}(es) registrado(s)` : `Agregue uno por cada ${noun} producido`}</small></span></div>
                ${altaBatch ? `<button type="button" class="btn primary block" data-ej="b-nuevo">${icon('plus')} Nuevo ${noun}</button>` : `<p class="hint" style="margin:6px 2px 0">${enProceso ? 'Los agrega quien registra.' : `Ya no se agregan ${noun}es.`}</p>`}
              </div>
            </div>
            ${lotes.length ? `<div class="section-title mt">${icon('package')} ${Noun}es de la prueba</div><div class="unit-grid">${lotes.join('')}</div>` : ''}`
            : vacio('Aún no hay parámetros definidos (pestaña Registro).')}
          ${enProceso && areas.length < 4 ? `<p class="hint mt-s">¿Falta un parámetro? <button class="link-btn" data-tab="registro">${icon('plus')} Agregar en Registro</button></p>` : ''}
        </div>
      </div>
      <div>
        ${terminador ? `<div class="card fin-card">
          <div class="fin-head"><span class="fin-ico">${icon('flag')}</span><div><b>¿Ya terminó la prueba?</b>
            <span>${fin ? `Fecha de ejecución: ${esc(fechaEjecTxt(P))}. ${fin < todayISO() ? 'Ya concluyó.' : 'Si no la termina, se terminará sola al acabar el día ' + esc(fmtDate(fin)) + '.'}` : 'Termínela cuando se acabe de producir.'}</span></div></div>
          <button class="btn primary block lg" data-pa="terminar" ${D.R.length || D.B.length ? '' : 'disabled'}>${icon('flag')} Terminar prueba</button>
          <p class="hint mt-s">${D.R.length || D.B.length ? 'Lo pendiente de laboratorio se completa después.' : 'Requiere al menos un dato registrado.'}</p>
          ${puedeEn(P, 'preparar') && P.fecha_planeada ? `<button class="link-btn" data-ej="fecha">${icon('calendar')} Cambiar fecha final</button>` : ''}
        </div>` : ''}
        <div class="card ${terminador ? 'mt' : ''}">
          <div class="card-head"><div><h3>Participación por área</h3><p>Quién ya registró datos</p></div></div>
          <div class="area-rows">${estadoAreas(P, E, items, D)}</div>
        </div>
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
          let r = await capturaForm(P, { unidad: 'batch' });
          while (r?.siguiente) r = await capturaForm(P, { unidad: 'batch', previo: r.previo });
          recargar(); return;
        }
        case 'general': if (!await capturaForm(P, { unidad: 'corrida' })) return; break;
        case 'b-cap': if (!await capturaForm(P, { unidad: 'batch', batch: D.B.find((x) => x.id === id) })) return; break;
        case 'b-del':
          if (!await confirmDialog({ title: `Eliminar ${noun}`, message: `Se eliminará el ${noun}. Si ya tiene parámetros registrados, bórrelos primero.`, confirmText: 'Eliminar', danger: true })) return;
          mustRow(await sb.from('batches_prubind').delete().eq('id', id).select('id')); break;
        case 'fecha': {
          const r = await confirmDialog({ title: 'Fecha final de ejecución', message: `Inicia el ${fmtDate(P.fecha_planeada)}. La prueba se termina sola al acabar el último día.`, confirmText: 'Guardar',
            input: { label: 'Último día de la prueba', type: 'date', value: fin || '', min: todayISO() > P.fecha_planeada ? todayISO() : P.fecha_planeada, required: true } });
          if (!r) return;
          must(await sb.rpc('prubind_cambiar_fecha_fin', { p_prueba: P.id, p_fecha_fin: r.value }));
          toast('Fecha de ejecución actualizada.', 'success'); ctx.refrescar('proceso'); return;
        }
        default: return;
      }
      recargar();
    } catch (err) { toast(errMsg(err), 'error'); recargar(); }
  });
}
