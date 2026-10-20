// =====================================================================
// Administración (solo administradores): usuarios con su puesto y matriz
// de autoridades (puesto × tipo de prueba × acción). El rol de
// administrador NO confiere autoridad técnica.
// Alta de usuarios: se puede buscar una cuenta existente de Supabase Auth
// (se llenan nombre, correo y foto). Si el correo no tiene cuenta, se crea
// con una contraseña temporal mediante la Edge Function
// "gestionar_usuarios_prubind" (la llave secreta vive solo en Supabase).
// =====================================================================
import {
  sb, state, esc, icon, toast, errMsg, openModal, confirmDialog, checkForm, formValues, DataTable, paged,
  sanitizeSearch, debounce, getAreas, getCat, invalidateCat, opciones, pill, must, mustRow, fmtDateTime,
  avatarHTML, prepararFoto, subirFoto, borrarFotoPropia, refreshIcons, fieldError, emptyState, ACCIONES,
} from '../core.js';

let root, table, cuentas = new Map();
const EMAIL_RE = /^[a-z0-9._%+-]+@petstable\.mx$/i;

export default {
  async render(el, params) {
    root = el;
    const tab = ['usuarios', 'autoridades'].includes(params.tab) ? params.tab : 'usuarios';
    const puestos = await getCat('puestos');
    el.innerHTML = `
      <section class="page-intro">
        <div><span class="eyebrow">Administración</span><h1>Usuarios</h1>
          <p>Personas autorizadas, su puesto y qué registra, evalúa o dictamina cada puesto por área y tipo de prueba.</p></div>
        <div class="page-actions"><button class="btn primary" data-u="nuevo">${icon('user-plus')} Nuevo usuario</button></div>
      </section>
      <div class="tabs" role="tablist">
        <button role="tab" data-tab="usuarios">${icon('users')} Usuarios</button>
        <button role="tab" data-tab="autoridades">${icon('key-round')} Autoridades</button>
      </div>
      <div data-pane="usuarios">
        <div class="card">
          <div class="toolbar">
            <div class="search">${icon('search')}<input type="search" id="u-q" placeholder="Buscar por nombre o correo" aria-label="Buscar"></div>
            <select id="u-rol" aria-label="Rol"><option value="">Todos los roles</option><option value="admin">Administrador</option><option value="usuario">Usuario</option></select>
            <select id="u-fun" aria-label="Puesto"><option value="">Todos los puestos</option><option value="sin">Sin puesto</option>${puestos.map((p) => `<option value="${esc(p.id)}">${esc(p.nombre)}</option>`).join('')}</select>
            <select id="u-activo" aria-label="Estado"><option value="">Todos</option><option value="true">Activos</option><option value="false">Inactivos</option></select>
          </div>
          <div id="u-table"></div>
        </div>
      </div>
      <div data-pane="autoridades" class="hidden"><div id="aut-box"></div></div>`;

    table = new DataTable(el.querySelector('#u-table'), {
      sort: { key: 'nombre', asc: true },
      columns: [
        { label: 'Usuario', sort: 'nombre', cls: 'col-user', render: (u) => `<div class="user-cell">
            <span class="user-photo">${avatarHTML(u.nombre, u.foto_url, 'sm')}</span>
            <div class="user-txt"><div class="cell-main">${esc(u.nombre)}${u.id === state.profile.id ? ' <span class="cell-sub">(tú)</span>' : ''}</div>
            <div class="cell-sub">${esc(u.email)}</div></div></div>` },
        { label: 'Puesto / área', render: (u) => `<div class="puesto-txt">${u.puesto_cat ? esc(u.puesto_cat.nombre) : '<span class="warn-txt">Sin puesto</span>'}</div><div class="cell-sub">${esc(u.area?.nombre || '')}</div>` },
        { label: 'Rol', sort: 'rol', render: (u) => (u.rol === 'admin' ? pill('Administrador', 'orange') : pill('Usuario', 'info')) },
        { label: 'Último acceso', render: (u) => cuentaHTML(u.email) },
        { label: 'Estado', sort: 'activo', render: (u) => (u.activo ? pill('Activo', 'ok') : pill('Inactivo', 'gray')) },
        { label: 'Acciones', cls: 'actions', render: (u) => {
          const sinCuenta = cuentas.get(u.email.toLowerCase())?.tiene_cuenta === false;
          return `<div class="row-actions">
            ${sinCuenta && u.activo ? `<button class="icon-btn ok" data-ua="cuenta" data-id="${esc(u.id)}" title="Crear cuenta de acceso" aria-label="Crear cuenta de acceso">${icon('key-round')}</button>` : ''}
            <button class="icon-btn" data-ua="editar" data-id="${esc(u.id)}" title="Editar" aria-label="Editar">${icon('pencil')}</button>
            ${u.id === state.profile.id ? '' : `<button class="icon-btn ${u.activo ? 'warn' : 'ok'}" data-ua="toggle" data-id="${esc(u.id)}" title="${u.activo ? 'Desactivar' : 'Activar'}" aria-label="${u.activo ? 'Desactivar' : 'Activar'}">${icon(u.activo ? 'user-x' : 'user-check')}</button>`}
          </div>`;
        } },
      ],
      empty: { ico: 'user-cog', title: 'Sin usuarios', text: 'Registra a las personas autorizadas.' },
      fetch: async ({ from, to, sort, filters: f }) => {
        let q = sb.from('usuarios_prubind').select('id, email, nombre, puesto, puesto_id, foto_url, rol, activo, area_id, area:areas_prubind(nombre), puesto_cat:puestos_prubind(nombre)', { count: 'exact' });
        const s = sanitizeSearch(f.q);
        if (s) q = q.or(`nombre.ilike.*${s}*,email.ilike.*${s}*`);
        if (f.rol) q = q.eq('rol', f.rol);
        if (f.fun === 'sin') q = q.is('puesto_id', null); else if (f.fun) q = q.eq('puesto_id', f.fun);
        if (f.activo) q = q.eq('activo', f.activo === 'true');
        const [res, cu] = await Promise.all([paged(q, { from, to, sort }, [['nombre', true]]), sb.rpc('prubind_estado_cuentas')]);
        must(res);
        if (!cu.error) cuentas = new Map((cu.data || []).map((c) => [c.email.toLowerCase(), c]));
        return { rows: res.data, count: res.count };
      },
    });
    const apply = () => table.setFilters({ q: el.querySelector('#u-q').value, rol: el.querySelector('#u-rol').value, fun: el.querySelector('#u-fun').value, activo: el.querySelector('#u-activo').value });
    el.querySelector('#u-q').addEventListener('input', debounce(apply, 350));
    ['#u-rol', '#u-fun', '#u-activo'].forEach((s) => el.querySelector(s).addEventListener('change', apply));
    el.addEventListener('click', onClick);
    await apply();
    if (tab !== 'usuarios') el.querySelector(`[data-tab="${tab}"]`).click();
    else el.querySelector('[data-tab="usuarios"]').classList.add('active');
  },
  destroy() { root = null; table = null; },
};

