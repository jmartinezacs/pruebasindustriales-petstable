// =====================================================================
// Registro de datos de la prueba en UN SOLO formulario.
// Cada parámetro se registra para toda la prueba (un valor) o por batch:
// al elegir "Por batch" aparece un renglón por batch (número y valor) y se
// agregan los que se necesiten. Los batches se crean solos con su número
// (p. ej. 29, 30, 31) y se comparten entre parámetros.
// Cada quien solo edita los parámetros de su área:
//   · Calidad: inspectores o Jefe de Calidad.
//   · Producción: supervisores o Gerente de Producción.
//   · Seguridad: Supervisor o Ingeniero de Seguridad.
//   · Mantenimiento: Jefe o técnicos de Mantenimiento.
// Un valor que aún no se tiene se marca "Pendiente" y se completa al
// evaluar o en el dictamen. Cada parámetro puede llevar evidencia.
// =====================================================================
import {
  sb, state, esc, icon, toast, openModal, nullIfEmpty, must, mustRow, getCat, unidadTxt,
  todayISO, puedeEn, puedeArea, misAreas, AREAS, AREAS_ORDEN, COMPLEMENTARIAS, ayuda,
} from '../core.js';
import { aviso, criterioTxt, eviPicker, eviChips, campoValor, leerValor, payloadValor, subirArchivos } from './exp_comun.js';

const TITULO_CAT = { sensorial: 'Evaluación sensorial', microbiologia: 'Microbiología', bromatologia: 'Análisis bromatológicos (proximal)' };
const ICO_CAT = { sensorial: 'eye', microbiologia: 'microscope', bromatologia: 'flask-round' };
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

/**
 * Formulario único de registro de datos de la prueba.
 * @param {object} P prueba (v_pruebas)
 * @returns {Promise<false|true>}
 */
