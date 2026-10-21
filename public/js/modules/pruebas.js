// =====================================================================
// Pruebas industriales: lista, registro (etapa 1) y expediente por etapas
// Registro → En proceso → Evaluaciones complementarias →
// Resultados → Recomendaciones → Dictamen → Cierre.
// Cualquier persona registra la prueba (quien primero tenga conocimiento
// de ella) con los parámetros a evaluar por área.
// =====================================================================
import {
  sb, state, esc, icon, toast, errMsg, openModal, confirmDialog, checkForm, formValues, nullIfEmpty, numOrNull, must, mustRow,
  DataTable, paged, sanitizeSearch, debounce, fmtDate, fmtDateTime, fmtQty, pill, estadoPill, prioPill, puedeEn, autoridad,
  getCat, invalidateCat, opciones, ESTADOS_PRUEBA, etapasDe, CERRADAS, ABIERTAS, PRIORIDADES, CAMPOS_REGISTRO, AREAS, AREAS_ORDEN, avatarHTML, emptyState, errorState,
  refreshIcons, todayISO, navigate, bindCounters, prefs, fmtBytes, dayStartTs, dayEndTs, ayuda, avisar,
} from '../core.js';
import { box, txt, cardHead, btn, iconBtn, aviso, vacio, accion, subirEvidencia, abrirAdjunto } from './exp_comun.js';
import { montarSelector, montarParametrosPrueba } from './exp_registro.js';
import { etapaProceso, etapaComplementarias } from './exp_ejec.js';
import { etapaResultados, etapaRecomendaciones } from './exp_eval.js';
import { etapaDictamen, etapaCierre } from './exp_dict.js';

let root, table, P = null, E = null, tabActual = null, ejecSel = null;

export default {
  async render(el, params) {
    root = el;
    if (params.id) return renderDetalle(params.id, params.tab);
    return renderLista(params);
  },
  destroy() { root = null; table = null; P = null; },
};

// Etapa en la que se encuentra la prueba ('fin' = concluida)
export const etapaDe = (estado, e = {}) => ({ registrada: 'registro', en_preparacion: 'registro', preparada: 'registro', en_ejecucion: 'proceso',
  en_evaluacion: e.eval_faltantes > 0 ? 'resultados' : 'recomendaciones', pendiente_resultados: e.eval_faltantes > 0 ? 'resultados' : 'recomendaciones',
  pendiente_dictamen: 'dictamen', requiere_repeticion: 'dictamen', aprobada: 'cierre', rechazada: 'cierre',
  cerrada_aprobada: 'fin', cerrada_rechazada: 'fin', cancelada: 'registro' }[estado] || 'registro');
const ETAPA_EVIDENCIA = { proceso: 'ejecucion', complementarias: 'ejecucion', resultados: 'evaluacion', recomendaciones: 'evaluacion', dictamen: 'dictamen', cierre: 'cierre', fin: 'cierre', registro: 'registro' };
const objetoTxt = (p) => [p.receta_nombre || p.producto_nombre, p.materia_prima_nombre,
  p.proveedor_nombre, p.equipo_nombre, p.empaque, p.proceso].filter(Boolean).join(' · ');

