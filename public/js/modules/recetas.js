// =====================================================================
// Recetas: catálogo maestro. En pantalla solo se muestra el nombre de la
// receta; internamente se conserva el historial de cambios (versiones).
// La receta vigente nunca se modifica: los cambios se preparan aparte y
// se publican; una prueba nunca altera la receta oficial.
// =====================================================================
import {
  sb, state, esc, icon, toast, errMsg, openModal, confirmDialog, checkForm, must, mustRow,
  getCat, invalidateCat, opciones, unidadTxt, fmtDate, fmtQty, pill, emptyState, errorState, refreshIcons, ayuda,
} from '../core.js';

let root, sel = null;

export default {
  async render(el, params) { root = el; sel = params.r || null; el.addEventListener('click', onClick); await pintar(); },
  destroy() { root = null; },
};

// Nombre interno de la siguiente versión (no se muestra al usuario)
const siguienteVersion = (V, recetaId) => `v${V.filter((v) => v.receta_id === recetaId).length + 1}`;

async function pintar() {
  root.innerHTML = '<div class="card"><div class="skeleton" style="height:120px"></div></div>';
  try {
    const [rec, ver, ing, materias, unidades] = await Promise.all([
      sb.from('recetas_prubind').select('*').order('nombre'),
      sb.from('receta_versiones_prubind').select('*, origen:pruebas_prubind!receta_versiones_prubind_origen_fk(folio)').order('created_at'),
      sb.from('receta_ingredientes_prubind').select('*').order('orden'),
      getCat('materias'), getCat('unidades'),
    ]);
    [rec, ver, ing].forEach(must);
    const R = rec.data, V = ver.data, I = ing.data;
    if (!R.some((x) => x.id === sel)) sel = R[0]?.id || null;
    const r = R.find((x) => x.id === sel);
    const vs = V.filter((v) => v.receta_id === sel);
    const vigente = vs.find((v) => v.estado === 'vigente');
    const borrador = vs.find((v) => v.estado === 'borrador');
    const historicas = vs.filter((v) => v.estado === 'historica').sort((a, b) => b.created_at.localeCompare(a.created_at));
    const admin = state.isAdmin;
    const mp = (id) => materias.find((m) => m.id === id)?.nombre || '?';

    const tabla = (v, editable) => {
      const is = I.filter((i) => i.version_id === v.id);
      if (!is.length) return `<p class="hint">${editable ? 'Agregue los ingredientes con “Ingrediente”.' : 'Sin ingredientes.'}</p>`;
      const total = is.reduce((s, i) => s + (unidadTxt(unidades, i.unidad_id) === 'kg' ? Number(i.cantidad) : 0), 0);
      return `<div class="table-wrap responsive"><table class="table"><thead><tr><th>Ingrediente</th><th>Cantidad por batch</th>${editable ? '<th class="actions"></th>' : ''}</tr></thead><tbody>
        ${is.map((i) => `<tr><td data-label="Ingrediente"><div class="td-in cell-main">${esc(mp(i.materia_prima_id))}</div></td>
          <td data-label="Cantidad"><div class="td-in">${esc(fmtQty(i.cantidad, unidadTxt(unidades, i.unidad_id)))}</div></td>
          ${editable ? `<td class="actions" data-label=""><div class="td-in"><div class="row-actions"><button class="icon-btn" data-rc="ing-editar" data-id="${esc(i.id)}" title="Editar cantidad" aria-label="Editar cantidad">${icon('pencil')}</button><button class="icon-btn bad" data-rc="ing-del" data-id="${esc(i.id)}" title="Quitar" aria-label="Quitar">${icon('trash-2')}</button></div></div></td>` : ''}</tr>`).join('')}
      </tbody></table></div><p class="hint mt-s">Total por batch: <b>${esc(fmtQty(Math.round(total * 1000) / 1000, 'kg'))}</b> (ingredientes en kg).</p>`;
    };

    root.innerHTML = `
      <section class="page-intro"><div><span class="eyebrow">Datos maestros</span><h1>Recetas</h1>
        <p>Ingredientes y cantidades estándar por batch. Registrar o ejecutar una prueba nunca modifica la receta oficial.</p></div>
        ${admin ? `<div class="page-actions"><button class="btn primary" data-rc="nueva">${icon('plus')} Nueva receta</button></div>` : ''}</section>
      ${R.length ? `<div class="cat-layout">
        <nav class="cat-nav" aria-label="Recetas">${R.map((x) => `<button data-sel="${esc(x.id)}" class="${x.id === sel ? 'active' : ''} ${x.activo ? '' : 'off'}">${icon('book-open')}<span>${esc(x.nombre)}${x.activo ? '' : '<small>inactiva</small>'}</span></button>`).join('')}</nav>
        <div>${r ? `
          <div class="card version-card vigente"><div class="card-head"><div><h3>${esc(r.nombre)} ${r.activo ? '' : pill('Inactiva', 'gray')}</h3>
              <p>${vigente ? `Receta vigente${vigente.vigente_desde ? ` desde ${fmtDate(vigente.vigente_desde)}` : ''}${vigente.origen ? ` · actualizada por la prueba ${esc(vigente.origen.folio)}` : ''}` : 'Aún no tiene una receta vigente.'}</p></div>
            ${admin ? `<div class="head-btns"><button class="btn secondary" data-rc="editar">${icon('pencil')} Renombrar</button>
              ${!borrador ? `<button class="btn secondary" data-rc="cambios">${icon('file-pen')} ${vigente ? 'Modificar receta' : 'Capturar ingredientes'}</button>` : ''}</div>` : ''}</div>
            ${vigente ? tabla(vigente, false) : '<p class="hint">Capture los ingredientes y publíquelos para usar la receta en las pruebas.</p>'}</div>
          ${borrador ? `<div class="card mt version-card borrador"><div class="card-head"><div><h3>Cambios en preparación ${pill('Sin publicar', 'warn')} ${ayuda('Estos cambios no afectan la receta vigente ni las pruebas hasta que se publiquen.')}</h3>
              <p>${borrador.origen ? `Propuestos por la prueba ${esc(borrador.origen.folio)}` : `Iniciados el ${fmtDate(borrador.created_at.slice(0, 10))}`}</p></div>
            ${admin ? `<div class="head-btns"><button class="btn secondary" data-rc="ing-nuevo" data-v="${esc(borrador.id)}">${icon('plus')} Ingrediente</button>
              <button class="btn ghost danger-text" data-rc="descartar" data-v="${esc(borrador.id)}">${icon('x')} Descartar</button>
              <button class="btn primary" data-rc="publicar" data-v="${esc(borrador.id)}">${icon('badge-check')} Publicar</button></div>` : ''}</div>
            ${tabla(borrador, admin)}</div>` : ''}
          ${historicas.length ? `<details class="card mt hist"><summary>${icon('history')} Historial: ${historicas.length} receta(s) anterior(es)</summary>
            ${historicas.map((v) => `<div class="mt"><p class="cell-sub">Vigente hasta que se publicó un cambio${v.vigente_desde ? ` · vigente desde ${fmtDate(v.vigente_desde)}` : ''}${v.origen ? ` · prueba ${esc(v.origen.folio)}` : ''}</p>${tabla(v, false)}</div>`).join('')}</details>` : ''}
        ` : ''}</div>
      </div>` : `<div class="card">${emptyState({ ico: 'book-open', title: 'Sin recetas', text: admin ? 'Registre las recetas con “Nueva receta”.' : 'Un administrador debe registrar las recetas.' })}</div>`}`;
    root._d = { R, V, I, materias, unidades, borrador, vigente };
    refreshIcons();
  } catch (err) { root.innerHTML = errorState(err); refreshIcons(); }
}

