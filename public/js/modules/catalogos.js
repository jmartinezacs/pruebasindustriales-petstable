// =====================================================================
// Catálogos y datos maestros (administradores; lotes de materia prima
// también Compras/Almacén). Registros activos/inactivos: lo que tiene
// historial no se elimina, se desactiva.
// =====================================================================
import {
  sb, state, esc, icon, toast, errMsg, openModal, confirmDialog, checkForm, nullIfEmpty, numOrNull, must, mustRow,
  getCat, invalidateCat, opciones, unidadTxt, fmtDate, pill, emptyState, errorState, refreshIcons, debounce, autoridadAlguna,
  CATEGORIAS, NIVELES, CAMPOS_REGISTRO, SECCIONES_PREP, OPCIONES_TXT, AREAS,
} from '../core.js';
import { parametroForm } from './exp_registro.js';

const TIPO_RES = { numerico: 'Numérico', opcion: 'Opciones (conforme / no conforme…)', diluciones: 'Conteo por diluciones', presencia: 'Presencia / ausencia' };
const CAT_MP = { ingrediente: 'Ingrediente', empaque_primario: 'Empaque primario', empaque_secundario: 'Empaque secundario', otro: 'Otro' };
const OPC_POSIBLES = ['conforme', 'no_conforme', 'no_aplica', 'no_evaluado', 'pendiente'];
const kv = (o) => Object.entries(o).map(([value, nombre]) => ({ id: value, nombre }));

