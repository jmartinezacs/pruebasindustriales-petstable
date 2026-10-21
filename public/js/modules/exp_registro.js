// =====================================================================
// Etapa 1 · Registro: parámetros a evaluar por área y formulación.
// Cada área define sus parámetros (o indica que no tiene nada que evaluar)
// antes de iniciar o durante la prueba. Los parámetros de Calidad son casi
// siempre los mismos; los de Producción y Mantenimiento cambian según la
// prueba, por eso se pueden agregar (y quedan guardados en el catálogo).
// =====================================================================
import {
  sb, state, esc, icon, toast, errMsg, openModal, confirmDialog, checkForm, formValues, nullIfEmpty, numOrNull, must, mustRow,
  getCat, invalidateCat, opciones, unidadTxt, fmtQty, pill, puedeEn, puedeArea, refreshIcons, ayuda, autoridadAlguna,
  AREAS, AREAS_ORDEN,
} from '../core.js';
import { cardHead, btn, iconBtn, aviso, vacio, accion, criterioTxt } from './exp_comun.js';

// Los parámetros se definen o se agregan mientras la prueba no termina
const ABIERTA = ['registrada', 'en_preparacion', 'preparada', 'en_ejecucion'];

// Cómo se mide un parámetro (texto corto)
export const medidaTxt = (m, unidades) => (m.tipo_resultado === 'numerico' || m.tipo_resultado === 'diluciones'
  ? (unidadTxt(unidades, m.unidad_id) || 'valor') : m.tipo_resultado === 'presencia' ? 'ausencia / presencia' : 'conforme / no conforme');

export async function plantillaDe(tipo) {
  const { data, error } = await sb.from('plantilla_evaluacion_prubind').select('metodo_id, obligatorio, nivel, orden').eq('tipo', tipo).eq('activo', true).order('orden');
  if (error) throw error;
  return data;
}