function cuentaHTML(email) {
  const c = cuentas.get(String(email).toLowerCase());
  if (!c) return '<span class="cell-sub">—</span>';
  if (!c.tiene_cuenta) return '<span class="cell-sub" style="color:var(--bad)">Sin cuenta de acceso</span>';
  if (!c.ultimo_acceso) return '<span class="cell-sub">Aún no ha entrado</span>';
  return `<span class="mono">${fmtDateTime(c.ultimo_acceso)}</span>`;
}

async function onClick(e) {
  const t = e.target.closest('[data-tab]');
  if (t) {
    root.querySelectorAll('[data-tab]').forEach((b) => b.classList.toggle('active', b === t));
    root.querySelectorAll('[data-pane]').forEach((p) => p.classList.toggle('hidden', p.dataset.pane !== t.dataset.tab));
    root.querySelector('[data-u="nuevo"]').classList.toggle('hidden', t.dataset.tab !== 'usuarios');
    history.replaceState(null, '', `#/usuarios?tab=${t.dataset.tab}`);
    if (t.dataset.tab === 'autoridades') renderAutoridades(); else table.load();
    return;
  }
  if (e.target.closest('[data-u="nuevo"]')) { if (await openUsuarioForm()) table.load(); return; }
  const au = e.target.closest('[data-au]');
  if (au) { await accionAutoridad(au); return; }
  const a = e.target.closest('[data-ua]');
  if (!a) return;
  const u = table.row(a.dataset.id);
  if (!u) return;
  try {
    if (a.dataset.ua === 'editar' && await openUsuarioForm(u)) table.load();
    if (a.dataset.ua === 'cuenta' && await openCrearCuenta(u)) table.load();
    if (a.dataset.ua === 'toggle') {
      const ok = await confirmDialog({
        title: u.activo ? 'Desactivar usuario' : 'Activar usuario', danger: u.activo, confirmText: u.activo ? 'Desactivar' : 'Activar',
        message: u.activo ? `${u.nombre} ya no podrá entrar a Pruebas industriales. Su cuenta en otras aplicaciones no se modifica.` : `${u.nombre} podrá volver a entrar a Pruebas industriales.`,
      });
      if (!ok) return;
      mustRow(await sb.from('usuarios_prubind').update({ activo: !u.activo }).eq('id', u.id).select('id'));
      toast(u.activo ? 'Usuario desactivado.' : 'Usuario activado.', 'success'); table.load();
    }
  } catch (err) { toast(errMsg(err), 'error'); }
}

