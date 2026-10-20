// =====================================================================
// Etapas 6 y 7 · Dictamen de Alta Dirección (con el consolidado de
// resultados y recomendaciones por área) y Cierre.
// La aprobación no libera producto ni autoriza el cambio en producción:
// la implementación requiere autorizaciones separadas.
// =====================================================================
import {
  sb, state, esc, icon, toast, errMsg, openModal, confirmDialog, getCat, invalidateCat, opciones, fmtDateTime,
  pill, estadoPill, autoridad, AREAS, AREAS_OBLIGATORIAS, refreshIcons,
} from '../core.js';
import { box, txt, cardHead, btn, aviso, vacio, checklist, accion } from './exp_comun.js';
import { consolidarResultados, EVAL, SENTIDO } from './exp_eval.js';

const DICT = { aprobada: ['Aprobada', 'ok'], rechazada: ['Rechazada', 'bad'], requiere_repeticion: ['Requiere repetición', 'warn'], pendiente_resultados: ['Pendiente de resultados', 'warn'] };

async function consolidado(P) {
  const [batches, lotes, controles, dict, aut, adj, puestos, autImpl, RES] = await Promise.all([
    sb.from('v_batches_prubind').select('*').eq('prueba_id', P.id).order('ejecucion').order('numero'),
    sb.from('lotes_diarios_prubind').select('*').eq('prueba_id', P.id).order('fecha'),
    sb.from('ejecucion_controles_prubind').select('*').eq('prueba_id', P.id).order('created_at'),
    sb.from('dictamenes_prubind').select('*, por:usuarios_prubind!dictamenes_prubind_emitido_por_fkey(nombre), motivo:motivos_prubind(nombre)').eq('prueba_id', P.id).order('created_at'),
    sb.from('autorizaciones_prubind').select('*, por:usuarios_prubind!autorizaciones_prubind_autorizado_por_fkey(nombre), puesto:puestos_prubind(nombre)').eq('prueba_id', P.id).order('created_at'),
    sb.from('adjuntos_prubind').select('id, nombre, etapa, created_at, tipo:tipos_evidencia_prubind(nombre)').eq('prueba_id', P.id),
    getCat('puestos'),
    sb.from('autoridades_prubind').select('tipo, accion, puesto_id, usuario_id, activo').eq('accion', 'autorizar_implementacion').eq('activo', true),
    consolidarResultados(P),
  ]);
  [batches, lotes, controles, dict, aut, adj, autImpl].forEach((r) => { if (r.error) throw r.error; });
  return { B: batches.data, L: lotes.data, C: controles.data, D: dict.data, A: aut.data, ADJ: adj.data, puestos, RES,
    IMPL: autImpl.data.filter((a) => !a.tipo || a.tipo === P.tipo) };
}

