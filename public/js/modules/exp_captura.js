// =====================================================================
// Captura por unidad de prueba: toda la prueba (registro general) o un
// batch / corrida. Cada quien solo edita los parámetros de su área:
//   · Calidad: inspectores o Jefe de Calidad.
//   · Producción: supervisores o Gerente de Producción.
//   · Seguridad: Supervisor o Ingeniero de Seguridad.
//   · Mantenimiento: Jefe o técnicos de Mantenimiento.
// Los análisis de laboratorio y sensoriales (bromatológicos, microbiología,
// sensorial) se registran para toda la prueba. Un valor que aún no se tiene
// se marca "Pendiente" y se completa al evaluar o en el dictamen. Cada
// parámetro puede llevar evidencia (fotos, reportes). La muestra se crea
// sola por unidad.
// =====================================================================
import {
  sb, state, esc, icon, toast, openModal, nullIfEmpty, must, mustRow, getCat, opciones, unidadTxt,
  todayISO, puedeEn, puedeArea, misAreas, AREAS, AREAS_ORDEN, COMPLEMENTARIAS, ayuda,
} from '../core.js';
import { aviso, criterioTxt, aLocal, eviPicker, eviChips, campoValor, leerValor, payloadValor, subirArchivos } from './exp_comun.js';

const TITULO_CAT = { sensorial: 'Evaluación sensorial', microbiologia: 'Microbiología', bromatologia: 'Análisis bromatológicos (proximal)' };
const ICO_CAT = { sensorial: 'eye', microbiologia: 'microscope', bromatologia: 'flask-round' };
export const NIVELES_UNIDAD = { batch: ['batch', 'lote_diario', 'compuesta'], corrida: ['corrida'], punto: ['punto'] };
export const ABIERTA = ['registrada', 'en_preparacion', 'preparada', 'en_ejecucion'];
const COMPLETAR = ['en_evaluacion', 'pendiente_resultados'];
const pad = (n) => String(n).padStart(2, '0');
const codigoLoteHoy = () => { const d = new Date(); return `L-${pad(d.getDate())}${pad(d.getMonth() + 1)}${String(d.getFullYear()).slice(2)}`; };
export const esLab = (m) => COMPLEMENTARIAS.includes(m?.categoria);
const conValor = (r) => r.valor_num != null || !!r.valor_opcion;

// Estado esperado según el criterio del plan (null si no hay criterio)
function evaluar(pl, m, valor) {
  if (valor === '' || valor == null) return null;
  if (m.tipo_resultado === 'numerico' || m.tipo_resultado === 'diluciones') {
    if (pl.crit_minimo == null && pl.crit_maximo == null) return null;
    const v = Number(valor);
    return (pl.crit_minimo == null || v >= pl.crit_minimo) && (pl.crit_maximo == null || v <= pl.crit_maximo) ? 'conforme' : 'no_conforme';
  }
  if (m.tipo_resultado === 'presencia') return /ausencia/i.test(pl.crit_texto || '') ? (valor === 'ausencia' ? 'conforme' : 'no_conforme') : null;
  if (['conforme', 'no_conforme', 'no_aplica', 'pendiente'].includes(valor)) return valor;
  return valor === 'no_evaluado' ? 'no_aplica' : null;
}

function ayudaMetodo(pl, m, un) {
  const crit = criterioTxt(pl, un);
  return [crit ? `Criterio: ${crit}${pl.crit_referencia ? ` (${pl.crit_referencia})` : ''}` : 'Sin criterio cargado: lo evalúa el responsable del área.',
    m.tecnica, m.horas_lectura ? `Lectura a las ${m.horas_lectura} h` : '', (m.diluciones || []).length ? `Diluciones ${m.diluciones.join(', ')}` : '',
    m.base_expresion ? `Base ${m.base_expresion}` : ''].filter(Boolean).join(' · ');
}

