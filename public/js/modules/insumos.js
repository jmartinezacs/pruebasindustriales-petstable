// =====================================================================
// Abastecimiento: materiales previstos de todas las pruebas abiertas.
// Compras y Almacén confirman compra y disponibilidad. No bloquea el
// flujo, pero da visibilidad de lo que falta.
// =====================================================================
import {
  sb, esc, icon, toast, errMsg, openModal, mustRow, nullIfEmpty, DataTable, paged, debounce, must, fmtQty, fmtDate, dispPill, estadoPill, prioPill,
  DISPONIBILIDAD, getCat, unidadTxt, errorState, refreshIcons, puedeEn, autoridadAlguna,
} from '../core.js';


const EDITABLES = ['registrada', 'en_preparacion', 'preparada', 'en_ejecucion'];
let table;

export default {
  async render(el, params) {
    let tipos, materias, unidades;
    try { [tipos, materias, unidades] = await Promise.all([getCat('tipos'), getCat('materias'), getCat('unidades')]); } catch (err) { el.innerHTML = errorState(err); refreshIcons(); return; }
    const mp = (id) => materias.find((m) => m.id === id)?.nombre || '?';
    el.innerHTML = `
      <section class="page-intro">
        <div><span class="eyebrow">Abastecimiento</span><h1>Materiales para pruebas</h1>
          <p>Materias primas previstas en la preparación de cada prueba: necesidad de compra y disponibilidad.${autoridadAlguna('abastecer') ? '' : ' Solo Compras y Almacén (o quien prepara la prueba) pueden actualizarlas.'}</p></div>
      </section>
      <div class="card">
        <div class="toolbar">
          <select id="is-disp" aria-label="Disponibilidad"><option value="faltantes">Sin confirmar o faltantes</option>${Object.entries(DISPONIBILIDAD).map(([k, v]) => `<option value="${k}">${esc(v.label)}</option>`).join('')}<option value="">Todas</option></select>
          <select id="is-mp" aria-label="Materia prima"><option value="">Todas las materias primas</option>${materias.map((m) => `<option value="${esc(m.id)}">${esc(m.nombre)}</option>`).join('')}</select>
          <select id="is-tipo" aria-label="Tipo de prueba"><option value="">Todos los tipos</option>${tipos.map((t) => `<option value="${esc(t.codigo)}">${esc(t.nombre)}</option>`).join('')}</select>
          <label class="check"><input type="checkbox" id="is-compra"> Solo las que requieren compra</label>
        </div>
        <div id="is-table"></div>
      </div>`;
    const $ = (s) => el.querySelector(s);
    if (params.disp !== undefined && (params.disp === '' || DISPONIBILIDAD[params.disp])) $('#is-disp').value = params.disp;
    table = new DataTable($('#is-table'), {
      sort: { key: 'created_at', asc: true },
      columns: [
        { label: 'Materia prima', render: (m) => `<div class="cell-main">${esc(mp(m.materia_prima_id))}</div>${m.observaciones ? `<div class="cell-sub">${esc(m.observaciones)}</div>` : ''}` },
        { label: 'Prueba', render: (m) => `<a class="link" href="#/pruebas?id=${esc(m.prueba_id)}&tab=registro"><b class="mono">${esc(m.prueba.folio)}</b></a>
            <div class="cell-sub">${esc(tipos.find((t) => t.codigo === m.prueba.tipo)?.nombre || m.prueba.tipo)} · ${estadoPill(m.prueba.estado)} ${m.prueba.prioridad !== 'normal' ? prioPill(m.prueba.prioridad) : ''}</div>` },
        { label: 'Fecha planeada', render: (m) => `<span class="mono">${m.prueba.fecha_planeada ? fmtDate(m.prueba.fecha_planeada) : '—'}</span>` },
        { label: 'Cantidad', sort: 'cantidad', render: (m) => esc(fmtQty(m.cantidad, unidadTxt(unidades, m.unidad_id))) },
        { label: 'Compra', sort: 'requiere_compra', render: (m) => (m.requiere_compra ? '<b class="warn-txt">Requiere compra</b>' : '<span class="cell-sub">No</span>') },
        { label: 'Disponibilidad', sort: 'disponibilidad', render: (m) => dispPill(m.disponibilidad) },
        { label: '', cls: 'actions', render: (m) => (EDITABLES.includes(m.prueba.estado) && puedeEn(m.prueba, 'abastecer')
          ? `<button class="icon-btn ok" data-ab="${esc(m.id)}" title="Compra y disponibilidad" aria-label="Compra y disponibilidad">${icon('package-check')}</button>` : '') },
      ],
      empty: { ico: 'package-check', title: 'Sin materiales en esta vista', text: 'Los materiales se capturan en la etapa de Preparación de cada prueba.' },
      fetch: async ({ from, to, sort, filters: f }) => {
        let q = sb.from('prueba_materiales_prubind')
          .select('*, prueba:pruebas_prubind!inner(id, folio, tipo, estado, prioridad, fecha_planeada, registrado_por, responsable_inicial_id, responsable_ejecucion_id)', { count: 'exact' })
          .in('prueba.estado', EDITABLES);
        if (f.disp === 'faltantes') q = q.neq('disponibilidad', 'disponible');
        else if (f.disp) q = q.eq('disponibilidad', f.disp);
        if (f.mp) q = q.eq('materia_prima_id', f.mp);
        if (f.tipo) q = q.eq('prueba.tipo', f.tipo);
        if (f.compra) q = q.eq('requiere_compra', true);
        const { data, count } = must(await paged(q, { from, to, sort }));
        return { rows: data, count };
      },
    });
    const apply = () => table.setFilters({ disp: $('#is-disp').value, mp: $('#is-mp').value, tipo: $('#is-tipo').value, compra: $('#is-compra').checked });
    ['#is-disp', '#is-mp', '#is-tipo', '#is-compra'].forEach((s) => $(s).addEventListener('change', debounce(apply, 50)));
    el.addEventListener('click', async (e) => {
      const b = e.target.closest('[data-ab]');
      if (!b) return;
      const m = table.row(b.dataset.ab);
      if (!m) return;
      try { if (await abastoForm(m, mp)) table.load(); } catch (err) { toast(errMsg(err), 'error'); }
    });
    await apply();
  },
  destroy() { table = null; },
};

// Compra y disponibilidad de un material (Compras / Almacén)
function abastoForm(m, mp) {
  return openModal({
    title: 'Compra y disponibilidad', subtitle: mp(m.materia_prima_id), size: 'sm',
    body: `<label class="check"><input type="checkbox" name="compra" ${m.requiere_compra ? 'checked' : ''}> Requiere compra</label>
      <div class="field"><label for="ab-d">Disponibilidad <span class="req">*</span></label><select id="ab-d" name="disp" required>${Object.entries(DISPONIBILIDAD).map(([k, v]) => `<option value="${k}" ${k === m.disponibilidad ? 'selected' : ''}>${esc(v.label)}</option>`).join('')}</select></div>
      <div class="field"><label for="ab-o">Observaciones</label><textarea id="ab-o" name="obs" maxlength="300" placeholder="Proveedor, fecha estimada, ubicación en almacén…">${esc(m.observaciones || '')}</textarea></div>`,
    onSubmit: async ({ form }) => {
      mustRow(await sb.from('prueba_materiales_prubind').update({ requiere_compra: form.elements.compra.checked, disponibilidad: form.elements.disp.value,
        observaciones: nullIfEmpty(form.elements.obs.value.trim()) }).eq('id', m.id).select('id'));
      toast('Disponibilidad actualizada.', 'success');
    },
  });
}