// ============================== LISTA ==============================
async function renderLista(params) {
  let tipos = [], usuarios = [];
  try { [tipos, usuarios] = await Promise.all([getCat('tipos'), getCat('usuarios')]); } catch (err) { root.innerHTML = errorState(err); refreshIcons(); return; }
  root.innerHTML = `
    <section class="page-intro">
      <div><span class="eyebrow">Seguimiento</span><h1>Pruebas industriales</h1>
        <p>Registro → En proceso → Evaluaciones complementarias → Resultados → Recomendaciones → Dictamen → Cierre.</p></div>
      <div class="page-actions">${btn('data-pl="csv"', 'download', 'Exportar CSV')}<button class="btn primary" data-pl="nueva">${icon('flask-conical')} Nueva prueba industrial</button></div>
    </section>
    <div class="card">
      <div class="toolbar">
        <div class="search">${icon('search')}<input type="search" id="pl-q" placeholder="Folio, cambio, receta, materia prima o equipo" aria-label="Buscar"></div>
        <select id="pl-tipo" aria-label="Tipo"><option value="">Todos los tipos</option>${tipos.map((t) => `<option value="${esc(t.codigo)}">${esc(t.nombre)}</option>`).join('')}</select>
        <select id="pl-estado" aria-label="Estado"><option value="abiertas">Abiertas</option><option value="">Todos los estados</option>
          ${Object.entries(ESTADOS_PRUEBA).filter(([k]) => !['en_preparacion', 'preparada'].includes(k)).map(([k, v]) => `<option value="${k}">${esc(v.label)}</option>`).join('')}</select>
        <select id="pl-resp" aria-label="Responsable"><option value="">Cualquier responsable</option><option value="yo">Yo</option>${usuarios.map((u) => `<option value="${esc(u.id)}">${esc(u.nombre)}</option>`).join('')}</select>
        <select id="pl-prio" aria-label="Prioridad"><option value="">Cualquier prioridad</option>${Object.entries(PRIORIDADES).map(([k, v]) => `<option value="${k}">${v.label}</option>`).join('')}</select>
        <span class="date-range"><input type="date" id="pl-desde" aria-label="Registrada desde"> a <input type="date" id="pl-hasta" aria-label="Registrada hasta"></span>
      </div>
      <div id="pl-table"></div>
    </div>`;
  const $ = (s) => root.querySelector(s);
  $('#pl-tipo').value = params.tipo || '';
  $('#pl-estado').value = params.estado ?? (prefs.get('prubind.pruebas.estado2') ?? 'abiertas');
  $('#pl-resp').value = params.resp || '';
  const consulta = (f, cols, count = true) => {
    let q = sb.from('v_pruebas_prubind').select(cols, count ? { count: 'exact' } : undefined);
    const s = sanitizeSearch(f.q);
    if (s) q = q.or(`folio.ilike.*${s}*,cambio.ilike.*${s}*,receta_nombre.ilike.*${s}*,materia_prima_nombre.ilike.*${s}*,equipo_nombre.ilike.*${s}*,empaque.ilike.*${s}*`);
    if (f.tipo) q = q.eq('tipo', f.tipo);
    if (f.estado === 'abiertas') q = q.in('estado', ABIERTAS); else if (f.estado) q = q.eq('estado', f.estado);
    const r = f.resp === 'yo' ? state.profile.id : f.resp;
    if (r) q = q.or(`registrado_por.eq.${r},responsable_inicial_id.eq.${r},responsable_ejecucion_id.eq.${r}`);
    if (f.prio) q = q.eq('prioridad', f.prio);
    if (f.desde) q = q.gte('created_at', dayStartTs(f.desde));
    if (f.hasta) q = q.lt('created_at', dayEndTs(f.hasta));
    return q;
  };
  table = new DataTable($('#pl-table'), {
    sort: { key: 'created_at', asc: false },
    baseFilters: ['estado'],
    rowClass: (p) => `row-link ${p.prioridad === 'urgente' && !CERRADAS.includes(p.estado) ? 'row-urg' : ''}`,
    columns: [
      { label: 'Folio', sort: 'folio', render: (p) => `<b class="mono">${esc(p.folio)}</b><div class="cell-sub">${esc(p.tipo_nombre)}</div>` },
      { label: 'Prueba', sort: 'cambio', render: (p) => `<div class="cell-main">${esc(p.cambio)}</div><div class="cell-sub">${esc(objetoTxt(p) || '—')}</div>` },
      { label: 'Prioridad', sort: 'prioridad', render: (p) => prioPill(p.prioridad) },
      { label: 'Responsable', render: (p) => { const otro = p.responsable_inicial_id && p.responsable_inicial_id !== p.registrado_por;
        return `<div class="user-cell">${otro ? avatarHTML(p.responsable_inicial_nombre, null, 'sm') : avatarHTML(p.registrado_por_nombre, p.registrado_por_foto, 'sm')}<div class="user-txt"><div class="cell-main">${esc(otro ? p.responsable_inicial_nombre : p.registrado_por_nombre)}</div>${otro ? `<div class="cell-sub">Registró: ${esc(p.registrado_por_nombre)}</div>` : ''}${p.responsable_ejecucion_nombre ? `<div class="cell-sub">Ejec.: ${esc(p.responsable_ejecucion_nombre)}</div>` : ''}</div></div>`; } },
      { label: 'Etapa', render: (p) => etapasMini(p) },
      { label: 'Estado', sort: 'estado', render: (p) => `${estadoPill(p.estado)}${p.ejecucion_actual > 1 ? `<div class="cell-sub">Ejecución #${p.ejecucion_actual}</div>` : ''}` },
      { label: 'Registrada', sort: 'created_at', render: (p) => `<span class="mono">${fmtDate(p.created_at.slice(0, 10))}</span>` },
    ],
    empty: { ico: 'flask-conical', title: 'Sin pruebas', text: 'Registre una prueba previamente acordada con “Nueva prueba industrial”.' },
    fetch: async ({ from, to, sort, filters: f }) => {
      const { data, count } = must(await paged(consulta(f, 'id, folio, tipo, tipo_nombre, cambio, producto_nombre, receta_nombre, receta_version, materia_prima_nombre, proveedor_nombre, equipo_nombre, empaque, proceso, prioridad, registrado_por_nombre, registrado_por_foto, responsable_ejecucion_nombre, estado, ejecucion_actual, created_at'), { from, to, sort }, [['created_at', false]]));
      return { rows: data, count };
    },
  });
  const filtros = () => ({ q: $('#pl-q').value, tipo: $('#pl-tipo').value, estado: $('#pl-estado').value, resp: $('#pl-resp').value, prio: $('#pl-prio').value, desde: $('#pl-desde').value, hasta: $('#pl-hasta').value });
  const apply = () => { prefs.set('prubind.pruebas.estado2', $('#pl-estado').value); return table.setFilters(filtros()); };
  $('#pl-q').addEventListener('input', debounce(apply, 350));
  ['#pl-tipo', '#pl-estado', '#pl-resp', '#pl-prio', '#pl-desde', '#pl-hasta'].forEach((s) => $(s).addEventListener('change', apply));
  root.addEventListener('click', async (e) => {
    if (e.target.closest('[data-pl="nueva"]')) { const id = await openRegistro(); if (id) navigate(`#/pruebas?id=${id}`); return; }
    if (e.target.closest('[data-pl="csv"]')) {
      try {
        const { data } = must(await consulta(filtros(), 'folio, tipo_nombre, cambio, receta_nombre, materia_prima_nombre, proveedor_nombre, equipo_nombre, prioridad, area_nombre, registrado_por_nombre, responsable_ejecucion_nombre, estado, ejecucion_actual, created_at, cerrada_at', false).order('created_at', { ascending: false }).limit(5000));
        exportarCSV(data);
      } catch (err) { toast(errMsg(err), 'error'); }
      return;
    }
    const tr = e.target.closest('tr.row-link');
    if (tr && !e.target.closest('a,button')) navigate(`#/pruebas?id=${tr.dataset.id}`);
  });
  await apply();
}

export function etapasMini(p) {
  const et = etapasDe(p.tipo);
  const cur = etapaDe(p.estado, { eval_faltantes: 1 });
  const n = cur === 'fin' ? et.length : et.findIndex(([k]) => k === cur);
  return `<div class="etapas-mini" title="${esc(ESTADOS_PRUEBA[p.estado]?.label)}">${et.map((_, i) => `<span class="${i < n ? 'done' : i === n ? 'cur' : ''} ${p.estado === 'cancelada' ? 'off' : ''}"></span>`).join('')}</div>`;
}

function exportarCSV(rows) {
  const cols = [['folio', 'Folio'], ['tipo_nombre', 'Tipo'], ['cambio', 'Cambio'], ['receta_nombre', 'Receta'], ['materia_prima_nombre', 'Materia prima'], ['proveedor_nombre', 'Proveedor'],
    ['equipo_nombre', 'Equipo'], ['prioridad', 'Prioridad'], ['area_nombre', 'Área'], ['registrado_por_nombre', 'Registró'], ['responsable_ejecucion_nombre', 'Responsable de ejecución'],
    ['estado', 'Estado'], ['ejecucion_actual', 'Ejecución'], ['created_at', 'Registrada'], ['cerrada_at', 'Cerrada']];
  const cel = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`;
  const out = '﻿' + [cols.map(([, l]) => cel(l)).join(','), ...rows.map((r) => cols.map(([k]) => cel(k === 'estado' ? ESTADOS_PRUEBA[r[k]]?.label : k.endsWith('_at') ? fmtDateTime(r[k]) : r[k])).join(','))].join('\r\n');
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([out], { type: 'text/csv;charset=utf-8' }));
  a.download = `pruebas-industriales-${new Date().toISOString().slice(0, 10)}.csv`;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  toast(`${rows.length} prueba(s) exportadas.`, 'success');
}

// ============================== ETAPA 1 · REGISTRO ==============================
// Datos de la prueba (folio, fecha, hora y quién registra se asignan solos),
// prioridad y los parámetros del área de quien registra.
// Devuelve el id creado, true al editar o false si se cancela
const EJEMPLO_CAMBIO = {
  producto_nuevo: 'Ej. Receta nueva de pavo con arroz',
  cambio_formulacion: 'Ej. Reducir 10 % el filete de pollo y aumentar el recorte',
  cambio_proveedor: 'Ej. Harina de arroz del proveedor alterno',
  material_empaque: 'Ej. Film Chicken Chase formato 4x2',
  cambio_proceso: 'Ej. Aumentar el tiempo de cocción 5 minutos',
};
const PRIO = {
  normal: ['Normal'],
  alta: ['Alta'],
  urgente: ['Urgente'],
};
// Catálogos que se pueden ampliar desde el propio menú
const ALTA = {
  receta_version_id: { tipo: 'receta', cat: 'versiones', opcion: 'Agregar receta nueva…', campo: 'Nombre de la receta', listo: 'Receta agregada.' },
  materia_prima_id: { tipo: 'materia_prima', cat: 'materias', opcion: 'Agregar materia prima nueva…', campo: 'Nombre de la materia prima', listo: 'Materia prima agregada.' },
  proveedor_id: { tipo: 'proveedor', cat: 'proveedores', opcion: 'Agregar proveedor nuevo…', campo: 'Nombre del proveedor', listo: 'Proveedor agregado.' },
};
const NUEVO = '__nuevo__';
// Encabezado de cada bloque del formulario
const paso = (n, titulo, sub, extra = '') => `<div class="fs-step full"><span class="fs-num">${n}</span><div><b>${esc(titulo)}</b><small>${esc(sub)}</small></div>${extra}</div>`;
const esOtro = (o) => /^otro\b/i.test(o?.nombre || '');

export async function openRegistro(p = null) {
  let c;
  try {
    const [tipos, versiones, materias, proveedores, objetivos] = await Promise.all(['tipos', 'versiones', 'materias', 'proveedores', 'objetivos'].map((n) => getCat(n)));
    c = { tipos, versiones, materias, proveedores, objetivos };
  } catch (err) { toast(errMsg(err), 'error'); return false; }
  const tiposAct = c.tipos.filter((t) => t.activo || t.codigo === p?.tipo);
  const recetasDe = (vs) => vs.filter((v) => v.estado === 'vigente' || v.id === p?.receta_version_id).sort((a, b) => (a.receta?.nombre || '').localeCompare(b.receta?.nombre || ''));
  const optsDe = {
    receta_version_id: (sel) => opciones(recetasDe(c.versiones), sel, { label: (v) => v.receta?.nombre || '—', vacio: 'Selecciona…' }),
    materia_prima_id: (sel) => opciones(c.materias.filter((m) => m.activo !== false || m.id === sel), sel),
    proveedor_id: (sel) => opciones(c.proveedores.filter((m) => m.activo !== false || m.id === sel), sel, { vacio: 'Sin proveedor' }),
  };
  const conNuevo = (campo, sel) => `${optsDe[campo](sel)}<option value="${NUEVO}">➕ ${ALTA[campo].opcion}</option>`;
  const objetivosDe = (tipo, sel) => {
    const xs = c.objetivos.filter((o) => (o.activo && (!o.tipo || o.tipo === tipo)) || o.id === sel)
      .sort((a, b) => Number(esOtro(a)) - Number(esOtro(b)) || (a.orden ?? 0) - (b.orden ?? 0));
    return opciones(xs, sel, { vacio: 'Selecciona el objetivo…' });
  };
  const ahora = new Intl.DateTimeFormat('es-MX', { dateStyle: 'long', timeStyle: 'short', timeZone: 'America/Mexico_City' }).format(new Date());
  let selector = null;
  return openModal({
    title: p ? `Editar registro ${p.folio}` : 'Nueva prueba industrial', size: 'lg', submitText: p ? 'Guardar cambios' : 'Registrar prueba',
    subtitle: p ? p.tipo_nombre : `Registra ${state.profile.nombre} · ${ahora.replace(/\.$/, '')}. El folio, la fecha y la hora se asignan al guardar.`,
    body: `<div class="form-grid">
        ${paso(1, 'Datos de la prueba', 'Qué se va a probar y para qué')}
        <div class="field full"><label for="rg-tipo">Tipo de prueba <span class="req">*</span></label>
          <select id="rg-tipo" name="tipo" required ${p ? 'disabled' : ''}>${opciones(tiposAct, p?.tipo, { value: (t) => t.codigo })}</select><small class="hint" id="rg-desc"></small></div>
        <div class="field full"><label for="rg-cam">Nombre de la prueba <span class="req">*</span> ${ayuda('Qué se va a probar, en pocas palabras.')}</label>
          <input id="rg-cam" name="cambio" required minlength="3" maxlength="500" value="${esc(p?.cambio || '')}"></div>
        <div class="field full"><label for="rg-obj">Objetivo <span class="req">*</span> ${ayuda('Qué se desea evaluar con la prueba. El catálogo de objetivos se administra en Catálogos.')}</label>
          <select id="rg-obj" name="objetivo_id" required>${objetivosDe(p?.tipo, p?.objetivo_id)}</select></div>
        <div class="field full hidden" id="rg-objd-w"><label for="rg-objd">Describa el objetivo <span class="req">*</span></label>
          <input id="rg-objd" name="objetivo_desc" maxlength="500" value="${esc(p?.objetivo_desc || '')}"></div>
        <div class="field" data-campo="receta"><label for="rg-rec">Receta <span class="req hidden" id="rg-rec-req">*</span> ${ayuda('Se usa la receta vigente. La prueba nunca modifica la receta oficial. Si no existe, elija «Agregar receta nueva».')}</label>
          <select id="rg-rec" name="receta_version_id">${conNuevo('receta_version_id', p?.receta_version_id)}</select></div>
        <div class="field" data-campo="materia_prima"><label for="rg-mp">Materia prima</label><select id="rg-mp" name="materia_prima_id">${conNuevo('materia_prima_id', p?.materia_prima_id)}</select></div>
        <div class="field" data-campo="proveedor"><label for="rg-prov">Proveedor</label><select id="rg-prov" name="proveedor_id">${conNuevo('proveedor_id', p?.proveedor_id)}</select></div>
        <div class="field" data-campo="empaque"><label for="rg-emp">Material de empaque a probar</label><input id="rg-emp" name="empaque" maxlength="200" value="${esc(p?.empaque || '')}" placeholder="Ej. Film Chicken Chase formato 4x2"></div>
        <div class="field" data-campo="proceso"><label for="rg-proc">Proceso que cambia</label><input id="rg-proc" name="proceso" maxlength="200" value="${esc(p?.proceso || '')}"></div>
        <div class="field"><label for="rg-fecha">Fecha de ejecución</label><input id="rg-fecha" name="fecha_planeada" type="date" value="${esc(p?.fecha_planeada || '')}"></div>

        ${paso(2, 'Prioridad', 'Qué tan pronto debe atenderse')}
        <div class="field full"><div class="prio-seg" role="radiogroup" aria-label="Prioridad">${Object.entries(PRIO).map(([k, [l]]) => `<label class="prio-${k}"><input type="radio" name="prioridad" value="${k}" ${k === (p?.prioridad || 'normal') ? 'checked' : ''}>
          <span><i class="pdot"></i><b>${l}</b></span></label>`).join('')}</div></div>
        <div class="field full hidden" id="rg-just-w"><label for="rg-just" id="rg-just-l">¿Por qué es alta? <span class="req">*</span></label><input id="rg-just" name="prioridad_just" maxlength="300" value="${esc(p?.prioridad_just || '')}"></div>

        ${p ? '' : `${paso(3, 'Parámetros a evaluar', 'Calidad, Producción, Seguridad y Mantenimiento; cada área define los suyos')}
        <div class="full" id="rg-params"></div>`}
      </div>`,
    onOpen: ({ form }) => {
      bindCounters(form);
      const tipoSel = () => p?.tipo || form.elements.tipo.value;
      if (!p) selector = montarSelector(form.querySelector('#rg-params'), { getTipo: tipoSel, puedeDefinir: (area) => autoridad(tipoSel(), `evaluar_${area}`) });
      const objetivo = () => {
        const o = c.objetivos.find((x) => x.id === form.elements.objetivo_id.value);
        const otro = esOtro(o);
        form.querySelector('#rg-objd-w').classList.toggle('hidden', !otro);
        form.elements.objetivo_desc.required = otro;
      };
      const sync = () => {
        const t = c.tipos.find((x) => x.codigo === tipoSel());
        const campos = t?.campos_registro || [];
        form.querySelector('#rg-desc').textContent = t?.descripcion || '';
        form.querySelectorAll('[data-campo]').forEach((w) => w.classList.toggle('hidden', !campos.includes(w.dataset.campo)));
        const recObl = t?.codigo === 'cambio_formulacion';
        form.querySelector('#rg-rec-req').classList.toggle('hidden', !recObl);
        form.elements.receta_version_id.required = recObl && campos.includes('receta');
        form.elements.cambio.placeholder = EJEMPLO_CAMBIO[t?.codigo] || 'Describa brevemente qué se va a probar';
        const actual = form.elements.objetivo_id.value;
        form.elements.objetivo_id.innerHTML = objetivosDe(t?.codigo, actual);
        objetivo();
        selector?.recargar();
      };
      const prio = () => {
        const v = form.querySelector('input[name=prioridad]:checked')?.value;
        form.querySelector('#rg-just-w').classList.toggle('hidden', v === 'normal');
        form.querySelector('#rg-just-l').firstChild.textContent = v === 'urgente' ? '¿Por qué es urgente? ' : '¿Por qué es alta? ';
      };
      form.elements.tipo.addEventListener('change', sync); sync();
      form.elements.objetivo_id.addEventListener('change', objetivo);
      form.querySelectorAll('input[name=prioridad]').forEach((r) => r.addEventListener('change', prio)); prio();
      // "Agregar … nuevo" desde el menú
      Object.keys(ALTA).forEach((campo) => {
        const sel = form.elements[campo]; let previo = sel.value;
        sel.addEventListener('focus', () => { if (sel.value !== NUEVO) previo = sel.value; });
        sel.addEventListener('change', async () => {
          if (sel.value !== NUEVO) { previo = sel.value; return; }
          const A = ALTA[campo];
          const r = await confirmDialog({ title: A.opcion.replace('…', ''), message: A.tipo === 'receta'
            ? 'Se crea la receta y queda disponible para todas las pruebas. Sus ingredientes se capturan en la formulación de la prueba o en Recetas.'
            : 'Queda guardado en el catálogo para usarlo en otras pruebas.', confirmText: 'Agregar', input: { label: A.campo, required: true, maxlength: 150 } });
          if (!r) { sel.value = previo; return; }
          try {
            const { data: id } = must(await sb.rpc('prubind_alta_rapida', { p_tipo: A.tipo, p_nombre: r.value }));
            invalidateCat(A.cat); if (campo === 'receta_version_id') invalidateCat('productos');
            c[A.cat] = await getCat(A.cat, { force: true });
            sel.innerHTML = conNuevo(campo, id); sel.value = id; previo = id;
            toast(A.listo, 'success');
          } catch (err) { toast(errMsg(err), 'error'); sel.value = previo; }
        });
      });
    },
    onSubmit: async ({ form }) => {
      const prioridad = form.querySelector('input[name=prioridad]:checked')?.value || 'normal';
      if (!checkForm(form, { prioridad_just: (v) => (prioridad !== 'normal' && !v.trim() ? 'Explique el motivo de la prioridad.' : '') })) return false;
      const v = formValues(form);
      const t = c.tipos.find((x) => x.codigo === (p?.tipo || v.tipo));
      const campo = (k, val) => ((t?.campos_registro || []).includes(k) && val !== NUEVO ? nullIfEmpty(val) : null);
      const obj = c.objetivos.find((x) => x.id === v.objetivo_id);
      const params = selector?.leer();
      const payload = {
        objetivo_id: nullIfEmpty(v.objetivo_id), objetivo_desc: esOtro(obj) ? nullIfEmpty(v.objetivo_desc) : null, cambio: v.cambio.trim(),
        prioridad, prioridad_just: prioridad === 'normal' ? null : v.prioridad_just,
        receta_version_id: campo('receta', v.receta_version_id), materia_prima_id: campo('materia_prima', v.materia_prima_id),
        proveedor_id: campo('proveedor', v.proveedor_id), empaque: campo('empaque', v.empaque), proceso: campo('proceso', v.proceso),
        fecha_planeada: nullIfEmpty(v.fecha_planeada),
      };
      if (p) { mustRow(await sb.from('pruebas_prubind').update(payload).eq('id', p.id).select('id')); toast('Registro actualizado.', 'success'); return true; }
      const { data } = must(await sb.from('pruebas_prubind').insert({ ...payload, tipo: v.tipo, registrado_por: state.profile.id }).select('id, folio').single());
      avisar('nueva_prueba', data.id);
      // Parámetros del área de quien registra
      try {
        if (params.ids.length) must(await sb.rpc('prubind_definir_parametros', { p_prueba: data.id, p_agregar: params.ids, p_quitar: [] }));
      } catch (err) { toast(`Prueba ${data.folio} registrada, pero: ${errMsg(err)}. Revise los parámetros en el expediente.`, 'warning', 8000); return data.id; }
      toast(`Prueba registrada con folio ${data.folio}.`, 'success');
      return data.id;
    },
  });
}


// ============================== EXPEDIENTE ==============================
async function cargar(id) {
  const [p, e] = await Promise.all([
    sb.from('v_pruebas_prubind').select('*').eq('id', id).maybeSingle(),
    sb.rpc('prubind_eval_estado', { p_prueba: id }),
  ]);
  if (p.error) throw p.error;
  if (e.error) throw e.error;
  return [p.data, e.data];
}

async function renderDetalle(id, tab) {
  root.innerHTML = '<div class="card"><div class="skeleton" style="height:28px;width:40%"></div><div class="skeleton" style="height:16px;margin-top:12px"></div></div>';
  try { [P, E] = await cargar(id); } catch (err) { root.innerHTML = errorState(err); refreshIcons(); return; }
  if (!root) return;
  if (!P) {
    root.innerHTML = `<div class="card">${emptyState({ ico: 'search-x', title: 'Prueba no encontrada', text: 'Pudo haber sido eliminada o no tiene acceso.', action: `<a class="btn secondary" href="#/pruebas">${icon('arrow-left')} Volver a pruebas</a>` })}</div>`;
    refreshIcons(); return;
  }
  // Pestañas de versiones anteriores
  const ALIAS_TAB = { preparacion: 'registro', ejecucion: 'proceso', evaluacion: 'resultados' };
  const actual = etapaDe(P.estado, E);
  tabActual = ALIAS_TAB[tab] || tab || (actual === 'fin' ? 'cierre' : actual);
  ejecSel = null;
  pintar();
  root.addEventListener('click', onClick);
  await cargarTab();
}

function pintar() {
  const et = etapasDe(P.tipo);
  const cur = etapaDe(P.estado, E);
  const n = cur === 'fin' ? et.length : et.findIndex(([k]) => k === cur);
  const tabs = [...et, ['seguimiento', 'Seguimiento', 'messages-square'], ['evidencia', 'Evidencia', 'paperclip']];
  root.innerHTML = `
    <a class="back-link" href="#/pruebas">${icon('arrow-left')} Pruebas</a>
    <section class="prueba-head card">
      <div class="ph-top">
        <div class="ph-title">
          <span class="eyebrow">${esc(P.folio)} · ${esc(P.tipo_nombre)}${P.ejecucion_actual > 1 ? ` · ejecución #${P.ejecucion_actual}` : ''}</span>
          <h1>${esc(P.cambio)}</h1>
          <p>${esc(objetoTxt(P) || 'Sin objeto especificado')} · Registró ${esc(P.registrado_por_nombre)} el ${fmtDateTime(P.created_at)}</p>
        </div>
        <div class="ph-estado">${estadoPill(P.estado)} ${prioPill(P.prioridad)}</div>
      </div>
      <ol class="stepper ${P.estado === 'cancelada' ? 'is-cancelled' : ''}" aria-label="Etapas de la prueba">${et.map(([k, l], i) => {
        const done = i < n; const ultima = i === et.length - 1;
        const cls = done ? `done ${ultima && P.estado === 'cerrada_rechazada' ? 'rechazada' : ultima && P.estado === 'cerrada_aprobada' ? 'aprobada' : ''}` : i === n ? 'current' : '';
        return `<li class="${cls}"><button type="button" class="st-dot" data-tab="${k}" aria-label="${esc(l)}">${done ? icon('check') : i + 1}</button><span class="st-lbl">${esc(l)}</span></li>`;
      }).join('')}</ol>
      ${P.estado === 'cancelada' ? aviso(`<b>Prueba cancelada</b> por ${esc(P.cancelado_por_nombre || '—')} el ${fmtDateTime(P.cancelado_at)}: ${esc(P.motivo_cancelacion)}`, 'warn', 'ban') : ''}
      ${siguientePaso()}
      <div class="ph-actions">${accionesHTML()}</div>
    </section>
    <div class="tabs mt" role="tablist">${tabs.map(([k, l, ic]) => `<button role="tab" data-tab="${k}" class="${k === tabActual ? 'active' : ''}" aria-selected="${k === tabActual}">${icon(ic)} ${esc(l)}</button>`).join('')}</div>
    <div id="pd-pane"></div>`;
  refreshIcons();
}

// Qué falta y a quién le corresponde
function siguientePaso() {
  const e = P.estado;
  // Áreas cuyo responsable (usted) aún no define sus parámetros ni indicó que no tiene nada que evaluar
  const sinPar = E.sin_parametros || [];
  const porDefinir = AREAS_ORDEN.filter((a) => !(E.areas || []).includes(a) && !sinPar.includes(a) && autoridad(P.tipo, `evaluar_${a}`));
  const definir = porDefinir.length
    ? [`Definir los parámetros de ${porDefinir.map((a) => AREAS[a].label).join(' y ')} o indicar que su área no tiene nada que evaluar (pestaña Registro).`, true] : null;
  const registro = puedeEn(P, 'preparar')
    ? ['Iniciar la prueba cuando esté lista. Las áreas que aún no definen sus parámetros pueden agregarlos durante la prueba.', true]
    : definir || [`Esperando a que ${P.registrado_por_nombre || 'quien registró la prueba'} la inicie.`, false];
  const misAreas = AREAS_ORDEN.filter((a) => autoridad(P.tipo, `evaluar_${a}`) || autoridad(P.tipo, `capturar_${a}`));
  const proceso = definir || [misAreas.length
    ? 'Registrar los parámetros de su área (para toda la prueba o por batch). Cuando su área termine puede evaluar y dar su veredicto, sin esperar a las demás.'
    : 'Cada área registra sus parámetros, los evalúa y da su veredicto. Al terminar, quien registró la prueba la da por terminada.', misAreas.length > 0 || puedeEn(P, 'preparar')];
  const evalua = E.eval_faltantes > 0
    ? [`Cada área evalúa sus parámetros: Cumple, No cumple o No se pudo determinar (${E.eval_faltantes} por evaluar).`, puedeEn(P, 'evaluar')]
    : [`Cada área que participó da su veredicto y recomendación (${E.recom_faltantes} pendiente(s)); después pasa sola a dictamen.`, puedeEn(P, 'evaluar')];
  const msgs = {
    registrada: definir && !puedeEn(P, 'preparar') ? definir : registro, en_preparacion: registro, preparada: registro, en_ejecucion: proceso,
    en_evaluacion: evalua, pendiente_resultados: evalua,
    pendiente_dictamen: ['Alta Dirección revisa los resultados y los veredictos de las áreas y emite el dictamen; si lo aprueba, queda autorizado implementar el cambio.', autoridad(P.tipo, 'dictaminar')],
    requiere_repeticion: ['Iniciar una nueva ejecución vinculada a este registro.', puedeEn(P, 'preparar') || autoridad(P.tipo, 'dictaminar')],
    aprobada: ['Cerrar la prueba (Gerencia de Procesos y Mejora Continua). El cambio ya quedó autorizado en el dictamen.', autoridad(P.tipo, 'cerrar')],
    rechazada: ['Cerrar la prueba (Gerencia de Procesos y Mejora Continua).', autoridad(P.tipo, 'cerrar')],
  }[e];
  if (!msgs) return '';
  return `<div class="next-step ${msgs[1] ? 'mine' : ''}">${icon(msgs[1] ? 'hand' : 'navigation')}<span><b>${msgs[1] ? 'Te corresponde:' : 'Siguiente paso:'}</b> ${esc(msgs[0])}</span></div>`;
}

function accionesHTML() {
  const e = P.estado, b = [];
  const B = (a, ico, t, cls = 'secondary') => b.push(`<button class="btn ${cls}" data-pa="${a}">${icon(ico)} ${esc(t)}</button>`);
  if (['registrada', 'en_preparacion', 'preparada'].includes(e) && puedeEn(P, 'preparar')) { B('iniciar', 'play', 'Iniciar prueba', 'primary btn-iniciar'); B('editar', 'pencil', 'Editar registro'); }
  if (e === 'en_ejecucion' && (puedeEn(P, 'preparar') || puedeEn(P, 'ejecutar'))) B('terminar', 'flag', 'Terminar prueba');
  if (e === 'requiere_repeticion' && (puedeEn(P, 'preparar') || autoridad(P.tipo, 'dictaminar'))) B('nueva_ejecucion', 'repeat', 'Iniciar nueva ejecución', 'primary');
  b.push(`<button class="btn secondary" data-pa="imprimir">${icon('printer')} Expediente</button>`);
  if (!CERRADAS.includes(e) && puedeEn(P, 'cancelar')) B('cancelar', 'ban', 'Cancelar prueba', 'ghost danger-text');
  if (e === 'registrada' && (P.registrado_por === state.profile.id || state.isAdmin)) B('eliminar', 'trash-2', 'Eliminar', 'ghost danger-text');
  return b.join('');
}

async function refrescar(tab = tabActual, ejecucion = null) {
  if (!P || !root) return;
  document.dispatchEvent(new Event('prubind:cambio'));
  try {
    const [np, ne] = await cargar(P.id);
    if (!root) return;
    if (!np) { navigate('#/pruebas'); return; }
    P = np; E = ne; tabActual = tab; ejecSel = ejecucion;
    pintar();
    await cargarTab();
  } catch (err) { toast(errMsg(err), 'error'); }
}

async function cargarTab() {
  const viejo = root?.querySelector('#pd-pane');
  if (!viejo) return;
  // En pantallas angostas las pestañas se desplazan: centrar la activa sin mover la página
  const tb = root.querySelector('.tabs'), act = tb?.querySelector('.active');
  if (tb && act && tb.scrollWidth > tb.clientWidth) {
    const r = act.getBoundingClientRect(), rt = tb.getBoundingClientRect();
    tb.scrollLeft += r.left - rt.left - (rt.width - r.width) / 2;
  }
  // Contenedor nuevo: los listeners de la pestaña anterior no se acumulan
  const pane = viejo.cloneNode(false); viejo.replaceWith(pane);
  pane.innerHTML = '<div class="card"><div class="skeleton" style="height:120px"></div></div>';
  const tab = tabActual;
  const ctx = { P, E, ejecucion: ejecSel, refrescar };
  try {
    const f = { registro: tabRegistro, proceso: etapaProceso, complementarias: etapaComplementarias, resultados: etapaResultados,
      recomendaciones: etapaRecomendaciones, dictamen: etapaDictamen, cierre: etapaCierre, seguimiento: tabSeguimiento, evidencia: tabEvidencia }[tab] || tabRegistro;
    await f(pane, ctx);
    bindCounters(pane);
  } catch (err) {
    console.error(err);
    if (root && tab === tabActual) pane.innerHTML = `<div class="card">${errorState(err).replace('data-action="retry"', 'data-retry')}</div>`;
  }
  refreshIcons();
}

async function onClick(e) {
  const t = e.target.closest('[data-tab]');
  if (t) {
    tabActual = t.dataset.tab; ejecSel = null;
    root.querySelectorAll('.tabs [data-tab]').forEach((b) => { b.classList.toggle('active', b.dataset.tab === tabActual); b.setAttribute('aria-selected', String(b.dataset.tab === tabActual)); });
    history.replaceState(null, '', `#/pruebas?id=${P.id}&tab=${tabActual}`);
    cargarTab(); return;
  }
  if (e.target.closest('[data-retry]')) { cargarTab(); return; }
  const a = e.target.closest('[data-pa]');
  if (!a) return;
  try {
    switch (a.dataset.pa) {
      case 'editar': if (await openRegistro(P)) refrescar(); return;
      case 'iniciar': {
        const sinPar = E.sin_parametros || [];
        const lineas = AREAS_ORDEN.map((a) => `<li>${icon(AREAS[a].ico)} <b>${esc(AREAS[a].label)}:</b> ${(E.areas || []).includes(a) ? 'parámetros definidos'
          : sinPar.includes(a) ? 'sin nada que evaluar' : 'aún sin parámetros (puede agregarlos durante la prueba)'}</li>`).join('');
        if (!await confirmDialog({ title: `Iniciar ${P.folio}`, html: `<p>La prueba pasará a <b>En proceso</b> y se avisará a las áreas para que registren sus parámetros.</p><ul class="ini-areas">${lineas}</ul>`, confirmText: 'Iniciar prueba' })) return;
        await accion(P.id, 'iniciar'); toast('Prueba iniciada: las áreas ya pueden registrar sus parámetros.', 'success'); refrescar('proceso'); return;
      }
      case 'terminar': {
        if (!await confirmDialog({ title: `Terminar ${P.folio}`, message: 'Ya no se agregarán batches. Las áreas que registraron datos completan su evaluación y su veredicto (los análisis de laboratorio pendientes se pueden completar después); las que no registraron nada no participan.', confirmText: 'Terminar prueba' })) return;
        const est = await accion(P.id, 'terminar_ejecucion');
        toast(est === 'pendiente_dictamen' ? 'Prueba terminada: todas las áreas ya habían evaluado, pasó al dictamen.' : 'Prueba terminada: continúa la evaluación por área.', 'success');
        refrescar(est === 'pendiente_dictamen' ? 'dictamen' : 'resultados'); return;
      }
      case 'nueva_ejecucion':
        if (!await confirmDialog({ title: 'Nueva ejecución', message: `Se abrirá la ejecución #${P.ejecucion_actual + 1} vinculada a ${P.folio}, con los mismos parámetros a evaluar. El historial anterior se conserva.`, confirmText: 'Iniciar' })) return;
        await accion(P.id, 'nueva_ejecucion'); toast('Nueva ejecución abierta.', 'success'); refrescar('proceso'); return;
      case 'imprimir': tabActual = 'cierre'; refrescar('cierre'); return;
      case 'cancelar': {
        const r = await confirmDialog({ title: `Cancelar ${P.folio}`, message: 'La prueba quedará cancelada y no podrá modificarse. Su información se conserva.', confirmText: 'Cancelar prueba', danger: true,
          input: { label: 'Motivo de la cancelación', required: true, maxlength: 500 } });
        if (!r) return;
        await accion(P.id, 'cancelar', { texto: r.value }); toast('Prueba cancelada.', 'success'); refrescar(); return;
      }
      case 'eliminar':
        if (!await confirmDialog({ title: `Eliminar ${P.folio}`, message: 'Se eliminará el registro. Esta acción no se puede deshacer.', confirmText: 'Eliminar', danger: true })) return;
        mustRow(await sb.from('pruebas_prubind').delete().eq('id', P.id).select('id'));
        toast('Registro eliminado.', 'success'); navigate('#/pruebas'); return;
      default: return;
    }
  } catch (err) { toast(errMsg(err), 'error'); }
}

