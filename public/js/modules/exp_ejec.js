// =====================================================================
// Etapa 2 · En proceso.
// La prueba se registra solo después de que quien la registró la INICIA.
// Todo se registra en UN SOLO formulario: cada parámetro va para toda la
// prueba (un valor) o por batch (un renglón por batch con su número). Cada
// área solo edita sus propios parámetros y participa si registra algún
// dato. La evaluación empieza cuando la prueba se termina, con el botón
// "Terminar prueba" o sola al concluir su fecha de ejecución.
// =====================================================================
import {
  sb, esc, icon, toast, errMsg, confirmDialog, must, getCat, fmtDate, todayISO, pill, puedeEn, puedeArea, misAreas,
  AREAS, AREAS_ORDEN, COMPLEMENTARIAS, refreshIcons, fechaEjecTxt, fechaFinDe,
} from '../core.js';
import { aviso, vacio } from './exp_comun.js';
import { registroForm, esLab } from './exp_captura.js';

const COMPLETAR = ['en_evaluacion', 'pendiente_resultados'];
const ANTES = ['registrada', 'en_preparacion', 'preparada'];
const NOM_CAT = { sensorial: 'Sensorial', microbiologia: 'Microbiología', bromatologia: 'Bromatológicos' };

async function cargarDatos(P, ej) {
  const [metodos, batches, plan, resultados] = await Promise.all([
    getCat('metodos'),
    sb.from('v_batches_prubind').select('*').eq('prueba_id', P.id).eq('ejecucion', ej).order('numero'),
    sb.from('plan_evaluacion_prubind').select('id, nivel, metodo_id').eq('prueba_id', P.id).eq('incluido', true),
    sb.from('resultados_prubind').select('id, plan_id, muestra_id, valor_num, valor_opcion').eq('prueba_id', P.id).eq('ejecucion', ej),
  ]);
  [batches, plan, resultados].forEach((r) => { if (r.error) throw r.error; });
  const met = (id) => metodos.find((m) => m.id === id);
  const conValor = (r) => r.valor_num != null || r.valor_opcion;
  // Parámetros marcados "Pendiente" (resultado sin valor y sin ningún valor registrado)
  const pendientes = plan.data.filter((pl) => resultados.data.some((r) => r.plan_id === pl.id) && !resultados.data.some((r) => r.plan_id === pl.id && conValor(r)));
  return { met, B: batches.data, PL: plan.data.filter((pl) => met(pl.metodo_id)), R: resultados.data.filter(conValor), pendientes };
}

