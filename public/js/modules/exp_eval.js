// =====================================================================
// Etapa 4 · Resultados por parámetro y etapa 5 · Recomendaciones.
// Se consolida lo registrado: parámetro, resultado obtenido, criterio y
// evaluación Cumple / No cumple. "Cumple" queda "Sin observaciones" de
// forma predeterminada; "No cumple" exige explicar por qué.
// Cada área evalúa lo suyo: Calidad → Jefe de Calidad; Producción →
// Gerente de Producción; Seguridad → Supervisor de Seguridad, Salud y
// Ambiente; Mantenimiento → Jefe de Mantenimiento. Después cada área
// registra su recomendación y la prueba pasa al dictamen de Alta Dirección.
// =====================================================================
import {
  sb, state, esc, icon, toast, errMsg, must, mustRow, getCat, unidadTxt, fmtDateTime, pill, puedeArea,
  AREAS, AREAS_ORDEN, AREAS_OBLIGATORIAS, COMPLEMENTARIAS, OPCIONES_TXT, refreshIcons,
} from '../core.js';
import { cardHead, aviso, vacio, checklist, accion, criterioTxt } from './exp_comun.js';

const EVALUA = ['en_evaluacion', 'pendiente_resultados'];
export const EVAL = { cumple: ['Cumple', 'ok'], no_cumple: ['No cumple', 'bad'] };
export const SENTIDO = { favorable: ['Favorable', 'ok', 'Recomienda implementar el cambio'], no_favorable: ['No favorable', 'bad', 'No recomienda implementar el cambio'], repetir: ['Repetir prueba', 'warn', 'Recomienda repetir o ajustar la prueba'] };

// Consolidado de la ejecución actual: filas a evaluar por área
export async function consolidarResultados(P, ej = P.ejecucion_actual) {
  const [metodos, unidades, plan, res, pars, ctrl, ev, rec] = await Promise.all([
    getCat('metodos'), getCat('unidades'),
    sb.from('plan_evaluacion_prubind').select('*').eq('prueba_id', P.id).eq('incluido', true).order('orden'),
    sb.from('v_resultados_prubind').select('id, plan_id, valor_num, valor_opcion, dilucion, estado, justificacion, unidad, batch_numero, muestra_nivel, capturado_por_nombre').eq('prueba_id', P.id).eq('ejecucion', ej).order('created_at'),
    sb.from('prueba_parametros_prubind').select('*').eq('prueba_id', P.id).order('orden'),
    sb.from('ejecucion_controles_prubind').select('*').eq('prueba_id', P.id).eq('ejecucion', ej),
    sb.from('evaluaciones_prubind').select('*, por:usuarios_prubind!evaluaciones_prubind_evaluado_por_fkey(nombre)').eq('prueba_id', P.id).eq('ejecucion', ej),
    sb.from('recomendaciones_prubind').select('*, por:usuarios_prubind!recomendaciones_prubind_emitido_por_fkey(nombre)').eq('prueba_id', P.id).eq('ejecucion', ej),
  ]);
  [plan, res, pars, ctrl, ev, rec].forEach((r) => { if (r.error) throw r.error; });
  const met = (id) => metodos.find((m) => m.id === id);
  const filas = [];
  plan.data.forEach((pl) => {
    const m = met(pl.metodo_id); if (!m) return;
    const R = res.data.filter((r) => r.plan_id === pl.id && (r.valor_num != null || r.valor_opcion));
    const valores = R.map((r) => {
      const v = r.valor_opcion ? (OPCIONES_TXT[r.valor_opcion] || r.valor_opcion) : `${r.valor_num}${r.unidad ? ` ${r.unidad}` : ''}`;
      const donde = r.batch_numero ? `B${r.batch_numero}${r.dilucion ? ` ${r.dilucion}` : ''}` : r.dilucion || '';
      return { txt: donde ? `${donde}: ${v}` : v, fuera: r.estado === 'no_conforme', just: r.justificacion };
    });
    filas.push({ key: `pl:${pl.id}`, plan_id: pl.id, area: m.area, compl: COMPLEMENTARIAS.includes(m.categoria), nombre: m.nombre,
      criterio: criterioTxt(pl, unidadTxt(unidades, m.unidad_id)), ref: pl.crit_referencia, valores, conValor: R.length > 0,
      requerida: pl.obligatorio || R.length > 0, ev: ev.data.find((x) => x.plan_id === pl.id) });
  });
  pars.data.forEach((x) => {
    const c = ctrl.data.find((k) => k.prueba_parametro_id === x.id);
    filas.push({ key: `par:${x.id}`, prueba_parametro_id: x.id, area: 'produccion', compl: false, nombre: `${x.nombre} (${P.equipo_nombre || 'equipo'})`,
      criterio: x.minimo != null || x.maximo != null ? criterioTxt({ crit_minimo: x.minimo, crit_maximo: x.maximo }, unidadTxt(unidades, x.unidad_id)) : (x.referencia || '').split(' · ')[0],
      valores: c?.valor != null ? [{ txt: `${c.valor} ${unidadTxt(unidades, x.unidad_id)}`.trim(), fuera: c.resultado === 'no_conforme', just: c.observaciones }] : [],
      conValor: c?.valor != null, requerida: true, ev: ev.data.find((k) => k.prueba_parametro_id === x.id) });
  });
  const areas = AREAS_ORDEN.filter((a) => filas.some((f) => f.area === a));
  const faltan = (a) => filas.filter((f) => f.area === a && f.requerida && !f.ev).length;
  return { filas, areas, faltan, REC: rec.data };
}