// ---------- Pestaña Registro ----------
async function tabRegistro(pane) {
  const editable = ['registrada', 'en_preparacion', 'preparada'].includes(P.estado) && puedeEn(P, 'preparar');
  // Puesto de quien registró (para la tarjeta de la persona)
  let puesto = '';
  try {
    const [us, ps] = await Promise.all([getCat('usuarios'), getCat('puestos')]);
    const u = us.find((x) => x.id === P.registrado_por);
    puesto = ps.find((x) => x.id === u?.puesto_id)?.nombre || '';
  } catch { /* sin puesto */ }
  const ICO = { producto: 'cooking-pot', receta: 'cooking-pot', materia_prima: 'wheat', proveedor: 'truck', empaque: 'package', proceso: 'cog', equipo: 'wrench' };
  const VAL = { producto: P.receta_nombre || P.producto_nombre, receta: P.receta_nombre, materia_prima: P.materia_prima_nombre,
    proveedor: P.proveedor_nombre, empaque: P.empaque, proceso: P.proceso, equipo: P.equipo_nombre };
  const dato = (ico, l, v) => `<div class="rg-dato"><span class="rd-ico">${icon(ico)}</span><div><small>${esc(l)}</small><b>${v}</b></div></div>`;
  const hoy = todayISO();
  const fecha = P.fecha_planeada ? `${fmtDate(P.fecha_planeada)}${P.fecha_planeada === hoy ? ' <em class="rd-hoy">Hoy</em>' : ''}` : '<span class="cell-sub">Sin fecha</span>';
  pane.innerHTML = `<div class="card rg-ficha">
      <div class="rg-main">
        <div class="rg-top"><span class="pc-folio mono">${esc(P.folio)}</span><span class="rg-tipo">${esc(P.tipo_nombre)}</span>
          ${editable ? `<span class="rg-edit">${btn('data-pa="editar"', 'pencil', 'Editar', 'ghost sm')}</span>` : ''}</div>
        <h3 class="rg-nombre">${esc(P.cambio)}</h3>
        <p class="rg-obj">${icon('target')}<span><small>Objetivo</small>${esc(P.objetivo_desc || P.objetivo_nombre || 'Sin objetivo')}${P.objetivo_desc && P.objetivo_nombre && !/^otro/i.test(P.objetivo_nombre) ? ` · <span class="cell-sub">${esc(P.objetivo_nombre)}</span>` : ''}</span></p>
        <div class="rg-datos">
          ${dato('calendar', 'Fecha de ejecución', fecha)}
          ${dato('flag', 'Prioridad', `${prioPill(P.prioridad)}${P.prioridad_just ? `<span class="rd-sub">${esc(P.prioridad_just)}</span>` : ''}`)}
          ${(P.campos_registro || []).filter((k) => VAL[k]).map((k) => dato(ICO[k] || 'circle', CAMPOS_REGISTRO[k], esc(VAL[k]))).join('')}
        </div>
      </div>
      <aside class="rg-persona">
        <small>Registró la prueba</small>
        ${avatarHTML(P.registrado_por_nombre, P.registrado_por_foto, 'lg')}
        <b>${esc(P.registrado_por_nombre)}</b>
        ${puesto ? `<span class="rp-puesto">${esc(puesto)}</span>` : ''}
        <span class="rp-fecha">${icon('clock')} ${fmtDateTime(P.created_at)}</span>
      </aside>
    </div>
    <div id="rg-par"></div>`;
  refreshIcons();
  const recargar = () => refrescar('registro');
  await montarParametrosPrueba(pane.querySelector('#rg-par'), P, recargar);
}

