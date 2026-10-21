// =====================================================================
// Etapas 5 y 6 · Dictamen y aprobación de Alta Dirección (con el
// consolidado de resultados y veredictos por área) y Cierre.
// Quien dictamina puede completar ahí mismo los valores que quedaron
// pendientes, o emitir su dictamen con ellos pendientes, y adjuntar
// evidencia. Un dictamen "Aprobada" autoriza implementar el cambio; después
// la Gerencia de Procesos y Mejora Continua cierra la prueba.
// =====================================================================
import {
  sb, esc, icon, toast, errMsg, openModal, confirmDialog, getCat, opciones, fmtDateTime, fmtDate,
  pill, estadoPill, autoridad, AREAS, AREAS_ORDEN, EVALUACION, VEREDICTO, ADJ_ACCEPT, refreshIcons, fechaEjecTxt,
} from '../core.js';
import { box, txt, cardHead, btn, aviso, vacio, checklist, accion, subirArchivos, eviChips } from './exp_comun.js';
import { consolidarResultados, listaEval, enlazarEval, guardarEvaluacion } from './exp_eval.js';

const DICT = { aprobada: ['Aprobada · implementación autorizada', 'ok'], rechazada: ['Rechazada', 'bad'], requiere_repeticion: ['Requiere repetición', 'warn'], pendiente_resultados: ['Pendiente de resultados', 'warn'] };

async function consolidado(P) {
  const [batches, lotes, controles, dict, adj, RES] = await Promise.all([
    sb.from('v_batches_prubind').select('*').eq('prueba_id', P.id).order('ejecucion').order('numero'),
    sb.from('lotes_diarios_prubind').select('*').eq('prueba_id', P.id).order('fecha'),
    sb.from('ejecucion_controles_prubind').select('*').eq('prueba_id', P.id).order('created_at'),
    sb.from('dictamenes_prubind').select('*, por:usuarios_prubind!dictamenes_prubind_emitido_por_fkey(nombre), motivo:motivos_prubind(nombre)').eq('prueba_id', P.id).order('created_at'),
    sb.from('adjuntos_prubind').select('id, nombre, ruta, etapa, plan_id, batch_id, created_at, tipo:tipos_evidencia_prubind(nombre), subio:usuarios_prubind!adjuntos_prubind_subido_por_fkey(nombre)').eq('prueba_id', P.id).order('created_at'),
    consolidarResultados(P),
  ]);
  [batches, lotes, controles, dict, adj].forEach((r) => { if (r.error) throw r.error; });
  return { B: batches.data, L: lotes.data, C: controles.data, D: dict.data, ADJ: adj.data, RES };
}