// Parámetros que se registran en una unidad: en "toda la prueba" van todos; por batch, todos menos los de
// laboratorio y sensoriales (esos se registran una vez para toda la prueba).
export function itemsDe(plan, met, { unidad = 'corrida' } = {}) {
  return plan.filter((pl) => { const m = met(pl.metodo_id); return m && (unidad !== 'batch' || !esLab(m)); });
}
// ¿Los parámetros del equipo van en esta unidad?
export const conEquipo = ({ unidad }) => unidad === 'corrida';

/**
 * @param {object} P prueba (v_pruebas)
 * @param {object} op { unidad: 'batch'|'corrida', batch?, previo? }
 * @returns {Promise<false|{siguiente:boolean, previo:object}>}
 */
export async function capturaForm(P, { unidad, batch = null, punto = null, previo = null }) {
  const ej = P.ejecucion_actual;
  const fab = P.ejecucion_form === 'fabricacion';
  const equipoAqui = conEquipo({ unidad });
  const [metodos, unidades, motivos, plan, muestras, resultados, lotes, nums, pars, controles, adjs] = await Promise.all([
    getCat('metodos'), getCat('unidades'), getCat('motivos'),
    sb.from('plan_evaluacion_prubind').select('*').eq('prueba_id', P.id).eq('incluido', true).order('orden'),
    sb.from('muestras_prubind').select('*').eq('prueba_id', P.id).eq('ejecucion', ej),
    sb.from('resultados_prubind').select('*').eq('prueba_id', P.id).eq('ejecucion', ej),
    unidad === 'batch' ? sb.from('lotes_diarios_prubind').select('*').eq('prueba_id', P.id).eq('ejecucion', ej).order('fecha') : { data: [] },
    unidad === 'batch' ? sb.from('batches_prubind').select('id, numero').eq('prueba_id', P.id).eq('ejecucion', ej) : { data: [] },
    equipoAqui ? sb.from('prueba_parametros_prubind').select('*').eq('prueba_id', P.id).order('orden') : { data: [] },
    equipoAqui ? sb.from('ejecucion_controles_prubind').select('*').eq('prueba_id', P.id).eq('ejecucion', ej) : { data: [] },
    sb.from('adjuntos_prubind').select('id, nombre, ruta, plan_id, batch_id').eq('prueba_id', P.id).not('plan_id', 'is', null),
  ]);
  [plan, muestras, resultados, lotes, nums, pars, controles, adjs].forEach((r) => { if (r.error) throw r.error; });
  const un = (id) => unidadTxt(unidades, id);
  const met = (id) => metodos.find((m) => m.id === id);
  const motDesv = motivos.filter((m) => m.tipo === 'desviacion');

  // Permisos: cada área captura lo suyo durante el proceso; los resultados se pueden completar hasta la evaluación
  const abierta = P.estado === 'en_ejecucion';
  const enCaptura = abierta || COMPLETAR.includes(P.estado);
  const capArea = (area) => enCaptura && (puedeArea(P, 'capturar', area) || puedeArea(P, 'evaluar', area));
  const ejecuta = abierta && puedeEn(P, 'ejecutar');            // alta de batches y datos generales del batch
  const equipoEdit = abierta && capArea('produccion');

  const muestra = muestras.data.find((s) => (unidad === 'batch' ? s.nivel === 'batch' && s.batch_id === batch?.id : s.nivel === 'corrida'));
  const R = muestra ? resultados.data.filter((r) => r.muestra_id === muestra.id) : [];
  const evid = (pl) => adjs.data.filter((a) => a.plan_id === pl.id && (a.batch_id || null) === (unidad === 'batch' ? batch?.id || '' : null));
  // Por batch también aparecen los de laboratorio que ya tengan algo registrado en ese batch (registros anteriores)
  const todosItems = plan.data.filter((pl) => { const m = met(pl.metodo_id); return m && (unidad !== 'batch' || !esLab(m) || R.some((r) => r.plan_id === pl.id)); });
  // Solo se muestran las áreas de quien registra (el administrador y quien solo consulta ven todas)
  const editablesTodos = todosItems.filter((pl) => capArea(met(pl.metodo_id).area));
  const verAreas = new Set([...misAreas(P), ...editablesTodos.map((pl) => met(pl.metodo_id).area)]);
  const items = todosItems.filter((pl) => verAreas.has(met(pl.metodo_id).area));
  const ocultas = todosItems.length - items.length;
  const editables = items.filter((pl) => capArea(met(pl.metodo_id).area));
  const esPendiente = (pl) => { const xs = R.filter((r) => r.plan_id === pl.id); return xs.length > 0 && !xs.some(conValor); };

  // Apartados por área; dentro de Calidad, laboratorio y sensorial por categoría
  const clave = (m) => (esLab(m) ? m.categoria : m.area);
  const ORDEN = ['calidad', ...COMPLEMENTARIAS, 'produccion', 'seguridad', 'mantenimiento'];
  const grupos = {};
  items.forEach((pl) => { (grupos[clave(met(pl.metodo_id))] ||= []).push(pl); });
  const secciones = Object.keys(grupos).sort((a, b) => ORDEN.indexOf(a) - ORDEN.indexOf(b));
  const tituloSec = (k) => (TITULO_CAT[k] ? `${icon(ICO_CAT[k])} ${esc(TITULO_CAT[k])} <span class="cell-sub">· Calidad</span>` : `${icon(AREAS[k].ico)} ${esc(AREAS[k].label)}`);

  // ---------- Campo de cada parámetro ----------
  const campo = (pl) => {
    const m = met(pl.metodo_id); const u = un(m.unidad_id); const edit = capArea(m.area);
    const etiqueta = `${esc(m.nombre)}${u && u !== m.nombre && m.tipo_resultado !== 'diluciones' ? ` <span class="cell-sub">(${esc(u)})</span>` : ''} ${ayuda(ayudaMetodo(pl, m, u))}`;
    const pend = esPendiente(pl);
    const vals = R.filter((r) => r.plan_id === pl.id && conValor(r));
    const just = R.find((r) => r.plan_id === pl.id && r.justificacion)?.justificacion || '';
    return `<div class="cap-item ${pend ? 'is-pend' : ''}" data-pl="${esc(pl.id)}">
      <div class="cap-lbl">${etiqueta}${m.codigo === 'SEN-SABOR' ? '<div class="cell-sub warn-txt">Solo conforme al protocolo autorizado y en condiciones de inocuidad.</div>' : ''}</div>
      <div class="cap-in">${campoValor(m, `r_${pl.id}`, { valores: vals, unidad: u, placeholder: criterioTxt(pl, u) || '', disabled: !edit || pend })}</div>
      ${edit ? `<div class="cap-tools"><label class="pend-tg" title="Aún no se tiene el valor; se completa después"><input type="checkbox" name="pd_${esc(pl.id)}" ${pend ? 'checked' : ''}>${icon('hourglass')}<span>Pendiente</span></label>
        ${eviPicker(`f_${pl.id}`, evid(pl))}</div>` : evid(pl).length ? `<div class="cap-tools">${eviChips(evid(pl))}</div>` : ''}
      <div class="cap-just hidden"><input name="j_${pl.id}" maxlength="500" value="${esc(just)}" placeholder="No cumple: explique brevemente *" aria-label="Explicación de ${esc(m.nombre)}" ${edit ? '' : 'disabled'}></div>
    </div>`;
  };

  // ---------- Datos del batch ----------
  const loteHoy = lotes.data.find((l) => l.fecha === todayISO());
  const nuevo = unidad === 'batch' && !batch;
  let cabecera = '';
  if (unidad === 'batch') {
    const dis = ejecuta ? '' : 'disabled';
    const nounL = fab ? 'batch' : 'corrida';
    // Número de batch según la programación del día (p. ej. 29, 30, 31); se sugiere el siguiente
    const siguienteNum = nums.data.reduce((mx, b) => Math.max(mx, b.numero), 0) + 1;
    cabecera = `
      <div class="field"><label for="cp-num">Número de ${nounL} <span class="req">*</span> ${ayuda(`El número que tiene el ${nounL} en la programación del día (por ejemplo 29, 30 o 31).`)}</label>
        <input id="cp-num" name="numero" type="number" inputmode="numeric" min="1" max="999" step="1" required value="${batch ? batch.numero : siguienteNum}" ${dis}></div>
      ${nuevo ? `<div class="field"><label for="cp-f">Fecha y hora</label><input id="cp-f" name="fecha_hora" type="datetime-local" required value="${aLocal(new Date())}"></div>` : ''}
      <div class="field full"><span class="label">¿${fab ? 'El batch se produjo' : 'La corrida se hizo'} sin problemas?</span>
        <div class="seg" role="radiogroup">${[['conforme', 'Sí'], ['no_conforme', 'No, hubo una desviación']].map(([k, l]) => `<label class="seg-opt"><input type="radio" name="op" value="${k}" ${k === (batch?.resultado_op === 'no_conforme' ? 'no_conforme' : 'conforme') ? 'checked' : ''} ${dis}><span>${l}</span></label>`).join('')}</div></div>
      <div class="field full hidden" id="cp-inc-w"><div class="form-grid">
        <div class="field"><label for="cp-m">Tipo de desviación</label><select id="cp-m" name="motivo" ${dis}>${opciones(motDesv, batch?.motivo_desviacion_id, { vacio: 'Seleccione…' })}</select></div>
        <div class="field"><label for="cp-i">¿Qué pasó? <span class="req">*</span></label><input id="cp-i" name="inc" maxlength="1000" value="${esc(batch?.incidencias || '')}" ${dis}></div></div></div>
`;
  }

  // ---------- Parámetros del equipo (Producción) ----------
  let equipoHTML = '';
  if (equipoAqui && pars.data.length && verAreas.has('produccion')) {
    const dis = equipoEdit ? '' : 'disabled';
    const C = controles.data;
    equipoHTML = `<div class="form-section">${icon('gauge')} Parámetros del equipo <span class="cell-sub">· Producción</span></div>
      ${pars.data.map((x) => { const c = C.find((k) => k.prueba_parametro_id === x.id); const rango = x.minimo != null || x.maximo != null;
        const ref = rango ? criterioTxt({ crit_minimo: x.minimo, crit_maximo: x.maximo }, un(x.unidad_id)) : (x.valor_objetivo || (x.referencia || '').split(' · ')[0]);
        return `<div class="cap-item" data-par="${esc(x.id)}">
          <div class="cap-lbl">${esc(x.nombre)} ${un(x.unidad_id) ? `<span class="cell-sub">(${esc(un(x.unidad_id))})</span>` : ''} ${ayuda(`${rango ? 'Rango aceptado' : 'Valor de referencia'}: ${ref || 'sin dato'}.`)}</div>
          <div class="cap-in"><input type="number" step="any" inputmode="decimal" name="p_${x.id}" value="${esc(c?.valor ?? '')}" placeholder="${esc(ref || '')}" ${dis}>
            ${rango ? '' : `<select name="pe_${x.id}" data-native ${dis} aria-label="Resultado de ${esc(x.nombre)}"><option value="conforme" ${c?.resultado !== 'no_conforme' ? 'selected' : ''}>Correcto</option><option value="no_conforme" ${c?.resultado === 'no_conforme' ? 'selected' : ''}>Fuera de lo esperado</option></select>`}</div>
          <div class="cap-just hidden"><input name="pj_${x.id}" maxlength="500" value="${esc(c?.observaciones || '')}" placeholder="Fuera de rango: explique brevemente *" ${dis}></div></div>`; }).join('')}`;
  }

  const puedeAlgo = editables.length > 0 || (unidad === 'batch' && ejecuta) || (equipoHTML && equipoEdit);
  const noun = fab ? 'Batch' : 'Corrida';
  const titulo = unidad === 'batch' ? (batch ? `${noun} #${batch.numero}` : `Nuevo ${noun.toLowerCase()}`) : unidad === 'punto' ? `Punto: ${punto.nombre}` : 'Toda la prueba';
  return openModal({
    title: titulo, subtitle: `${P.folio} · ${P.cambio}`, size: 'lg', submitText: puedeAlgo ? 'Guardar' : 'Cerrar',
    body: `<div class="unit-banner ${unidad === 'batch' ? 'is-batch' : 'is-general'}"><span class="ub-ico">${icon(unidad === 'batch' ? 'package' : 'layers')}</span>
        <div><small>Registrando en</small><b>${esc(titulo)}</b><span>${unidad === 'batch' ? `Valores de este ${fab ? 'batch' : 'corrida'}.` : 'Lo que se mide una sola vez, incluidos laboratorio y sensorial.'}</span></div></div>${!puedeAlgo ? aviso('Solo consulta: cada área registra sus propios parámetros.') : editables.length < items.length ? '<p class="hint">Los parámetros de otras áreas son solo de consulta.</p>' : ''}${ocultas ? `<p class="hint">${icon('eye-off')} Solo se muestran los parámetros de su área.</p>` : ''}
      <div class="form-grid">${cabecera}${equipoHTML}
      ${secciones.map((k) => `<div class="form-section">${tituloSec(k)}${k === 'microbiologia' ? ` ${ayuda('Capture cada dilución leída en UFC/g. Lo que aún no tenga lectura márquelo como Pendiente.')}` : ''}</div>
        <div class="cap-grid">${grupos[k].map(campo).join('')}</div>`).join('')}
      ${!secciones.length && !equipoHTML ? '<p class="hint full">No hay parámetros para registrar aquí.</p>' : ''}
      ${nuevo ? '<label class="check full"><input type="checkbox" name="siguiente" checked> Al guardar, capturar el siguiente batch</label>' : ''}
      </div>
      ${editables.length ? `<p class="hint">${icon('hourglass')} Marque <b>Pendiente</b> lo que aún no tenga (p. ej. resultados de laboratorio).</p>` : ''}`,
    onOpen: ({ form }) => {
      const sync = () => {
        const op = form.querySelector('input[name=op]:checked')?.value;
        form.querySelector('#cp-inc-w')?.classList.toggle('hidden', op !== 'no_conforme');
        form.querySelectorAll('.cap-item[data-pl]').forEach((w) => {
          const pl = items.find((x) => x.id === w.dataset.pl); const m = met(pl.metodo_id);
          const pend = !!form.elements[`pd_${pl.id}`]?.checked;
          w.classList.toggle('is-pend', pend);
          if (capArea(m.area)) w.querySelectorAll(`.cap-in [name^="r_${pl.id}"]`).forEach((i) => { i.disabled = pend; });
          const vals = pend ? [] : [...w.querySelectorAll(`[name^="r_${pl.id}"]`)].map((i) => i.value).filter((v) => v !== '');
          const nc = vals.some((v) => evaluar(pl, m, v) === 'no_conforme');
          w.querySelector('.cap-just').classList.toggle('hidden', !nc);
          w.classList.toggle('nc', !!nc);
        });
        form.querySelectorAll('.cap-item[data-par]').forEach((w) => {
          const x = pars.data.find((k) => k.id === w.dataset.par); const v = form.elements[`p_${x.id}`].value;
          const fuera = v !== '' && (x.minimo != null || x.maximo != null ? !((x.minimo == null || Number(v) >= x.minimo) && (x.maximo == null || Number(v) <= x.maximo))
            : form.elements[`pe_${x.id}`]?.value === 'no_conforme');
          w.querySelector('.cap-just').classList.toggle('hidden', !fuera);
          w.classList.toggle('nc', !!fuera);
        });
      };
      form.addEventListener('input', sync); form.addEventListener('change', sync); sync();
    },
    onSubmit: async ({ form, setError }) => {
      if (!puedeAlgo) return;
      const f = form.elements;
      const faltaJust = [...form.querySelectorAll('.cap-just:not(.hidden) input:not([disabled])')].find((i) => !i.value.trim());
      if (faltaJust) { faltaJust.focus(); setError('Explique brevemente los valores que no cumplen.'); return false; }
      if (unidad === 'batch' && ejecuta) {
        const n = Number(f.numero.value);
        if (!Number.isInteger(n) || n < 1 || n > 999) { f.numero.focus(); setError(`Indique el número de ${fab ? 'batch' : 'corrida'} (1 a 999).`); return false; }
        if (nums.data.some((b) => b.numero === n && b.id !== batch?.id)) { f.numero.focus(); setError(`Ya existe el ${fab ? 'batch' : 'corrida'} número ${n} en esta prueba.`); return false; }
        if (f.op?.value === 'no_conforme' && !f.inc.value.trim()) { f.inc.focus(); setError('Describa qué pasó en el batch.'); return false; }
      }

      // 1. Batch (alta o datos generales)
      let batchId = batch?.id;
      let loteId = null;
      if (unidad === 'batch' && ejecuta) {
        const datos = { numero: Number(f.numero.value), resultado_op: f.op?.value || 'conforme', motivo_desviacion_id: f.op?.value === 'no_conforme' ? nullIfEmpty(f.motivo.value) : null,
          incidencias: f.op?.value === 'no_conforme' ? nullIfEmpty(f.inc.value) : null };
        if (nuevo) {
          // Lote del día: se crea solo con el primer batch del día
          loteId = loteHoy?.id || must(await sb.from('lotes_diarios_prubind').insert({ prueba_id: P.id, codigo: codigoLoteHoy(), fecha: todayISO() }).select('id').single()).data.id;
          batchId = must(await sb.from('batches_prubind').insert({ ...datos, prueba_id: P.id, lote_diario_id: loteId,
            fecha_hora: new Date(f.fecha_hora.value).toISOString(), responsable_id: state.profile.id }).select('id').single()).data.id;
        } else if (['numero', 'resultado_op', 'motivo_desviacion_id', 'incidencias'].some((k) => String(datos[k] ?? '') !== String(batch[k] ?? ''))) {
          mustRow(await sb.from('batches_prubind').update(datos).eq('id', batch.id).select('id'));
        }
        previo = { lote: loteId || batch?.lote_diario_id };
      }

      // 2. Parámetros del equipo
      if (equipoHTML && equipoEdit) {
        for (const x of pars.data) {
          const v = f[`p_${x.id}`].value; const c = controles.data.find((k) => k.prueba_parametro_id === x.id);
          if (v === '' && !c) continue;
          const rango = x.minimo != null || x.maximo != null;
          const res = v === '' ? 'pendiente' : rango ? ((x.minimo == null || Number(v) >= x.minimo) && (x.maximo == null || Number(v) <= x.maximo) ? 'conforme' : 'no_conforme') : f[`pe_${x.id}`].value;
          const payload = { valor: nullIfEmpty(v), resultado: res, observaciones: res === 'no_conforme' ? nullIfEmpty(f[`pj_${x.id}`].value) : null, unidad_id: x.unidad_id };
          if (c) { if (String(c.valor ?? '') !== String(payload.valor ?? '') || c.resultado !== res || (c.observaciones || null) !== payload.observaciones) mustRow(await sb.from('ejecucion_controles_prubind').update(payload).eq('id', c.id).select('id')); }
          else must(await sb.from('ejecucion_controles_prubind').insert({ ...payload, prueba_id: P.id, prueba_parametro_id: x.id, nombre: x.nombre }));
        }
      }

      // 3. Resultados de los parámetros (solo los del área de quien captura)
      const archivos = editables.map((pl) => [pl, [...(f[`f_${pl.id}`]?.files || [])]]).filter(([, xs]) => xs.length);
      let muestraId = muestra?.id;
      if (editables.length) {
        const cambios = [];
        for (const pl of editables) {
          const m = met(pl.metodo_id);
          const previos = R.filter((r) => r.plan_id === pl.id);
          // Pendiente: se guarda un resultado sin valor (y se quitan los valores que hubiera)
          if (f[`pd_${pl.id}`]?.checked) {
            if (previos.length && !previos.some(conValor)) continue;
            previos.forEach((r) => cambios.push(['del', r.id]));
            cambios.push(['ins', null, { plan_id: pl.id, metodo_id: m.id, dilucion: m.tipo_resultado === 'diluciones' ? m.diluciones[0] : null, valor_num: null, valor_opcion: null, estado: 'pendiente' }]);
            continue;
          }
          const just = nullIfEmpty(f[`j_${pl.id}`]?.value.trim());
          for (const { d, v } of leerValor(form, m, `r_${pl.id}`)) {
            const previoR = previos.find((r) => (r.dilucion || null) === d);
            if (v === '') { if (previoR) cambios.push(['del', previoR.id]); continue; }
            const payload = { ...payloadValor(m, v) };
            payload.estado = evaluar(pl, m, v) || 'pendiente';
            payload.justificacion = payload.estado === 'no_conforme' ? (just || previoR?.justificacion || null) : null;
            if (previoR) {
              const igual = String(previoR.valor_num ?? '') === String(payload.valor_num ?? '') && (previoR.valor_opcion || null) === (payload.valor_opcion || null)
                && previoR.estado === payload.estado && (previoR.justificacion || null) === (payload.justificacion || null);
              if (!igual) cambios.push(['upd', previoR.id, payload]);
            } else cambios.push(['ins', null, { ...payload, plan_id: pl.id, metodo_id: m.id, dilucion: d }]);
          }
        }
        const nuevaMuestra = async () => must(await sb.from('muestras_prubind').insert({ prueba_id: P.id, nivel: unidad === 'batch' ? 'batch' : unidad, codigo: '', fecha_muestreo: todayISO(),
          batch_id: unidad === 'batch' ? batchId : null, punto_id: unidad === 'punto' ? punto.id : null }).select('id').single()).data.id;
        if (!muestraId && (cambios.some(([t]) => t === 'ins') || archivos.length)) muestraId = await nuevaMuestra();
        // Primero se borra (un "Pendiente" reemplaza los valores anteriores)
        for (const [t, id] of cambios.filter(([t]) => t === 'del')) mustRow(await sb.from('resultados_prubind').delete().eq('id', id).select('id'));
        for (const [t, id, payload] of cambios.filter(([t]) => t !== 'del')) {
          if (t === 'upd') mustRow(await sb.from('resultados_prubind').update(payload).eq('id', id).select('id'));
          else must(await sb.from('resultados_prubind').insert({ ...payload, prueba_id: P.id, muestra_id: muestraId, capturado_por: state.profile.id }));
        }
      }

      // 4. Evidencia de cada parámetro
      if (archivos.length) {
        const { data: rs } = must(await sb.from('resultados_prubind').select('id, plan_id').eq('muestra_id', muestraId));
        let n = 0;
        for (const [pl, files] of archivos) {
          n += await subirArchivos(P, files, { plan_id: pl.id, batch_id: unidad === 'batch' ? batchId : null, resultado_id: rs.find((r) => r.plan_id === pl.id)?.id || null, etapa: 'ejecucion' });
        }
        if (n) toast(`${n} evidencia(s) adjuntada(s).`, 'success');
      }
      toast(nuevo ? 'Batch registrado.' : 'Registro guardado.', 'success');
      return { siguiente: nuevo && !!f.siguiente?.checked, previo };
    },
  });
}

// Avance de captura: [con resultado, total]
export function avanceUnidad(items, R) {
  const hechos = items.filter((pl) => R.some((r) => r.plan_id === pl.id && conValor(r))).length;
  return [hechos, items.length];
}
// Áreas presentes en una lista de parámetros
export const areasDe = (items, met) => AREAS_ORDEN.filter((a) => items.some((pl) => met(pl.metodo_id)?.area === a));