// ---------- Seguimiento ----------
const SEG_ICO = { nota: 'message-square', estado: 'flag', sistema: 'cpu' };
async function tabSeguimiento(pane) {
  const { data, error } = await sb.from('v_seguimiento_prubind').select('id, tipo, texto, created_at, usuario, foto_url').eq('prueba_id', P.id)
    .order('created_at', { ascending: false }).order('id', { ascending: false }).limit(400);
  if (error) throw error;
  pane.innerHTML = `<div class="card">${cardHead('Seguimiento', 'Notas del equipo y eventos registrados automáticamente (usuario, fecha y hora).')}
    <form class="note-form" id="seg-form" novalidate>
      <div class="field" style="margin:0"><label for="seg-txt" class="sr-only">Nueva nota</label>
        <textarea id="seg-txt" name="texto" maxlength="2000" rows="2" required placeholder="Nota, acuerdo u observación…" data-counter></textarea></div>
      <button class="btn primary" type="submit">${icon('send')} Agregar nota</button></form>
    ${data.length ? `<ol class="timeline">${data.map((s) => `<li class="tl-${s.tipo}"><span class="tl-ico">${icon(SEG_ICO[s.tipo] || 'dot')}</span>
      <div class="tl-body"><div class="tl-head">${s.tipo === 'nota' ? avatarHTML(s.usuario, s.foto_url, 'xs') : ''}<b>${esc(s.usuario || 'Sistema')}</b><span>${fmtDateTime(s.created_at)}</span></div><p>${esc(s.texto)}</p></div></li>`).join('')}</ol>`
      : vacio('Sin seguimiento.')}</div>`;
  refreshIcons();
  pane.querySelector('#seg-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const f = e.target;
    if (!checkForm(f)) return;
    const b = f.querySelector('button[type=submit]'); if (b.disabled) return; b.disabled = true;
    try { must(await sb.from('seguimiento_prubind').insert({ prueba_id: P.id, texto: f.elements.texto.value.trim(), tipo: 'nota' })); toast('Nota agregada.', 'success'); refrescar('seguimiento'); }
    catch (err) { toast(errMsg(err), 'error'); b.disabled = false; }
  });
}