function resumenHTML(P, K, ej) {
  const B = K.B.filter((b) => b.ejecucion === ej), L = K.L.filter((l) => l.ejecucion === ej), C = K.C.filter((c) => c.ejecucion === ej);
  const { filas, areas, REC } = K.RES;
  const nc = filas.filter((f) => f.ev?.evaluacion === 'no_cumple');
  const sinEval = filas.filter((f) => f.requerida && !f.ev);
  return `
    <div class="detail-grid">
      ${box('Objetivo', esc(P.objetivo_desc || P.objetivo_nombre || '—'), true)}
      ${box('Prueba', txt(P.cambio), true)}
      ${box('Ejecución', `#${ej}${P.ejecucion_actual > 1 ? ` de ${P.ejecucion_actual}` : ''}`)}
      ${box(P.ejecucion_form === 'fabricacion' ? 'Lotes diarios y batches' : 'Corrida', P.ejecucion_form === 'fabricacion'
        ? (L.map((l) => `${esc(l.codigo)}: ${B.filter((b) => b.lote_diario_id === l.id).map((b) => `#${b.numero}${b.resultado_op === 'no_conforme' ? ' (con desviación)' : ''}`).join(', ')}`).join('<br>') || '—')
        : `${C.length} parámetro(s) del equipo registrados`)}
      ${box('Resultados por área', areas.map((a) => { const fs = filas.filter((f) => f.area === a && f.ev); const n = fs.filter((f) => f.ev.evaluacion === 'no_cumple').length;
        return `${esc(AREAS[a].label)}: <b class="ok-txt">${fs.length - n} ${fs.length - n === 1 ? 'cumple' : 'cumplen'}</b>${n ? ` · <b class="bad-txt">${n} no ${n === 1 ? 'cumple' : 'cumplen'}</b>` : ''}`; }).join('<br>') || '—', true)}
      ${box('Parámetros que no cumplen', nc.length ? nc.map((f) => `<div class="nc-line"><b>${esc(f.nombre)}</b> (${esc(AREAS[f.area].label)})${f.criterio ? ` · criterio ${esc(f.criterio)}` : ''}<br><span class="cell-sub">${f.valores.map((v) => esc(v.txt)).join(' · ')}</span><br>${esc(f.ev.observaciones)}</div>`).join('') : '<span class="ok-txt">Todos cumplen</span>', true)}
      ${sinEval.length ? box('Sin evaluar', sinEval.map((f) => esc(f.nombre)).join(', '), true) : ''}
      ${box('Recomendaciones de las áreas', areas.map((a) => { const r = REC.find((x) => x.area === a);
        return `<div class="nc-line"><b>${esc(AREAS[a].label)}</b>: ${r ? `${pill(SENTIDO[r.sentido][0], SENTIDO[r.sentido][1])} ${esc(r.recomendacion)} <span class="cell-sub">· ${esc(r.por?.nombre || '')}</span>` : AREAS_OBLIGATORIAS.includes(a) ? '<span class="warn-txt">Pendiente</span>' : '<span class="cell-sub">No registró su parte (área opcional)</span>'}</div>`; }).join('') || '—', true)}
      ${box('Evidencia adjunta', K.ADJ.length ? `${K.ADJ.length} archivo(s): ${K.ADJ.slice(0, 6).map((a) => esc(a.tipo?.nombre || a.nombre)).join(', ')}${K.ADJ.length > 6 ? '…' : ''}` : '<span class="cell-sub">Sin evidencia adjunta</span>', true)}
    </div>`;
}

export async function etapaDictamen(pane, ctx) {
  const { P, E } = ctx;
  if (['registrada', 'en_preparacion', 'preparada', 'en_ejecucion', 'en_evaluacion', 'pendiente_resultados'].includes(P.estado) && !P.ultimo_dictamen) {
    pane.innerHTML = aviso('Alta Dirección emite el dictamen cuando todas las áreas evaluaron sus resultados y registraron su recomendación.'); refreshIcons(); return;
  }
  const K = await consolidado(P);
  const puedeDict = P.estado === 'pendiente_dictamen' && autoridad(P.tipo, 'dictaminar');
  const bloqueos = [
    [E.eval_faltantes === 0, 'Resultados evaluados por todas las áreas'],
    [E.recom_faltantes === 0, 'Recomendaciones de todas las áreas'],
  ];
  pane.innerHTML = `
    <div class="grid grid-main">
      <div class="card">${cardHead('Resumen consolidado', 'Resultados por parámetro y recomendaciones de cada área.')}${resumenHTML(P, K, P.ejecucion_actual)}</div>
      <div class="card">${cardHead('Dictamen de Alta Dirección')}
        ${checklist(bloqueos)}
        ${E.no_cumple && P.estado === 'pendiente_dictamen' ? aviso(`${E.no_cumple} parámetro(s) no cumplen. Para aprobar, explique la decisión en la conclusión.`, 'warn', 'alert-triangle') : ''}
        ${puedeDict ? `<button class="btn primary block" data-dc="emitir">${icon('gavel')} Emitir dictamen</button>`
          : P.estado === 'pendiente_dictamen' ? aviso('El dictamen lo emite Alta Dirección (Directora de Calidad o Director de Producción).') : ''}
        <div class="section-title">${icon('history')} Historial de dictámenes</div>
        ${K.D.length ? `<div class="list">${K.D.slice().reverse().map((d) => `<div class="list-item">${pill(...DICT[d.dictamen])}<div class="li-main"><b>Ejecución #${d.ejecucion} · ${esc(d.por?.nombre || '')}</b>
          <span>${fmtDateTime(d.created_at)}${d.motivo ? ` · ${esc(d.motivo.nombre)}` : ''}${d.descripcion ? ` · ${esc(d.descripcion)}` : ''}</span></div></div>`).join('')}</div>` : vacio('Sin dictámenes.')}
      </div>
    </div>`;
  refreshIcons();
  pane.addEventListener('click', async (e) => {
    if (!e.target.closest('[data-dc="emitir"]')) return;
    try { if (await dictamenForm(P, bloqueos.every(([ok]) => ok), E.no_cumple)) ctx.refrescar(); } catch (err) { toast(errMsg(err), 'error'); }
  });
}

async function dictamenForm(P, aprobable, noCumple) {
  const motivos = (await getCat('motivos', { activos: true })).filter((m) => m.tipo === 'rechazo');
  return openModal({
    title: 'Emitir dictamen', subtitle: `${P.folio} · ${P.cambio}`, submitText: 'Emitir dictamen', size: 'lg',
    body: `<div class="field"><span class="label">Dictamen <span class="req">*</span></span>
        <div class="radio-cards multi">
          <label><input type="radio" name="d" value="aprobada" ${aprobable ? '' : 'disabled'}><span>${icon('badge-check')} Aprobada</span></label>
          <label><input type="radio" name="d" value="rechazada"><span>${icon('x-octagon')} Rechazada</span></label>
          <label><input type="radio" name="d" value="requiere_repeticion"><span>${icon('repeat')} Requiere repetición</span></label>
          <label><input type="radio" name="d" value="pendiente_resultados"><span>${icon('hourglass')} Pendiente de resultados</span></label>
        </div>${aprobable ? '' : '<small class="hint">"Aprobada" no está disponible: faltan evaluaciones o recomendaciones de las áreas.</small>'}</div>
      <div class="field hidden" id="dc-mot-w"><label for="dc-mot">Motivo de rechazo <span class="req">*</span></label><select id="dc-mot" name="motivo">${opciones(motivos, null)}</select></div>
      <div class="field"><label for="dc-t">Conclusión</label><textarea id="dc-t" name="texto" maxlength="1000" rows="3" placeholder="${noCumple ? 'Obligatoria para aprobar con parámetros que no cumplen y para repetir la prueba' : 'Obligatoria si se requiere repetición'}"></textarea></div>
      ${aviso('Un dictamen aprobado no libera el producto ni autoriza por sí mismo el cambio en producción.', '', 'info')}`,
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
      await accion(P.id, 'dictaminar', { dictamen: d, motivo_id: form.elements.motivo.value || null, texto });
      toast(`Dictamen emitido: ${DICT[d][0]}.`, 'success');
    },
  });
}

export async function etapaCierre(pane, ctx) {
  const { P, E } = ctx;
  if (!['aprobada', 'rechazada', 'cerrada_aprobada', 'cerrada_rechazada', 'cancelada'].includes(P.estado)) {
    pane.innerHTML = aviso('El cierre se realiza después del dictamen aprobado o rechazado.'); refreshIcons(); return;
  }
  const K = await consolidado(P);
  const ult = K.D[K.D.length - 1];
  const impl = K.A.filter((a) => a.tipo === 'implementacion');

  const firmas = K.IMPL.map((a) => {
    const nombre = a.puesto_id ? (K.puestos.find((p) => p.id === a.puesto_id)?.nombre || 'Puesto') : 'Usuario asignado';
    const f = impl.find((z) => (a.puesto_id && z.puesto_id === a.puesto_id) || (a.usuario_id && z.autorizado_por === a.usuario_id));
    return [!!f, `${nombre}${f ? ` — ${f.por?.nombre} · ${fmtDateTime(f.created_at)}` : ' — pendiente'}`];
  });
  const yaFirme = impl.some((z) => z.autorizado_por === state.profile.id || (z.puesto_id && z.puesto_id === state.profile.puesto_id));
  const puedeCerrar = ['aprobada', 'rechazada'].includes(P.estado) && autoridad(P.tipo, 'cerrar');
  const puedeImpl = P.estado === 'cerrada_aprobada' && autoridad(P.tipo, 'autorizar_implementacion') && !yaFirme;
  const implCompleta = firmas.length > 0 && firmas.every(([ok]) => ok);
  const publicable = state.isAdmin && P.estado === 'cerrada_aprobada' && implCompleta && P.receta_version_id && (P.secciones_prep || []).includes('formulacion');
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
      <div class="card">${cardHead('Cierre e implementación')}
        ${puedeCerrar ? `<button class="btn primary block" data-ci="cerrar">${icon('archive')} Cerrar prueba</button>` : ['aprobada', 'rechazada'].includes(P.estado) ? aviso('Cierra quien tenga autoridad de cierre para este tipo de prueba.') : ''}
        <div class="section-title">${icon('stamp')} Autorización para implementar el cambio</div>
        ${P.estado === 'cerrada_aprobada' || impl.length ? (firmas.length ? checklist(firmas) : aviso('No hay puestos configurados para autorizar la implementación de este tipo de prueba (Autoridades).', 'warn', 'alert-triangle')) : vacio('Disponible cuando la prueba esté cerrada y aprobada.')}
        ${puedeImpl ? `<button class="btn primary block" data-ci="impl">${icon('stamp')} Autorizar implementación</button>` : ''}
        ${implCompleta ? aviso('Implementación autorizada por todos los puestos requeridos.', '', 'check-circle-2') : ''}
        ${publicable ? `<button class="btn secondary block mt-s" data-ci="publicar">${icon('book-plus')} Actualizar la receta con la formulación aprobada</button>` : ''}
        ${aviso('Una prueba aprobada no libera el producto experimental para comercialización ni autoriza por sí misma el cambio en la producción habitual.', 'warn', 'shield-alert')}
      </div>
    </div>`;
  refreshIcons();
  pane.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-ci]');
    if (!b) return;
    try {
      if (b.dataset.ci === 'imprimir') { imprimir(P, K, E); return; }
      if (b.dataset.ci === 'cerrar') {
        const conPend = P.estado === 'rechazada' && E.obligatorios_faltantes > 0;
        const r = await confirmDialog({ title: 'Cerrar prueba', message: `${P.folio} quedará ${P.estado === 'aprobada' ? 'cerrada y aprobada' : 'cerrada y rechazada'}. Ya no podrá modificarse.`,
          confirmText: 'Cerrar', input: { label: conPend ? 'Disposición formal (hay parámetros sin resultado)' : 'Comentario de cierre (opcional)', required: conPend, maxlength: 1000 } });
        if (!r) return;
        await accion(P.id, 'cerrar', { texto: r.value }); toast('Prueba cerrada.', 'success');
      } else if (b.dataset.ci === 'impl') {
        const r = await confirmDialog({ title: 'Autorizar implementación', message: `Registra su autorización (${state.profile.puesto || 'sin puesto'}) para implementar el cambio evaluado en ${P.folio}.`, confirmText: 'Autorizar',
          input: { label: 'Comentario (opcional)', required: false, maxlength: 500 } });
        if (!r) return;
        await accion(P.id, 'autorizar_implementacion', { texto: r.value }); toast('Autorización registrada.', 'success');
      } else if (b.dataset.ci === 'publicar') {
        if (!await confirmDialog({ title: `Actualizar la receta ${P.receta_nombre}`, message: `La formulación aprobada pasará a ser la receta vigente de "${P.receta_nombre}". La receta anterior se conserva en el historial.`,
          confirmText: 'Actualizar receta' })) return;
        // El nombre interno de la versión se asigna solo (no se muestra al usuario)
        const versiones = await getCat('versiones', { force: true });
        const recetaId = versiones.find((v) => v.id === P.receta_version_id)?.receta_id;
        await accion(P.id, 'publicar_formulacion', { version: `v${versiones.filter((v) => v.receta_id === recetaId).length + 1}` });
        invalidateCat('versiones');
        toast('Receta actualizada con la formulación aprobada.', 'success');
      } else return;
      ctx.refrescar();
    } catch (err) { toast(errMsg(err), 'error'); }
  });
}

