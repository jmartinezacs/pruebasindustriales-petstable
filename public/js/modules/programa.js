// =====================================================================
// Ejecución: todos los batches registrados de todas las pruebas,
// agrupados por lote diario. La captura se hace en el expediente
// (pestaña Ejecución); aquí se consulta y se filtra.
// =====================================================================
import {
  sb, esc, icon, DataTable, paged, sanitizeSearch, debounce, must, fmtDate, fmtDateTime, pill, estadoPill,
  getCat, errorState, refreshIcons, dayStartTs, dayEndTs,
} from '../core.js';

const OP = { pendiente: ['Pendiente', 'warn'], conforme: ['Conforme', 'ok'], no_conforme: ['No conforme', 'bad'] };
let table;

export default {
  async render(el, params) {
    let tipos = [];
    try { tipos = await getCat('tipos'); } catch (err) { el.innerHTML = errorState(err); refreshIcons(); return; }
    el.innerHTML = `
      <section class="page-intro">
        <div><span class="eyebrow">Producción</span><h1>Batches ejecutados</h1>
          <p>Registro de batches de todas las pruebas, por lote diario. Para capturar, abre la prueba en su etapa «En proceso».</p></div>
      </section>
      <div class="card">
        <div class="toolbar">
          <div class="search">${icon('search')}<input type="search" id="pg-q" placeholder="Buscar por folio, lote diario o receta" aria-label="Buscar"></div>
          <select id="pg-op" aria-label="Resultado operativo"><option value="">Cualquier resultado</option>${Object.entries(OP).map(([k, [l]]) => `<option value="${k}">${esc(l)}</option>`).join('')}</select>
          <select id="pg-tipo" aria-label="Tipo de prueba"><option value="">Todos los tipos</option>${tipos.map((t) => `<option value="${esc(t.codigo)}">${esc(t.nombre)}</option>`).join('')}</select>
          <label class="check"><input type="checkbox" id="pg-act" checked> Solo ejecución vigente</label>
          <span class="date-range"><input type="date" id="pg-desde" aria-label="Desde"> a <input type="date" id="pg-hasta" aria-label="Hasta"></span>
        </div>
        <div id="pg-table"></div>
      </div>`;
    const $ = (s) => el.querySelector(s);
    if (params.op && OP[params.op]) $('#pg-op').value = params.op;
    table = new DataTable($('#pg-table'), {
      sort: { key: 'fecha_hora', asc: false },
      rowClass: (b) => (b.resultado_op === 'no_conforme' && !b.resolucion ? 'row-bad' : ''),
      columns: [
        { label: 'Fecha y hora', sort: 'fecha_hora', render: (b) => `<span class="mono">${fmtDateTime(b.fecha_hora)}</span>` },
        { label: 'Prueba', sort: 'folio', render: (b) => `<a class="cell-main link" href="#/pruebas?id=${esc(b.prueba_id)}&tab=proceso">${esc(b.folio)}</a>
            <div class="cell-sub">${esc(b.tipo_nombre)} · ${estadoPill(b.prueba_estado)}</div>` },
        { label: 'Lote diario / batch', sort: 'lote_codigo', render: (b) => `<b>${esc(b.lote_codigo || '—')}</b> · #${b.numero}
            <div class="cell-sub">${b.lote_fecha ? fmtDate(b.lote_fecha) : ''}${b.ejecucion > 1 ? ` · ejecución ${b.ejecucion}` : ''}${b.ejecucion !== b.ejecucion_actual ? ' (anterior)' : ''}</div>` },
        { label: 'Receta', render: (b) => (b.receta_nombre ? esc(b.receta_nombre) : '<span class="cell-sub">Formulación de la prueba</span>') },
        { label: 'Peso · Temp · Consist.', render: (b) => `<span class="mono">${b.peso_real_kg ?? '—'} kg · ${b.temp_coccion_c ?? '—'} °C · ${b.consistencia_cm_s ?? '—'} cm/s</span>` },
        { label: 'Responsable', sort: 'responsable_nombre', render: (b) => esc(b.responsable_nombre || '—') },
        { label: 'Resultado', sort: 'resultado_op', render: (b) => `${pill(...(OP[b.resultado_op] || [b.resultado_op, 'gray']))}${b.incidencias ? `<div class="cell-sub">${esc(b.incidencias)}</div>` : ''}${b.resolucion ? `<div class="cell-sub ok-txt">Resuelto</div>` : ''}` },
      ],
      empty: { ico: 'factory', title: 'Sin batches', text: 'Los batches aparecen aquí al registrarse en la etapa de Ejecución de cada prueba.' },
      fetch: async ({ from, to, sort, filters: f }) => {
        let q = sb.from('v_batches_prubind').select('*', { count: 'exact' });
        if (f.op) q = q.eq('resultado_op', f.op);
        if (f.tipo) q = q.eq('tipo', f.tipo);
        if (f.desde) q = q.gte('fecha_hora', dayStartTs(f.desde));
        if (f.hasta) q = q.lt('fecha_hora', dayEndTs(f.hasta));
        const s = sanitizeSearch(f.q);
        if (s) q = q.or(`folio.ilike.*${s}*,lote_codigo.ilike.*${s}*,receta_nombre.ilike.*${s}*`);
        const { data, count } = must(await paged(q, { from, to, sort }, [['numero', false]]));
        // "Ejecución vigente" compara dos columnas: se filtra en el cliente sobre la página
        return { rows: f.act ? data.filter((b) => b.ejecucion === b.ejecucion_actual) : data, count };
      },
    });
    const apply = () => table.setFilters({
      q: $('#pg-q').value, op: $('#pg-op').value, tipo: $('#pg-tipo').value, act: $('#pg-act').checked,
      desde: $('#pg-desde').value, hasta: $('#pg-hasta').value,
    });
    $('#pg-q').addEventListener('input', debounce(apply, 350));
    ['#pg-op', '#pg-tipo', '#pg-act', '#pg-desde', '#pg-hasta'].forEach((s) => $(s).addEventListener('change', apply));
    await apply();
  },
  destroy() { table = null; },
};