// ---------- Contraseña temporal ----------
function generarPassword() {
  const abc = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz', num = '23456789', sym = '#$%*+-?';
  const pick = (s) => s[crypto.getRandomValues(new Uint32Array(1))[0] % s.length];
  const chars = [pick(abc.slice(0, 24)), pick(abc.slice(24)), pick(num), pick(sym)];
  while (chars.length < 12) chars.push(pick(abc + num));
  for (let i = chars.length - 1; i > 0; i--) { const j = crypto.getRandomValues(new Uint32Array(1))[0] % (i + 1); [chars[i], chars[j]] = [chars[j], chars[i]]; }
  return chars.join('');
}
const pwRule = (v) => (v.length < 8 ? 'Mínimo 8 caracteres.' : !/[A-Za-z]/.test(v) || !/\d/.test(v) ? 'Incluye letras y números.' : '');
function passwordFieldHTML(id) {
  return `<div class="field"><label for="${id}">Contraseña temporal <span class="req">*</span></label>
      <div class="pw-wrap"><input id="${id}" name="password" type="text" autocomplete="new-password" minlength="8" maxlength="72" spellcheck="false" required>
      <button type="button" class="pw-toggle" data-genpw title="Generar contraseña" aria-label="Generar contraseña">${icon('wand-2')}</button></div>
      <small class="hint">Compártela de forma privada; la persona podrá cambiarla en <b>Mi perfil</b>.</small></div>`;
}
function bindPwGenerator(form) {
  form.querySelector('[data-genpw]')?.addEventListener('click', () => {
    form.elements.password.value = generarPassword();
    form.elements.password.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

async function crearCuenta(email, password) {
  const { data, error } = await sb.functions.invoke('gestionar_usuarios_prubind', { body: { accion: 'crear_cuenta', email, password } });
  if (error) {
    let msg = error.message;
    try { const b = await error.context?.json(); if (b?.error) msg = b.error; } catch { /* sin cuerpo */ }
    const e = new Error(msg); e.status = error.context?.status; throw e;
  }
  return data;
}

async function openCrearCuenta(u) {
  return openModal({
    title: 'Crear cuenta de acceso', subtitle: `${u.nombre} · ${u.email}`, size: 'sm', submitText: 'Crear cuenta',
    body: `<div class="notice">${icon('info')}<span>Este correo aún no tiene cuenta Pet's Table. Se creará ya confirmada con la contraseña temporal que definas.</span></div>
      ${passwordFieldHTML('cc-pw')}`,
    onOpen: ({ form }) => bindPwGenerator(form),
    onSubmit: async ({ form }) => {
      if (!checkForm(form, { password: pwRule })) return false;
      await crearCuenta(u.email, form.elements.password.value);
      toast(`Cuenta creada para ${u.nombre}. Comparte su contraseña temporal de forma privada.`, 'success', 7000);
    },
  });
}

// ---------- Alta / edición ----------
async function openUsuarioForm(u = null) {
  let areas, puestos;
  try { [areas, puestos] = await Promise.all([getAreas({ soloActivas: true }), getCat('puestos')]); } catch (err) { toast(errMsg(err), 'error'); return false; }
  const self = u && u.id === state.profile.id;
  let fotoBlob = null, fotoExistente = null, quitarFoto = false, cuentaEstado = u ? 'n/a' : 'pendiente', checkTok = 0, buscaTok = 0;

  return openModal({
    title: u ? 'Editar usuario' : 'Nuevo usuario', submitText: u ? 'Guardar cambios' : 'Registrar usuario', size: 'lg',
    body: `
      ${self ? `<div class="notice warn">${icon('lock')}<span>No puedes cambiar tu propio correo, rol ni estado. Pide a otro administrador que lo haga.</span></div>` : ''}
      ${u ? '' : `<div class="acc-box">
        <div class="section-title" style="margin:4px 0 6px">${icon('search')} Buscar en cuentas existentes (Supabase Authentication)</div>
        <div class="toolbar" style="margin:0"><div class="search">${icon('search')}<input type="search" id="us-busca" placeholder="Escribe nombre o correo (mín. 2 letras)" autocomplete="off" aria-label="Buscar cuentas existentes"></div></div>
        <div class="acc-results" id="us-busca-res"><span class="hint">Si la persona ya usa otra app de Pet's Table, selecciónala aquí: se llenan su nombre, correo y foto. Si no aparece, captura los datos abajo.</span></div>
      </div>`}
      <div class="photo-pick">
        <span id="us-prev">${avatarHTML(u?.nombre || '?', u?.foto_url)}</span>
        <div><div class="btns">
            <label class="btn secondary" for="us-foto" style="cursor:pointer">${icon('camera')} ${u?.foto_url ? 'Cambiar foto' : 'Subir foto'}</label>
            <button type="button" class="btn secondary" id="us-galeria">${icon('images')} Fotos existentes</button>
            <button type="button" class="btn ghost ${u?.foto_url ? '' : 'hidden'}" id="us-quitar">${icon('trash-2')} Quitar</button>
          </div>
          <input id="us-foto" type="file" accept="image/jpeg,image/png,image/webp" class="sr-only">
          <small class="hint">JPG, PNG o WEBP de hasta 5 MB. Se recorta en cuadrado y se optimiza automáticamente.</small></div>
      </div>
      <div class="form-grid" style="margin-top:8px">
        <div class="field full"><label for="us-nombre">Nombre completo <span class="req">*</span></label>
          <input id="us-nombre" name="nombre" required minlength="2" maxlength="120" value="${esc(u?.nombre || '')}" autocomplete="off"></div>
        <div class="field full"><label for="us-email">Correo corporativo <span class="req">*</span></label>
          <input id="us-email" name="email" type="email" required maxlength="120" autocomplete="off" value="${esc(u?.email || '')}" placeholder="nombre@petstable.mx" ${u ? 'disabled' : ''}>
          ${u ? '<small class="hint">El correo vincula la cuenta de acceso; para cambiarlo, desactiva este usuario y registra uno nuevo.</small>' : ''}</div>
        <div class="field"><label for="us-puesto">Puesto</label>
          <select id="us-puesto" name="puesto_id">${opciones(puestos, u?.puesto_id, { vacio: 'Sin puesto' })}</select>
          <small class="hint">El puesto define su autoridad técnica (pestaña Autoridades).</small></div>
        <div class="field"><label for="us-area">Área</label>
          <select id="us-area" name="area_id"><option value="">Sin área</option>
            ${areas.map((a) => `<option value="${esc(a.id)}" ${u?.area_id === a.id ? 'selected' : ''}>${esc(a.nombre)}</option>`).join('')}</select></div>
        <div class="field full"><label for="us-rol">Rol <span class="req">*</span></label>
          <select id="us-rol" name="rol" required ${self ? 'disabled' : ''}>
            <option value="usuario" ${u?.rol !== 'admin' ? 'selected' : ''}>Usuario — registra pruebas y actúa según su puesto</option>
            <option value="admin" ${u?.rol === 'admin' ? 'selected' : ''}>Administrador — catálogos, recetas, plantillas, usuarios y permisos técnicos</option></select>
          <small class="hint">El rol de administrador no otorga autoridad para aprobar resultados ni cambios.</small></div>
      </div>
      ${u ? '' : `<div class="acc-box"><div class="section-title" style="margin:4px 0 6px">${icon('key-round')} Cuenta de acceso</div>
        <div id="us-acc"><span class="hint">Escribe el correo para verificar si ya tiene cuenta Pet's Table.</span></div></div>`}`,
    onOpen: ({ form }) => {
      const prev = form.querySelector('#us-prev');
      const nombreVal = () => form.elements.nombre.value || '?';
      form.querySelector('#us-foto').addEventListener('change', async (ev) => {
        const file = ev.target.files?.[0];
        if (!file) return;
        try {
          fotoBlob = await prepararFoto(file); quitarFoto = false;
          const url = URL.createObjectURL(fotoBlob);
          prev.innerHTML = `<span class="avatar"><img src="${url}" alt=""></span>`;
          form.querySelector('#us-quitar').classList.remove('hidden');
        } catch (err) { toast(errMsg(err), 'error'); }
        ev.target.value = '';
      });
      form.querySelector('#us-quitar').addEventListener('click', () => {
        fotoBlob = null; fotoExistente = null; quitarFoto = true;
        prev.innerHTML = avatarHTML(nombreVal(), null);
        form.querySelector('#us-quitar').classList.add('hidden');
        form.dispatchEvent(new Event('input'));
      });
      const ponerFotoExistente = (url) => {
        fotoBlob = null; quitarFoto = false; fotoExistente = url;
        prev.innerHTML = avatarHTML(nombreVal(), url);
        form.querySelector('#us-quitar').classList.remove('hidden');
        form.dispatchEvent(new Event('input'));
      };
      form.querySelector('#us-galeria').addEventListener('click', async () => {
        const url = await elegirFotoExistente();
        if (url) ponerFotoExistente(url);
      });
      if (u) return;
      // Búsqueda de cuentas existentes en Supabase Auth
      const res = form.querySelector('#us-busca-res');
      let resultados = [];
      form.querySelector('#us-busca').addEventListener('input', debounce(async (ev) => {
        const q = ev.target.value.trim();
        const t = ++buscaTok;
        if (q.length < 2) { res.innerHTML = '<span class="hint">Escribe al menos 2 letras.</span>'; return; }
        res.innerHTML = '<span class="hint">Buscando…</span>';
        const { data, error } = await sb.rpc('prubind_buscar_cuentas', { p_q: q });
        if (t !== buscaTok) return;
        if (error) { res.innerHTML = `<span class="hint" style="color:var(--bad)">${esc(errMsg(error))}</span>`; return; }
        resultados = data || [];
        res.innerHTML = resultados.length ? resultados.map((r, i) => `<button type="button" data-cuenta="${i}" ${r.ya_registrado ? 'disabled' : ''}>
            ${avatarHTML(r.nombre, r.foto_sugerida, 'sm')}<span class="acc-main"><b>${esc(r.nombre)}</b><small>${esc(r.email)}${r.ultimo_acceso ? ` · último acceso ${fmtDateTime(r.ultimo_acceso)}` : ''}</small></span>
            ${r.ya_registrado ? pill('Ya tiene acceso', 'gray') : pill('Agregar', 'ok')}</button>`).join('')
          : '<span class="hint">No hay cuentas con ese texto. Captura los datos abajo para crear una nueva.</span>';
        refreshIcons();
      }, 350));
      res.addEventListener('click', (ev) => {
        const b = ev.target.closest('[data-cuenta]');
        if (!b || b.disabled) return;
        const r = resultados[Number(b.dataset.cuenta)];
        form.elements.nombre.value = r.nombre;
        form.elements.email.value = r.email;
        form.elements.email.dispatchEvent(new Event('input', { bubbles: true }));
        if (r.foto_sugerida && !fotoBlob) ponerFotoExistente(r.foto_sugerida);
        res.querySelectorAll('[data-cuenta]').forEach((x) => x.classList.toggle('sel', x === b));
        form.elements.puesto_id.focus();
        toast(`${r.nombre} seleccionado. Completa puesto, área y rol.`, 'info');
      });
      // Verificación de cuenta existente al escribir el correo
      const acc = form.querySelector('#us-acc');
      const check = debounce(async () => {
        const t = ++checkTok;
        const email = form.elements.email.value.trim().toLowerCase();
        if (!EMAIL_RE.test(email)) { cuentaEstado = 'pendiente'; acc.innerHTML = '<span class="hint">Escribe un correo @petstable.mx válido.</span>'; return; }
        acc.innerHTML = '<span class="hint">Verificando…</span>';
        const { data, error } = await sb.rpc('prubind_correo_tiene_cuenta', { p_email: email });
        if (t !== checkTok) return;
        if (error) { cuentaEstado = 'pendiente'; acc.innerHTML = `<span class="hint" style="color:var(--bad)">${esc(errMsg(error))}</span>`; return; }
        if (data) {
          cuentaEstado = 'existe';
          acc.innerHTML = `<div class="notice" style="margin:0">${icon('check-circle-2')}<span>Este correo ya tiene cuenta Pet's Table. Entrará con la <b>misma contraseña</b> que usa en las otras aplicaciones.</span></div>`;
        } else {
          cuentaEstado = 'nueva';
          acc.innerHTML = `<div class="notice warn" style="margin:0 0 6px">${icon('user-plus')}<span>Este correo no tiene cuenta. Se creará al registrar al usuario.</span></div>${passwordFieldHTML('us-pw')}`;
          bindPwGenerator(form);
        }
        refreshIcons();
      }, 450);
      form.elements.email.addEventListener('input', check);
    },
    onSubmit: async ({ form, setError }) => {
      if (!checkForm(form, {
        email: (v) => (u || EMAIL_RE.test(v) ? '' : 'Debe ser un correo @petstable.mx.'),
        password: pwRule,
      })) return false;
      if (!u && cuentaEstado === 'pendiente') { setError('Espera a que se verifique la cuenta del correo.'); return false; }
      const v = formValues(form);
      const payload = { nombre: v.nombre.replace(/\s+/g, ' '), puesto_id: v.puesto_id || null, area_id: v.area_id || null };
      if (!self) payload.rol = v.rol;

      let nuevaFoto = null;
      if (fotoBlob) nuevaFoto = await subirFoto(fotoBlob);
      if (nuevaFoto) payload.foto_url = nuevaFoto;
      else if (fotoExistente) payload.foto_url = fotoExistente;
      else if (quitarFoto) payload.foto_url = null;

      let id = u?.id;
      try {
        if (u) {
          mustRow(await sb.from('usuarios_prubind').update(payload).eq('id', u.id).select('id'));
          if ((nuevaFoto || fotoExistente || quitarFoto) && u.foto_url && u.foto_url !== payload.foto_url) borrarFotoPropia(u.foto_url);
        } else {
          payload.email = v.email.toLowerCase();
          id = must(await sb.from('usuarios_prubind').insert(payload).select('id').single()).data.id;
        }
      } catch (err) {
        if (nuevaFoto) borrarFotoPropia(nuevaFoto);
        if (err.code === '23505') { fieldError(form.elements.email, 'Ese correo ya está registrado en Pruebas industriales.'); return false; }
        throw err;
      }

      invalidateCat('usuarios');
      if (!u && cuentaEstado === 'nueva') {
        try {
          await crearCuenta(payload.email, v.password);
          toast(`${payload.nombre} registrado y con cuenta creada. Comparte su contraseña temporal de forma privada.`, 'success', 8000);
        } catch (err) {
          toast(`${payload.nombre} quedó registrado, pero no se pudo crear su cuenta: ${String(err.message).replace(/\.$/, '')}. Usa el botón de llave en la tabla para reintentar.`, 'warning', 10000);
        }
      } else {
        toast(u ? 'Usuario actualizado.' : `${payload.nombre} registrado. Ya puede entrar con su cuenta Pet's Table.`, 'success', 6000);
      }
      // Si el admin se editó a sí mismo, refrescar encabezado y permisos
      if (self) {
        Object.assign(state.profile, { nombre: payload.nombre, foto_url: 'foto_url' in payload ? payload.foto_url : state.profile.foto_url });
        if (payload.puesto_id !== state.profile.puesto_id) toast('Cambió tu puesto: recarga la página para aplicar tus nuevas autoridades.', 'info', 7000);
        const top = document.getElementById('top-avatar');
        if (top) top.outerHTML = avatarHTML(state.profile.nombre, state.profile.foto_url).replace('class="avatar ', 'id="top-avatar" class="avatar ');
        document.getElementById('top-name').textContent = state.profile.nombre;
      }
    },
  });
}

// Galería del bucket público "avatares" (fotos ya cargadas en Supabase Storage; solo se enlazan)
async function elegirFotoExistente() {
  const { data, error } = await sb.storage.from('avatares').list('', { limit: 500, sortBy: { column: 'name', order: 'asc' } });
  if (error) { toast(errMsg(error), 'error'); return null; }
  const fotos = (data || []).filter((f) => /\.(png|jpe?g|webp)$/i.test(f.name));
  if (!fotos.length) { toast('No hay fotos disponibles en la carpeta "avatares".', 'warning'); return null; }
  const url = (n) => sb.storage.from('avatares').getPublicUrl(n).data.publicUrl;
  const r = await openModal({
    title: 'Fotos existentes', subtitle: 'Carpeta “avatares” de Supabase Storage. Toca una foto para usarla.', size: 'lg', confirmDiscard: false,
    body: `<div class="toolbar"><div class="search">${icon('search')}<input type="search" id="gal-q" placeholder="Filtrar por nombre" aria-label="Filtrar fotos"></div></div>
      <div class="photo-gallery" id="gal">${fotos.map((f) => `<button type="button" data-url="${esc(url(f.name))}" data-n="${esc(f.name.toLowerCase())}">
        <img src="${esc(url(f.name))}" alt="" loading="lazy"><span>${esc(f.name.replace(/\.[^.]+$/, ''))}</span></button>`).join('')}</div>`,
    onOpen: ({ wrap, close }) => {
      wrap.querySelector('#gal').addEventListener('click', (e) => { const b = e.target.closest('[data-url]'); if (b) close(b.dataset.url); });
      wrap.querySelector('#gal-q').addEventListener('input', (e) => {
        const q = e.target.value.toLowerCase();
        wrap.querySelectorAll('#gal [data-n]').forEach((b) => b.classList.toggle('hidden', !b.dataset.n.includes(q)));
      });
    },
  });
  return typeof r === 'string' ? r : null;
}

// ---------- Matriz de autoridades (puesto o persona × tipo × acción) ----------
async function renderAutoridades() {
  const box = root.querySelector('#aut-box');
  box.innerHTML = '<div class="card"><div class="skeleton" style="height:80px"></div></div>';
  try {
    const [au, tipos, puestos, us] = await Promise.all([
      sb.from('autoridades_prubind').select('*').order('created_at'),
      getCat('tipos', { force: true }), getCat('puestos', { force: true }),
      sb.from('usuarios_prubind').select('id, nombre, puesto_id, activo').order('nombre'),
    ]);
    must(au); must(us);
    const tNom = (c) => (c ? tipos.find((t) => t.codigo === c)?.nombre || c : 'Todos los tipos');
    const quien = (a) => (a.puesto_id ? { ico: 'briefcase', txt: puestos.find((p) => p.id === a.puesto_id)?.nombre || '?', sub: us.data.filter((u) => u.puesto_id === a.puesto_id && u.activo).map((u) => u.nombre).join(', ') || 'Nadie tiene este puesto' }
      : { ico: 'user', txt: us.data.find((u) => u.id === a.usuario_id)?.nombre || '?', sub: 'Asignación individual' });
    box.innerHTML = `<div class="notice">${icon('info')}<span>Define quién puede actuar en cada etapa. Los <b>administradores no tienen autoridad técnica</b> por su rol: solo la tienen si su puesto o su persona aparecen aquí. Cualquier usuario activo puede registrar pruebas.</span></div>
      <div class="card"><div class="card-head"><div><h3>Autoridades</h3><p>${au.data.filter((a) => a.activo).length} asignaciones activas</p></div>
        <button class="btn primary" data-au="nueva">${icon('plus')} Agregar autoridad</button></div>
      ${Object.entries(ACCIONES).map(([k, lbl]) => { const rs = au.data.filter((a) => a.accion === k);
        return `<div class="plan-grupo"><div class="section-title">${icon('key-round')} ${esc(lbl)}</div>
          ${rs.length ? `<div class="table-wrap responsive"><table class="table"><thead><tr><th>Quién</th><th>Tipo de prueba</th><th>Estado</th><th class="actions"></th></tr></thead><tbody>
          ${rs.map((a) => { const q = quien(a); return `<tr class="${a.activo ? '' : 'row-off'}"><td data-label="Quién"><div class="td-in"><div class="cell-main">${icon(q.ico)} ${esc(q.txt)}</div><div class="cell-sub">${esc(q.sub)}</div></div></td>
            <td data-label="Tipo"><div class="td-in">${esc(tNom(a.tipo))}</div></td>
            <td data-label="Estado"><div class="td-in">${a.activo ? pill('Activa', 'ok') : pill('Inactiva', 'gray')}</div></td>
            <td class="actions" data-label=""><div class="td-in"><div class="row-actions">
              <button class="icon-btn ${a.activo ? 'warn' : 'ok'}" data-au="toggle" data-id="${esc(a.id)}" title="${a.activo ? 'Desactivar' : 'Activar'}" aria-label="${a.activo ? 'Desactivar' : 'Activar'}">${icon(a.activo ? 'eye-off' : 'eye')}</button>
              <button class="icon-btn bad" data-au="eliminar" data-id="${esc(a.id)}" title="Eliminar" aria-label="Eliminar">${icon('trash-2')}</button></div></div></td></tr>`; }).join('')}
          </tbody></table></div>` : '<p class="hint warn-txt">Nadie tiene esta autoridad: la etapa quedará detenida.</p>'}</div>`; }).join('')}</div>`;
    box._d = { au: au.data, tipos, puestos, us: us.data };
  } catch (err) {
    box.innerHTML = `<div class="card">${emptyState({ ico: 'wifi-off', title: 'No se pudo cargar', text: errMsg(err) })}</div>`;
  }
  refreshIcons();
}

async function accionAutoridad(b) {
  const box = root.querySelector('#aut-box');
  const { au, tipos, puestos, us } = box._d || {};
  if (!au) return;
  const a = au.find((x) => x.id === b.dataset.id);
  try {
    if (b.dataset.au === 'toggle' && a) mustRow(await sb.from('autoridades_prubind').update({ activo: !a.activo }).eq('id', a.id).select('id'));
    else if (b.dataset.au === 'eliminar' && a) {
      if (!await confirmDialog({ title: 'Eliminar autoridad', message: 'Se quitará esta asignación. Las acciones ya registradas conservan su historial.', confirmText: 'Eliminar', danger: true })) return;
      mustRow(await sb.from('autoridades_prubind').delete().eq('id', a.id).select('id'));
    } else if (b.dataset.au === 'nueva') {
      const ok = await openModal({
        title: 'Agregar autoridad', size: 'sm', submitText: 'Agregar',
        body: `<div class="field"><label for="au-a">Acción <span class="req">*</span></label><select id="au-a" name="accion" required><option value="">Selecciona…</option>${Object.entries(ACCIONES).map(([k, l]) => `<option value="${k}">${esc(l)}</option>`).join('')}</select></div>
          <div class="field"><label for="au-t">Tipo de prueba</label><select id="au-t" name="tipo"><option value="">Todos los tipos</option>${tipos.filter((t) => t.activo).map((t) => `<option value="${esc(t.codigo)}">${esc(t.nombre)}</option>`).join('')}</select></div>
          <div class="field"><span class="label">Asignar a</span><div class="seg-opt"><label><input type="radio" name="modo" value="puesto" checked> Puesto</label><label><input type="radio" name="modo" value="usuario"> Persona</label></div></div>
          <div class="field" data-modo="puesto"><label for="au-p">Puesto <span class="req">*</span></label><select id="au-p" name="puesto">${opciones(puestos.filter((p) => p.activo !== false))}</select></div>
          <div class="field hidden" data-modo="usuario"><label for="au-u">Persona <span class="req">*</span></label><select id="au-u" name="usuario">${opciones(us.filter((u) => u.activo))}</select></div>`,
        onOpen: ({ form }) => form.addEventListener('change', () => {
          const m = form.elements.modo.value;
          form.querySelectorAll('[data-modo]').forEach((d) => d.classList.toggle('hidden', d.dataset.modo !== m));
        }),
        onSubmit: async ({ form }) => {
          const e = form.elements, m = e.modo.value, v = m === 'puesto' ? e.puesto.value : e.usuario.value;
          if (!e.accion.value) { fieldError(e.accion, 'Selecciona la acción.'); return false; }
          if (!v) { fieldError(m === 'puesto' ? e.puesto : e.usuario, 'Selecciona a quién.'); return false; }
          const { error } = await sb.from('autoridades_prubind').insert({ accion: e.accion.value, tipo: e.tipo.value || null, puesto_id: m === 'puesto' ? v : null, usuario_id: m === 'usuario' ? v : null });
          if (error) { toast(error.code === '23505' ? 'Esa autoridad ya existe.' : errMsg(error), 'error'); return false; }
        },
      });
      if (!ok) return;
    } else return;
    toast('Autoridades actualizadas. Los usuarios verán el cambio al recargar la página.', 'success', 6000);
    renderAutoridades();
  } catch (err) { toast(errMsg(err), 'error'); }
}