// ============================== RESULTADOS ==============================
export async function etapaResultados(pane, ctx) {
  const { P } = ctx;
  const K = await consolidarResultados(P);
  const enEval = EVALUA.includes(P.estado);
  const puedeEv = (a) => enEval && puedeArea(P, 'evaluar', a);
  const previo = ['registrada', 'en_preparacion', 'preparada', 'en_ejecucion'].includes(P.estado);

  const valoresHTML = (f) => (f.valores.length ? f.valores.map((v) => `<div class="${v.fuera ? 'bad-txt' : ''}">${esc(v.txt)}${v.fuera ? ` ${icon('alert-triangle')}` : ''}${v.just ? `<div class="cell-sub">${esc(v.just)}</div>` : ''}</div>`).join('')
    : '<span class="cell-sub">Sin resultado</span>');
  const fila = (f) => {
    const edit = puedeEv(f.area) && f.conValor;
    const sel = f.ev?.evaluacion;
    return `<tr class="${sel === 'no_cumple' ? 'row-bad' : ''}" data-fila="${esc(f.key)}">
      <td data-label="Parámetro"><div class="td-in"><div class="cell-main">${esc(f.nombre)}</div></div></td>
      <td data-label="Resultado"><div class="td-in">${valoresHTML(f)}</div></td>
      <td data-label="Criterio"><div class="td-in">${f.criterio ? esc(f.criterio) : '<span class="cell-sub">—</span>'}${f.ref ? `<div class="cell-sub">${esc(f.ref)}</div>` : ''}</div></td>
      <td data-label="Evaluación"><div class="td-in">${edit ? `<div class="seg sm" role="radiogroup" aria-label="Evaluación de ${esc(f.nombre)}">
          <label class="seg-opt ok"><input type="radio" name="ev_${esc(f.key)}" value="cumple" ${sel === 'cumple' ? 'checked' : ''}><span>Cumple</span></label>
          <label class="seg-opt bad"><input type="radio" name="ev_${esc(f.key)}" value="no_cumple" ${sel === 'no_cumple' ? 'checked' : ''}><span>No cumple</span></label></div>`
        : sel ? pill(...EVAL[sel]) : `<span class="cell-sub">${f.conValor ? 'Por evaluar' : f.requerida ? 'Falta el resultado' : 'Opcional'}</span>`}</div></td>
      <td data-label="Observaciones"><div class="td-in">${edit ? `<input name="ob_${esc(f.key)}" maxlength="500" value="${esc(f.ev && f.ev.observaciones !== 'Sin observaciones' ? f.ev.observaciones : '')}" placeholder="Sin observaciones" aria-label="Observaciones de ${esc(f.nombre)}">`
        : f.ev ? `${esc(f.ev.observaciones)}<div class="cell-sub">${esc(f.ev.por?.nombre || '')} · ${fmtDateTime(f.ev.updated_at)}</div>` : ''}</div></td></tr>`;
  };
  const tabla = (fs) => `<div class="table-wrap responsive"><table class="table res-table"><thead><tr><th>Parámetro</th><th>Resultado</th><th>Criterio</th><th>Evaluación</th><th>Observaciones</th></tr></thead>
    <tbody>${fs.map(fila).join('')}</tbody></table></div>`;

  pane.innerHTML = `${previo ? aviso('Los resultados se evalúan cuando termina el registro durante el proceso. Mientras tanto, aquí se ve lo registrado hasta ahora.') : ''}
    ${K.areas.length ? '' : `<div class="card">${vacio('La prueba no tiene parámetros a evaluar.')}</div>`}
    ${K.areas.map((a) => {
      const fs = K.filas.filter((f) => f.area === a); const proc = fs.filter((f) => !f.compl), compl = fs.filter((f) => f.compl);
      const total = fs.filter((f) => f.requerida).length; const falta = K.faltan(a);
      return `<form class="card mt area-eval" data-area="${a}" novalidate>
        ${cardHead(`${AREAS[a].label}`, `${total - falta} de ${total} evaluados${AREAS_OBLIGATORIAS.includes(a) ? '' : ' · área opcional: si no se evalúa, la prueba sigue avanzando'}`,
          puedeEv(a) && fs.some((f) => f.conValor && !f.ev) ? `<button type="button" class="btn ghost sm" data-re="todo-cumple">${icon('check-check')} Marcar pendientes como Cumple</button>` : '')}
        ${proc.length ? tabla(proc) : ''}
        ${compl.length ? `<div class="section-title">${icon('microscope')} Evaluaciones complementarias</div>${tabla(compl)}` : ''}
        ${puedeEv(a) ? `<div class="form-foot"><div class="form-error" role="alert"></div><button type="submit" class="btn primary">${icon('save')} Guardar evaluación de ${esc(AREAS[a].label)}</button></div>`
          : enEval && falta ? aviso(`Lo evalúa el responsable de ${esc(AREAS[a].label)}.`) : ''}
      </form>`;
    }).join('')}`;
  refreshIcons();

  pane.addEventListener('click', (e) => {
    const b = e.target.closest('[data-re="todo-cumple"]');
    if (!b) return;
    b.closest('form').querySelectorAll('tr[data-fila]').forEach((tr) => {
      const radios = tr.querySelectorAll('input[type=radio]');
      if (radios.length && ![...radios].some((r) => r.checked)) radios[0].checked = true;
    });
  });
  pane.addEventListener('submit', async (e) => {
    e.preventDefault();
    const form = e.target; const area = form.dataset.area; const err = form.querySelector('.form-error');
    const btnG = form.querySelector('button[type=submit]');
    err.textContent = '';
    const cambios = [];
    for (const f of K.filas.filter((x) => x.area === area && x.conValor)) {
      const evv = form.querySelector(`input[name="ev_${f.key}"]:checked`)?.value;
      if (!evv) continue;
      const obsIn = form.elements[`ob_${f.key}`]; const obs = obsIn?.value.trim() || '';
      if (evv === 'no_cumple' && !obs) { err.textContent = `Explique por qué "${f.nombre}" no cumple.`; obsIn?.focus(); return; }
      const payload = { evaluacion: evv, observaciones: obs || 'Sin observaciones' };
      if (f.ev) { if (f.ev.evaluacion !== evv || f.ev.observaciones !== payload.observaciones) cambios.push(['upd', f.ev.id, payload]); }
      else cambios.push(['ins', null, { ...payload, prueba_id: P.id, area, plan_id: f.plan_id || null, prueba_parametro_id: f.prueba_parametro_id || null, evaluado_por: state.profile.id }]);
    }
    if (!cambios.length) { err.textContent = 'Marque Cumple o No cumple en los parámetros que va a evaluar.'; return; }
    btnG.disabled = true;
    try {
      for (const [t, id, payload] of cambios) {
        if (t === 'upd') mustRow(await sb.from('evaluaciones_prubind').update(payload).eq('id', id).select('id'));
        else must(await sb.from('evaluaciones_prubind').insert(payload));
      }
      toast(`Evaluación de ${AREAS[area].label} guardada.`, 'success');
      const K2 = await consolidarResultados(P);
      ctx.refrescar(K2.faltan(area) === 0 ? 'recomendaciones' : 'resultados');
    } catch (ex) { err.textContent = errMsg(ex); btnG.disabled = false; }
  });
}