// ---------- Evidencia ----------
const ETAPA_TXT = { registro: 'Registro', preparacion: 'Preparación', ejecucion: 'Ejecución', evaluacion: 'Evaluación', dictamen: 'Dictamen', cierre: 'Cierre' };
async function tabEvidencia(pane) {
  const { data, error } = await sb.from('adjuntos_prubind')
    .select('*, subio:usuarios_prubind!adjuntos_prubind_subido_por_fkey(nombre), tipo:tipos_evidencia_prubind(nombre), resultado:resultados_prubind(metodo:metodos_prubind(nombre)), batch:batches_prubind(numero)')
    .eq('prueba_id', P.id).order('created_at', { ascending: false });
  if (error) throw error;
  const cerrada = ['cerrada_aprobada', 'cerrada_rechazada'].includes(P.estado);
  pane.innerHTML = `<div class="card">${cardHead('Evidencia documental', 'Reportes de laboratorio, fotografías, fichas técnicas, certificados…', btn('data-adj="subir"', 'upload', 'Adjuntar evidencia', 'primary'))}
    ${data.length ? `<div class="list">${data.map((a) => `<div class="list-item">
        <span class="file-ico">${icon(/^image\//.test(a.mime || '') ? 'image' : /pdf/.test(a.mime || '') ? 'file-text' : /sheet|excel|csv/.test(a.mime || '') ? 'file-spreadsheet' : 'file')}</span>
        <div class="li-main"><b>${esc(a.nombre)}</b><span>${esc([a.tipo?.nombre, a.etapa && ETAPA_TXT[a.etapa], a.resultado?.metodo?.nombre && `Resultado: ${a.resultado.metodo.nombre}`, a.batch && `Batch #${a.batch.numero}`, a.descripcion, fmtBytes(a.tamano), a.subio?.nombre, fmtDateTime(a.created_at)].filter(Boolean).join(' · '))}</span></div>
        <div class="row-actions">${iconBtn(`data-adj="abrir" data-ruta="${esc(a.ruta)}"`, 'external-link', 'Abrir')}
          ${!cerrada && (state.isAdmin || a.subido_por === state.profile.id) ? iconBtn(`data-adj="eliminar" data-id="${esc(a.id)}" data-ruta="${esc(a.ruta)}"`, 'trash-2', 'Eliminar', 'bad') : ''}</div></div>`).join('')}</div>`
      : vacio('Sin evidencia adjunta.')}</div>`;
  refreshIcons();
  pane.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-adj]');
    if (!b) return;
    try {
      if (b.dataset.adj === 'subir') { if (await subirEvidencia(P, { etapa: ETAPA_EVIDENCIA[etapaDe(P.estado, E)] })) refrescar('evidencia'); }
      else if (b.dataset.adj === 'abrir') await abrirAdjunto(b.dataset.ruta);
      else if (b.dataset.adj === 'eliminar') {
        if (!await confirmDialog({ title: 'Eliminar evidencia', message: 'El archivo se eliminará definitivamente.', confirmText: 'Eliminar', danger: true })) return;
        mustRow(await sb.from('adjuntos_prubind').delete().eq('id', b.dataset.id).select('id'));
        await sb.storage.from('adjuntos_prubind').remove([b.dataset.ruta]).catch(() => {});
        toast('Evidencia eliminada.', 'success'); refrescar('evidencia');
      }
    } catch (err) { toast(errMsg(err), 'error'); }
  });
}