// Definición de cada catálogo
const DEFS = {
  // Oculto: los productos equivalen a las recetas (se administran en Recetas); se conserva para el historial
  productos: { label: 'Productos', icon: 'box', table: 'productos_prubind', cat: 'productos', order: 'nombre', oculto: true,
    fields: [{ n: 'codigo', l: 'Código', t: 'text', max: 30 }, { n: 'nombre', l: 'Nombre', t: 'text', req: true, max: 150 }],
    cols: [['Producto', (r) => `<div class="cell-main">${esc(r.nombre)}</div><div class="cell-sub">${esc(r.codigo || '')}</div>`]] },
  materias: { label: 'Materias primas', icon: 'wheat', table: 'materias_primas_prubind', cat: 'materias', order: 'nombre',
    fields: [{ n: 'nombre', l: 'Nombre', t: 'text', req: true, max: 150 },
      { n: 'categoria', l: 'Categoría', t: 'select', req: true, opts: () => kv(CAT_MP) }, { n: 'unidad_id', l: 'Unidad', t: 'select', opts: async () => (await getCat('unidades')).map((u) => ({ ...u, nombre: u.simbolo })) }],
    cols: [['Material', (r) => `<div class="cell-main">${esc(r.nombre)}</div>`], ['Categoría', (r) => esc(CAT_MP[r.categoria])], ['Unidad', (r, x) => esc(unidadTxt(x.unidades, r.unidad_id))]] },
  proveedores: { label: 'Proveedores', icon: 'truck', table: 'proveedores_prubind', cat: 'proveedores', order: 'nombre',
    fields: [{ n: 'nombre', l: 'Nombre', t: 'text', req: true, max: 150 }, { n: 'contacto', l: 'Contacto', t: 'text', max: 200 }],
    cols: [['Proveedor', (r) => `<div class="cell-main">${esc(r.nombre)}</div><div class="cell-sub">${esc(r.contacto || '')}</div>`]] },
  lotes: { oculto: true, label: 'Lotes de materia prima', icon: 'barcode', table: 'lotes_mp_prubind', order: 'created_at', abasto: true,
    fields: [{ n: 'materia_prima_id', l: 'Materia prima', t: 'select', req: true, opts: () => getCat('materias') }, { n: 'proveedor_id', l: 'Proveedor', t: 'select', opts: () => getCat('proveedores') },
      { n: 'lote', l: 'Lote', t: 'text', req: true, max: 60 }, { n: 'fecha_recepcion', l: 'Fecha de recepción', t: 'date' }, { n: 'caducidad', l: 'Caducidad', t: 'date' }],
    cols: [['Lote', (r, x) => `<div class="cell-main mono">${esc(r.lote)}</div><div class="cell-sub">${esc(x.materias.find((m) => m.id === r.materia_prima_id)?.nombre || '')}</div>`],
      ['Proveedor', (r, x) => esc(x.proveedores.find((p) => p.id === r.proveedor_id)?.nombre || '—')], ['Recepción', (r) => fmtDate(r.fecha_recepcion)], ['Caducidad', (r) => fmtDate(r.caducidad)]] },
  equipos: { oculto: true, label: 'Equipos y maquinaria', icon: 'cog', table: 'equipos_prubind', cat: 'equipos', order: 'nombre',
    fields: [{ n: 'codigo', l: 'Código', t: 'text', max: 30 }, { n: 'nombre', l: 'Nombre', t: 'text', req: true, max: 150 }, { n: 'area_id', l: 'Área', t: 'select', opts: () => getCat('areas') }],
    cols: [['Equipo', (r) => `<div class="cell-main">${esc(r.nombre)}</div><div class="cell-sub">${esc(r.codigo || '')}</div>`], ['Área', (r, x) => esc(x.areas.find((a) => a.id === r.area_id)?.nombre || '—')]] },
  parametros: { oculto: true, label: 'Parámetros de operación', icon: 'gauge', table: 'equipo_parametros_prubind', cat: 'parametros', order: 'nombre', filtro: { n: 'equipo_id', l: 'Equipo', opts: () => getCat('equipos') },
    fields: [{ n: 'equipo_id', l: 'Equipo', t: 'select', req: true, opts: () => getCat('equipos') }, { n: 'nombre', l: 'Parámetro', t: 'text', req: true, max: 120 },
      { n: 'unidad_id', l: 'Unidad', t: 'select', opts: async () => (await getCat('unidades')).map((u) => ({ ...u, nombre: u.simbolo })) },
      { n: 'minimo', l: 'Mínimo', t: 'number' }, { n: 'maximo', l: 'Máximo', t: 'number' },
      { n: 'referencia', l: 'Referencia de la especificación aprobada', t: 'text', max: 200, full: true, hint: 'Obligatoria si se captura un rango. No capture límites sin documento que los respalde.' }],
    cols: [['Parámetro', (r, x) => `<div class="cell-main">${esc(r.nombre)}</div><div class="cell-sub">${esc(x.equipos.find((e) => e.id === r.equipo_id)?.nombre || '')}</div>`],
      ['Rango', (r, x) => (r.minimo != null || r.maximo != null ? `${r.minimo ?? '—'} – ${r.maximo ?? '—'} ${esc(unidadTxt(x.unidades, r.unidad_id))}<div class="cell-sub">${esc(r.referencia || '')}</div>` : '<span class="cell-sub">Sin rango</span>')]] },
  metodos: { label: 'Parámetros a evaluar', icon: 'microscope', table: 'metodos_prubind', cat: 'metodos', order: 'codigo', filtro: { n: 'area', l: 'Área', opts: () => Object.entries(AREAS).map(([id, a]) => ({ id, nombre: a.label })) }, formulario: true,
    fields: [],
    cols: [['Código', (r) => `<b class="mono">${esc(r.codigo)}</b>`], ['Parámetro', (r) => esc(r.nombre)], ['Área', (r) => esc(AREAS[r.area]?.label || '')],
      ['Se cuantifica', (r) => (['numerico', 'diluciones'].includes(r.tipo_resultado) ? 'Cuantitativo' : 'Cualitativo')],
      ['Unidad', (r, x) => esc(unidadTxt(x.unidades, r.unidad_id) || '—')]] },
  // Retirados de la app (v5.8): no se usan en el flujo actual; las tablas y su historial se conservan
  especificaciones: { oculto: true, label: 'Especificaciones y criterios', icon: 'ruler', table: 'especificaciones_prubind', order: 'updated_at', filtro: { n: 'metodo_id', l: 'Método', opts: () => getCat('metodos') },
    fields: [{ n: 'metodo_id', l: 'Método o control', t: 'select', req: true, opts: () => getCat('metodos'), full: true },
      { n: 'producto_id', l: 'Receta (vacío = general)', t: 'select', opts: () => getCat('productos') }, { n: 'materia_prima_id', l: 'Materia prima (vacío = general)', t: 'select', opts: () => getCat('materias') },
      { n: 'minimo', l: 'Mínimo', t: 'number' }, { n: 'maximo', l: 'Máximo', t: 'number' },
      { n: 'criterio_texto', l: 'Criterio en texto', t: 'text', max: 200, hint: 'Ej. "Ausencia en 25 g". Use mínimo/máximo para criterios numéricos.' },
      { n: 'referencia', l: 'Referencia del documento aprobado', t: 'text', req: true, max: 200, full: true }, { n: 'version', l: 'Versión', t: 'text', max: 20 },
      { n: 'vigente', l: 'Vigente', t: 'bool' }],
    cols: [['Método', (r, x) => `<div class="cell-main">${esc(x.metodos.find((m) => m.id === r.metodo_id)?.nombre || '')}</div><div class="cell-sub">${esc([x.productos.find((p) => p.id === r.producto_id)?.nombre, x.materias.find((m) => m.id === r.materia_prima_id)?.nombre].filter(Boolean).join(' · ') || 'General')}</div>`],
      ['Criterio', (r) => esc(r.minimo != null || r.maximo != null ? `${r.minimo ?? '—'} – ${r.maximo ?? '—'}` : r.criterio_texto || '')],
      ['Referencia', (r) => `<span class="cell-sub">${esc(r.referencia)} · v${esc(r.version)}</span> ${r.vigente ? pill('Vigente', 'ok') : pill('No vigente', 'gray')}`]] },
  plantillas: { oculto: true, label: 'Plantillas de evaluación', icon: 'layout-template', table: 'plantilla_evaluacion_prubind', order: 'orden', filtro: { n: 'tipo', l: 'Tipo de prueba', opts: async () => (await getCat('tipos')).map((t) => ({ id: t.codigo, nombre: t.nombre })), req: true },
    fields: [{ n: 'tipo', l: 'Tipo de prueba', t: 'select', req: true, opts: async () => (await getCat('tipos')).map((t) => ({ id: t.codigo, nombre: t.nombre })) },
      { n: 'metodo_id', l: 'Método o control', t: 'select', req: true, opts: () => getCat('metodos') },
      { n: 'nivel', l: 'Nivel de muestreo sugerido', t: 'select', req: true, opts: () => kv(NIVELES) }, { n: 'orden', l: 'Orden', t: 'number', int: true }, { n: 'obligatorio', l: 'Sugerido (aparece marcado al registrar)', t: 'bool' }],
    cols: [['Método', (r, x) => { const m = x.metodos.find((k) => k.id === r.metodo_id); return `<div class="cell-main">${esc(m?.nombre || '')}</div><div class="cell-sub">${esc(CATEGORIAS[m?.categoria] || '')}</div>`; }],
      ['Nivel', (r) => esc(NIVELES[r.nivel])], ['', (r) => (r.obligatorio ? pill('Sugerido', 'orange') : pill('Disponible', 'gray'))]] },
  tipos: { label: 'Tipos de prueba', icon: 'flask-conical', table: 'tipos_prueba_prubind', cat: 'tipos', order: 'orden', pk: 'codigo',
    fields: [{ n: 'codigo', l: 'Código interno', t: 'text', req: true, max: 40, soloAlta: true, pattern: '[a-z_]{3,40}', hint: 'Minúsculas y guion bajo; no se puede cambiar.' },
      { n: 'nombre', l: 'Nombre', t: 'text', req: true, max: 80 }, { n: 'descripcion', l: 'Descripción', t: 'text', max: 300, full: true }, { n: 'orden', l: 'Orden', t: 'number', int: true },
      { n: 'campos_registro', l: 'Campos del registro', t: 'checks', opts: () => kv(CAMPOS_REGISTRO), full: true },
      { n: 'secciones_prep', l: 'Secciones de preparación', t: 'checks', opts: () => kv(SECCIONES_PREP), full: true },
      { n: 'ejecucion_form', l: 'Formulario de ejecución', t: 'select', req: true, opts: () => kv({ fabricacion: 'Fabricación (lotes diarios y batches)', controles: 'Controles y parámetros' }) },
      { n: 'equipo_id', l: 'Equipo predeterminado', t: 'select', opts: () => getCat('equipos'), hint: 'Sus parámetros se cargan solos en la preparación (p. ej. ULMA en empaque primario).' },
      { n: 'requiere_aut_ejecucion', l: 'Requiere autorización de ejecución', t: 'bool' }],
    cols: [['Tipo', (r) => `<div class="cell-main">${esc(r.nombre)}</div><div class="cell-sub">${esc(r.descripcion || '')}</div>`],
      ['Plantilla', (r) => `<span class="cell-sub">${esc((r.campos_registro || []).map((k) => CAMPOS_REGISTRO[k]).join(', '))}<br>${esc(r.ejecucion_form === 'fabricacion' ? 'Fabricación' : 'Controles')}${r.requiere_aut_ejecucion ? ' · requiere autorización' : ''}</span>`]] },
  objetivos: { label: 'Objetivos', icon: 'target', table: 'objetivos_prubind', cat: 'objetivos', order: 'orden',
    fields: [{ n: 'nombre', l: 'Objetivo', t: 'text', req: true, max: 120 }, { n: 'tipo', l: 'Solo para el tipo (vacío = todos)', t: 'select', opts: async () => (await getCat('tipos')).map((t) => ({ id: t.codigo, nombre: t.nombre })) },
      { n: 'orden', l: 'Orden', t: 'number', int: true }],
    cols: [['Objetivo', (r) => esc(r.nombre)], ['Tipo', (r, x) => esc(x.tipos.find((t) => t.codigo === r.tipo)?.nombre || 'Todos')]] },
  motivos: { oculto: true, label: 'Motivos de rechazo y desviación', icon: 'octagon-alert', table: 'motivos_prubind', cat: 'motivos', order: 'nombre', filtro: { n: 'tipo', l: 'Tipo', opts: () => kv({ rechazo: 'Rechazo', desviacion: 'Desviación' }) },
    fields: [{ n: 'tipo', l: 'Tipo', t: 'select', req: true, opts: () => kv({ rechazo: 'Rechazo', desviacion: 'Desviación' }) }, { n: 'nombre', l: 'Motivo', t: 'text', req: true, max: 120 }],
    cols: [['Motivo', (r) => esc(r.nombre)], ['Tipo', (r) => (r.tipo === 'rechazo' ? pill('Rechazo', 'bad') : pill('Desviación', 'warn'))]] },
  evidencias: { label: 'Tipos de evidencia', icon: 'file-check', table: 'tipos_evidencia_prubind', cat: 'evidencias', order: 'nombre',
    fields: [{ n: 'nombre', l: 'Tipo de evidencia', t: 'text', req: true, max: 80 }], cols: [['Tipo', (r) => esc(r.nombre)]] },
  unidades: { label: 'Unidades de medida', icon: 'scale', table: 'unidades_prubind', cat: 'unidades', order: 'simbolo',
    fields: [{ n: 'simbolo', l: 'Símbolo', t: 'text', req: true, max: 20 }, { n: 'nombre', l: 'Nombre', t: 'text', req: true, max: 60 }],
    cols: [['Unidad', (r) => `<b>${esc(r.simbolo)}</b> <span class="cell-sub">${esc(r.nombre)}</span>`]] },
  puestos: { label: 'Puestos', icon: 'briefcase', table: 'puestos_prubind', cat: 'puestos', order: 'nombre',
    fields: [{ n: 'nombre', l: 'Puesto', t: 'text', req: true, max: 80 }], cols: [['Puesto', (r) => esc(r.nombre)]] },
  areas: { label: 'Áreas', icon: 'building-2', table: 'areas_prubind', cat: 'areas', order: 'nombre',
    fields: [{ n: 'nombre', l: 'Área', t: 'text', req: true, max: 80 }], cols: [['Área', (r) => esc(r.nombre)]] },
};

