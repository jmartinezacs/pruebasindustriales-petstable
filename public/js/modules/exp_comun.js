// =====================================================================
// Utilidades compartidas por las etapas del expediente de una prueba.
// =====================================================================
import {
  sb, state, esc, icon, toast, openModal, checkForm, nullIfEmpty, must, getCat, opciones,
  ADJ_MAX_MB, ADJ_ACCEPT, rutaAdjunto, avisar, OPCIONES_TXT,
} from '../core.js';

export const box = (l, v, full = false) => `<div class="info-box ${full ? 'full' : ''}"><small>${esc(l)}</small><div>${v}</div></div>`;
export const txt = (s) => `<span style="white-space:pre-wrap">${esc(s || '—')}</span>`;
export const cardHead = (title, sub = '', btns = '') =>
  `<div class="card-head"><div><h3>${esc(title)}</h3>${sub ? `<p>${sub}</p>` : ''}</div>${btns ? `<div class="head-btns">${btns}</div>` : ''}</div>`;
export const btn = (attrs, ico, label, cls = 'secondary') => `<button class="btn ${cls}" ${attrs}>${icon(ico)} ${esc(label)}</button>`;
export const iconBtn = (attrs, ico, title, cls = '') => `<button class="icon-btn ${cls}" ${attrs} title="${esc(title)}" aria-label="${esc(title)}">${icon(ico)}</button>`;
export const aviso = (msg, cls = '', ico = 'info') => `<div class="notice ${cls}">${icon(ico)}<span>${msg}</span></div>`;
// Valor para <input type="datetime-local"> en la hora local del dispositivo
const pad2 = (n) => String(n).padStart(2, '0');
export const aLocal = (ts) => { const d = new Date(ts); return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}T${pad2(d.getHours())}:${pad2(d.getMinutes())}`; };
export const vacio = (t) => `<p class="hint" style="margin:6px 0">${esc(t)}</p>`;

// Lista de requisitos con palomita / tache
export const checklist = (items) => `<ul class="checklist">${items.map(([ok, t]) =>
  `<li class="${ok ? 'ok' : 'no'}">${icon(ok ? 'check-circle-2' : 'circle-dashed')}<span>${esc(t)}</span></li>`).join('')}</ul>`;

// Ejecuta una acción del flujo (RPC) y avisa a quien corresponda; devuelve el estado nuevo
export async function accion(pid, nombre, datos = {}) {
  const estado = must(await sb.rpc('prubind_accion', { p_prueba: pid, p_accion: nombre, p_datos: datos })).data?.estado;
  if (nombre === 'iniciar') avisar('iniciada', pid);
  else if (nombre === 'dictaminar') avisar('dictamen', pid);
  else if (estado === 'pendiente_dictamen' && ['enviar_dictamen', 'terminar_ejecucion'].includes(nombre)) avisar('lista_dictamen', pid);
  else if (nombre === 'terminar_ejecucion') avisar('terminada', pid);
  document.dispatchEvent(new Event('prubind:cambio'));
  return estado;
}

// Subir evidencia ligada a la prueba (y opcionalmente a un resultado o batch)
export async function subirEvidencia(P, { resultado_id = null, batch_id = null, etapa = null, titulo = 'Adjuntar evidencia' } = {}) {
  const tipos = await getCat('evidencias', { activos: true });
  return openModal({
    title: titulo, subtitle: `${P.folio} · ${P.cambio}`, submitText: 'Subir', size: 'sm',
    body: `<div class="field"><label for="ev-f">Archivo <span class="req">*</span></label><input id="ev-f" name="archivo" type="file" required accept="${ADJ_ACCEPT}">
        <small class="hint">PDF, imágenes, Excel, Word, CSV o texto. Máx. ${ADJ_MAX_MB} MB.</small></div>
      <div class="field"><label for="ev-t">Tipo de evidencia</label><select id="ev-t" name="tipo">${opciones(tipos, null, { vacio: 'Sin clasificar' })}</select></div>
      <div class="field"><label for="ev-d">Descripción</label><input id="ev-d" name="descripcion" maxlength="300"></div>`,
    onSubmit: async ({ form }) => {
      const file = form.elements.archivo.files?.[0];
      if (!checkForm(form, { archivo: () => (!file ? 'Selecciona un archivo.' : file.size > ADJ_MAX_MB * 1048576 ? `El archivo supera ${ADJ_MAX_MB} MB.` : '') })) return false;
      const ruta = rutaAdjunto(P.id, file.name);
      const up = await sb.storage.from('adjuntos_prubind').upload(ruta, file, { contentType: file.type || 'application/octet-stream', upsert: false });
      if (up.error) throw up.error;
      const ins = await sb.from('adjuntos_prubind').insert({
        prueba_id: P.id, nombre: file.name.slice(0, 200), ruta, mime: file.type || null, tamano: file.size,
        tipo_evidencia_id: nullIfEmpty(form.elements.tipo.value), descripcion: nullIfEmpty(form.elements.descripcion.value.trim()),
        resultado_id, batch_id, etapa, subido_por: state.profile.id,
      });
      if (ins.error) { await sb.storage.from('adjuntos_prubind').remove([ruta]).catch(() => {}); throw ins.error; }
      toast('Evidencia adjuntada.', 'success');
    },
  });
}

// Sube archivos sin abrir un formulario (evidencia de un parámetro o del dictamen); devuelve cuántos subió
export async function subirArchivos(P, files, { plan_id = null, batch_id = null, resultado_id = null, etapa = null, descripcion = null } = {}) {
  let n = 0;
  for (const file of files) {
    if (file.size > ADJ_MAX_MB * 1048576) { toast(`${file.name} supera ${ADJ_MAX_MB} MB; no se subió.`, 'warning'); continue; }
    const ruta = rutaAdjunto(P.id, file.name);
    const up = await sb.storage.from('adjuntos_prubind').upload(ruta, file, { contentType: file.type || 'application/octet-stream', upsert: false });
    if (up.error) throw up.error;
    const ins = await sb.from('adjuntos_prubind').insert({ prueba_id: P.id, nombre: file.name.slice(0, 200), ruta, mime: file.type || null, tamano: file.size,
      plan_id, batch_id, resultado_id, etapa, descripcion, subido_por: state.profile.id });
    if (ins.error) { await sb.storage.from('adjuntos_prubind').remove([ruta]).catch(() => {}); throw ins.error; }
    n += 1;
  }
  return n;
}

// Botón para elegir archivos de evidencia (sin subirlos todavía) y los ya subidos
export const eviPicker = (name, adjs = []) => `<div class="evi-pick">
  ${adjs.map((a) => `<button type="button" class="evi-chip" data-ver-adj="${esc(a.ruta)}" title="Abrir ${esc(a.nombre)}">${icon('paperclip')}<span>${esc(a.nombre)}</span></button>`).join('')}
  <label class="evi-add" title="Adjuntar evidencia">${icon('paperclip')}<span>Evidencia</span><input type="file" name="${esc(name)}" multiple accept="${ADJ_ACCEPT}" hidden></label>
  <span class="evi-sel"></span></div>`;
// Lista corta de evidencias (solo lectura)
export const eviChips = (adjs = []) => (adjs.length ? `<div class="evi-pick">${adjs.map((a) =>
  `<button type="button" class="evi-chip" data-ver-adj="${esc(a.ruta)}" title="Abrir ${esc(a.nombre)}">${icon('paperclip')}<span>${esc(a.nombre)}</span></button>`).join('')}</div>` : '');
// Muestra cuántos archivos se eligieron en cada selector
document.addEventListener('change', (e) => {
  const inp = e.target.closest('.evi-add input[type=file]');
  if (!inp) return;
  const out = inp.closest('.evi-pick')?.querySelector('.evi-sel');
  if (out) out.textContent = inp.files.length ? `${inp.files.length} archivo(s) por subir` : '';
});
document.addEventListener('click', (e) => {
  const b = e.target.closest('[data-ver-adj]');
  if (!b) return;
  e.preventDefault();
  abrirAdjunto(b.dataset.verAdj).catch((err) => toast(err.message || 'No se pudo abrir el archivo.', 'error'));
});

// Campo para capturar el valor de un parámetro (numérico, opción, presencia o diluciones)
export function campoValor(m, name, { valores = [], unidad = '', placeholder = '', disabled = false } = {}) {
  const dis = disabled ? 'disabled' : '';
  if (m.tipo_resultado === 'diluciones') {
    return `<div class="dil-grid">${m.diluciones.map((d, i) => { const r = valores.find((x) => x.dilucion === d);
      return `<label>${esc(d)} <span class="cell-sub">${esc(unidad || 'UFC/g')}</span><input type="number" step="any" min="0" inputmode="decimal" name="${name}_${i}" value="${esc(r?.valor_num ?? '')}" ${dis}></label>`; }).join('')}</div>`;
  }
  const r1 = valores.find((x) => !x.dilucion);
  if (m.tipo_resultado === 'numerico') {
    return `<input type="number" step="any" inputmode="decimal" name="${name}" value="${esc(r1?.valor_num ?? '')}" placeholder="${esc(placeholder)}" ${dis}>`;
  }
  const ops = m.tipo_resultado === 'presencia' ? ['ausencia', 'presencia'] : ((m.opciones || []).length ? m.opciones.filter((o) => o !== 'pendiente') : ['conforme', 'no_conforme', 'no_aplica']);
  return `<select name="${name}" data-native ${dis}><option value="">Sin registrar</option>${ops.map((o) => `<option value="${esc(o)}" ${r1?.valor_opcion === o ? 'selected' : ''}>${esc(OPCIONES_TXT[o] || o)}</option>`).join('')}</select>`;
}
// Valores escritos en el campo: [{ d: dilución|null, v: texto }]
export const leerValor = (form, m, name) => (m.tipo_resultado === 'diluciones'
  ? m.diluciones.map((d, i) => ({ d, v: form.elements[`${name}_${i}`]?.value ?? '' }))
  : [{ d: null, v: form.elements[name]?.value ?? '' }]);
export const payloadValor = (m, v) => (m.tipo_resultado === 'numerico' || m.tipo_resultado === 'diluciones' ? { valor_num: Number(v), valor_opcion: null } : { valor_opcion: v, valor_num: null });

export async function abrirAdjunto(ruta) {
  const w = window.open('', '_blank');
  const { data, error } = await sb.storage.from('adjuntos_prubind').createSignedUrl(ruta, 120);
  if (error) { w?.close(); throw error; }
  if (w) { w.opener = null; w.location.href = data.signedUrl; } else location.assign(data.signedUrl);
}

// Texto del criterio copiado al plan
export function criterioTxt(pl, unidad = '') {
  const u = unidad ? ` ${unidad}` : '';
  if (pl.crit_minimo != null && pl.crit_maximo != null) return `${pl.crit_minimo} – ${pl.crit_maximo}${u}`;
  if (pl.crit_minimo != null) return `≥ ${pl.crit_minimo}${u}`;
  if (pl.crit_maximo != null) return `≤ ${pl.crit_maximo}${u}`;
  return pl.crit_texto || '';
}
