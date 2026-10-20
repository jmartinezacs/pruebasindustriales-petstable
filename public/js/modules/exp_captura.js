// =====================================================================
// Captura por unidad de prueba (batch, corrida o punto) y por sección:
//   · proceso: lo que registran Calidad (inspectores) y Producción
//     (supervisores) durante el proceso.
//   · complementarias: evaluación sensorial, microbiología y bromatología.
//   · general: Seguridad y Mantenimiento (una vez por prueba) y los
//     parámetros del equipo.
// Cada quien solo edita los parámetros de su área; el resto se ve en
// modo consulta. La muestra se crea sola por unidad.
// =====================================================================
import {
  sb, state, esc, icon, toast, openModal, nullIfEmpty, must, mustRow, getCat, opciones, unidadTxt, fmtDate,
  todayISO, puedeEn, puedeArea, OPCIONES_TXT, AREAS, AREAS_ORDEN, COMPLEMENTARIAS, ayuda,
} from '../core.js';
import { aviso, criterioTxt, aLocal } from './exp_comun.js';

const TITULO_CAT = { sensorial: 'Evaluación sensorial', microbiologia: 'Microbiología', bromatologia: 'Análisis bromatológicos (proximal)' };
const ICO_CAT = { sensorial: 'eye', microbiologia: 'microscope', bromatologia: 'flask-round' };
export const NIVELES_UNIDAD = { batch: ['batch', 'lote_diario', 'compuesta'], corrida: ['corrida'], punto: ['punto'] };
export const ABIERTA = ['registrada', 'en_preparacion', 'preparada', 'en_ejecucion'];
const COMPLETAR = ['en_evaluacion', 'pendiente_resultados'];
const pad = (n) => String(n).padStart(2, '0');
const codigoLoteHoy = () => { const d = new Date(); return `L-${pad(d.getDate())}${pad(d.getMonth() + 1)}${String(d.getFullYear()).slice(2)}`; };

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

// Parámetros del plan que corresponden a la unidad y la sección
export function itemsDe(plan, met, { unidad, seccion, fab }) {
  return plan.filter((pl) => {
    const m = met(pl.metodo_id);
    if (!m || !NIVELES_UNIDAD[unidad].includes(pl.nivel)) return false;
    const compl = COMPLEMENTARIAS.includes(m.categoria);
    if (seccion === 'complementarias') return compl;
    if (compl) return false;
    if (seccion === 'proceso') return unidad === 'batch' || ['calidad', 'produccion'].includes(m.area);
    return fab || ['seguridad', 'mantenimiento'].includes(m.area);   // general
  });
}
// ¿Los parámetros del equipo van en esta sección?
export const conEquipo = ({ unidad, seccion, fab }) => unidad === 'corrida' && ((fab && seccion === 'general') || (!fab && seccion === 'proceso'));

/**
 * @param {object} P prueba (v_pruebas)
 * @param {object} op { unidad: 'batch'|'corrida'|'punto', seccion, batch?, punto?, previo? }
 * @returns {Promise<false|{siguiente:boolean, previo:object}>}
 */