let root, actual, filas = [], aux = {}, filtroVal = '';

export default {
  async render(el, params) {
    root = el;
    const visibles = Object.entries(DEFS).filter(([, d]) => !d.oculto && (state.isAdmin || (d.abasto && autoridadAlguna('abastecer'))));
    actual = DEFS[params.c] && visibles.some(([k]) => k === params.c) ? params.c : visibles[0]?.[0];
    el.innerHTML = `
      <section class="page-intro"><div><span class="eyebrow">Datos maestros</span><h1>Catálogos</h1>
        <p>Registros reutilizables. Lo que tiene historial no se elimina: se desactiva y se conserva la trazabilidad.</p></div></section>
      <div class="cat-layout">
        <nav class="cat-nav" aria-label="Catálogos">${visibles.map(([k, d]) => `<button data-c="${k}" class="${k === actual ? 'active' : ''}">${icon(d.icon)}<span>${esc(d.label)}</span></button>`).join('')}</nav>
        <div class="card" id="cat-box"></div>
      </div>`;
    el.addEventListener('click', onClick);
    el.addEventListener('input', debounce((e) => { if (e.target.id === 'cat-q') pintarTabla(); }, 200));
    el.addEventListener('change', (e) => {
      if (e.target.id === 'cat-act') pintarTabla();
      if (e.target.id === 'cat-f') { filtroVal = e.target.value; cargar(); }
    });
    await cargar();
  },
  destroy() { root = null; },
};