export async function registroForm(P) {
  const ej = P.ejecucion_actual;
  const fab = P.ejecucion_form === 'fabricacion';
  const noun = fab ? 'batch' : 'corrida', Noun = fab ? 'Batch' : 'Corrida';
  const [metodos, unidades, plan, muestras, resultados, batches, lotes, pars, controles, adjs] = await Promise.all([
    getCat('metodos'), getCat('unidades'),
    sb.from('plan_evaluacion_prubind').select('*').eq('prueba_id', P.id).eq('incluido', true).order('orden'),
    sb.from('muestras_prubind').select('*').eq('prueba_id', P.id).eq('ejecucion', ej),
    sb.from('resultados_prubind').select('*').eq('prueba_id', P.id).eq('ejecucion', ej),
    sb.from('batches_prubind').select('id, numero, lote_diario_id').eq('prueba_id', P.id).eq('ejecucion', ej).order('numero'),
    sb.from('lotes_diarios_prubind').select('*').eq('prueba_id', P.id).eq('ejecucion', ej).order('fecha'),
    sb.from('prueba_parametros_prubind').select('*').eq('prueba_id', P.id).order('orden'),
    sb.from('ejecucion_controles_prubind').select('*').eq('prueba_id', P.id).eq('ejecucion', ej),
    sb.from('adjuntos_prubind').select('id, nombre, ruta, plan_id, batch_id').eq('prueba_id', P.id).not('plan_id', 'is', null),
  ]);
  [plan, muestras, resultados, batches, lotes, pars, controles, adjs].forEach((r) => { if (r.error) throw r.error; });
  const un = (id) => unidadTxt(unidades, id);
  const met = (id) => metodos.find((m) => m.id === id);

  // Permisos: cada área registra lo suyo durante el proceso; con la prueba terminada solo se completan valores
  const abierta = P.estado === 'en_ejecucion';
  const enCaptura = abierta || COMPLETAR.includes(P.estado);
  const capArea = (area) => enCaptura && (puedeArea(P, 'capturar', area) || puedeArea(P, 'evaluar', area));
  const altaBatch = abierta && puedeEn(P, 'ejecutar');
  const equipoEdit = abierta && capArea('produccion');

  // Dónde está cada resultado: registro general o el batch de su muestra
  const general = muestras.data.find((s) => s.nivel === 'corrida');
  const batchDeMuestra = (mid) => { const s = muestras.data.find((x) => x.id === mid); return s?.nivel === 'batch' ? batches.data.find((b) => b.id === s.batch_id) : null; };
  const resDe = (pl) => resultados.data.filter((r) => r.plan_id === pl.id);
  const generalDe = (pl) => resDe(pl).filter((r) => r.muestra_id === general?.id);
  const porBatchDe = (pl) => {
    const filas = new Map();
    resDe(pl).forEach((r) => { const b = batchDeMuestra(r.muestra_id); if (!b) return; if (!filas.has(b.numero)) filas.set(b.numero, []); filas.get(b.numero).push(r); });
    return [...filas.entries()].sort((a, b) => a[0] - b[0]).map(([numero, rs]) => ({ numero, rs }));
  };
  const esPendiente = (pl) => { const xs = resDe(pl); return xs.length > 0 && !xs.some(conValor); };
  const evid = (pl) => adjs.data.filter((a) => a.plan_id === pl.id);

  // Solo se muestran las áreas de quien registra (el administrador y quien solo consulta ven todas)
  const todos = plan.data.filter((pl) => met(pl.metodo_id));
  const editablesTodos = todos.filter((pl) => capArea(met(pl.metodo_id).area));
  const verAreas = new Set([...misAreas(P), ...editablesTodos.map((pl) => met(pl.metodo_id).area)]);
  const items = todos.filter((pl) => verAreas.has(met(pl.metodo_id).area));
  const ocultas = todos.length - items.length;
  const editables = items.filter((pl) => capArea(met(pl.metodo_id).area));

  // Apartados por área; dentro de Calidad, laboratorio y sensorial por categoría
  const clave = (m) => (esLab(m) ? m.categoria : m.area);
  const ORDEN = ['calidad', ...COMPLEMENTARIAS, 'produccion', 'seguridad', 'mantenimiento'];
  const grupos = {};
  items.forEach((pl) => { (grupos[clave(met(pl.metodo_id))] ||= []).push(pl); });
  const secciones = Object.keys(grupos).sort((a, b) => ORDEN.indexOf(a) - ORDEN.indexOf(b));
  const tituloSec = (k) => (TITULO_CAT[k] ? `${icon(ICO_CAT[k])} ${esc(TITULO_CAT[k])} <span class="cell-sub">· Calidad</span>` : `${icon(AREAS[k].ico)} ${esc(AREAS[k].label)}`);

  // Números de batch ya usados en la prueba (sugerencias)
  const numerosUsados = () => batches.data.map((b) => b.numero);
  let fila = 0;
  const renglon = (pl, numero, rs, dis) => {
    const m = met(pl.metodo_id); const k = fila++;
    return `<div class="rp-row" data-k="${k}"><label class="rp-num"><span>${Noun}</span><input type="number" inputmode="numeric" min="1" max="999" step="1" name="bn_${pl.id}_${k}" value="${esc(numero ?? '')}" list="rp-nums" ${dis} aria-label="Número de ${noun}"></label>
      <div class="rp-val">${campoValor(m, `bv_${pl.id}_${k}`, { valores: rs || [], unidad: un(m.unidad_id), placeholder: criterioTxt(pl, un(m.unidad_id)) || 'Valor', disabled: !!dis })}</div>
      ${dis ? '' : `<button type="button" class="icon-btn bad" data-rp="quitar" title="Quitar ${noun}" aria-label="Quitar ${noun}">${icon('x')}</button>`}</div>`;
  };

  // ---------- Cada parámetro ----------
  const campo = (pl) => {
    const m = met(pl.metodo_id); const u = un(m.unidad_id); const edit = capArea(m.area);
    const dis = edit ? '' : 'disabled';
    const filasB = porBatchDe(pl).filter((x) => x.rs.some(conValor));
    const modo = filasB.length ? 'batch' : 'general';
    const pend = esPendiente(pl);
    const just = resDe(pl).find((r) => r.justificacion)?.justificacion || '';
    const etiqueta = `${esc(m.nombre)}${u && u !== m.nombre && m.tipo_resultado !== 'diluciones' ? ` <span class="cell-sub">(${esc(u)})</span>` : ''} ${ayuda(ayudaMetodo(pl, m, u))}`;
    const puedeBatch = edit && (altaBatch || filasB.length);
    return `<div class="rp-item ${pend ? 'is-pend' : ''}" data-pl="${esc(pl.id)}" data-modo="${modo}">
      <div class="rp-head"><div class="cap-lbl">${etiqueta}${m.codigo === 'SEN-SABOR' ? '<div class="cell-sub warn-txt">Solo conforme al protocolo autorizado y en condiciones de inocuidad.</div>' : ''}</div>
        ${puedeBatch || filasB.length ? `<div class="rp-modo" role="radiogroup" aria-label="Cómo se registra ${esc(m.nombre)}">
          <label><input type="radio" name="md_${pl.id}" value="general" ${modo === 'general' ? 'checked' : ''} ${dis}><span>Toda la prueba</span></label>
          <label><input type="radio" name="md_${pl.id}" value="batch" ${modo === 'batch' ? 'checked' : ''} ${puedeBatch ? '' : 'disabled'}><span>Por ${noun}</span></label></div>` : ''}</div>
      <div class="rp-general">${campoValor(m, `g_${pl.id}`, { valores: generalDe(pl).filter(conValor), unidad: u, placeholder: criterioTxt(pl, u) || '', disabled: !edit })}</div>
      <div class="rp-batches">
        <div class="rp-rows">${filasB.map((x) => renglon(pl, x.numero, x.rs.filter(conValor), dis)).join('')}</div>
        ${puedeBatch && altaBatch ? `<button type="button" class="rp-add" data-rp="agregar">${icon('plus')} Agregar ${noun}</button>` : ''}
      </div>
      ${edit ? `<div class="cap-tools"><label class="pend-tg" title="Aún no se tiene el valor; se completa después"><input type="checkbox" name="pd_${esc(pl.id)}" ${pend ? 'checked' : ''}>${icon('hourglass')}<span>Pendiente</span></label>
        ${eviPicker(`f_${pl.id}`, evid(pl))}</div>` : evid(pl).length ? `<div class="cap-tools">${eviChips(evid(pl))}</div>` : ''}
      <div class="cap-just hidden"><input name="j_${pl.id}" maxlength="500" value="${esc(just)}" placeholder="No cumple: explique brevemente *" aria-label="Explicación de ${esc(m.nombre)}" ${dis}></div>
    </div>`;
  };

  // ---------- Parámetros del equipo (Producción, toda la prueba) ----------
  let equipoHTML = '';
  if (pars.data.length && verAreas.has('produccion')) {
    const dis = equipoEdit ? '' : 'disabled';
    const C = controles.data;
    equipoHTML = `<div class="form-section">${icon('gauge')} Parámetros del equipo <span class="cell-sub">· Producción</span></div>
      <div class="cap-grid">${pars.data.map((x) => { const c = C.find((k) => k.prueba_parametro_id === x.id); const rango = x.minimo != null || x.maximo != null;
        const ref = rango ? criterioTxt({ crit_minimo: x.minimo, crit_maximo: x.maximo }, un(x.unidad_id)) : (x.valor_objetivo || (x.referencia || '').split(' · ')[0]);
        return `<div class="cap-item" data-par="${esc(x.id)}">
          <div class="cap-lbl">${esc(x.nombre)} ${un(x.unidad_id) ? `<span class="cell-sub">(${esc(un(x.unidad_id))})</span>` : ''} ${ayuda(`${rango ? 'Rango aceptado' : 'Valor de referencia'}: ${ref || 'sin dato'}.`)}</div>
          <div class="cap-in"><input type="number" step="any" inputmode="decimal" name="p_${x.id}" value="${esc(c?.valor ?? '')}" placeholder="${esc(ref || '')}" ${dis}>
            ${rango ? '' : `<select name="pe_${x.id}" data-native ${dis} aria-label="Resultado de ${esc(x.nombre)}"><option value="conforme" ${c?.resultado !== 'no_conforme' ? 'selected' : ''}>Correcto</option><option value="no_conforme" ${c?.resultado === 'no_conforme' ? 'selected' : ''}>Fuera de lo esperado</option></select>`}</div>
          <div class="cap-just hidden"><input name="pj_${x.id}" maxlength="500" value="${esc(c?.observaciones || '')}" placeholder="Fuera de rango: explique brevemente *" ${dis}></div></div>`; }).join('')}</div>`;
  }

  const puedeAlgo = editables.length > 0 || (equipoHTML && equipoEdit);
  return openModal({
    title: puedeAlgo ? 'Registrar datos de la prueba' : 'Datos de la prueba', subtitle: `${P.folio} · ${P.cambio}`, size: 'lg', submitText: puedeAlgo ? 'Guardar' : 'Cerrar',
    body: `<div class="rp-guia">${icon('info')}<span>Escriba un valor si aplica a <b>toda la prueba</b>. Si se mide en cada ${noun}, elija <b>Por ${noun}</b> y agregue un renglón por cada uno con su número (p. ej. 29, 30, 31).</span></div>
      ${!puedeAlgo ? aviso('Solo consulta: cada área registra sus propios parámetros.') : editables.length < items.length ? '<p class="hint">Los parámetros de otras áreas son solo de consulta.</p>' : ''}${ocultas ? `<p class="hint">${icon('eye-off')} Solo se muestran los parámetros de su área.</p>` : ''}
      <datalist id="rp-nums">${numerosUsados().map((n) => `<option value="${n}"></option>`).join('')}</datalist>
      <div class="rp-lista">${secciones.map((k) => `<div class="form-section">${tituloSec(k)}${k === 'microbiologia' ? ` ${ayuda('Capture cada dilución leída en UFC/g. Lo que aún no tenga lectura márquelo como Pendiente.')}` : ''}</div>
        ${grupos[k].map(campo).join('')}`).join('')}
      ${equipoHTML}
      ${!secciones.length && !equipoHTML ? '<p class="hint">Aún no hay parámetros definidos (pestaña Registro).</p>' : ''}</div>
      ${editables.length ? `<p class="hint">${icon('hourglass')} Marque <b>Pendiente</b> lo que aún no tenga (p. ej. resultados de laboratorio).</p>` : ''}`,
    onOpen: ({ form }) => {
      // Siguiente número sugerido: el primer batch de la prueba que este parámetro aún no tiene, o el siguiente
      const sugerido = (w) => {
        const ya = [...w.querySelectorAll('.rp-num input')].map((i) => Number(i.value)).filter(Boolean);
        const usados = [...new Set([...numerosUsados(), ...[...form.querySelectorAll('.rp-num input')].map((i) => Number(i.value)).filter(Boolean)])].sort((a, b) => a - b);
        return usados.find((n) => !ya.includes(n)) ?? (Math.max(0, ...usados, ...ya) + 1);
      };
      const sync = () => {
        form.querySelectorAll('.rp-item').forEach((w) => {
          const pl = items.find((x) => x.id === w.dataset.pl); const m = met(pl.metodo_id); const edit = capArea(m.area);
          const modo = form.querySelector(`input[name="md_${pl.id}"]:checked`)?.value || 'general';
          const pend = !!form.elements[`pd_${pl.id}`]?.checked;
          w.dataset.modo = modo;
          w.classList.toggle('is-pend', pend);
          if (edit) w.querySelectorAll('.rp-general [name], .rp-val [name], .rp-num input').forEach((i) => { i.disabled = pend; });
          if (modo === 'batch' && !w.querySelector('.rp-row') && edit && altaBatch) {
            w.querySelector('.rp-rows').insertAdjacentHTML('beforeend', renglon(pl, sugerido(w), [], ''));
            refreshIconsIn();
          }
          const sel = modo === 'batch' ? '.rp-val [name]' : '.rp-general [name]';
          const vals = pend ? [] : [...w.querySelectorAll(sel)].map((i) => i.value).filter((v) => v !== '');
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
      form.addEventListener('click', (e) => {
        const b = e.target.closest('[data-rp]');
        if (!b) return;
        const w = b.closest('.rp-item'); const pl = items.find((x) => x.id === w.dataset.pl);
        if (b.dataset.rp === 'agregar') {
          w.querySelector('.rp-rows').insertAdjacentHTML('beforeend', renglon(pl, sugerido(w), [], ''));
          refreshIconsIn(w); w.querySelector('.rp-row:last-child .rp-val [name]')?.focus();
        } else if (b.dataset.rp === 'quitar') {
          b.closest('.rp-row').remove();
          if (!w.querySelector('.rp-row')) { const g = w.querySelector('input[value="general"]'); if (g) g.checked = true; }
        }
        sync();
      });
      form.addEventListener('input', sync); form.addEventListener('change', sync); sync();
    },
    onSubmit: async ({ form, setError }) => {
      if (!puedeAlgo) return;
      const f = form.elements;
      const faltaJust = [...form.querySelectorAll('.cap-just:not(.hidden) input:not([disabled])')].find((i) => !i.value.trim());
      if (faltaJust) { faltaJust.focus(); setError('Explique brevemente los valores que no cumplen.'); return false; }

      // 1. Qué quedó en el formulario para cada parámetro
      const planes = [];
      for (const pl of editables) {
        const m = met(pl.metodo_id); const w = form.querySelector(`.rp-item[data-pl="${CSS.escape(pl.id)}"]`);
        const pend = !!f[`pd_${pl.id}`]?.checked;
        const modo = form.querySelector(`input[name="md_${pl.id}"]:checked`)?.value || 'general';
        const filas = [];
        if (!pend && modo === 'batch') {
          for (const row of w.querySelectorAll('.rp-row')) {
            const k = row.dataset.k; const numero = Number(f[`bn_${pl.id}_${k}`].value);
            const entradas = leerValor(form, m, `bv_${pl.id}_${k}`);
            if (!entradas.some((x) => x.v !== '')) continue;
            if (!Number.isInteger(numero) || numero < 1 || numero > 999) { f[`bn_${pl.id}_${k}`].focus(); setError(`Indique el número de ${noun} de "${m.nombre}" (1 a 999).`); return false; }
            if (filas.some((x) => x.numero === numero)) { f[`bn_${pl.id}_${k}`].focus(); setError(`"${m.nombre}" tiene repetido el ${noun} ${numero}.`); return false; }
            if (!altaBatch && !batches.data.some((b) => b.numero === numero)) { setError(`La prueba ya terminó: no se agregan ${noun}es nuevos.`); return false; }
            filas.push({ numero, entradas });
          }
        }
        planes.push({ pl, m, pend, modo, filas, just: nullIfEmpty(f[`j_${pl.id}`]?.value.trim()) });
      }

      // 2. Batches que hacen falta (se crean solos con su número)
      const nums = [...new Set(planes.flatMap((x) => x.filas.map((r) => r.numero)))];
      let lote = lotes.data.find((l) => l.fecha === todayISO());
      for (const n of nums) {
        if (batches.data.some((b) => b.numero === n)) continue;
        if (!lote) lote = must(await sb.from('lotes_diarios_prubind').insert({ prueba_id: P.id, codigo: codigoLoteHoy(), fecha: todayISO() }).select('*').single()).data;
        const b = must(await sb.from('batches_prubind').insert({ prueba_id: P.id, lote_diario_id: lote.id, numero: n, fecha_hora: new Date().toISOString(),
          resultado_op: 'conforme', responsable_id: state.profile.id }).select('id, numero, lote_diario_id').single()).data;
        batches.data.push(b);
      }
      const muestraIds = new Map();
      const muestraDe = async (numero) => {
        const key = numero ?? 'general';
        if (muestraIds.has(key)) return muestraIds.get(key);
        const b = numero != null ? batches.data.find((x) => x.numero === numero) : null;
        let s = muestras.data.find((x) => (b ? x.nivel === 'batch' && x.batch_id === b.id : x.nivel === 'corrida'));
        if (!s) {
          s = must(await sb.from('muestras_prubind').insert({ prueba_id: P.id, nivel: b ? 'batch' : 'corrida', codigo: '', fecha_muestreo: todayISO(), batch_id: b?.id || null }).select('*').single()).data;
          muestras.data.push(s);
        }
        muestraIds.set(key, s.id);
        return s.id;
      };

      // 3. Cambios de resultados (primero se borra lo que ya no aplica)
      const borrar = [], escribir = [];
      for (const { pl, m, pend, modo, filas, just } of planes) {
        const previos = resDe(pl);
        if (pend) {
          if (previos.length && !previos.some(conValor)) continue;
          previos.forEach((r) => borrar.push(r.id));
          escribir.push(['ins', null, { plan_id: pl.id, metodo_id: m.id, dilucion: m.tipo_resultado === 'diluciones' ? m.diluciones[0] : null, valor_num: null, valor_opcion: null, estado: 'pendiente' }, null]);
          continue;
        }
        // Destinos: toda la prueba (un valor) o cada batch
        const destinos = modo === 'batch' ? filas.map((x) => ({ numero: x.numero, entradas: x.entradas })) : [{ numero: null, entradas: leerValor(form, m, `g_${pl.id}`) }];
        const usados = new Set();
        for (const { numero, entradas } of destinos) {
          const enDestino = previos.filter((r) => (numero == null ? r.muestra_id === general?.id : batchDeMuestra(r.muestra_id)?.numero === numero));
          for (const { d, v } of entradas) {
            const previoR = enDestino.find((r) => (r.dilucion || null) === d);
            if (v === '') continue;
            if (previoR) usados.add(previoR.id);
            const payload = { ...payloadValor(m, v) };
            payload.estado = evaluar(pl, m, v) || 'pendiente';
            payload.justificacion = payload.estado === 'no_conforme' ? (just || previoR?.justificacion || null) : null;
            if (previoR) {
              const igual = String(previoR.valor_num ?? '') === String(payload.valor_num ?? '') && (previoR.valor_opcion || null) === (payload.valor_opcion || null)
                && previoR.estado === payload.estado && (previoR.justificacion || null) === (payload.justificacion || null);
              if (!igual) escribir.push(['upd', previoR.id, payload, null]);
            } else escribir.push(['ins', null, { ...payload, plan_id: pl.id, metodo_id: m.id, dilucion: d }, numero]);
          }
        }
        previos.filter((r) => !usados.has(r.id)).forEach((r) => borrar.push(r.id));
      }
      for (const id of borrar) mustRow(await sb.from('resultados_prubind').delete().eq('id', id).select('id'));
      for (const [t, id, payload, numero] of escribir) {
        if (t === 'upd') mustRow(await sb.from('resultados_prubind').update(payload).eq('id', id).select('id'));
        else must(await sb.from('resultados_prubind').insert({ ...payload, prueba_id: P.id, muestra_id: await muestraDe(numero), capturado_por: state.profile.id }));
      }

      // 4. Parámetros del equipo
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

      // 5. Batches que quedaron sin ningún dato (p. ej. un número mal escrito) se quitan
      if (altaBatch && borrar.length) {
        const { data: rs } = must(await sb.from('resultados_prubind').select('muestra_id').eq('prueba_id', P.id).eq('ejecucion', ej));
        for (const b of batches.data) {
          const ms = muestras.data.filter((s) => s.batch_id === b.id);
          if (ms.some((s) => rs.some((r) => r.muestra_id === s.id))) continue;
          try {
            for (const s of ms) mustRow(await sb.from('muestras_prubind').delete().eq('id', s.id).select('id'));
            mustRow(await sb.from('batches_prubind').delete().eq('id', b.id).select('id'));
          } catch { /* se conserva si no se puede quitar */ }
        }
      }

      // 6. Evidencia de cada parámetro
      const archivos = editables.map((pl) => [pl, [...(f[`f_${pl.id}`]?.files || [])]]).filter(([, xs]) => xs.length);
      if (archivos.length) {
        const { data: rs } = must(await sb.from('resultados_prubind').select('id, plan_id').eq('prueba_id', P.id).eq('ejecucion', ej));
        let n = 0;
        for (const [pl, files] of archivos) n += await subirArchivos(P, files, { plan_id: pl.id, resultado_id: rs.find((r) => r.plan_id === pl.id)?.id || null, etapa: 'ejecucion' });
        if (n) toast(`${n} evidencia(s) adjuntada(s).`, 'success');
      }
      toast('Datos guardados.', 'success');
      return true;
    },
  });
}

const refreshIconsIn = () => { try { window.lucide?.createIcons(); } catch { /* sin íconos */ } };

// Áreas presentes en una lista de parámetros
export const areasDe = (items, met) => AREAS_ORDEN.filter((a) => items.some((pl) => met(pl.metodo_id)?.area === a));
