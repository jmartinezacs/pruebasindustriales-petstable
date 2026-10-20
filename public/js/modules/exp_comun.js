// =====================================================================
// Utilidades compartidas por las etapas del expediente de una prueba.
// =====================================================================
import {
  sb, state, esc, icon, toast, openModal, checkForm, nullIfEmpty, must, getCat, opciones,
  ADJ_MAX_MB, ADJ_ACCEPT, rutaAdjunto,
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

// Ejecuta una acción del flujo (RPC)
export async function accion(pid, nombre, datos = {}) {
  must(await sb.rpc('prubind_accion', { p_prueba: pid, p_accion: nombre, p_datos: datos }));
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