async function cargar() {
  const d = DEFS[actual];
  const box = root.querySelector('#cat-box');
  box.innerHTML = '<div class="skeleton" style="height:120px"></div>';
  try {
    const [rows, unidades, materias, proveedores, areas, equipos, metodos, productos, tipos] = await Promise.all([
      (async () => { let q = sb.from(d.table).select('*').order(d.order, { ascending: d.order !== 'created_at' && d.order !== 'updated_at' });
        if (d.filtro && filtroVal) q = q.eq(d.filtro.n, filtroVal); return must(await q.limit(2000)).data; })(),
      getCat('unidades'), getCat('materias'), getCat('proveedores'), getCat('areas'), getCat('equipos'), getCat('metodos'), getCat('productos'), getCat('tipos'),
    ]);
    filas = rows; aux = { unidades, materias, proveedores, areas, equipos, metodos, productos, tipos };
    const fopts = d.filtro ? await d.filtro.opts() : [];
    if (d.filtro?.req && !filtroVal && fopts.length) { filtroVal = fopts[0].id; return cargar(); }
    box.innerHTML = `<div class="card-head"><div><h3>${icon(d.icon)} ${esc(d.label)}</h3><p>${filas.length} registro(s)</p></div>
        <button class="btn primary" data-cat="nuevo">${icon('plus')} Nuevo</button></div>
      <div class="toolbar">
        <div class="search">${icon('search')}<input type="search" id="cat-q" placeholder="Buscar" aria-label="Buscar"></div>
        ${d.filtro ? `<select id="cat-f" aria-label="${esc(d.filtro.l)}">${d.filtro.req ? '' : `<option value="">${esc(d.filtro.l)}: todos</option>`}${fopts.map((o) => `<option value="${esc(o.id)}" ${o.id === filtroVal ? 'selected' : ''}>${esc(o.nombre)}</option>`).join('')}</select>` : ''}
        <label class="check"><input type="checkbox" id="cat-act"> Incluir inactivos</label>
      </div>
      <div id="cat-tabla"></div>`;
    pintarTabla();
  } catch (err) { box.innerHTML = errorState(err); refreshIcons(); }
}