// ============================== RECOMENDACIONES ==============================
export async function etapaRecomendaciones(pane, ctx) {
  const { P } = ctx;
  const K = await consolidarResultados(P);
  const enEval = EVALUA.includes(P.estado);
  const lista = K.areas.map((a) => [!!K.REC.find((r) => r.area === a), AREAS_OBLIGATORIAS.includes(a) ? AREAS[a].label : `${AREAS[a].label} (opcional: no detiene la prueba)`]);
  const completo = AREAS_OBLIGATORIAS.filter((a) => K.areas.includes(a)).every((a) => K.faltan(a) === 0 && K.REC.some((r) => r.area === a)) && K.areas.some((a) => AREAS_OBLIGATORIAS.includes(a));

  const tarjeta = (a) => {
    const r = K.REC.find((x) => x.area === a); const falta = K.faltan(a);
    const nc = K.filas.filter((f) => f.area === a && f.ev?.evaluacion === 'no_cumple');
    const puede = enEval && puedeArea(P, 'evaluar', a);
    const nOk = K.filas.filter((f) => f.area === a && f.ev?.evaluacion === 'cumple').length;
    const resumen = `<p class="hint">${nOk} ${nOk === 1 ? 'cumple' : 'cumplen'} · <span class="${nc.length ? 'bad-txt' : ''}">${nc.length} no ${nc.length === 1 ? 'cumple' : 'cumplen'}</span>${nc.length ? `: ${nc.map((f) => esc(f.nombre)).join(', ')}` : ''}</p>`;
    let cuerpo;
    if (puede && falta === 0) {
      cuerpo = `<form class="rec-form" data-area="${a}" novalidate>
        <div class="field"><span class="label">Recomendación del área <span class="req">*</span></span>
          <div class="radio-cards multi">${Object.entries(SENTIDO).map(([k, [l, , d]]) => `<label><input type="radio" name="sentido" value="${k}" ${r?.sentido === k ? 'checked' : ''}><span>${esc(l)}<small>${esc(d)}</small></span></label>`).join('')}</div></div>
        <div class="field"><label for="rec-${a}">Recomendaciones y acciones derivadas <span class="req">*</span></label>
          <textarea id="rec-${a}" name="texto" rows="3" maxlength="1000" data-counter placeholder="Qué recomienda el área de acuerdo con los resultados obtenidos">${esc(r?.recomendacion || '')}</textarea></div>
        <div class="form-foot"><div class="form-error" role="alert"></div><button type="submit" class="btn primary">${icon('save')} ${r ? 'Actualizar' : 'Guardar'} recomendación</button></div></form>`;
    } else if (r) {
      cuerpo = `<div>${pill(SENTIDO[r.sentido][0], SENTIDO[r.sentido][1])} <span class="cell-sub">${esc(r.por?.nombre || '')} · ${fmtDateTime(r.updated_at)}</span></div><p class="pre">${esc(r.recomendacion)}</p>`;
    } else if (falta) {
      cuerpo = aviso(`Primero se evalúan los resultados del área (${falta} por evaluar).`, '', 'list-checks');
    } else cuerpo = vacio(`Pendiente: la registra el responsable de ${AREAS[a].label}.${AREAS_OBLIGATORIAS.includes(a) ? "" : " Si no la registra, la prueba sigue avanzando."}`);
    return `<div class="card mt"><div class="card-head"><div><h3>${icon(AREAS[a].ico)} ${esc(AREAS[a].label)}</h3><p>${esc(AREAS[a].desc)}</p></div>${r ? pill('Registrada', 'ok') : AREAS_OBLIGATORIAS.includes(a) ? pill('Pendiente', 'warn') : pill('Opcional', 'gray')}</div>
      ${resumen}${cuerpo}</div>`;
  };

  pane.innerHTML = `${['registrada', 'en_preparacion', 'preparada', 'en_ejecucion'].includes(P.estado) ? aviso('Las recomendaciones se registran después de evaluar los resultados.') : ''}
    <div class="grid grid-main">
      <div>${K.areas.map(tarjeta).join('') || `<div class="card">${vacio('Sin áreas participantes.')}</div>`}</div>
      <div class="card"><div class="card-head"><div><h3>Para pasar a dictamen</h3><p>Cuando todas las áreas registran su recomendación, la prueba pasa sola al dictamen de Alta Dirección.</p></div></div>
        ${checklist(lista)}
        ${enEval && completo ? `<button class="btn primary block mt" data-rc="enviar">${icon('send')} Enviar a dictamen</button>` : ''}
      </div>
    </div>`;
  refreshIcons();

  const enviar = async (auto) => {
    await accion(P.id, 'enviar_dictamen');
    toast(auto ? 'Todas las áreas registraron su recomendación: la prueba pasó al dictamen de Alta Dirección.' : 'Prueba enviada a dictamen.', 'success');
    ctx.refrescar('dictamen');
  };
  pane.addEventListener('click', async (e) => {
    if (!e.target.closest('[data-rc="enviar"]')) return;
    try { await enviar(false); } catch (err) { toast(errMsg(err), 'error'); }
  });
  pane.addEventListener('submit', async (e) => {
    e.preventDefault();
    const form = e.target; const area = form.dataset.area; const err = form.querySelector('.form-error');
    const sentido = form.querySelector('input[name=sentido]:checked')?.value; const texto = form.elements.texto.value.trim();
    if (!sentido) { err.textContent = 'Elija si la recomendación es favorable, no favorable o repetir.'; return; }
    if (texto.length < 3) { err.textContent = 'Escriba la recomendación del área.'; form.elements.texto.focus(); return; }
    const btnG = form.querySelector('button[type=submit]'); btnG.disabled = true;
    try {
      const r = K.REC.find((x) => x.area === area);
      if (r) mustRow(await sb.from('recomendaciones_prubind').update({ sentido, recomendacion: texto }).eq('id', r.id).select('id'));
      else must(await sb.from('recomendaciones_prubind').insert({ prueba_id: P.id, area, sentido, recomendacion: texto, emitido_por: state.profile.id }));
      toast(`Recomendación de ${AREAS[area].label} guardada.`, 'success');
      // Si ya están todas, pasa sola al dictamen
      const { data } = must(await sb.rpc('prubind_eval_estado', { p_prueba: P.id }));
      if (data.eval_faltantes === 0 && data.recom_faltantes === 0) { try { await enviar(true); return; } catch { /* se puede enviar manualmente */ } }
      ctx.refrescar('recomendaciones');
    } catch (ex) { err.textContent = errMsg(ex); btnG.disabled = false; }
  });
}