// ---------- Formulario de parámetro (catálogo y "Agregar parámetro" en una prueba) ----------
// Solo lo indispensable: nombre, área, cómo se cuantifica y unidad. El código se asigna solo.
// En una prueba (area fija): si el nombre ya está en el catálogo del área se usa ese; si no, se crea
// (solo el responsable del área). En el catálogo (metodo = editar) se actualiza el registro.
// Los parámetros "conteo por diluciones" cuentan como cuantitativos y "ausencia / presencia" como
// cualitativos; si no se cambia el tipo, conservan su forma de captura.
const CUANTI = ['numerico', 'diluciones'];
export async function parametroForm({ area = null, tipo = null, excluir = [], metodo = null } = {}) {
  const [metodos, unidades] = await Promise.all([getCat('metodos'), getCat('unidades', { activos: true })]);
  const ya = new Set(excluir);
  const enPrueba = !!area && !metodo;
  const norm = (s) => String(s || '').trim().toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
  const areaDe = (form) => area || form.elements.area?.value || '';
  const existente = (form) => enPrueba && metodos.find((m) => m.area === areaDe(form) && m.activo !== false && norm(m.nombre) === norm(form.elements.nombre.value));
  const disponibles = enPrueba ? metodos.filter((m) => m.activo !== false && m.area === area && !ya.has(m.id)) : [];
  const tipoIni = metodo ? (CUANTI.includes(metodo.tipo_resultado) ? 'numerico' : 'opcion') : 'numerico';
  // Áreas que puede elegir: las que evalúa (el administrador, todas)
  const areasOk = AREAS_ORDEN.filter((a) => state.isAdmin || autoridadAlguna(`evaluar_${a}`));
  return openModal({
    title: metodo ? 'Editar parámetro' : `Nuevo parámetro${area ? ` · ${AREAS[area].label}` : ''}`, size: 'sm', submitText: metodo ? 'Guardar' : 'Agregar',
    body: `${metodo ? `<p class="hint">Código: <b class="mono">${esc(metodo.codigo)}</b> (se asigna solo)</p>` : ''}
      <div class="field"><label for="pf-n">Nombre del parámetro <span class="req">*</span></label>
        <input id="pf-n" name="nombre" maxlength="150" required ${enPrueba ? 'list="pf-lista"' : ''} autocomplete="off" placeholder="Ej. Tiempo de enfriamiento" value="${esc(metodo?.nombre || '')}">
        ${enPrueba ? `<datalist id="pf-lista">${disponibles.map((m) => `<option value="${esc(m.nombre)}"></option>`).join('')}</datalist>` : ''}
        <small class="hint" id="pf-estado"></small></div>
      ${area ? '' : `<div class="field"><label for="pf-a">Área <span class="req">*</span></label><select id="pf-a" name="area" required>
        ${opciones(areasOk.map((a) => ({ id: a, nombre: AREAS[a].label })), metodo?.area || (areasOk.length === 1 ? areasOk[0] : ''), { vacio: 'Selecciona…' })}</select></div>`}
      <div id="pf-nuevo">
        <div class="field"><span class="label">¿Cómo se cuantifica? <span class="req">*</span></span>
          <div class="seg" role="radiogroup">
            <label class="seg-opt"><input type="radio" name="tipo" value="numerico" ${tipoIni === 'numerico' ? 'checked' : ''}><span>Cuantitativo (valor)</span></label>
            <label class="seg-opt"><input type="radio" name="tipo" value="opcion" ${tipoIni === 'opcion' ? 'checked' : ''}><span>Cualitativo (conforme / no conforme)</span></label></div></div>
        <div class="field" id="pf-u-w"><label for="pf-u">Unidad ${ayuda('Por ejemplo %, °C, min, kg. Déjela vacía si el valor no lleva unidad.')}</label>
          <select id="pf-u" name="unidad">${opciones(unidades, metodo?.unidad_id || null, { label: (u) => `${u.simbolo} · ${u.nombre}`, vacio: 'Sin unidad' })}</select></div>
      </div>`,
    onOpen: ({ form }) => {
      const sync = () => {
        const ex = existente(form);
        form.querySelector('#pf-nuevo').classList.toggle('hidden', !!ex);
        const nom = form.elements.nombre.value.trim();
        form.querySelector('#pf-estado').innerHTML = !enPrueba ? '' : !nom ? 'Si ya existe en el catálogo aparecerá como sugerencia.'
          : ex && ya.has(ex.id) ? `${icon('info')} Ya está en esta prueba.`
            : ex ? `${icon('check')} Ya existe en el catálogo (${esc(medidaTxt(ex, unidades))}); se agrega a la prueba.`
              : `${icon('sparkles')} Parámetro nuevo: se guarda en el catálogo de ${esc(AREAS[area].label)}.`;
        form.querySelector('#pf-u-w').classList.toggle('hidden', form.querySelector('input[name=tipo]:checked')?.value !== 'numerico');
        refreshIcons();
      };
      form.addEventListener('input', sync); form.addEventListener('change', sync); sync();
    },
    onSubmit: async ({ form, setError }) => {
      const v = formValues(form);
      if (!checkForm(form, { nombre: (x) => (x.trim().length < 2 ? 'Escriba el nombre del parámetro.' : '') })) return false;
      const ar = areaDe(form);
      const tipoRes = form.querySelector('input[name=tipo]:checked')?.value || 'numerico';
      const unidad = tipoRes === 'numerico' ? nullIfEmpty(v.unidad) : null;
      if (metodo) {
        // Sin cambio de tipo se conserva la forma de captura (diluciones / ausencia-presencia)
        const mismo = (CUANTI.includes(metodo.tipo_resultado) ? 'numerico' : 'opcion') === tipoRes;
        const payload = { nombre: v.nombre.trim(), area: ar, unidad_id: unidad };
        if (!mismo) Object.assign(payload, { tipo_resultado: tipoRes, opciones: tipoRes === 'opcion' ? ['conforme', 'no_conforme', 'no_aplica'] : [], diluciones: [] });
        mustRow(await sb.from('metodos_prubind').update(payload).eq('id', metodo.id).select('id'));
        invalidateCat('metodos');
        toast('Parámetro actualizado.', 'success');
        return metodo.id;
      }
      const ex = existente(form);
      if (ex && ya.has(ex.id)) { setError('Ese parámetro ya está en esta prueba.'); return false; }
      if (ex) return ex.id;
      const { data } = must(await sb.rpc('prubind_nuevo_parametro', { p_nombre: v.nombre.trim(), p_area: ar, p_tipo_resultado: tipoRes,
        p_unidad: unidad, p_tipo_prueba: tipo }));
      invalidateCat('metodos');
      toast('Parámetro guardado en el catálogo.', 'success');
      return data;
    },
  });
}