function pintarTabla() {
  const d = DEFS[actual];
  const q = (root.querySelector('#cat-q')?.value || '').toLowerCase();
  const inact = root.querySelector('#cat-act')?.checked;
  const pk = d.pk || 'id';
  const rows = filas.filter((r) => (inact || r.activo !== false) && (!q || JSON.stringify(r).toLowerCase().includes(q)));
  root.querySelector('#cat-tabla').innerHTML = rows.length ? `<div class="table-wrap responsive"><table class="table"><thead><tr>${d.cols.map(([l]) => `<th>${esc(l)}</th>`).join('')}<th>Estado</th><th class="actions"></th></tr></thead><tbody>
    ${rows.map((r) => `<tr class="${r.activo === false ? 'row-off' : ''}">${d.cols.map(([l, f]) => `<td data-label="${esc(l)}"><div class="td-in">${f(r, aux)}</div></td>`).join('')}
      <td data-label="Estado"><div class="td-in">${r.activo === false ? pill('Inactivo', 'gray') : pill('Activo', 'ok')}</div></td>
      <td class="actions" data-label=""><div class="td-in"><div class="row-actions">
        <button class="icon-btn" data-cat="editar" data-id="${esc(r[pk])}" title="Editar" aria-label="Editar">${icon('pencil')}</button>
        <button class="icon-btn ${r.activo === false ? 'ok' : 'warn'}" data-cat="toggle" data-id="${esc(r[pk])}" title="${r.activo === false ? 'Activar' : 'Desactivar'}" aria-label="${r.activo === false ? 'Activar' : 'Desactivar'}">${icon(r.activo === false ? 'eye' : 'eye-off')}</button>
        ${state.isAdmin && pk === 'id' ? `<button class="icon-btn bad" data-cat="eliminar" data-id="${esc(r[pk])}" title="Eliminar" aria-label="Eliminar">${icon('trash-2')}</button>` : ''}</div></div></td></tr>`).join('')}
    </tbody></table></div>` : emptyState({ ico: d.icon, title: q ? 'Sin coincidencias' : 'Catálogo vacío', text: q ? '' : 'Agregue el primer registro con "Nuevo".' });
  refreshIcons();
}