async function onClick(e) {
  const s = e.target.closest('[data-sel]');
  if (s) { sel = s.dataset.sel; history.replaceState(null, '', `#/recetas?r=${sel}`); return pintar(); }
  const b = e.target.closest('[data-rc]');
  if (!b || !root?._d) return;
  const { R, V, I, materias, unidades, vigente } = root._d;
  const r = R.find((x) => x.id === sel);
  try {
    switch (b.dataset.rc) {
      case 'nueva': case 'editar': {
        const x = b.dataset.rc === 'editar' ? r : null;
        const ok = await openModal({
          title: x ? 'Renombrar receta' : 'Nueva receta', size: 'sm', submitText: x ? 'Guardar' : 'Crear',
          body: `<div class="field"><label for="re-n">Nombre de la receta <span class="req">*</span></label><input id="re-n" name="nombre" required maxlength="150" value="${esc(x?.nombre || '')}"></div>
            ${x ? `<label class="check"><input type="checkbox" name="activo" ${x.activo ? 'checked' : ''}> Activa (disponible para nuevas pruebas)</label>` : '<p class="hint">Después capture los ingredientes y publíquelos.</p>'}`,
          onSubmit: async ({ form }) => {
            if (!checkForm(form)) return false;
            const nombre = form.elements.nombre.value.trim();
            if (x) { mustRow(await sb.from('recetas_prubind').update({ nombre, activo: form.elements.activo.checked }).eq('id', x.id).select('id')); return; }
            const nueva = must(await sb.from('recetas_prubind').insert({ nombre }).select('id').single()).data;
            must(await sb.from('receta_versiones_prubind').insert({ receta_id: nueva.id, version: 'v1' }));
            sel = nueva.id;
          },
        });
        if (!ok) return; break;
      }
      case 'cambios': {
        if (vigente) {
          if (!await confirmDialog({ title: `Modificar ${r.nombre}`, message: 'Se copiarán los ingredientes actuales para editarlos. La receta vigente no cambia hasta que publique.', confirmText: 'Continuar' })) return;
          must(await sb.rpc('prubind_clonar_version', { p_version: vigente.id, p_nueva: siguienteVersion(V, r.id) }));
        } else must(await sb.from('receta_versiones_prubind').insert({ receta_id: r.id, version: siguienteVersion(V, r.id) }));
        break;
      }
      case 'descartar': {
        if (!await confirmDialog({ title: 'Descartar cambios', message: 'Se eliminarán los cambios sin publicar. La receta vigente no se modifica.', confirmText: 'Descartar', danger: true })) return;
        must(await sb.from('receta_ingredientes_prubind').delete().eq('version_id', b.dataset.v));
        mustRow(await sb.from('receta_versiones_prubind').delete().eq('id', b.dataset.v).select('id'));
        break;
      }
      case 'publicar': {
        if (!I.some((i) => i.version_id === b.dataset.v)) { toast('Agregue al menos un ingrediente.', 'warning'); return; }
        if (!await confirmDialog({ title: `Publicar ${r.nombre}`, message: 'Los cambios quedarán como la receta vigente. La receta anterior se conserva en el historial.', confirmText: 'Publicar' })) return;
        mustRow(await sb.from('receta_versiones_prubind').update({ estado: 'vigente' }).eq('id', b.dataset.v).select('id'));
        break;
      }
      case 'ing-nuevo': case 'ing-editar': {
        const i = I.find((x) => x.id === b.dataset.id);
        const vid = i?.version_id || b.dataset.v;
        const ya = new Set(I.filter((x) => x.version_id === vid).map((x) => x.materia_prima_id));
        const ok = await openModal({
          title: i ? `Cantidad de ${materias.find((m) => m.id === i.materia_prima_id)?.nombre || ''}` : 'Agregar ingrediente', size: 'sm',
          body: `${i ? '' : `<div class="field"><label for="ri-m">Materia prima <span class="req">*</span></label><select id="ri-m" name="mp" required>${opciones(materias.filter((m) => m.activo && !ya.has(m.id)), null)}</select>
              <small class="hint">¿No aparece? Agréguela en Catálogos → Materias primas.</small></div>`}
            <div class="form-grid"><div class="field"><label for="ri-c">Cantidad por batch <span class="req">*</span></label><input id="ri-c" name="cant" type="number" min="0.0001" step="any" inputmode="decimal" required value="${esc(i?.cantidad ?? '')}"></div>
            <div class="field"><label for="ri-u">Unidad</label><select id="ri-u" name="un" required>${opciones(unidades, i?.unidad_id || unidades.find((u) => u.simbolo === 'kg')?.id, { label: (u) => u.simbolo, vacio: null })}</select></div></div>`,
          onOpen: ({ form }) => form.elements.mp?.addEventListener('change', () => { const m = materias.find((x) => x.id === form.elements.mp.value); if (m?.unidad_id) form.elements.un.value = m.unidad_id; }),
          onSubmit: async ({ form }) => {
            if (!checkForm(form)) return false;
            const p = { cantidad: Number(form.elements.cant.value), unidad_id: form.elements.un.value };
            if (i) mustRow(await sb.from('receta_ingredientes_prubind').update(p).eq('id', i.id).select('id'));
            else must(await sb.from('receta_ingredientes_prubind').insert({ ...p, version_id: vid, materia_prima_id: form.elements.mp.value, orden: I.filter((x) => x.version_id === vid).length + 1 }));
          },
        });
        if (!ok) return; break;
      }
      case 'ing-del': mustRow(await sb.from('receta_ingredientes_prubind').delete().eq('id', b.dataset.id).select('id')); break;
      default: return;
    }
    invalidateCat('versiones');
    toast('Receta actualizada.', 'success');
    pintar();
  } catch (err) { toast(errMsg(err), 'error'); }
}