// ---------- Selector de parámetros en el formulario de registro ----------
// Cada quien elige solo los parámetros de SU área (Jefe de Calidad → Calidad,
// Gerente de Producción → Producción, etc.). Las demás áreas los definen
// después desde el expediente. Quien registra indica si la prueba involucra
// Seguridad o Mantenimiento.
// Devuelve { recargar(), leer() → { ids, involucradas } }.
export function montarSelector(cont, { getTipo, puedeDefinir }) {
  let tipo = null, metodos = [], unidades = [], plantilla = [];
  const extra = {};            // ids agregados a mano, por área
  const marcados = new Map();  // estado de cada casilla (se conserva al repintar)
  const activas = new Set();   // áreas opcionales involucradas

  const pintar = () => {
    const met = (id) => metodos.find((m) => m.id === id);
    const fila = (m, def) => {
      const on = marcados.has(m.id) ? marcados.get(m.id) : def;
      return `<label class="chk-param"><input type="checkbox" value="${esc(m.id)}" ${on ? 'checked' : ''}>
        <span>${esc(m.nombre)} <span class="cell-sub">(${esc(medidaTxt(m, unidades))})</span></span></label>`;
    };
    cont.innerHTML = AREAS_ORDEN.map((area) => {
      const A = AREAS[area];
      const involucrada = true;
      const propia = puedeDefinir(area);
      const cabeza = `<div class="area-head">${icon(A.ico)}<div><b>${esc(A.label)}</b><span>${esc(A.desc)}</span></div>
        </div>`;
      const toggle = '';
      if (!propia) {
        return `<div class="area-block ${involucrada ? '' : 'off'}" data-area="${area}">${cabeza}${toggle}
          ${involucrada ? `<p class="hint area-nota">${icon('info')} ${esc(A.label)} define sus propios parámetros desde la prueba, una vez registrada.</p>` : ''}</div>`;
      }
      const base = plantilla.map((pt) => ({ m: met(pt.metodo_id), def: false })).filter((x) => x.m && x.m.activo !== false && x.m.area === area);
      (extra[area] || []).forEach((id) => { if (!base.some((x) => x.m.id === id) && met(id)) base.push({ m: met(id), def: true }); });
      const proceso = base;
      return `<div class="area-block propia ${involucrada ? '' : 'off'}" data-area="${area}">${cabeza}${toggle}
        <div class="area-list ${involucrada ? '' : 'hidden'}">
          <p class="hint area-nota">${icon('user-check')} Usted define los parámetros de ${esc(A.label)}.</p>
          ${proceso.length ? `<div class="chk-grid">${proceso.map((x) => fila(x.m, x.def)).join('')}</div>` : ''}
          ${!base.length ? '<p class="hint">Sin parámetros sugeridos para este tipo de prueba.</p>' : ''}
          <button type="button" class="btn teal sm add-par" data-add="${area}">${icon('plus')} Agregar parámetro de ${esc(A.label)}</button>
        </div></div>`;
    }).join('');
    refreshIcons();
  };

  const cargar = async () => {
    const t = getTipo();
    if (!t) { cont.innerHTML = '<p class="hint">Elija el tipo de prueba para ver los parámetros.</p>'; tipo = null; return; }
    if (t === tipo) return;
    tipo = t; marcados.clear(); Object.keys(extra).forEach((k) => delete extra[k]);
    cont.innerHTML = '<div class="skeleton" style="height:120px"></div>';
    try {
      [metodos, unidades, plantilla] = await Promise.all([getCat('metodos'), getCat('unidades'), plantillaDe(t)]);
      pintar();
    } catch (err) { cont.innerHTML = aviso(errMsg(err), 'bad', 'alert-triangle'); }
  };

  cont.addEventListener('change', (e) => {
    const t = e.target;
    if (t.matches('[data-toggle]')) { if (t.checked) activas.add(t.dataset.toggle); else activas.delete(t.dataset.toggle); pintar(); return; }
    if (t.matches('.chk-param input')) marcados.set(t.value, t.checked);
  });
  cont.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-add]');
    if (!b) return;
    e.preventDefault();
    const area = b.dataset.add;
    const ya = [...cont.querySelectorAll('.chk-param input')].map((i) => i.value);
    try {
      const id = await parametroForm({ area, tipo, excluir: ya });
      if (!id) return;
      metodos = await getCat('metodos');
      (extra[area] ||= []).push(id); marcados.set(id, true);
      pintar();
    } catch (err) { toast(errMsg(err), 'error'); }
  });

  cargar();
  return {
    recargar: cargar,
    leer: () => {
      const ids = [];
      cont.querySelectorAll('.area-block.propia').forEach((blk) => {
        if (blk.querySelector('.area-list')?.classList.contains('hidden')) return;
        ids.push(...[...blk.querySelectorAll('.chk-param input:checked')].map((i) => i.value));
      });
      return { ids, involucradas: [...AREAS_ORDEN] };
    },
  };
}