export async function capturaForm(P, { unidad, seccion = 'proceso', batch = null, punto = null, previo = null }) {
  const ej = P.ejecucion_actual;
  const fab = P.ejecucion_form === 'fabricacion';
  const equipoAqui = conEquipo({ unidad, seccion, fab });
  const [metodos, unidades, motivos, materias, plan, muestras, resultados, lotes, lotesMp, pars, controles] = await Promise.all([
    getCat('metodos'), getCat('unidades'), getCat('motivos'), getCat('materias'),
    sb.from('plan_evaluacion_prubind').select('*').eq('prueba_id', P.id).eq('incluido', true).order('orden'),
    sb.from('muestras_prubind').select('*').eq('prueba_id', P.id).eq('ejecucion', ej),
    sb.from('resultados_prubind').select('*').eq('prueba_id', P.id).eq('ejecucion', ej),
    unidad === 'batch' && seccion === 'proceso' ? sb.from('lotes_diarios_prubind').select('*').eq('prueba_id', P.id).eq('ejecucion', ej).order('fecha') : { data: [] },
    unidad === 'batch' && seccion === 'proceso' ? sb.from('lotes_mp_prubind').select('id, lote, materia_prima_id, caducidad').eq('activo', true).order('lote').limit(1000) : { data: [] },
    equipoAqui ? sb.from('prueba_parametros_prubind').select('*').eq('prueba_id', P.id).order('orden') : { data: [] },
    equipoAqui ? sb.from('ejecucion_controles_prubind').select('*').eq('prueba_id', P.id).eq('ejecucion', ej) : { data: [] },
  ]);
  [plan, muestras, resultados, lotes, lotesMp, pars, controles].forEach((r) => { if (r.error) throw r.error; });
  const un = (id) => unidadTxt(unidades, id);
  const met = (id) => metodos.find((m) => m.id === id);
  const mpNom = (id) => materias.find((m) => m.id === id)?.nombre || '';
  const motDesv = motivos.filter((m) => m.tipo === 'desviacion');

  // Permisos: cada área captura lo suyo durante el proceso; los resultados se pueden completar hasta la evaluación
  const abierta = ABIERTA.includes(P.estado);
  const enCaptura = abierta || COMPLETAR.includes(P.estado);
  const capArea = (area) => enCaptura && (puedeArea(P, 'capturar', area) || puedeArea(P, 'evaluar', area) || P.responsable_ejecucion_id === state.profile.id);
  const ejecuta = abierta && puedeEn(P, 'ejecutar');            // alta de batches y datos generales del batch
  const equipoEdit = abierta && capArea('produccion') && puedeEn(P, 'ejecutar');

  const muestra = muestras.data.find((s) => (unidad === 'batch' ? s.nivel === 'batch' && s.batch_id === batch?.id
    : unidad === 'punto' ? s.punto_id === punto?.id : s.nivel === 'corrida'));
  const R = muestra ? resultados.data.filter((r) => r.muestra_id === muestra.id) : [];
  const items = itemsDe(plan.data, met, { unidad, seccion, fab });
  const editables = items.filter((pl) => capArea(met(pl.metodo_id).area));

  // Apartados por área (Calidad, complementarias por categoría, Producción, Seguridad, Mantenimiento)
  const clave = (m) => (COMPLEMENTARIAS.includes(m.categoria) ? m.categoria : m.area);
  const ORDEN = ['calidad', ...COMPLEMENTARIAS, 'produccion', 'seguridad', 'mantenimiento'];
  const grupos = {};
  items.forEach((pl) => { (grupos[clave(met(pl.metodo_id))] ||= []).push(pl); });
  const secciones = Object.keys(grupos).sort((a, b) => ORDEN.indexOf(a) - ORDEN.indexOf(b));
  const tituloSec = (k) => (TITULO_CAT[k] ? `${icon(ICO_CAT[k])} ${esc(TITULO_CAT[k])}` : `${icon(AREAS[k].ico)} ${esc(AREAS[k].label)}`);

  // ---------- Campo de cada parámetro ----------
  const campo = (pl) => {
    const m = met(pl.metodo_id); const u = un(m.unidad_id); const dis = capArea(m.area) ? '' : 'disabled';
    const r1 = R.find((r) => r.plan_id === pl.id && !r.dilucion);
    const etiqueta = `${esc(m.nombre)}${u && u !== m.nombre && m.tipo_resultado !== 'diluciones' ? ` <span class="cell-sub">(${esc(u)})</span>` : ''} ${ayuda(ayudaMetodo(pl, m, u))}`;
    let input;
    if (m.tipo_resultado === 'diluciones') {
      input = `<div class="dil-grid">${m.diluciones.map((d, i) => { const r = R.find((x) => x.plan_id === pl.id && x.dilucion === d);
        return `<label>${esc(d)} <span class="cell-sub">${esc(u || 'UFC/g')}</span><input type="number" step="any" min="0" inputmode="decimal" name="r_${pl.id}_${i}" value="${esc(r?.valor_num ?? '')}" ${dis}></label>`; }).join('')}</div>`;
    } else if (m.tipo_resultado === 'numerico') {
      input = `<input type="number" step="any" inputmode="decimal" name="r_${pl.id}" value="${esc(r1?.valor_num ?? '')}" ${dis} placeholder="${esc(criterioTxt(pl, u) || '')}">`;
    } else {
      const ops = m.tipo_resultado === 'presencia' ? ['ausencia', 'presencia'] : ((m.opciones || []).length ? m.opciones.filter((o) => o !== 'pendiente') : ['conforme', 'no_conforme', 'no_aplica']);
      input = `<select name="r_${pl.id}" data-native ${dis}><option value="">Sin registrar</option>${ops.map((o) => `<option value="${esc(o)}" ${r1?.valor_opcion === o ? 'selected' : ''}>${esc(OPCIONES_TXT[o] || o)}</option>`).join('')}</select>`;
    }
    const just = R.find((r) => r.plan_id === pl.id && r.justificacion)?.justificacion || '';
    return `<div class="cap-item" data-pl="${esc(pl.id)}">
      <div class="cap-lbl">${etiqueta}${m.codigo === 'SEN-SABOR' ? '<div class="cell-sub warn-txt">Solo conforme al protocolo autorizado y en condiciones de inocuidad.</div>' : ''}</div>
      <div class="cap-in">${input}</div>
      <div class="cap-just hidden"><input name="j_${pl.id}" maxlength="500" value="${esc(just)}" placeholder="No cumple: explique brevemente *" aria-label="Explicación de ${esc(m.nombre)}" ${dis}></div>
    </div>`;
  };

  // ---------- Datos del batch (solo en el registro durante el proceso) ----------
  const loteHoy = lotes.data.find((l) => l.fecha === todayISO());
  const nuevo = unidad === 'batch' && !batch;
  let cabecera = '';
  if (unidad === 'batch' && seccion === 'proceso') {
    const dis = ejecuta ? '' : 'disabled';
    const selMp = new Set(batch ? (batch.lotes_mp || []).map((x) => x.lote_mp_id) : (previo?.lotesMp || []));
    const loteSel = previo?.lote || loteHoy?.id || (lotes.data.length ? '' : '__hoy');
    cabecera = `
      ${nuevo ? `<div class="form-section">${icon('package')} Batch</div>
        <div class="field"><label for="cp-l">Lote diario <span class="req">*</span> ${ayuda('Agrupa los batches producidos el mismo día. Si es el primer batch del día, se crea solo.')}</label>
          <select id="cp-l" name="lote" required>${loteHoy ? '' : `<option value="__hoy" ${loteSel === '__hoy' ? 'selected' : ''}>Nuevo lote de hoy: ${esc(codigoLoteHoy())}</option>`}${opciones(lotes.data, loteSel, { label: (l) => `${l.codigo} · ${fmtDate(l.fecha)}`, vacio: null })}</select></div>
        <div class="field"><label for="cp-f">Fecha y hora</label><input id="cp-f" name="fecha_hora" type="datetime-local" required value="${aLocal(new Date())}"></div>` : ''}
      <div class="field full"><span class="label">¿El batch se produjo sin problemas?</span>
        <div class="seg" role="radiogroup">${[['conforme', 'Sí'], ['no_conforme', 'No, hubo una desviación']].map(([k, l]) => `<label class="seg-opt"><input type="radio" name="op" value="${k}" ${k === (batch?.resultado_op === 'no_conforme' ? 'no_conforme' : 'conforme') ? 'checked' : ''} ${dis}><span>${l}</span></label>`).join('')}</div></div>
      <div class="field full hidden" id="cp-inc-w"><div class="form-grid">
        <div class="field"><label for="cp-m">Tipo de desviación</label><select id="cp-m" name="motivo" ${dis}>${opciones(motDesv, batch?.motivo_desviacion_id, { vacio: 'Seleccione…' })}</select></div>
        <div class="field"><label for="cp-i">¿Qué pasó? <span class="req">*</span></label><input id="cp-i" name="inc" maxlength="1000" value="${esc(batch?.incidencias || '')}" ${dis}></div></div></div>
      ${lotesMp.data.length && ejecuta ? `<details class="mas-datos"><summary>${icon('chevrons-up-down')} Lotes de materia prima utilizados (trazabilidad) · ${selMp.size} seleccionado(s)</summary>
        <div class="toolbar" style="margin:0 0 6px"><div class="search">${icon('search')}<input type="search" id="cp-q" placeholder="Filtrar lotes" aria-label="Filtrar lotes"></div></div>
        <div class="chk-list" id="cp-mps">${lotesMp.data.map((l) => `<label data-n="${esc(`${mpNom(l.materia_prima_id)} ${l.lote}`.toLowerCase())}"><input type="checkbox" value="${esc(l.id)}" ${selMp.has(l.id) ? 'checked' : ''}> ${esc(mpNom(l.materia_prima_id))} · <b>${esc(l.lote)}</b>${l.caducidad ? ` <span class="cell-sub">cad. ${fmtDate(l.caducidad)}</span>` : ''}</label>`).join('')}</div></details>` : ''}`;
  }

  // ---------- Parámetros del equipo (Producción) ----------
  let equipoHTML = '';
  if (equipoAqui && pars.data.length) {
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

  const puedeAlgo = editables.length > 0 || (unidad === 'batch' && seccion === 'proceso' && ejecuta) || (equipoHTML && equipoEdit);
  const titulo = unidad === 'batch' ? (batch ? `Batch #${batch.numero}` : 'Nuevo batch') : unidad === 'punto' ? `Punto: ${punto.nombre}`
    : seccion === 'general' ? 'Registro general de la prueba' : seccion === 'complementarias' ? 'Evaluaciones complementarias' : 'Registro de la corrida';
  return openModal({
    title: `${titulo}${seccion === 'complementarias' && unidad === 'batch' ? ' · complementarias' : ''}`, subtitle: `${P.folio} · ${P.cambio}`, size: 'lg', submitText: puedeAlgo ? 'Guardar' : 'Cerrar',
    body: `${!puedeAlgo ? aviso('Solo consulta: cada área registra sus propios parámetros.') : editables.length < items.length ? `<p class="hint">Usted registra los parámetros de su área; los demás se muestran como consulta.</p>` : ''}
      <div class="form-grid">${cabecera}${equipoHTML}
      ${secciones.map((k) => `<div class="form-section">${tituloSec(k)}${k === 'microbiologia' ? ` ${ayuda('Capture cada dilución leída en UFC/g. Puede dejar en blanco lo que aún no tenga lectura y completarlo después.')}` : ''}</div>
        <div class="cap-grid">${grupos[k].map(campo).join('')}</div>`).join('')}
      ${!secciones.length && !equipoHTML ? '<p class="hint full">No hay parámetros para registrar en esta sección.</p>' : ''}
      ${nuevo ? '<label class="check full"><input type="checkbox" name="siguiente" checked> Al guardar, capturar el siguiente batch</label>' : ''}
      </div>
      <p class="hint">Puede guardar con campos vacíos y completarlos cuando tenga los resultados.</p>`,
    onOpen: ({ form }) => {
      const sync = () => {
        const op = form.querySelector('input[name=op]:checked')?.value;
        form.querySelector('#cp-inc-w')?.classList.toggle('hidden', op !== 'no_conforme');
        form.querySelectorAll('.cap-item[data-pl]').forEach((w) => {
          const pl = items.find((x) => x.id === w.dataset.pl); const m = met(pl.metodo_id);
          const vals = [...w.querySelectorAll(`[name^="r_${pl.id}"]`)].map((i) => i.value).filter((v) => v !== '');
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
      form.querySelector('#cp-q')?.addEventListener('input', (e) => {
        const q = e.target.value.toLowerCase();
        form.querySelectorAll('#cp-mps label').forEach((l) => l.classList.toggle('hidden', !l.dataset.n.includes(q)));
      });
    },
    onSubmit: async ({ form, setError }) => {
      if (!puedeAlgo) return;
      const f = form.elements;
      const faltaJust = [...form.querySelectorAll('.cap-just:not(.hidden) input:not([disabled])')].find((i) => !i.value.trim());
      if (faltaJust) { faltaJust.focus(); setError('Explique brevemente los valores que no cumplen.'); return false; }
      if (unidad === 'batch' && seccion === 'proceso' && ejecuta && f.op?.value === 'no_conforme' && !f.inc.value.trim()) { f.inc.focus(); setError('Describa qué pasó en el batch.'); return false; }

      // 1. Batch (alta o datos generales)
      let batchId = batch?.id;
      let loteId = null;
      if (unidad === 'batch' && seccion === 'proceso' && ejecuta) {
        const datos = { resultado_op: f.op?.value || 'conforme', motivo_desviacion_id: f.op?.value === 'no_conforme' ? nullIfEmpty(f.motivo.value) : null,
          incidencias: f.op?.value === 'no_conforme' ? nullIfEmpty(f.inc.value) : null };
        if (nuevo) {
          loteId = f.lote.value;
          if (loteId === '__hoy') loteId = must(await sb.from('lotes_diarios_prubind').insert({ prueba_id: P.id, codigo: codigoLoteHoy(), fecha: todayISO() }).select('id').single()).data.id;
          batchId = must(await sb.from('batches_prubind').insert({ ...datos, prueba_id: P.id, lote_diario_id: loteId, numero: 0,
            fecha_hora: new Date(f.fecha_hora.value).toISOString(), responsable_id: state.profile.id }).select('id').single()).data.id;
        } else if (['resultado_op', 'motivo_desviacion_id', 'incidencias'].some((k) => String(datos[k] ?? '') !== String(batch[k] ?? ''))) {
          mustRow(await sb.from('batches_prubind').update(datos).eq('id', batch.id).select('id'));
        }
        const marcados = [...form.querySelectorAll('#cp-mps input:checked')].map((i) => i.value);
        if (form.querySelector('#cp-mps')) {
          const antes = new Set(batch ? (batch.lotes_mp || []).map((x) => x.lote_mp_id) : []);
          const quitar = [...antes].filter((x) => !marcados.includes(x)); const agregar = marcados.filter((x) => !antes.has(x));
          if (quitar.length) must(await sb.from('batch_lotes_mp_prubind').delete().eq('batch_id', batchId).in('lote_mp_id', quitar));
          if (agregar.length) must(await sb.from('batch_lotes_mp_prubind').insert(agregar.map((x) => ({ batch_id: batchId, lote_mp_id: x }))));
        }
        previo = { lote: loteId || batch?.lote_diario_id, lotesMp: marcados };
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
      if (editables.length) {
        const cambios = [];
        for (const pl of editables) {
          const m = met(pl.metodo_id);
          const just = nullIfEmpty(f[`j_${pl.id}`]?.value.trim());
          const entradas = m.tipo_resultado === 'diluciones' ? m.diluciones.map((d, i) => ({ d, v: f[`r_${pl.id}_${i}`].value }))
            : [{ d: null, v: f[`r_${pl.id}`].value }];
          for (const { d, v } of entradas) {
            const previoR = R.find((r) => r.plan_id === pl.id && (r.dilucion || null) === d);
            if (v === '') { if (previoR) cambios.push(['del', previoR.id]); continue; }
            const payload = m.tipo_resultado === 'numerico' || m.tipo_resultado === 'diluciones' ? { valor_num: Number(v) } : { valor_opcion: v };
            payload.estado = evaluar(pl, m, v) || 'pendiente';
            payload.justificacion = payload.estado === 'no_conforme' ? (just || previoR?.justificacion || null) : null;
            if (previoR) {
              const igual = String(previoR.valor_num ?? '') === String(payload.valor_num ?? '') && (previoR.valor_opcion || null) === (payload.valor_opcion || null)
                && previoR.estado === payload.estado && (previoR.justificacion || null) === (payload.justificacion || null);
              if (!igual) cambios.push(['upd', previoR.id, payload]);
            } else cambios.push(['ins', null, { ...payload, plan_id: pl.id, metodo_id: m.id, dilucion: d }]);
          }
        }
        if (cambios.length) {
          let muestraId = muestra?.id;
          if (!muestraId && cambios.some(([t]) => t === 'ins')) {
            muestraId = must(await sb.from('muestras_prubind').insert({ prueba_id: P.id, nivel: unidad === 'batch' ? 'batch' : unidad, codigo: '', fecha_muestreo: todayISO(),
              batch_id: unidad === 'batch' ? batchId : null, punto_id: unidad === 'punto' ? punto.id : null }).select('id').single()).data.id;
          }
          for (const [t, id, payload] of cambios) {
            if (t === 'del') mustRow(await sb.from('resultados_prubind').delete().eq('id', id).select('id'));
            else if (t === 'upd') mustRow(await sb.from('resultados_prubind').update(payload).eq('id', id).select('id'));
            else must(await sb.from('resultados_prubind').insert({ ...payload, prueba_id: P.id, muestra_id: muestraId, capturado_por: state.profile.id }));
          }
        }
      }
      toast(nuevo ? 'Batch registrado.' : 'Registro guardado.', 'success');
      return { siguiente: nuevo && !!f.siguiente?.checked, previo };
    },
  });
}

// Avance de captura: [con resultado, total]
export function avanceUnidad(items, R) {
  const hechos = items.filter((pl) => R.some((r) => r.plan_id === pl.id && (r.valor_num != null || r.valor_opcion))).length;
  return [hechos, items.length];
}
// Áreas presentes en una lista de parámetros
export const areasDe = (items, met) => AREAS_ORDEN.filter((a) => items.some((pl) => met(pl.metodo_id)?.area === a));