// Expediente imprimible (ventana aparte, sin depender de estilos externos)
function imprimir(P, K, E) {
  const { filas, areas, REC } = K.RES;
  const fila = (a, b) => `<tr><th>${esc(a)}</th><td>${b}</td></tr>`;
  const ult = K.D[K.D.length - 1];
  const html = `<!doctype html><html lang="es"><head><meta charset="utf-8"><title>${esc(P.folio)} · Expediente</title>
    <style>body{font:12px/1.45 Segoe UI,Arial,sans-serif;color:#111;margin:24px}h1{font-size:18px;margin:0 0 4px}h2{font-size:14px;border-bottom:2px solid #F58020;padding-bottom:3px;margin:18px 0 8px}
    table{width:100%;border-collapse:collapse;margin:4px 0}th,td{border:1px solid #ccc;padding:4px 6px;text-align:left;vertical-align:top}th{background:#f4f4f4;width:28%}
    .t th{width:auto}.muted{color:#666}@media print{button{display:none}}</style></head><body>
    <h1>Pruebas industriales · ${esc(P.folio)}</h1><div class="muted">Pet's Table S.A. de C.V. · Calidad de producto · Generado ${esc(fmtDateTime(new Date().toISOString()))}</div>
    <h2>1. Registro</h2><table>${fila('Folio / tipo', esc(`${P.folio} · ${P.tipo_nombre}`))}${fila('Nombre de la prueba', esc(P.cambio))}${fila('Objetivo', esc(P.objetivo_desc || P.objetivo_nombre || ''))}
      ${fila('Involucrado', esc([P.receta_nombre || P.producto_nombre, P.materia_prima_nombre, P.proveedor_nombre, P.equipo_nombre, P.empaque, P.proceso].filter(Boolean).join(' · ')))}
      ${fila('Fecha de ejecución / batches / cantidad', esc(`${P.fecha_planeada || '—'} · ${P.batches_planeados ?? '—'} · ${P.cantidad_evaluar ? `${P.cantidad_evaluar} ${P.cantidad_unidad || ''}` : '—'}`))}
      ${fila('Registró', esc(`${P.registrado_por_nombre} · ${fmtDateTime(P.created_at)}`))}</table>
    <h2>2. Registro durante el proceso (ejecución #${P.ejecucion_actual})</h2><table class="t"><tr><th>Lote diario</th><th>Batch</th><th>Fecha</th><th>¿Sin problemas?</th><th>Incidencias</th></tr>
      ${K.B.filter((b) => b.ejecucion === P.ejecucion_actual).map((b) => `<tr><td>${esc(b.lote_codigo)}</td><td>#${b.numero}</td><td>${esc(fmtDateTime(b.fecha_hora))}</td><td>${b.resultado_op === 'no_conforme' ? 'No, hubo desviación' : 'Sí'}</td><td>${esc(b.incidencias || '')}</td></tr>`).join('')
        || '<tr><td colspan="5">Corrida de prueba (sin batches)</td></tr>'}</table>
    <h2>3–4. Resultados por parámetro</h2><table class="t"><tr><th>Área</th><th>Parámetro</th><th>Resultado</th><th>Criterio</th><th>Evaluación</th><th>Observaciones</th></tr>
      ${filas.map((f) => `<tr><td>${esc(AREAS[f.area].label)}</td><td>${esc(f.nombre)}</td><td>${f.valores.map((v) => esc(v.txt)).join('<br>') || '—'}</td><td>${esc(f.criterio || '—')}</td>
        <td>${f.ev ? esc(EVAL[f.ev.evaluacion][0]) : '—'}</td><td>${f.ev ? `${esc(f.ev.observaciones)}<br><span class="muted">${esc(f.ev.por?.nombre || '')}</span>` : ''}</td></tr>`).join('')}</table>
    <h2>5. Recomendaciones</h2><table class="t"><tr><th>Área</th><th>Sentido</th><th>Recomendación</th><th>Responsable</th></tr>
      ${areas.map((a) => { const r = REC.find((x) => x.area === a); return `<tr><td>${esc(AREAS[a].label)}</td><td>${r ? esc(SENTIDO[r.sentido][0]) : 'Pendiente'}</td><td>${esc(r?.recomendacion || '')}</td><td>${esc(r?.por?.nombre || '')}</td></tr>`; }).join('')}</table>
    <h2>6. Dictamen de Alta Dirección y cierre</h2><table>${fila('Dictamen', ult ? esc(`${DICT[ult.dictamen][0]} · ${ult.por?.nombre || ''} · ${fmtDateTime(ult.created_at)}${ult.motivo ? ` · ${ult.motivo.nombre}` : ''}${ult.descripcion ? ` · ${ult.descripcion}` : ''}`) : '—')}
      ${fila('Cierre', P.cerrada_at ? esc(`${P.cerrada_por_nombre} · ${fmtDateTime(P.cerrada_at)}`) : '—')}
      ${fila('Autorización de implementación', K.A.filter((a) => a.tipo === 'implementacion').map((a) => esc(`${a.puesto?.nombre || ''}: ${a.por?.nombre} · ${fmtDateTime(a.created_at)}`)).join('<br>') || '—')}
      ${fila('Evidencia', esc(`${K.ADJ.length} archivo(s)`))}</table>
    <p class="muted">La aprobación de una prueba no libera producto para comercialización ni autoriza por sí misma el cambio en producción.</p></body></html>`;
  const w = window.open('', '_blank');
  if (!w) { toast('Permita ventanas emergentes para imprimir el expediente.', 'warning'); return; }
  w.document.write(html); w.document.close();
  setTimeout(() => { try { w.focus(); w.print(); } catch { /* el usuario puede imprimir con Ctrl+P */ } }, 300);
}