async function onClick(e) {
  const c = e.target.closest('[data-c]');
  if (c) {
    actual = c.dataset.c; filtroVal = '';
    root.querySelectorAll('[data-c]').forEach((b) => b.classList.toggle('active', b === c));
    history.replaceState(null, '', `#/catalogos?c=${actual}`);
    return cargar();
  }
  const b = e.target.closest('[data-cat]');
  if (!b) return;
  const d = DEFS[actual], pk = d.pk || 'id';
  const r = filas.find((x) => String(x[pk]) === b.dataset.id);
  try {
    if (d.formulario && ['nuevo', 'editar'].includes(b.dataset.cat)) { if (await parametroForm({ metodo: b.dataset.cat === 'editar' ? r : null })) refrescar(); }
    else if (b.dataset.cat === 'nuevo') { if (await formulario(d, null)) refrescar(); }
    else if (b.dataset.cat === 'editar') { if (await formulario(d, r)) refrescar(); }
    else if (b.dataset.cat === 'toggle') {
      mustRow(await sb.from(d.table).update({ activo: r.activo === false }).eq(pk, r[pk]).select(pk));
      toast(r.activo === false ? 'Registro activado.' : 'Registro desactivado.', 'success'); refrescar();
    } else if (b.dataset.cat === 'eliminar') {
      if (!await confirmDialog({ title: 'Eliminar registro', message: 'Solo se eliminan registros sin historial. Si está en uso, desactívelo.', confirmText: 'Eliminar', danger: true })) return;
      mustRow(await sb.from(d.table).delete().eq(pk, r[pk]).select(pk)); toast('Registro eliminado.', 'success'); refrescar();
    }
  } catch (err) { toast(err.code === '23503' ? 'El registro está en uso: desactívelo en lugar de eliminarlo.' : errMsg(err), 'error'); }
}

function refrescar() { if (DEFS[actual].cat) invalidateCat(DEFS[actual].cat); if (actual === 'parametros') invalidateCat('parametros'); cargar(); }