// Parámetros (de la lista dada) con al menos un valor
const conDato = (items, R) => items.filter((pl) => R.some((r) => r.plan_id === pl.id)).length;
const puedeCapturarAlgo = (P, areas) => areas.some((a) => puedeArea(P, 'capturar', a) || puedeArea(P, 'evaluar', a));
const selEjecucion = (P, ej) => (P.ejecucion_actual > 1 ? `<label class="inline-sel">Ejecución <select id="ej-sel" data-native>${Array.from({ length: P.ejecucion_actual }, (_, i) => i + 1)
  .map((n) => `<option value="${n}" ${n === ej ? 'selected' : ''}>#${n}${n === P.ejecucion_actual ? ' (actual)' : ''}</option>`).join('')}</select></label>` : '');

// Avance de un grupo (área o categoría): barra fina con su color
const barras = (grupos, items, R) => grupos.map(([k, label, pred]) => {
  const xs = items.filter(pred); if (!xs.length) return '';
  const n = conDato(xs, R);
  return `<div class="ut-bar g-${k}" title="${esc(label)}: ${n} de ${xs.length} con dato"><span>${esc(label)}</span><i><b style="width:${Math.round((n / xs.length) * 100)}%"></b></i><em>${n}/${xs.length}</em></div>`;
}).join('');

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
      vencida ? 'No registró nada en la fecha de ejecución: se considera que no requirió participar' : `${xs.length} parámetro(s) por registrar`];
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
  const items = D.PL;
  const areas = AREAS_ORDEN.filter((a) => items.some((pl) => D.met(pl.metodo_id)?.area === a));
  // El avance muestra las áreas de quien consulta; la participación de todas va aparte
  const vis = misAreas(P);
  const cats = COMPLEMENTARIAS.filter((c) => items.some((pl) => D.met(pl.metodo_id)?.categoria === c));
  const grupos = [...areas.filter((a) => vis.includes(a)).map((a) => [a, AREAS[a].label, (pl) => D.met(pl.metodo_id)?.area === a && !esLab(D.met(pl.metodo_id))]),
    ...(vis.includes('calidad') ? cats.map((c) => [c, NOM_CAT[c], (pl) => D.met(pl.metodo_id)?.categoria === c]) : [])];
  const puede = enCaptura && puedeCapturarAlgo(P, areas);
  const terminador = enProceso && (puedeEn(P, 'preparar') || puedeEn(P, 'ejecutar'));
  const fin = fechaFinDe(P);
  const conMios = conDato(items.filter((pl) => vis.includes(D.met(pl.metodo_id)?.area)), D.R);

  let estadoHTML = '';
  if (!actual) estadoHTML = aviso(`Consulta de la ejecución #${ej}.`);
  else if (COMPLETAR.includes(P.estado)) estadoHTML = aviso('La prueba terminó: los responsables ya evalúan. Aún se pueden completar los valores pendientes.', '', 'info');
  else if (enProceso && !puede) estadoHTML = aviso('Cada área registra sus parámetros.');

  pane.innerHTML = `${estadoHTML}
    <div class="grid grid-main mt-s">
      <div>
        <div class="card reg-card">
          <div class="card-head"><div><h3>Datos de la prueba</h3><p>Un solo formulario: cada parámetro va para toda la prueba o por ${noun}.</p></div>${selEjecucion(P, ej)}</div>
          ${items.length ? `
            <button type="button" class="reg-cta ${puede ? '' : 'ver'}" data-ej="registrar">
              <span class="reg-ico">${icon(puede ? 'clipboard-pen' : 'eye')}</span>
              <span class="reg-txt"><b>${puede ? 'Registrar datos' : 'Ver datos registrados'}</b>
                <small>${puede ? (conMios ? `${conMios} parámetro(s) de su área con dato. Toque para continuar.` : 'Toque para capturar los valores de su área.') : 'Solo consulta.'}</small></span>
              ${icon('chevron-right')}
            </button>
            <div class="ut-bars reg-bars">${barras(grupos, items, D.R)}</div>
            <div class="section-title mt">${icon('package')} ${Noun}es registrados</div>
            ${D.B.length ? `<div class="chips reg-batches">${D.B.map((b) => `<span class="chip">${icon('package')} ${Noun} ${b.numero}</span>`).join('')}</div>`
              : `<p class="hint">Aún no hay ${noun}es. Se crean solos al elegir <b>Por ${noun}</b> en un parámetro y escribir su número.</p>`}`
            : vacio('Aún no hay parámetros definidos (pestaña Registro).')}
          ${enProceso && areas.length < 4 ? `<p class="hint mt-s">¿Falta un parámetro? <button class="link-btn" data-tab="registro">${icon('plus')} Agregar en Registro</button></p>` : ''}
        </div>
      </div>
      <div>
        ${terminador ? `<div class="card fin-card">
          <div class="fin-head"><span class="fin-ico">${icon('flag')}</span><div><b>¿Ya terminó la prueba?</b>
            <span>${fin ? `Fecha de ejecución: ${esc(fechaEjecTxt(P))}. ${fin < todayISO() ? 'Ya concluyó.' : `Si no la termina, se terminará sola al acabar el día ${esc(fmtDate(fin))}.`}` : 'Termínela cuando se acabe de producir.'} Al terminarla, los responsables podrán evaluar.</span></div></div>
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
    try {
      switch (b.dataset.ej) {
        case 'registrar': if (!await registroForm(P)) return; break;
        case 'fecha': {
          const r = await confirmDialog({ title: 'Fecha final de ejecución', message: `Inicia el ${fmtDate(P.fecha_planeada)}. La prueba se termina sola al acabar el último día.`, confirmText: 'Guardar',
            input: { label: 'Último día de la prueba', type: 'date', value: fin || '', min: todayISO() > P.fecha_planeada ? todayISO() : P.fecha_planeada, required: true } });
          if (!r) return;
          must(await sb.rpc('prubind_cambiar_fecha_fin', { p_prueba: P.id, p_fecha_fin: r.value }));
          toast('Fecha de ejecución actualizada.', 'success'); break;
        }
        default: return;
      }
      recargar();
    } catch (err) { toast(errMsg(err), 'error'); recargar(); }
  });
}
