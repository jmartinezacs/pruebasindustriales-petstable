// =====================================================================
// Bitácora de auditoría (solo administradores). Los registros se generan
// en la base de datos mediante triggers; no se pueden editar ni borrar.
// =====================================================================
import {
  sb, esc, icon, openModal, DataTable, paged, sanitizeSearch, debounce, pill, must, fmtDateTime, dayStartTs, dayEndTs,
} from '../core.js';

const TABLAS = {
  pruebas_prubind: 'Pruebas', prueba_formulacion_prubind: 'Formulación de prueba', prueba_materiales_prubind: 'Materiales de prueba',
  prueba_parametros_prubind: 'Parámetros de prueba', plan_evaluacion_prubind: 'Plan de evaluación', puntos_muestreo_prubind: 'Puntos de vida útil',
  lotes_diarios_prubind: 'Lotes diarios', batches_prubind: 'Batches', batch_lotes_mp_prubind: 'Lotes de MP por batch',
  ejecucion_controles_prubind: 'Controles de ejecución', muestras_prubind: 'Muestras', muestra_batches_prubind: 'Batches por muestra',
  resultados_prubind: 'Resultados', dictamenes_prubind: 'Dictámenes', autorizaciones_prubind: 'Autorizaciones', adjuntos_prubind: 'Evidencias',
  recetas_prubind: 'Recetas', receta_versiones_prubind: 'Versiones de receta', receta_ingredientes_prubind: 'Ingredientes de receta',
  productos_prubind: 'Productos', materias_primas_prubind: 'Materias primas', proveedores_prubind: 'Proveedores', lotes_mp_prubind: 'Lotes de materia prima',
  equipos_prubind: 'Equipos', equipo_parametros_prubind: 'Parámetros de equipo', metodos_prubind: 'Métodos de evaluación',
  especificaciones_prubind: 'Especificaciones', plantilla_evaluacion_prubind: 'Plantillas de evaluación', tipos_prueba_prubind: 'Tipos de prueba',
  objetivos_prubind: 'Objetivos', motivos_prubind: 'Motivos', tipos_evidencia_prubind: 'Tipos de evidencia', unidades_prubind: 'Unidades',
  puestos_prubind: 'Puestos', autoridades_prubind: 'Autoridades', usuarios_prubind: 'Usuarios', areas_prubind: 'Áreas',
};
const ACC = { INSERT: ['Alta', 'ok'], UPDATE: ['Cambio', 'info'], DELETE: ['Baja', 'bad'] };
let table;