function resumenHTML(P, K, ej) {
  const B = K.B.filter((b) => b.ejecucion === ej), L = K.L.filter((l) => l.ejecucion === ej), C = K.C.filter((c) => c.ejecucion === ej);
  const { filas, areas, REC } = K.RES;
  const nc = filas.filter((f) => f.ev?.evaluacion === 'no_cumple');
  const sinEval = filas.filter((f) => f.conValor && !f.ev);
  const pend = filas.filter((f) => f.pend && f.ev?.evaluacion !== 'no_determinado');
  const nd = filas.filter((f) => f.ev?.evaluacion === 'no_determinado');
  const part = areas.filter((a) => filas.some((f) => f.area === a && (f.conValor || f.ev)));
  return `
    <div class="detail-grid">
      ${box('Objetivo', esc(P.objetivo_desc || P.objetivo_nombre || '—'), true)}
      ${box('Ejecución', `#${ej}${P.ejecucion_actual > 1 ? ` de ${P.ejecucion_actual}` : ''}${P.fecha_planeada ? ` · ${esc(fechaEjecTxt(P))}` : ''}`)}
      ${B.length || C.length ? box(P.ejecucion_form === 'fabricacion' ? 'Lotes diarios y batches' : 'Corrida', P.ejecucion_form === 'fabricacion'
        ? (L.map((l) => `${esc(l.codigo)}: ${B.filter((b) => b.lote_diario_id === l.id).map((b) => `#${b.numero}${b.resultado_op === 'no_conforme' ? ' (con desviación)' : ''}`).join(', ')}`).join('<br>') || '—')
        : `${C.length} parámetro(s) del equipo registrados`) : ''}
      ${part.length ? box('Resultados por área', part.map((a) => { const fs = filas.filter((f) => f.area === a && f.ev); const n = fs.filter((f) => f.ev.evaluacion === 'no_cumple').length; const d = fs.filter((f) => f.ev.evaluacion === 'no_determinado').length;
        return `${esc(AREAS[a].label)}: <b class="ok-txt">${fs.length - n - d} ${fs.length - n - d === 1 ? 'cumple' : 'cumplen'}</b>${n ? ` · <b class="bad-txt">${n} no ${n === 1 ? 'cumple' : 'cumplen'}</b>` : ''}${d ? ` · <b class="warn-txt">${d} no se pudo determinar</b>` : ''}`; }).join('<br>'), true) : ''}
      ${nc.length ? box('Parámetros que no cumplen', nc.map((f) => `<div class="nc-line"><b>${esc(f.nombre)}</b> (${esc(AREAS[f.area].label)})${f.criterio ? ` · criterio ${esc(f.criterio)}` : ''}<br><span class="cell-sub">${f.valores.map((v) => esc(v.txt)).join(' · ')}</span><br>${esc(f.ev.observaciones)}</div>`).join(''), true) : ''}
      ${nd.length ? box('No se pudo determinar', nd.map((f) => `<div class="nc-line"><b>${esc(f.nombre)}</b> (${esc(AREAS[f.area].label)}): ${esc(f.ev.observaciones)}</div>`).join(''), true) : ''}
      ${pend.length ? box('Pendientes (sin valor)', pend.map((f) => esc(f.nombre)).join(', '), true) : ''}
      ${sinEval.length ? box('Sin evaluar', sinEval.map((f) => esc(f.nombre)).join(', '), true) : ''}
      ${REC.length ? box('Veredicto y recomendaciones de las áreas', AREAS_ORDEN.filter((a) => part.includes(a) || REC.some((x) => x.area === a)).map((a) => { const r = REC.find((x) => x.area === a);
        return `<div class="nc-line"><b>${esc(AREAS[a].label)}</b>: ${r ? `${pill(VEREDICTO[r.sentido][0], VEREDICTO[r.sentido][1])} ${esc(r.recomendacion)} <span class="cell-sub">· ${esc(r.por?.nombre || '')}</span>` : '<span class="warn-txt">Pendiente</span>'}</div>`; }).join(''), true) : ''}
      ${K.ADJ.length ? box('Evidencia adjunta', eviChips(K.ADJ), true) : ''}
    </div>`;
}

export async function etapaDictamen(pane, ctx) {
  const { P, E } = ctx;
  if (['registrada', 'en_preparacion', 'preparada', 'en_ejecucion', 'en_evaluacion', 'pendiente_resultados'].includes(P.estado) && !P.ultimo_dictamen) {
    pane.innerHTML = aviso('Alta Dirección emite el dictamen cuando la prueba termina y las áreas que participaron evaluaron sus resultados y dieron su veredicto.'); refreshIcons(); return;
  }
  const K = await consolidado(P);
  const puedeDict = P.estado === 'pendiente_dictamen' && autoridad(P.tipo, 'dictaminar');
  const bloqueos = [
    [E.eval_faltantes === 0, 'Resultados registrados evaluados por cada área'],
    [E.recom_faltantes === 0, 'Veredicto de las áreas que participaron'],
  ];
  // Valores que quedaron pendientes: quien dictamina puede completarlos aquí
  const pendientes = K.RES.filas.filter((f) => f.m && !f.conValor && (f.pend || (K.RES.participa(f.area) && (!f.ev || f.ev.evaluacion === 'no_determinado'))));
  const evDict = (ej) => K.ADJ.filter((a) => a.etapa === 'dictamen' && new Date(a.created_at) >= new Date(ej.created_at) - 60000);
  pane.innerHTML = `
    ${puedeDict && pendientes.length ? `<form class="card dict-pend" id="dc-pend" novalidate>${cardHead(`Valores pendientes (${pendientes.length})`, 'Si ya los tiene, complételos y evalúelos; si no, puede dictaminar con ellos pendientes.')}
        ${listaEval(pendientes, { edit: true, completarTodo: true })}
        <div class="form-foot"><div class="form-error" role="alert"></div><button type="submit" class="btn primary">${icon('save')} Guardar valores</button></div></form>` : ''}
    <div class="grid grid-main ${puedeDict && pendientes.length ? 'mt' : ''}">
      <div class="card">${cardHead('Resumen consolidado', 'Resultados por parámetro y recomendaciones de cada área.')}${resumenHTML(P, K, P.ejecucion_actual)}</div>
      <div class="card">${cardHead('Dictamen y aprobación', 'Alta Dirección dictamina; si aprueba, queda autorizado implementar el cambio.')}
        ${checklist(bloqueos)}
        ${E.no_cumple && P.estado === 'pendiente_dictamen' ? aviso(`${E.no_cumple} parámetro(s) no cumplen. Para aprobar, explique la decisión en la conclusión.`, 'warn', 'alert-triangle') : ''}
        ${puedeDict ? `<button class="btn primary block" data-dc="emitir">${icon('gavel')} Emitir dictamen</button>`
          : P.estado === 'pendiente_dictamen' ? aviso('El dictamen lo emite Alta Dirección (Directora de Calidad o Director de Producción).') : ''}
        <div class="section-title">${icon('history')} Historial de dictámenes</div>
        ${K.D.length ? `<div class="list">${K.D.slice().reverse().map((d) => `<div class="list-item">${pill(...DICT[d.dictamen])}<div class="li-main"><b>Ejecución #${d.ejecucion} · ${esc(d.por?.nombre || '')}</b>
          <span>${fmtDateTime(d.created_at)}${d.motivo ? ` · ${esc(d.motivo.nombre)}` : ''}${d.descripcion ? ` · ${esc(d.descripcion)}` : ''}</span>${eviChips(evDict(d))}</div></div>`).join('')}</div>` : vacio('Sin dictámenes.')}
      </div>
    </div>`;
  refreshIcons();
  const fp = pane.querySelector('#dc-pend');
  if (fp) {
    enlazarEval(fp);
    fp.addEventListener('submit', async (e) => {
      e.preventDefault();
      const err = fp.querySelector('.form-error'); const b = fp.querySelector('button[type=submit]');
      err.textContent = ''; b.disabled = true;
      try { await guardarEvaluacion(P, fp, pendientes); toast('Valores guardados.', 'success'); ctx.refrescar('dictamen'); }
      catch (ex) { err.textContent = errMsg(ex); b.disabled = false; }
    });
  }
  pane.addEventListener('click', async (e) => {
    if (!e.target.closest('[data-dc="emitir"]')) return;
    try { if (await dictamenForm(P, bloqueos.every(([ok]) => ok), E.no_cumple)) ctx.refrescar(); } catch (err) { toast(errMsg(err), 'error'); }
  });
}

async function dictamenForm(P, aprobable, noCumple) {
  const motivos = (await getCat('motivos', { activos: true })).filter((m) => m.tipo === 'rechazo');
  return openModal({
    title: 'Dictamen y aprobación', subtitle: `${P.folio} · ${P.cambio}`, submitText: 'Emitir dictamen', size: 'lg',
    body: `<div class="field"><span class="label">Dictamen <span class="req">*</span></span>
        <div class="radio-cards multi">
          <label><input type="radio" name="d" value="aprobada" ${aprobable ? '' : 'disabled'}><span>${icon('badge-check')} Aprobada<small>Se autoriza implementar el cambio</small></span></label>
          <label><input type="radio" name="d" value="rechazada"><span>${icon('x-octagon')} Rechazada</span></label>
          <label><input type="radio" name="d" value="requiere_repeticion"><span>${icon('repeat')} Requiere repetición</span></label>
          <label><input type="radio" name="d" value="pendiente_resultados"><span>${icon('hourglass')} Pendiente de resultados</span></label>
        </div>${aprobable ? '' : '<small class="hint">"Aprobada" no está disponible: faltan evaluaciones o recomendaciones de las áreas.</small>'}</div>
      <div class="field hidden" id="dc-mot-w"><label for="dc-mot">Motivo de rechazo <span class="req">*</span></label><select id="dc-mot" name="motivo">${opciones(motivos, null)}</select></div>
      <div class="field"><label for="dc-t">Conclusión</label><textarea id="dc-t" name="texto" maxlength="1000" rows="3" placeholder="${noCumple ? 'Obligatoria para aprobar con parámetros que no cumplen y para repetir la prueba' : 'Obligatoria si se requiere repetición'}"></textarea></div>
      <div class="field"><label for="dc-f">Evidencia (opcional)</label><input id="dc-f" name="archivos" type="file" multiple accept="${ADJ_ACCEPT}"><small class="hint">Fotos, reportes o documentos que respaldan el dictamen.</small></div>
      ${aviso('Al aprobar, Alta Dirección autoriza implementar el cambio. Después, la Gerencia de Procesos y Mejora Continua cierra la prueba.', '', 'info')}`,
    onOpen: ({ form }) => form.addEventListener('change', () => {
      form.querySelector('#dc-mot-w').classList.toggle('hidden', form.querySelector('input[name=d]:checked')?.value !== 'rechazada');
    }),
    onSubmit: async ({ form, setError }) => {
      const d = form.querySelector('input[name=d]:checked')?.value;
      if (!d) { setError('Seleccione el dictamen.'); return false; }
      const texto = form.elements.texto.value.trim();
      if (d === 'rechazada' && !form.elements.motivo.value) { setError('Seleccione el motivo de rechazo.'); return false; }
      if (d === 'requiere_repeticion' && !texto) { setError('Explique por qué se requiere repetir la prueba.'); return false; }
      if (d === 'aprobada' && noCumple && !texto) { setError('Hay parámetros que no cumplen: explique en la conclusión por qué se aprueba.'); return false; }
      const files = [...(form.elements.archivos.files || [])];
      await accion(P.id, 'dictaminar', { dictamen: d, motivo_id: form.elements.motivo.value || null, texto });
      if (files.length) {
        try { await subirArchivos(P, files, { etapa: 'dictamen', descripcion: 'Evidencia del dictamen' }); }
        catch (err) { toast(`Dictamen emitido, pero la evidencia no se subió: ${errMsg(err)}`, 'warning', 8000); }
      }
      toast(`Dictamen emitido: ${DICT[d][0]}.`, 'success');
    },
  });
}

export async function etapaCierre(pane, ctx) {
  const { P, E } = ctx;
  if (!['aprobada', 'rechazada', 'cerrada_aprobada', 'cerrada_rechazada', 'cancelada'].includes(P.estado)) {
    pane.innerHTML = `${aviso('El cierre se realiza después del dictamen aprobado o rechazado.')}
      <div class="card mt">${cardHead('Expediente', 'Puede imprimir el avance de la prueba en cualquier momento.', btn('data-ci="imprimir"', 'printer', 'Imprimir expediente'))}</div>`;
    refreshIcons();
    pane.addEventListener('click', async (e) => {
      if (!e.target.closest('[data-ci="imprimir"]')) return;
      try { await imprimir(P, consolidado(P)); } catch (err) { toast(errMsg(err), 'error'); }
    });
    return;
  }
  const K = await consolidado(P);
  const ult = K.D[K.D.length - 1];
  const puedeCerrar = ['aprobada', 'rechazada'].includes(P.estado) && autoridad(P.tipo, 'cerrar');
  const aprobada = ['aprobada', 'cerrada_aprobada'].includes(P.estado);
  pane.innerHTML = `
    <div class="grid grid-main">
      <div class="card">${cardHead('Expediente de cierre', '', btn('data-ci="imprimir"', 'printer', 'Imprimir expediente'))}
        <div class="detail-grid">
          ${box('Folio', `<b class="mono">${esc(P.folio)}</b>`)}
          ${box('Estado', estadoPill(P.estado))}
          ${box('Tipo y objetivo', `${esc(P.tipo_nombre)}<div class="cell-sub">${esc(P.objetivo_desc || P.objetivo_nombre || '')}</div>`, true)}
          ${box('Involucrado', esc([P.receta_nombre || P.producto_nombre, P.materia_prima_nombre, P.proveedor_nombre, P.equipo_nombre, P.empaque, P.proceso].filter(Boolean).join(' · ') || '—'), true)}
          ${box('Dictamen', ult ? `${pill(...DICT[ult.dictamen])} <span class="cell-sub">${esc(ult.por?.nombre || '')} · ${fmtDateTime(ult.created_at)}${ult.motivo ? ` · ${esc(ult.motivo.nombre)}` : ''}</span>${ult.descripcion ? `<div>${esc(ult.descripcion)}</div>` : ''}` : '—', true)}
          ${box('Responsables', `Registró: ${esc(P.registrado_por_nombre)}${P.responsable_inicial_nombre ? `<br>Responsable de seguimiento: ${esc(P.responsable_inicial_nombre)}` : ''}`, true)}
          ${box('Cierre', P.cerrada_at ? `${esc(P.cerrada_por_nombre || '')} · ${fmtDateTime(P.cerrada_at)}${P.disposicion_cierre ? `<div class="cell-sub">Disposición: ${esc(P.disposicion_cierre)}</div>` : ''}` : P.estado === 'cancelada' ? `Cancelada por ${esc(P.cancelado_por_nombre || '')} · ${fmtDateTime(P.cancelado_at)}<div class="cell-sub">${esc(P.motivo_cancelacion || '')}</div>` : 'Pendiente', true)}
        </div>
        <div class="section-title">${icon('list-checks')} Resultados y recomendaciones</div>${resumenHTML(P, K, P.ejecucion_actual)}
      </div>
      <div class="card">${cardHead('Cierre', 'Lo realiza la Gerencia de Procesos y Mejora Continua.')}
        ${aprobada ? aviso(`<b>Implementación autorizada</b> en el dictamen de Alta Dirección${ult ? ` (${esc(ult.por?.nombre || '')} · ${fmtDateTime(ult.created_at)})` : ''}.`, '', 'badge-check') : ''}
        ${puedeCerrar ? `<button class="btn primary block" data-ci="cerrar">${icon('archive')} Cerrar prueba</button>` : ['aprobada', 'rechazada'].includes(P.estado) ? aviso('Cierra quien tenga autoridad de cierre para este tipo de prueba.') : ''}
        ${P.cerrada_at ? aviso(`Prueba cerrada por ${esc(P.cerrada_por_nombre || '')} el ${fmtDateTime(P.cerrada_at)}.`, '', 'archive') : ''}
      </div>
    </div>`;
  refreshIcons();
  pane.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-ci]');
    if (!b) return;
    try {
      if (b.dataset.ci === 'imprimir') { await imprimir(P, K); return; }
      if (b.dataset.ci === 'cerrar') {
        const conPend = P.estado === 'rechazada' && E.obligatorios_faltantes > 0;
        const r = await confirmDialog({ title: 'Cerrar prueba', message: `${P.folio} quedará ${P.estado === 'aprobada' ? 'cerrada y aprobada' : 'cerrada y rechazada'}. Ya no podrá modificarse.`,
          confirmText: 'Cerrar', input: { label: conPend ? 'Disposición formal (hay parámetros sin resultado)' : 'Comentario de cierre (opcional)', required: conPend, maxlength: 1000 } });
        if (!r) return;
        await accion(P.id, 'cerrar', { texto: r.value }); toast('Prueba cerrada.', 'success');
      } else return;
      ctx.refrescar();
    } catch (err) { toast(errMsg(err), 'error'); }
  });
}

// Logo de la empresa tal como lo muestra la app (incrustado en el paquete o en /img)
function logoURL() {
  const bg = getComputedStyle(document.querySelector('.brand-logo') || document.body).backgroundImage || '';
  const m = bg.match(/url\(["']?(.*?)["']?\)/);
  if (!m) return '';
  return m[1].startsWith('/') ? `${location.origin}${m[1]}` : m[1];
}

// Expediente imprimible (ventana aparte, sin depender de estilos externos). Solo incluye las secciones con datos.
async function imprimir(P, datos) {
  const w = window.open('', '_blank');
  if (!w) { toast('Permita ventanas emergentes para imprimir el expediente.', 'warning'); return; }
  w.document.write('<p style="font:14px Segoe UI,Arial,sans-serif;margin:24px">Preparando expediente…</p>');
  const K = await datos;
  let usuarios = [], puestos = [];
  try { [usuarios, puestos] = await Promise.all([getCat('usuarios'), getCat('puestos')]); } catch { /* sin puestos */ }
  const puestoDe = (id) => puestos.find((p) => p.id === usuarios.find((u) => u.id === id)?.puesto_id)?.nombre || '';
  const { filas, REC } = K.RES;
  const ej = P.ejecucion_actual;
  const B = K.B.filter((b) => b.ejecucion === ej), C = K.C.filter((c) => c.ejecucion === ej);
  const dicts = K.D.filter((d) => d.ejecucion === ej);
  const ult = dicts[dicts.length - 1];
  const fila = (a, b) => (b ? `<tr><th>${esc(a)}</th><td>${b}</td></tr>` : '');
  const nomPar = (id) => filas.find((f) => f.plan_id === id)?.nombre || '';
  let n = 0; const sec = (t) => `<h2>${++n}. ${esc(t)}</h2>`;
  const conDatos = filas.filter((f) => f.conValor || f.ev || f.pend);
  const areasRes = AREAS_ORDEN.filter((a) => conDatos.some((f) => f.area === a));
  const firma = (rol, nombre, id, fecha) => `<div class="firma"><div class="linea"></div><b>${esc(nombre || '')}</b><span>${esc(puestoDe(id))}</span><small>${esc(rol)}${fecha ? ` · ${esc(fmtDateTime(fecha))}` : ''}</small></div>`;
  const logo = logoURL();
  const html = `<!doctype html><html lang="es"><head><meta charset="utf-8"><title>${esc(P.folio)} · Expediente</title>
    <style>body{font:12px/1.45 Segoe UI,Arial,sans-serif;color:#111;margin:24px}
    .enc{display:flex;align-items:center;gap:16px;border-bottom:3px solid #F58020;padding-bottom:10px;margin-bottom:6px}.enc img{height:58px;width:auto}
    .enc h1{font-size:18px;margin:0}.enc .muted{margin-top:2px}
    h2{font-size:14px;border-bottom:2px solid #F58020;padding-bottom:3px;margin:18px 0 8px;break-after:avoid}h3{font-size:12.5px;margin:10px 0 4px}
    table{width:100%;border-collapse:collapse;margin:4px 0}th,td{border:1px solid #ccc;padding:4px 6px;text-align:left;vertical-align:top}th{background:#f4f4f4;width:28%}
    .t th{width:auto}.muted{color:#666}.bad{color:#b42318;font-weight:600}.ok{color:#067647;font-weight:600}.warn{color:#b54708;font-weight:600}
    .firmas{display:flex;gap:40px;justify-content:space-around;margin-top:56px;break-inside:avoid}.firma{flex:1;max-width:280px;text-align:center;display:flex;flex-direction:column;gap:2px}
    .firma .linea{border-top:1.5px solid #111;margin-bottom:6px}.firma span{color:#444}.firma small{color:#666}
    tr{break-inside:avoid}@media print{button{display:none}body{margin:12mm}}</style></head><body>
    <div class="enc">${logo ? `<img src="${esc(logo)}" alt="Pet's Table">` : ''}<div><h1>Expediente de prueba industrial · ${esc(P.folio)}</h1>
      <div class="muted">Pet's Table S.A. de C.V. · Calidad de proceso · Generado ${esc(fmtDateTime(new Date().toISOString()))}</div></div></div>
    ${sec('Datos de la prueba')}<table>${fila('Folio / tipo', esc(`${P.folio} · ${P.tipo_nombre}`))}${fila('Nombre de la prueba', esc(P.cambio))}${fila('Objetivo', esc(P.objetivo_desc || P.objetivo_nombre || ''))}
      ${fila('Involucrado', esc([P.receta_nombre || P.producto_nombre, P.materia_prima_nombre, P.proveedor_nombre, P.equipo_nombre, P.empaque, P.proceso].filter(Boolean).join(' · ')))}
      ${fila('Fecha de ejecución', esc(fechaEjecTxt(P)))}${fila('Prioridad', esc(P.prioridad === 'normal' ? '' : `${P.prioridad === 'alta' ? 'Alta' : 'Urgente'}${P.prioridad_just ? ` · ${P.prioridad_just}` : ''}`))}
      ${fila('Registró', esc(`${P.registrado_por_nombre} · ${fmtDateTime(P.created_at)}`))}${fila('Ejecución', ej > 1 ? `#${ej}` : '')}</table>
    ${B.length ? `${sec(P.ejecucion_form === 'fabricacion' ? 'Batches producidos' : 'Corridas')}<table class="t"><tr><th>Lote diario</th><th>Número</th><th>Fecha</th><th>¿Sin problemas?</th><th>Incidencias</th></tr>
      ${B.map((b) => `<tr><td>${esc(b.lote_codigo)}</td><td>#${b.numero}</td><td>${esc(fmtDateTime(b.fecha_hora))}</td><td>${b.resultado_op === 'no_conforme' ? '<span class="bad">No, hubo desviación</span>' : 'Sí'}</td><td>${esc(b.incidencias || '')}</td></tr>`).join('')}</table>` : ''}
    ${C.length ? `${sec('Parámetros del equipo')}<table class="t"><tr><th>Parámetro</th><th>Valor</th><th>Resultado</th><th>Observaciones</th></tr>
      ${C.map((c) => `<tr><td>${esc(c.nombre)}</td><td>${esc(c.valor ?? '—')}</td><td>${c.resultado === 'no_conforme' ? '<span class="bad">Fuera de lo esperado</span>' : c.resultado === 'pendiente' ? 'Pendiente' : 'Correcto'}</td><td>${esc(c.observaciones || '')}</td></tr>`).join('')}</table>` : ''}
    ${areasRes.length ? `${sec('Resultados y evaluación por área')}${areasRes.map((a) => `<h3>${esc(AREAS[a].label)}</h3><table class="t"><tr><th>Parámetro</th><th>Resultado</th><th>Criterio</th><th>Evaluación</th><th>Observaciones</th></tr>
      ${conDatos.filter((f) => f.area === a).map((f) => `<tr><td>${esc(f.nombre)}</td><td>${f.valores.map((v) => `<span class="${v.fuera ? 'bad' : ''}">${esc(v.txt)}</span>`).join('<br>') || (f.pend ? '<span class="warn">Pendiente</span>' : '—')}</td><td>${esc(f.criterio || '—')}</td>
        <td>${f.ev ? `<span class="${EVALUACION[f.ev.evaluacion][1]}">${esc(EVALUACION[f.ev.evaluacion][0])}</span>` : '—'}</td><td>${f.ev ? `${esc(f.ev.observaciones === 'Sin observaciones' ? '' : f.ev.observaciones)}<br><span class="muted">${esc(f.ev.por?.nombre || '')}</span>` : ''}</td></tr>`).join('')}</table>`).join('')}` : ''}
    ${REC.length ? `${sec('Veredicto y recomendaciones de las áreas')}<table class="t"><tr><th>Área</th><th>Veredicto</th><th>Recomendación</th><th>Responsable</th></tr>
      ${AREAS_ORDEN.filter((a) => REC.some((x) => x.area === a)).map((a) => { const r = REC.find((x) => x.area === a); return `<tr><td>${esc(AREAS[a].label)}</td><td><span class="${VEREDICTO[r.sentido][1]}">${esc(VEREDICTO[r.sentido][0])}</span></td><td>${esc(r.recomendacion || '')}</td><td>${esc(r.por?.nombre || '')}</td></tr>`; }).join('')}</table>` : ''}
    ${dicts.length ? `${sec('Dictamen de Alta Dirección')}<table class="t"><tr><th>Dictamen</th><th>Emitió</th><th>Fecha</th><th>Conclusión</th></tr>
      ${dicts.map((d) => `<tr><td><span class="${DICT[d.dictamen][1]}">${esc(DICT[d.dictamen][0])}</span></td><td>${esc(d.por?.nombre || '')}</td><td>${esc(fmtDateTime(d.created_at))}</td><td>${esc([d.motivo?.nombre, d.descripcion].filter(Boolean).join(' · '))}</td></tr>`).join('')}</table>` : ''}
    ${P.cerrada_at || P.estado === 'cancelada' ? `${sec(P.estado === 'cancelada' ? 'Cancelación' : 'Cierre')}<table>${P.cerrada_at ? `${fila('Cerró', esc(`${P.cerrada_por_nombre || ''} · ${fmtDateTime(P.cerrada_at)}`))}${fila('Resultado', esc(P.estado === 'cerrada_aprobada' ? 'Cerrada y aprobada' : 'Cerrada y rechazada'))}${fila('Disposición', esc(P.disposicion_cierre || ''))}`
      : `${fila('Canceló', esc(`${P.cancelado_por_nombre || ''} · ${fmtDateTime(P.cancelado_at)}`))}${fila('Motivo', esc(P.motivo_cancelacion || ''))}`}</table>` : ''}
    ${K.ADJ.length ? `${sec('Evidencia adjunta')}<table class="t"><tr><th>Archivo</th><th>Parámetro / etapa</th><th>Subió</th><th>Fecha</th></tr>
      ${K.ADJ.map((a) => `<tr><td>${esc(a.nombre)}</td><td>${esc(nomPar(a.plan_id) || (a.etapa === 'dictamen' ? 'Dictamen' : a.etapa || ''))}</td><td>${esc(a.subio?.nombre || '')}</td><td>${esc(fmtDateTime(a.created_at))}</td></tr>`).join('')}</table>` : ''}
    ${ult || P.cerrada_at ? `<div class="firmas">${ult ? firma('Emitió el dictamen', ult.por?.nombre, ult.emitido_por, ult.created_at) : ''}${P.cerrada_at ? firma('Cerró la prueba', P.cerrada_por_nombre, P.cerrada_por, P.cerrada_at) : ''}</div>` : ''}
    ${ult?.dictamen === 'aprobada' ? '<p class="muted" style="margin-top:18px">Un dictamen "Aprobada" de Alta Dirección autoriza implementar el cambio evaluado.</p>' : ''}
    </body></html>`;
  w.document.open(); w.document.write(html); w.document.close();
  setTimeout(() => { try { w.focus(); w.print(); } catch { /* el usuario puede imprimir con Ctrl+P */ } }, 500);
}
