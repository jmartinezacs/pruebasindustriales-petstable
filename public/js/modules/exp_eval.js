// =====================================================================
// Etapa 4 · Resultados por parámetro y etapa 5 · Veredicto y
// recomendaciones por área.
// Cada área es independiente: evalúa lo suyo (✓ Cumple, ✗ No cumple o
// ? No se pudo determinar) y da su veredicto (satisfactoria / no
// satisfactoria) en cuanto termina, aunque la prueba siga en proceso.
// Lo que no tiene resultado (p. ej. bromatológicos de laboratorio) no
// detiene la evaluación. La prueba pasa sola al dictamen de Alta Dirección
// cuando termina y todas las áreas que participaron dieron su veredicto.
// =====================================================================
import {
  sb, state, esc, icon, toast, errMsg, must, mustRow, getCat, unidadTxt, fmtDateTime, pill, puedeArea, misAreas,
  AREAS, AREAS_ORDEN, COMPLEMENTARIAS, OPCIONES_TXT, EVALUACION, VEREDICTO, refreshIcons,
} from '../core.js';
import { aviso, vacio, checklist, accion, criterioTxt } from './exp_comun.js';

const EVALUA = ['en_ejecucion', 'en_evaluacion', 'pendiente_resultados'];
const TERMINADA = ['en_evaluacion', 'pendiente_resultados'];

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
      const donde = `${r.batch_numero ? `${P.ejecucion_form === 'fabricacion' ? 'Batch' : 'Corrida'} ${r.batch_numero}` : 'General'}${r.dilucion ? ` · ${r.dilucion}` : ''}`;
      return { txt: `${donde}: ${v}`, fuera: r.estado === 'no_conforme', just: r.justificacion };
    });
    filas.push({ key: `pl:${pl.id}`, plan_id: pl.id, area: m.area, compl: COMPLEMENTARIAS.includes(m.categoria), lab: m.categoria === 'bromatologia', nombre: m.nombre,
      criterio: criterioTxt(pl, unidadTxt(unidades, m.unidad_id)), ref: pl.crit_referencia, valores, conValor: R.length > 0,
      ev: ev.data.find((x) => x.plan_id === pl.id) });
  });
  pars.data.forEach((x) => {
    const c = ctrl.data.find((k) => k.prueba_parametro_id === x.id);
    filas.push({ key: `par:${x.id}`, prueba_parametro_id: x.id, area: 'produccion', compl: false, lab: false, nombre: `${x.nombre} (${P.equipo_nombre || 'equipo'})`,
      criterio: x.minimo != null || x.maximo != null ? criterioTxt({ crit_minimo: x.minimo, crit_maximo: x.maximo }, unidadTxt(unidades, x.unidad_id)) : (x.referencia || '').split(' · ')[0],
      valores: c?.valor != null ? [{ txt: `${c.valor} ${unidadTxt(unidades, x.unidad_id)}`.trim(), fuera: c.resultado === 'no_conforme', just: c.observaciones }] : [],
      conValor: c?.valor != null, ev: ev.data.find((k) => k.prueba_parametro_id === x.id) });
  });
  const areas = AREAS_ORDEN.filter((a) => filas.some((f) => f.area === a));
  // Por evaluar: lo que tiene resultado y aún no se evalúa
  const faltan = (a) => filas.filter((f) => f.area === a && f.conValor && !f.ev).length;
  // Participa el área con algún dato o alguna evaluación
  const participa = (a) => filas.some((f) => f.area === a && (f.conValor || f.ev));
  return { filas, areas, faltan, participa, REC: rec.data };
}

// Conteo ✓ ✗ ? de un área
const conteo = (fs) => Object.keys(EVALUACION).map((k) => [k, fs.filter((f) => f.ev?.evaluacion === k).length]);
const resumenEval = (fs) => `<span class="ev-sum">${conteo(fs).map(([k, n]) => `<span class="ev-n ${EVALUACION[k][1]}" title="${esc(EVALUACION[k][0])}">${icon(EVALUACION[k][2])} ${n}</span>`).join('')}</span>`;