// ---------- Tarjeta de parámetros en el expediente ----------
// Cada área agrega o quita los suyos; quien registra indica si se involucra
// Seguridad o Mantenimiento (no detienen la prueba si no registran su parte).
export async function montarParametrosPrueba(el, P, recargar) {
  const [metodos, unidades, plan, pars, conRes, sinPar] = await Promise.all([
    getCat('metodos'), getCat('unidades'),
    sb.from('plan_evaluacion_prubind').select('*').eq('prueba_id', P.id).eq('incluido', true).order('orden'),
    sb.from('prueba_parametros_prubind').select('*').eq('prueba_id', P.id).order('orden'),
    sb.from('resultados_prubind').select('plan_id').eq('prueba_id', P.id),
    sb.from('areas_sin_parametros_prubind').select('area, motivo, created_at, por:usuarios_prubind!areas_sin_parametros_prubind_declarado_por_fkey(nombre)').eq('prueba_id', P.id),
  ]);
  [plan, pars, conRes, sinPar].forEach((r) => { if (r.error) throw r.error; });
  const declarada = (a) => sinPar.data.find((s) => s.area === a);
  const usados = new Set(conRes.data.map((r) => r.plan_id));
  const met = (id) => metodos.find((m) => m.id === id);
  const abierta = ABIERTA.includes(P.estado);
  const editaArea = (area) => abierta && puedeArea(P, 'evaluar', area);
  const registra = abierta && puedeEn(P, 'preparar');
  const porArea = {};
  plan.data.forEach((pl) => { const m = met(pl.metodo_id); if (m) (porArea[m.area] ||= []).push({ pl, m }); });
  const involucradas = new Set([...(P.areas_involucradas || ['calidad', 'produccion']), ...Object.keys(porArea), ...(pars.data.length ? ['produccion'] : [])]);
  const areas = AREAS_ORDEN.filter((a) => involucradas.has(a));
  const sumables = [];
  const crit = (pl, m) => criterioTxt(pl, unidadTxt(unidades, m.unidad_id));
  const item = ({ pl, m }, area) => `<li><span>${esc(m.nombre)} <span class="cell-sub">· ${esc(medidaTxt(m, unidades))}${crit(pl, m) ? ` · criterio ${esc(crit(pl, m))}` : ''}</span></span>
    ${editaArea(area) && !usados.has(pl.id) ? iconBtn(`data-par="quitar" data-id="${esc(pl.id)}" data-nom="${esc(m.nombre)}"`, 'x', 'Quitar parámetro', 'bad') : ''}</li>`;
  el.innerHTML = `<div class="card mt">${cardHead('Parámetros a evaluar', 'Cada área define los suyos.')}
    <div class="areas-grid">${areas.map((area) => {
      const xs = porArea[area] || [], proc = xs;
      const sinDefinir = !xs.length && !(area === 'produccion' && pars.data.length);
      const dec = declarada(area);
      if (dec) {
        return `<div class="area-block area-na"><div class="area-head">${icon(AREAS[area].ico)}<div><b>${esc(AREAS[area].label)}</b><span>${esc(AREAS[area].desc)}</span></div>
            <span class="area-tag na">${icon('circle-slash')} Sin nada que evaluar</span></div>
          <p class="hint area-nota">${esc(dec.por?.nombre || 'El responsable')} indicó que su área no tiene nada que evaluar en esta prueba${dec.motivo ? `: “${esc(dec.motivo)}”` : '.'}</p>
          <div class="area-acts">${editaArea(area) ? `<button type="button" class="link-btn" data-par="retomar" data-area="${area}">${icon('rotate-ccw')} Sí hay algo que evaluar</button>` : ''}</div></div>`;
      }
      return `<div class="area-block ${sinDefinir ? 'pendiente' : ''}"><div class="area-head">${icon(AREAS[area].ico)}<div><b>${esc(AREAS[area].label)}</b><span>${esc(AREAS[area].desc)}</span></div>
          ${sinDefinir ? `<span class="area-tag wait">${icon('hourglass')} Por definir</span>` : `<span class="area-tag ok">${xs.length + (area === 'produccion' ? pars.data.length : 0)} parámetro(s)</span>`}</div>
        ${sinDefinir ? `<p class="hint area-nota">${editaArea(area) ? 'Defina los parámetros de su área.' : `${esc(AREAS[area].label)} aún no define sus parámetros.`}</p>` : ''}
        ${proc.length ? `<ul class="param-list">${proc.map((x) => item(x, area)).join('')}</ul>` : ''}
        ${area === 'produccion' && pars.data.length ? `<div class="sub-title">Parámetros del equipo (${esc(P.equipo_nombre || 'equipo')})</div><ul class="param-list">${pars.data.map((x) =>
          `<li><span>${esc(x.nombre)} <span class="cell-sub">· ${esc(x.minimo != null || x.maximo != null ? criterioTxt({ crit_minimo: x.minimo, crit_maximo: x.maximo }, unidadTxt(unidades, x.unidad_id)) : (x.referencia || '').split(' · ')[0] || 'referencia del equipo')}</span></span></li>`).join('')}</ul>` : ''}
        <div class="area-acts">${editaArea(area) ? `<button type="button" class="btn ${sinDefinir ? 'turq' : 'teal'} sm add-par" data-par="${sinDefinir ? 'definir' : 'agregar'}" data-area="${area}">${icon(sinDefinir ? 'list-checks' : 'plus')} ${sinDefinir ? 'Definir parámetros' : 'Agregar parámetro'}</button>
          ${!xs.length && !(area === 'produccion' && pars.data.length) ? `<button type="button" class="btn sm nada-btn" data-par="nada" data-area="${area}">${icon('circle-slash')} Nada que evaluar por mi área</button>` : ''}` : ''}</div></div>`;
    }).join('')}</div>
    ${sumables.length ? `<p class="hint mt-s">¿La prueba involucra otra área? ${sumables.map((a) => `<button type="button" class="link-btn" data-par="incluir" data-area="${a}">${icon('plus')} ${esc(AREAS[a].label)}</button>`).join(' ')}</p>` : ''}
  </div>`;
  refreshIcons();
  el.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-par]');
    if (!b) return;
    const area = b.dataset.area;
    try {
      switch (b.dataset.par) {
        case 'definir': {
          const ids = await definirForm(P, area);
          if (!ids) return;
          must(await sb.rpc('prubind_definir_parametros', { p_prueba: P.id, p_agregar: ids, p_quitar: [] }));
          toast(`Parámetros de ${AREAS[area].label} definidos.`, 'success'); break;
        }
        case 'agregar': {
          const id = await parametroForm({ area, tipo: P.tipo, excluir: plan.data.map((pl) => pl.metodo_id) });
          if (!id) return;
          must(await sb.rpc('prubind_definir_parametros', { p_prueba: P.id, p_agregar: [id], p_quitar: [] }));
          toast('Parámetro agregado a la prueba.', 'success'); break;
        }
        case 'quitar':
          if (!await confirmDialog({ title: 'Quitar parámetro', message: `"${b.dataset.nom}" ya no se evaluará en esta prueba.`, confirmText: 'Quitar' })) return;
          must(await sb.rpc('prubind_definir_parametros', { p_prueba: P.id, p_agregar: [], p_quitar: [b.dataset.id] }));
          toast('Parámetro quitado.', 'success'); break;
        case 'nada': {
          const r = await confirmDialog({ title: `${AREAS[area].label}: nada que evaluar`, message: `${AREAS[area].label} no participará en esta prueba${(porArea[area] || []).length ? ' y se quitarán los parámetros que había definido' : ''}. Si cambia de opinión, puede retomarla mientras la prueba no termine.`,
            confirmText: 'Confirmar', input: { label: 'Motivo (opcional)', maxlength: 300, placeholder: 'Ej. El cambio no afecta al área' } });
          if (!r) return;
          must(await sb.rpc('prubind_area_sin_parametros', { p_prueba: P.id, p_area: area, p_motivo: r.value || null, p_quitar: false }));
          toast(`${AREAS[area].label} quedó sin nada que evaluar en esta prueba.`, 'success'); break;
        }
        case 'retomar':
          must(await sb.rpc('prubind_area_sin_parametros', { p_prueba: P.id, p_area: area, p_motivo: null, p_quitar: true }));
          toast(`${AREAS[area].label} vuelve a participar: defina sus parámetros.`, 'success'); break;
        case 'incluir': case 'excluir': {
          const nuevas = [...involucradas].filter((a) => a !== area || b.dataset.par === 'incluir');
          if (b.dataset.par === 'incluir') nuevas.push(area);
          must(await sb.rpc('prubind_areas_involucradas', { p_prueba: P.id, p_areas: nuevas }));
          if (b.dataset.par === 'incluir' && editaArea(area)) { recargar(); return; }
          toast(b.dataset.par === 'incluir' ? `${AREAS[area].label} quedó involucrada en la prueba.` : `${AREAS[area].label} ya no participa en la prueba.`, 'success'); break;
        }
        default: return;
      }
      recargar();
    } catch (err) { toast(errMsg(err), 'error'); }
  });
}