export default {
  async render(el) {
    el.innerHTML = `
      <section class="page-intro">
        <div><span class="eyebrow">Auditoría</span><h1>Bitácora</h1>
          <p>Registro automático de altas, cambios y bajas en todo el sistema.</p></div>
      </section>
      <div class="card">
        <div class="toolbar">
          <div class="search">${icon('search')}<input type="search" id="b-q" placeholder="Buscar por correo del usuario" aria-label="Buscar"></div>
          <select id="b-tabla" aria-label="Módulo"><option value="">Todos los módulos</option>${Object.entries(TABLAS).map(([k, v]) => `<option value="${k}">${v}</option>`).join('')}</select>
          <select id="b-acc" aria-label="Acción"><option value="">Todas las acciones</option>${Object.entries(ACC).map(([k, [l]]) => `<option value="${k}">${l}</option>`).join('')}</select>
          <span class="date-range"><input type="date" id="b-desde" aria-label="Desde"> a <input type="date" id="b-hasta" aria-label="Hasta"></span>
        </div>
        <div id="b-table"></div>
      </div>`;
    table = new DataTable(el.querySelector('#b-table'), {
      sort: { key: 'created_at', asc: false },
      columns: [
        { label: 'Fecha', sort: 'created_at', render: (b) => `<span class="mono">${fmtDateTime(b.created_at)}</span>` },
        { label: 'Usuario', sort: 'usuario_email', render: (b) => esc(b.usuario_email || 'Sistema') },
        { label: 'Módulo', sort: 'tabla', render: (b) => esc(TABLAS[b.tabla] || b.tabla) },
        { label: 'Acción', sort: 'accion', render: (b) => pill(...(ACC[b.accion] || [b.accion, 'gray'])) },
        { label: 'Campos', render: (b) => `<span class="cell-sub">${esc(resumen(b))}</span>` },
        { label: '', cls: 'actions', render: (b) => `<button class="icon-btn" data-ba="${b.id}" title="Ver detalle" aria-label="Ver detalle">${icon('eye')}</button>` },
      ],
      empty: { ico: 'history', title: 'Sin registros', text: 'Los cambios en el sistema se registrarán aquí automáticamente.' },
      fetch: async ({ from, to, sort, filters: f }) => {
        let q = sb.from('bitacora_prubind').select('id, tabla, registro_id, accion, cambios, usuario_email, created_at', { count: 'exact' });
        const s = sanitizeSearch(f.q);
        if (s) q = q.ilike('usuario_email', `*${s}*`);
        if (f.tabla) q = q.eq('tabla', f.tabla);
        if (f.acc) q = q.eq('accion', f.acc);
        if (f.desde) q = q.gte('created_at', dayStartTs(f.desde));
        if (f.hasta) q = q.lt('created_at', dayEndTs(f.hasta));
        const { data, count } = must(await paged(q, { from, to, sort }));
        return { rows: data, count };
      },
    });
    const apply = () => table.setFilters({
      q: el.querySelector('#b-q').value, tabla: el.querySelector('#b-tabla').value, acc: el.querySelector('#b-acc').value,
      desde: el.querySelector('#b-desde').value, hasta: el.querySelector('#b-hasta').value,
    });
    el.querySelector('#b-q').addEventListener('input', debounce(apply, 350));
    ['#b-tabla', '#b-acc', '#b-desde', '#b-hasta'].forEach((s) => el.querySelector(s).addEventListener('change', apply));
    el.addEventListener('click', (e) => {
      const b = e.target.closest('[data-ba]');
      if (b) detalle(table.row(b.dataset.ba));
    });
    await apply();
  },
  destroy() { table = null; },
};

const OCULTOS = new Set(['id', 'created_at', 'updated_at']);
function resumen(b) {
  if (!b.cambios) return '—';
  const keys = Object.keys(b.cambios).filter((k) => !OCULTOS.has(k));
  return keys.length > 4 ? `${keys.slice(0, 4).join(', ')}…` : keys.join(', ');
}
const show = (v) => (v === null || v === undefined ? '∅' : typeof v === 'object' ? JSON.stringify(v) : String(v));

function detalle(b) {
  if (!b) return;
  let rows = '';
  if (b.cambios && b.accion === 'UPDATE') {
    rows = Object.entries(b.cambios).map(([k, [o, n]]) => `<tr><td><b>${esc(k)}</b></td><td class="old">${esc(show(o))}</td><td class="new">${esc(show(n))}</td></tr>`).join('');
    rows = `<table class="diff"><thead><tr><th>Campo</th><th>Antes</th><th>Después</th></tr></thead><tbody>${rows}</tbody></table>`;
  } else if (b.cambios) {
    rows = `<table class="diff"><thead><tr><th>Campo</th><th>Valor</th></tr></thead><tbody>${Object.entries(b.cambios)
      .map(([k, v]) => `<tr><td><b>${esc(k)}</b></td><td>${esc(show(v))}</td></tr>`).join('')}</tbody></table>`;
  } else rows = '<p class="hint">Sin detalle.</p>';
  openModal({
    title: `${TABLAS[b.tabla] || b.tabla} · ${ACC[b.accion]?.[0] || b.accion}`,
    subtitle: `${b.usuario_email || 'Sistema'} · ${fmtDateTime(b.created_at)} · Registro ${b.registro_id}`,
    size: 'lg', body: rows,
  });
}