async function formulario(d, r) {
  const opts = {};
  for (const f of d.fields) if (f.opts) opts[f.n] = await f.opts();
  const val = (f) => (r ? r[f.n] : f.t === 'bool' ? true : f.n === d.filtro?.n ? filtroVal : f.t === 'checks' || f.t === 'array' ? [] : '');
  const campo = (f) => {
    const v = val(f), id = `cf-${f.n}`;
    const lab = `<label for="${id}">${esc(f.l)}${f.req ? ' <span class="req">*</span>' : ''}</label>`;
    const hint = f.hint ? `<small class="hint">${esc(f.hint)}</small>` : '';
    const dis = r && f.soloAlta ? 'disabled' : '';
    if (f.t === 'select') return `<div class="field ${f.full ? 'full' : ''}">${lab}<select id="${id}" name="${f.n}" ${f.req ? 'required' : ''} ${dis}>${opciones(opts[f.n], v ?? '', { vacio: f.req ? 'Selecciona…' : '—' })}</select>${hint}</div>`;
    if (f.t === 'bool') return `<label class="check ${f.full ? 'full' : ''}"><input type="checkbox" name="${f.n}" ${v ? 'checked' : ''}> ${esc(f.l)}</label>`;
    if (f.t === 'checks') return `<div class="field full"><span class="label">${esc(f.l)}</span><div class="chk-list inline">${opts[f.n].map((o) => `<label><input type="checkbox" name="${f.n}" value="${esc(o.id)}" ${(v || []).includes(o.id) ? 'checked' : ''}> ${esc(o.nombre)}</label>`).join('')}</div>${hint}</div>`;
    if (f.t === 'array') return `<div class="field ${f.full ? 'full' : ''}">${lab}<input id="${id}" name="${f.n}" value="${esc((v || []).join(', '))}">${hint}</div>`;
    const type = f.t === 'number' ? 'number' : f.t === 'date' ? 'date' : 'text';
    return `<div class="field ${f.full ? 'full' : ''}">${lab}<input id="${id}" name="${f.n}" type="${type}" ${type === 'number' ? `step="${f.int ? 1 : 'any'}"` : ''} ${f.max ? `maxlength="${f.max}"` : ''} ${f.req ? 'required' : ''} ${f.pattern ? `pattern="${f.pattern}" data-pattern-msg="Formato inválido."` : ''} ${dis} value="${esc(v ?? '')}" ${f.upper ? 'style="text-transform:uppercase"' : ''}>${hint}</div>`;
  };
  return openModal({
    title: r ? `Editar · ${d.label}` : `Nuevo · ${d.label}`, size: d.fields.length > 4 ? 'lg' : 'sm',
    body: `<div class="form-grid">${d.fields.map(campo).join('')}</div>`,
    onSubmit: async ({ form }) => {
      if (!checkForm(form, { referencia: (v, f) => (actual === 'parametros' && (f.minimo.value || f.maximo.value) && !v.trim() ? 'Cite la referencia que respalda el rango.' : '') })) return false;
      const payload = {};
      for (const f of d.fields) {
        if (r && f.soloAlta) continue;
        if (f.t === 'bool') payload[f.n] = form.elements[f.n].checked;
        else if (f.t === 'checks') payload[f.n] = [...form.querySelectorAll(`input[name="${f.n}"]:checked`)].map((i) => i.value);
        else if (f.t === 'array') payload[f.n] = form.elements[f.n].value.split(',').map((x) => x.trim()).filter(Boolean);
        else if (f.t === 'number') payload[f.n] = numOrNull(form.elements[f.n].value);
        else { const x = form.elements[f.n].value.trim(); payload[f.n] = f.upper ? x.toUpperCase() : nullIfEmpty(x); }
      }
      if (actual === 'lotes' && !r) payload.created_by = state.profile.id;
      const pk = d.pk || 'id';
      if (r) mustRow(await sb.from(d.table).update(payload).eq(pk, r[pk]).select(pk));
      else must(await sb.from(d.table).insert(payload));
      toast('Catálogo actualizado.', 'success');
    },
  });
}