// Elegir de una vez los parámetros sugeridos de un área (desde el expediente)
async function definirForm(P, area) {
  const [metodos, unidades, plantilla] = await Promise.all([getCat('metodos'), getCat('unidades'), plantillaDe(P.tipo)]);
  const base = plantilla.map((pt) => ({ m: metodos.find((x) => x.id === pt.metodo_id), def: false }))
    .filter((x) => x.m && x.m.activo !== false && x.m.area === area);
  const extra = [];
  const pintar = (form) => {
    const todos = [...base, ...extra.map((m) => ({ m, def: true }))];
    form.querySelector('#df-lista').innerHTML = todos.length ? `<div class="chk-grid">${todos.map(({ m, def }) => `<label class="chk-param"><input type="checkbox" name="m" value="${esc(m.id)}" ${def ? 'checked' : ''}>
      <span>${esc(m.nombre)} <span class="cell-sub">(${esc(medidaTxt(m, unidades))})</span></span></label>`).join('')}</div>` : '<p class="hint">Sin parámetros sugeridos; agregue los que necesite.</p>';
  };
  return openModal({
    title: `Parámetros de ${AREAS[area].label}`, subtitle: `${P.folio} · ${P.cambio}`, size: 'lg', submitText: 'Guardar parámetros',
    body: `<p class="hint">${esc(AREAS[area].desc)}. Marque lo que se medirá en esta prueba.</p><div id="df-lista"></div>
      <button type="button" class="link-btn" data-df="nuevo">${icon('plus')} Agregar otro parámetro</button>`,
    onOpen: ({ form }) => {
      pintar(form); refreshIcons();
      form.addEventListener('click', async (e) => {
        if (!e.target.closest('[data-df="nuevo"]')) return;
        const ya = [...form.querySelectorAll('input[name=m]')].map((i) => i.value);
        const id = await parametroForm({ area, tipo: P.tipo, excluir: ya });
        if (!id) return;
        const m = (await getCat('metodos')).find((x) => x.id === id);
        if (m) { extra.push(m); pintar(form); }
      });
    },
    onSubmit: async ({ form, setError }) => {
      const ids = [...form.querySelectorAll('input[name=m]:checked')].map((i) => i.value);
      if (!ids.length) { setError('Marque al menos un parámetro.'); return false; }
      return ids;
    },
  });
}