// ============================== RESULTADOS ==============================
export async function etapaResultados(pane, ctx) {
  const { P } = ctx;
  const K = await consolidarResultados(P);
  const enEval = EVALUA.includes(P.estado);
  const puedeEv = (a) => enEval && puedeArea(P, 'evaluar', a);
  const antes = ['registrada', 'en_preparacion', 'preparada'].includes(P.estado);
  const vis = misAreas(P);   // áreas propias abiertas y primero; las demás contraídas (se abren al tocarlas)

  const valoresHTML = (f) => (f.valores.length ? f.valores.map((v) => `<div class="${v.fuera ? 'bad-txt' : ''}">${esc(v.txt)}${v.fuera ? ` ${icon('alert-triangle')}` : ''}${v.just ? `<div class="cell-sub">${esc(v.just)}</div>` : ''}</div>`).join('')
    : f.lab ? `<span class="lab-pend">${icon('hourglass')} Pendiente de laboratorio</span>` : '<span class="cell-sub">Sin resultado</span>');
  const opcion = (f, k, habil) => {
    const [l, cls, ic] = EVALUACION[k];
    return `<label class="ev-opt ${cls} ${habil ? '' : 'off'}" title="${esc(l)}"><input type="radio" name="ev_${esc(f.key)}" value="${k}" ${f.ev?.evaluacion === k ? 'checked' : ''} ${habil ? '' : 'disabled'}>
      <span class="ev-btn" aria-hidden="true">${icon(ic)}</span><span class="sr-only">${esc(l)}</span></label>`;
  };
  const fila = (f) => {
    const edit = puedeEv(f.area);
    const sel = f.ev?.evaluacion;
    const obs = f.ev && f.ev.observaciones !== 'Sin observaciones' ? f.ev.observaciones : '';
    return `<div class="ev-row ${sel ? `is-${sel}` : ''}" data-fila="${esc(f.key)}">
      <div class="ev-param"><b>${esc(f.nombre)}</b>${f.criterio ? `<span>Criterio: ${esc(f.criterio)}${f.ref ? ` · ${esc(f.ref)}` : ''}</span>` : '<span>Sin criterio cargado</span>'}</div>
      <div class="ev-val">${valoresHTML(f)}</div>
      <div class="ev-pick">${edit ? `<div class="ev-opts" role="radiogroup" aria-label="Evaluación de ${esc(f.nombre)}">${opcion(f, 'cumple', f.conValor)}${opcion(f, 'no_cumple', f.conValor)}${opcion(f, 'no_determinado', true)}</div>`
        : sel ? pill(EVALUACION[sel][0], EVALUACION[sel][1]) : `<span class="cell-sub">${f.conValor ? 'Por evaluar' : '—'}</span>`}</div>
      <div class="ev-obs">${edit ? `<input name="ob_${esc(f.key)}" maxlength="500" value="${esc(obs)}" placeholder="${sel === 'no_cumple' || sel === 'no_determinado' ? 'Explique brevemente *' : 'Observaciones (opcional)'}" aria-label="Observaciones de ${esc(f.nombre)}">`
        : f.ev ? `${esc(f.ev.observaciones)}<div class="cell-sub">${esc(f.ev.por?.nombre || '')} · ${fmtDateTime(f.ev.updated_at)}</div>` : ''}</div>
    </div>`;
  };
  const lista = (fs) => `<div class="ev-list"><div class="ev-row ev-headrow" aria-hidden="true"><div>Parámetro</div><div>Resultado</div><div>Evaluación</div><div>Observaciones</div></div>${fs.map(fila).join('')}</div>`;

  pane.innerHTML = `${antes ? aviso('Se evalúa cuando la prueba ya inició.', '', 'circle-play') : ''}
    ${P.estado === 'en_ejecucion' ? aviso('Puede evaluar lo que su área ya registró.', 'info', 'zap') : ''}
    <div class="ev-legend">${Object.values(EVALUACION).map(([l, cls, ic]) => `<span class="ev-n ${cls}">${icon(ic)} ${esc(l)}</span>`).join('')}</div>
    ${K.areas.length ? '' : `<div class="card">${vacio('La prueba no tiene parámetros a evaluar.')}</div>`}
    ${[...K.areas].sort((x, y) => Number(!vis.includes(x)) - Number(!vis.includes(y))).map((a) => {
      const fs = K.filas.filter((f) => f.area === a); const proc = fs.filter((f) => !f.compl), compl = fs.filter((f) => f.compl);
      const conDato = fs.filter((f) => f.conValor).length; const evaluados = fs.filter((f) => f.ev).length; const falta = K.faltan(a);
      const sinDatos = !K.participa(a);
      return `<form class="card mt area-eval plegable g-${a} ${vis.includes(a) ? '' : 'colapsada'}" data-area="${a}" novalidate>
        <div class="card-head"><div class="ae-title"><span class="ar-ico">${icon(AREAS[a].ico)}</span><div><h3>${esc(AREAS[a].label)}</h3>
          <p>${sinDatos ? 'Aún sin datos registrados' : `${evaluados} evaluado(s) · ${conDato} con resultado${falta ? ` · <b>${falta} por evaluar</b>` : ''}`}</p></div></div>
          <div class="head-btns">${resumenEval(fs)}${puedeEv(a) && fs.some((f) => f.conValor && !f.ev) ? `<button type="button" class="btn ghost sm" data-re="todo-cumple">${icon('check-check')} Pendientes como Cumple</button>` : ''}<span class="pleg-ico">${icon('chevron-down')}</span></div></div>
        ${proc.length ? lista(proc) : ''}
        ${compl.length ? `<div class="section-title">${icon('microscope')} Evaluaciones complementarias</div>${lista(compl)}` : ''}
        ${puedeEv(a) ? `<div class="form-foot"><div class="form-error" role="alert"></div><button type="submit" class="btn primary">${icon('save')} Guardar evaluación de ${esc(AREAS[a].label)}</button></div>`
          : enEval && falta ? aviso(`Lo evalúa el responsable de ${esc(AREAS[a].label)}.`) : ''}
      </form>`;
    }).join('')}`;
  refreshIcons();

  // Al elegir ✗ o ?, la observación pasa a ser obligatoria
  pane.addEventListener('change', (e) => {
    const r = e.target.closest('.ev-opt input'); if (!r) return;
    const row = r.closest('.ev-row'); row.className = `ev-row is-${r.value}`;
    const ob = row.querySelector('.ev-obs input');
    if (ob) { ob.placeholder = r.value === 'cumple' ? 'Observaciones (opcional)' : 'Explique brevemente *'; if (r.value !== 'cumple' && !ob.value) ob.focus(); }
  });
  pane.addEventListener('click', (e) => {
    const b = e.target.closest('[data-re="todo-cumple"]');
    if (!b) return;
    b.closest('form').querySelectorAll('.ev-row[data-fila]').forEach((row) => {
      const radios = row.querySelectorAll('input[type=radio]:not([disabled])');
      if (radios.length && ![...radios].some((r) => r.checked) && radios[0].value === 'cumple') { radios[0].checked = true; row.className = 'ev-row is-cumple'; }
    });
  });
  pane.addEventListener('submit', async (e) => {
    e.preventDefault();
    const form = e.target; const area = form.dataset.area; const err = form.querySelector('.form-error');
    const btnG = form.querySelector('button[type=submit]');
    err.textContent = '';
    const cambios = [];
    for (const f of K.filas.filter((x) => x.area === area)) {
      const evv = form.querySelector(`input[name="ev_${CSS.escape(f.key)}"]:checked`)?.value;
      if (!evv) continue;
      const obsIn = form.elements[`ob_${f.key}`]; const obs = obsIn?.value.trim() || '';
      if (evv !== 'cumple' && !obs) { err.textContent = `Explique por qué "${f.nombre}" ${evv === 'no_cumple' ? 'no cumple' : 'no se pudo determinar'}.`; obsIn?.focus(); return; }
      const payload = { evaluacion: evv, observaciones: obs || 'Sin observaciones' };
      if (f.ev) { if (f.ev.evaluacion !== evv || f.ev.observaciones !== payload.observaciones) cambios.push(['upd', f.ev.id, payload]); }
      else cambios.push(['ins', null, { ...payload, prueba_id: P.id, area, plan_id: f.plan_id || null, prueba_parametro_id: f.prueba_parametro_id || null, evaluado_por: state.profile.id }]);
    }
    if (!cambios.length) { err.textContent = 'Marque ✓, ✗ o ? en los parámetros que va a evaluar.'; return; }
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

// ============================== VEREDICTO Y RECOMENDACIONES ==============================
export async function etapaRecomendaciones(pane, ctx) {
  const { P } = ctx;
  const K = await consolidarResultados(P);
  const enEval = EVALUA.includes(P.estado);
  const part = K.areas.filter((a) => K.participa(a));
  const noPart = AREAS_ORDEN.filter((a) => !part.includes(a));
  const listo = (a) => K.faltan(a) === 0 && K.REC.some((r) => r.area === a);
  const completo = part.length > 0 && part.every(listo);
  const vis = misAreas(P);   // áreas propias abiertas y primero; las demás contraídas

  const tarjeta = (a) => {
    const r = K.REC.find((x) => x.area === a); const falta = K.faltan(a);
    const fs = K.filas.filter((f) => f.area === a);
    const nc = fs.filter((f) => f.ev?.evaluacion === 'no_cumple');
    const puede = enEval && puedeArea(P, 'evaluar', a);
    const resumen = `<div class="ver-sum">${resumenEval(fs)}${nc.length ? `<span class="bad-txt">No cumple: ${nc.map((f) => esc(f.nombre)).join(', ')}</span>` : ''}</div>`;
    let cuerpo;
    if (puede && falta === 0) {
      const ops = ['favorable', 'no_favorable'].concat(r?.sentido === 'repetir' ? ['repetir'] : []);
      cuerpo = `<form class="rec-form" data-area="${a}" novalidate>
        <span class="label">Por parte de ${esc(AREAS[a].label)}, la prueba es: <span class="req">*</span></span>
        <div class="verdict-opts">${ops.map((k) => { const [l, cls, ic, d] = VEREDICTO[k];
          return `<label class="verdict ${cls}"><input type="radio" name="sentido" value="${k}" ${r?.sentido === k ? 'checked' : ''}><span class="vd-ico">${icon(ic)}</span><span class="vd-txt"><b>${esc(l)}</b><small>${esc(d)}</small></span></label>`; }).join('')}</div>
        <div class="field"><label for="rec-${a}">Recomendaciones y acciones derivadas <span class="req">*</span></label>
          <textarea id="rec-${a}" name="texto" rows="3" maxlength="1000" data-counter placeholder="Recomendación del área">${esc(r?.recomendacion || '')}</textarea></div>
        <div class="form-foot"><div class="form-error" role="alert"></div><button type="submit" class="btn primary">${icon('save')} ${r ? 'Actualizar' : 'Guardar'} veredicto</button></div></form>`;
    } else if (r) {
      const [l, cls, ic] = VEREDICTO[r.sentido];
      cuerpo = `<div class="verdict-done ${cls}"><span class="vd-ico">${icon(ic)}</span><div><b>${esc(l)}</b><span>${esc(r.por?.nombre || '')} · ${fmtDateTime(r.updated_at)}</span></div></div><p class="pre">${esc(r.recomendacion)}</p>`;
    } else if (falta) {
      cuerpo = aviso(`Primero evalúe los resultados (${falta} pendientes).`, '', 'list-checks');
    } else cuerpo = vacio(`Pendiente: lo registra el responsable de ${AREAS[a].label}.`);
    return `<div class="card mt plegable g-${a} ${vis.includes(a) ? '' : 'colapsada'}"><div class="card-head"><div class="ae-title"><span class="ar-ico">${icon(AREAS[a].ico)}</span><div><h3>${esc(AREAS[a].label)}</h3><p>${esc(AREAS[a].desc)}</p></div></div>
      <div class="head-btns">${r ? pill(VEREDICTO[r.sentido][0], VEREDICTO[r.sentido][1]) : pill('Pendiente', 'warn')}<span class="pleg-ico">${icon('chevron-down')}</span></div></div>${resumen}${cuerpo}</div>`;
  };

  pane.innerHTML = `${['registrada', 'en_preparacion', 'preparada'].includes(P.estado) ? aviso('El veredicto se da después de evaluar.', '', 'circle-play') : ''}
    <div class="grid grid-main">
      <div>${[...part].sort((x, y) => Number(!vis.includes(x)) - Number(!vis.includes(y))).map(tarjeta).join('') || `<div class="card">${vacio('Ninguna área ha registrado datos todavía.')}</div>`}
        ${noPart.length ? `<div class="card mt no-part"><div class="card-head"><div>${P.estado === 'en_ejecucion' ? '<h3>Áreas sin datos todavía</h3><p>Participan si registran algún dato.</p>'
          : '<h3>Áreas que no participaron</h3><p>No registraron datos.</p>'}</div></div>
          <div class="chips">${noPart.map((a) => `<span class="chip">${icon(AREAS[a].ico)} ${esc(AREAS[a].label)}</span>`).join('')}</div></div>` : ''}</div>
      <div class="card"><div class="card-head"><div><h3>Para pasar a dictamen</h3><p>Pasa sola a dictamen cuando todas las áreas dan su veredicto.</p></div></div>
        ${checklist([...(P.estado === 'en_ejecucion' ? [[false, 'Prueba terminada']] : []), ...part.map((a) => [listo(a), `Veredicto de ${AREAS[a].label}`])])}
        ${TERMINADA.includes(P.estado) && completo ? `<button class="btn primary block mt" data-rc="enviar">${icon('send')} Enviar a dictamen</button>` : ''}
      </div>
    </div>`;
  refreshIcons();

  const enviar = async (auto) => {
    await accion(P.id, 'enviar_dictamen');
    toast(auto ? 'Todas las áreas que participaron dieron su veredicto: la prueba pasó al dictamen de Alta Dirección.' : 'Prueba enviada a dictamen.', 'success');
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
    if (!sentido) { err.textContent = 'Elija si por parte de su área la prueba es satisfactoria o no satisfactoria.'; return; }
    if (texto.length < 3) { err.textContent = 'Escriba la recomendación del área.'; form.elements.texto.focus(); return; }
    const btnG = form.querySelector('button[type=submit]'); btnG.disabled = true;
    try {
      const r = K.REC.find((x) => x.area === area);
      if (r) mustRow(await sb.from('recomendaciones_prubind').update({ sentido, recomendacion: texto }).eq('id', r.id).select('id'));
      else must(await sb.from('recomendaciones_prubind').insert({ prueba_id: P.id, area, sentido, recomendacion: texto, emitido_por: state.profile.id }));
      toast(`Veredicto de ${AREAS[area].label} guardado.`, 'success');
      // Si la prueba ya terminó y están todas, pasa sola al dictamen
      if (TERMINADA.includes(P.estado)) {
        const { data } = must(await sb.rpc('prubind_eval_estado', { p_prueba: P.id }));
        if (data.eval_faltantes === 0 && data.recom_faltantes === 0) { try { await enviar(true); return; } catch { /* se puede enviar manualmente */ } }
      }
      ctx.refrescar('recomendaciones');
    } catch (ex) { err.textContent = errMsg(ex); btnG.disabled = false; }
  });
}