// ---------- Formulación de la prueba (nuevo producto y cambio en la formulación) ----------
const ACC_FORM = { sin_cambio: ['Sin cambio', 'gray'], modificar: ['Modificada', 'info'], agregar: ['Nueva', 'ok'], retirar: ['Se quita', 'bad'], sustituir: ['Sustituye', 'orange'] };
const copiada = new Set(); // la receta se copia sola una vez por prueba en la sesión

export async function montarFormulacion(el, P, recargar) {
  if (!(P.secciones_prep || []).includes('formulacion')) { el.innerHTML = ''; return; }
  const editable = ['registrada', 'en_preparacion'].includes(P.estado) && puedeEn(P, 'preparar');
  const [materias, unidades, res] = await Promise.all([getCat('materias'), getCat('unidades'),
    sb.from('prueba_formulacion_prubind').select('*').eq('prueba_id', P.id).order('orden')]);
  if (res.error) throw res.error;
  const F = res.data;
  if (editable && !F.length && P.receta_version_id && !copiada.has(P.id)) {
    copiada.add(P.id);
    try { await accion(P.id, 'copiar_receta'); recargar(); return; } catch (err) { toast(errMsg(err), 'error'); }
  }
  const mp = (id) => materias.find((m) => m.id === id)?.nombre || '—';
  const un = (id) => unidadTxt(unidades, id);
  el.innerHTML = `<div class="card mt">
    ${cardHead('Formulación de la prueba', P.receta_nombre ? `Basada en <b>${esc(P.receta_nombre)}</b>. Cambie cantidades, agregue o quite materias primas. La receta oficial no se modifica.` : 'Materias primas y cantidades por batch de la receta nueva.',
      editable ? `${btn('data-fo="nuevo"', 'plus', 'Agregar materia prima')}${P.receta_version_id && F.length ? btn('data-fo="copiar"', 'rotate-ccw', 'Restablecer receta original', 'ghost') : ''}` : '')}
    ${F.length ? `<div class="table-wrap responsive"><table class="table"><thead><tr><th>Materia prima</th><th>Receta original</th><th>Prueba (por batch)</th><th>Cambio</th><th class="actions"></th></tr></thead><tbody>
      ${F.map((f) => `<tr class="${f.accion !== 'sin_cambio' ? 'row-hl' : ''}">
        <td data-label="Materia prima"><div class="td-in"><div class="cell-main">${esc(mp(f.materia_prima_id))}</div>${f.sustituye_a_id ? `<div class="cell-sub">Sustituye a ${esc(mp(f.sustituye_a_id))}</div>` : ''}</div></td>
        <td data-label="Original"><div class="td-in">${f.cantidad_original != null ? esc(fmtQty(f.cantidad_original, un(f.unidad_id))) : '<span class="cell-sub">—</span>'}</div></td>
        <td data-label="Prueba"><div class="td-in">${editable ? `<input class="inline-num" type="number" min="0" step="any" inputmode="decimal" value="${esc(f.cantidad_propuesta ?? '')}" data-prop="${esc(f.id)}" aria-label="Cantidad en la prueba"> ${esc(un(f.unidad_id))}` : esc(fmtQty(f.cantidad_propuesta, un(f.unidad_id)))}</div></td>
        <td data-label="Cambio"><div class="td-in">${pill(...ACC_FORM[f.accion])}</div></td>
        <td class="actions" data-label=""><div class="td-in">${editable && f.accion !== 'retirar' ? iconBtn(`data-fo="quitar" data-id="${esc(f.id)}"`, 'minus-circle', f.cantidad_original != null ? 'Quitar de la prueba' : 'Eliminar', 'bad') : ''}</div></td></tr>`).join('')}
    </tbody></table></div>
    <p class="hint mt-s">Total por batch: <b>${esc(fmtQty(Math.round(F.reduce((s, f) => s + (un(f.unidad_id) === 'kg' ? Number(f.cantidad_propuesta || 0) : 0), 0) * 1000) / 1000, 'kg'))}</b>.${editable ? ` Para quitar una materia prima use ${icon('minus-circle')} o escriba 0.` : ''}</p>`
      : vacio(editable ? 'Agregue las materias primas de la receta.' : 'Sin formulación registrada.')}
    ${!editable && ['registrada', 'en_preparacion'].includes(P.estado) ? '' : !editable ? '<p class="hint">La formulación se ajusta antes de iniciar la prueba.</p>' : ''}
  </div>`;
  refreshIcons();
  el.addEventListener('change', async (e) => {
    const t = e.target.closest('[data-prop]');
    if (!t) return;
    try { mustRow(await sb.from('prueba_formulacion_prubind').update({ cantidad_propuesta: numOrNull(t.value) ?? 0 }).eq('id', t.dataset.prop).select('id')); recargar(); }
    catch (err) { toast(errMsg(err), 'error'); recargar(); }
  });
  el.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-fo]');
    if (!b) return;
    try {
      if (b.dataset.fo === 'nuevo') { if (!await ingredienteForm(P, materias, unidades, F)) return; }
      else if (b.dataset.fo === 'copiar') {
        if (!await confirmDialog({ title: 'Restablecer receta original', message: 'Se perderán los cambios hechos a la formulación de esta prueba.', confirmText: 'Restablecer', danger: true })) return;
        await accion(P.id, 'copiar_receta');
      } else if (b.dataset.fo === 'quitar') {
        const f = F.find((x) => x.id === b.dataset.id);
        if (f?.cantidad_original != null) mustRow(await sb.from('prueba_formulacion_prubind').update({ cantidad_propuesta: 0 }).eq('id', f.id).select('id'));
        else mustRow(await sb.from('prueba_formulacion_prubind').delete().eq('id', b.dataset.id).select('id'));
      } else return;
      recargar();
    } catch (err) { toast(errMsg(err), 'error'); }
  });
}

function ingredienteForm(P, materias, unidades, existentes = []) {
  const ya = new Set(existentes.map((x) => x.materia_prima_id));
  return openModal({
    title: 'Agregar materia prima', subtitle: P.folio, size: 'sm',
    body: `<div class="field"><label for="if-mp">Materia prima <span class="req">*</span></label><select id="if-mp" name="mp" required>${opciones(materias.filter((m) => m.activo && !ya.has(m.id)), null)}</select></div>
      <div class="form-grid"><div class="field"><label for="if-c">Cantidad por batch <span class="req">*</span></label><input id="if-c" name="cant" type="number" min="0.0001" step="any" inputmode="decimal" required></div>
      <div class="field"><label for="if-u">Unidad <span class="req">*</span></label><select id="if-u" name="un" required>${opciones(unidades, unidades.find((u) => u.simbolo === 'kg')?.id, { label: (u) => u.simbolo, vacio: null })}</select></div></div>
      <div class="field"><label for="if-s">¿Reemplaza a otra materia prima? ${ayuda('Elija la materia prima de la receta que esta sustituye. Déjelo vacío si solo se agrega.')}</label><select id="if-s" name="sus">${opciones(materias.filter((m) => ya.has(m.id)), null, { vacio: 'No, solo se agrega' })}</select></div>`,
    onOpen: ({ form }) => form.elements.mp.addEventListener('change', () => {
      const m = materias.find((x) => x.id === form.elements.mp.value);
      if (m?.unidad_id) form.elements.un.value = m.unidad_id;
    }),
    onSubmit: async ({ form }) => {
      if (!checkForm(form)) return false;
      const v = formValues(form);
      must(await sb.from('prueba_formulacion_prubind').insert({ prueba_id: P.id, materia_prima_id: v.mp, cantidad_propuesta: Number(v.cant), unidad_id: v.un,
        accion: v.sus ? 'sustituir' : 'agregar', sustituye_a_id: nullIfEmpty(v.sus) }));
      const reemplazada = v.sus && existentes.find((x) => x.materia_prima_id === v.sus && x.cantidad_original != null);
      if (reemplazada) mustRow(await sb.from('prueba_formulacion_prubind').update({ cantidad_propuesta: 0 }).eq('id', reemplazada.id).select('id'));
      toast('Materia prima agregada.', 'success');
    },
  });
}
