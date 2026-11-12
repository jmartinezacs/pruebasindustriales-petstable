// =====================================================================
// Perfil del usuario: datos, puesto y autoridades, cambio de contraseña, tema e
// instalación en la pantalla de inicio.
// =====================================================================
import {
  sb, state, esc, icon, refreshIcons, toast, errMsg, checkForm, prefs, fmtDateTime, APP_VERSION, avatarHTML, ACCIONES,
  getCat, push, K_THEME, emoji,
} from '../core.js';

// Créditos de la plataforma (la fotografía es la de su cuenta, desde el directorio de usuarios)
const AUTOR = { nombre: 'Javier Martínez González', cuenta: 'Javier Martínez' };
// Mosaico de información: ilustración, etiqueta y valor
const fila = (ilus, label, valor) => `<div class="pf-t"><span class="pf-ico">${emoji(ilus)}</span><div><small>${esc(label)}</small><b>${esc(valor)}</b></div></div>`;

// Estado y control de las notificaciones push de este dispositivo (tarjeta .avisos)
const ESTADO_AVISOS = { on: 'Notificaciones activadas', off: 'Notificaciones no disponibles', pend: 'Activa las notificaciones', info: 'Instala la app para recibirlas' };
async function pintarNotificaciones(box) {
  if (!box) return;
  const est = await push.estado().catch(() => 'no-soportado');
  const quien = 'Te avisaremos cuando te toque hacer algo en una prueba.';
  const [estado, texto, acc, extra] = {
    activo: ['on', quien, `<button class="btn primary sm" data-n="test">${icon('bell-ring')} Enviar aviso de prueba</button>
        <button class="btn secondary sm" data-n="off">${icon('bell-off')} Desactivar</button>`,
      `<details class="notif-ajustes"><summary>${icon('smartphone')} ¿No suena o no aparece en la pantalla bloqueada?</summary>
        <p><b>Android (Chrome):</b> mantén presionado el aviso de prueba → Configuración, o ve a Ajustes → Aplicaciones → Chrome → Notificaciones → busca este sitio y activa <b>Mostrar en pantalla emergente</b>, <b>Sonido</b> y <b>Pantalla de bloqueo</b>. Revisa también que “No molestar” esté apagado.</p>
        <p><b>iPhone:</b> Ajustes → Notificaciones → Pruebas industriales → activa <b>Permitir notificaciones</b>, <b>Pantalla bloqueada</b>, <b>Tiras</b> (estilo “Persistente”) y <b>Sonidos</b>. Revisa que el modo Concentración no lo silencie.</p>
      </details>`],
    inactivo: ['pend', quien, `<button class="btn primary sm" data-n="on">${icon('bell')} Activar notificaciones</button>`, ''],
    bloqueado: ['off', 'Las notificaciones están bloqueadas para este sitio. Permítelas desde la configuración del navegador (ícono del candado junto a la dirección) y vuelve a intentarlo.', '', ''],
    instalar: ['info', 'En iPhone/iPad las notificaciones solo funcionan con la app instalada: toca Compartir → “Agregar a pantalla de inicio”, ábrela desde ese ícono y regresa aquí para activarlas.', '', ''],
    'no-soportado': ['off', 'Este navegador no admite notificaciones web. Usa Chrome, Edge o Safari actualizados.', '', ''],
  }[est];
  const titulo = est === 'bloqueado' ? 'Notificaciones bloqueadas' : ESTADO_AVISOS[estado];
  box.innerHTML = `<div class="avisos ${estado}"><span class="avisos-ico">${emoji('n_avisos')}</span>
      <div class="avisos-txt"><b>${titulo}</b><p>${esc(texto)}</p></div>${acc ? `<div class="avisos-acc">${acc}</div>` : ''}</div>${extra}`;
  refreshIcons();
  box.querySelector('[data-n="test"]')?.addEventListener('click', async () => {
    // Aviso local con las mismas opciones que los avisos reales (vibración, permanece en pantalla)
    try {
      const reg = await navigator.serviceWorker.ready;
      // El service worker arma el ícono con tu foto y la insignia de la app, como en los avisos reales
      if (reg.active) {
        reg.active.postMessage({ tipo: 'aviso-prueba', title: 'Aviso de prueba · Pruebas industriales', body: 'Así se verán los avisos de las pruebas en este dispositivo.', foto: state.profile.foto_url || null });
        return;
      }
      await reg.showNotification('Aviso de prueba · Pruebas industriales', {
        body: 'Así se verán los avisos de las pruebas en este dispositivo.', icon: 'notif-icon.png', badge: 'notif-badge.png', actions: [{ action: 'ver', title: 'Ver ahora' }],
        tag: `prueba-${Date.now()}`, renotify: true, requireInteraction: true, silent: false, vibrate: [300, 120, 300, 120, 500], data: { url: '/#/perfil' },
      });
    } catch (err) { toast(errMsg(err), 'error'); }
  });
  box.querySelector('[data-n="on"], [data-n="off"]')?.addEventListener('click', async (e) => {
    const b = e.currentTarget; b.disabled = true;
    try {
      if (b.dataset.n === 'on') { await push.activar(); toast('Notificaciones activadas en este dispositivo.', 'success'); }
      else { await push.desactivar(); toast('Notificaciones desactivadas en este dispositivo.', 'success'); }
    } catch (err) { toast(errMsg(err), 'error'); }
    pintarNotificaciones(box);
  });
}

let deferredPrompt = null;
window.addEventListener('beforeinstallprompt', (e) => { e.preventDefault(); deferredPrompt = e; });

export default {
  async render(el) {
    const p = state.profile;
    const user = state.session?.user;
    const theme = prefs.get(K_THEME) || 'system';
    const standalone = push.instalada();
    let tipos = [];
    try { tipos = await getCat('tipos'); } catch { /* se muestran los códigos */ }
    const tNom = (c) => (c ? tipos.find((t) => t.codigo === c)?.nombre || c : 'todos los tipos');
    const aut = Object.entries(ACCIONES).map(([k, lbl]) => {
      const rs = (p.autoridades || []).filter((a) => a.accion === k);
      return rs.length ? { lbl, tipos: rs.some((a) => !a.tipo) ? 'Todos los tipos de prueba' : rs.map((a) => tNom(a.tipo)).join(', ') } : null;
    }).filter(Boolean);
    el.innerHTML = `
      <section class="page-intro"><div><span class="eyebrow">Cuenta</span><h1>Mi perfil</h1><p>Tus datos de acceso, autoridades y preferencias.</p></div></section>
      <div class="pf-grid">
        <section class="pf-id">
          <div class="pf-foto">${avatarHTML(p.nombre, p.foto_url, 'xl')}<span class="pf-verif" aria-hidden="true">${icon('badge-check')}</span></div>
          <span class="pf-rol ${p.rol === 'admin' ? 'admin' : ''}">${icon(p.rol === 'admin' ? 'crown' : 'user-round')} ${p.rol === 'admin' ? 'Administrador' : 'Usuario'}</span>
          <h2>${esc(p.nombre)}</h2>
          <p class="pf-puesto">${esc(p.puesto || 'Puesto no registrado')}</p>
          <span class="pf-mail">${icon('mail')} ${esc(p.email)}</span>
        </section>
        <div class="pf-info">
          <section class="pf-bloque"><h3 class="pf-sec">${icon('briefcase')} Información laboral</h3>
            <div class="pf-tiles t2">${fila('gafete', 'Puesto', p.puesto || 'Sin puesto asignado')}${fila('personas', 'Área', p.area || 'Sin área')}</div></section>
          <section class="pf-bloque"><h3 class="pf-sec">${icon('shield-check')} Acceso</h3>
            <div class="pf-tiles t2">${fila('llave', 'Permisos', p.rol === 'admin' ? 'Administración de catálogos, recetas, plantillas y usuarios; registrar y consultar pruebas' : 'Registrar y consultar pruebas; actuar según tus autoridades')}${fila('reloj', 'Último acceso', fmtDateTime(user?.last_sign_in_at))}</div></section>
          <section class="pf-bloque"><h3 class="pf-sec">${icon('bell')} Notificaciones en este dispositivo</h3><div id="notif-box"><div class="skeleton" style="height:64px"></div></div></section>
          <section class="pf-sistema"><span class="brand-logo pf-logo" aria-hidden="true"></span>
            <div><small>Pruebas industriales</small><b>Calidad de proceso <i aria-hidden="true">|</i> <span>Pet's Table</span></b></div>
            <span class="pf-ver"><small>Versión</small><b>${esc(APP_VERSION)}</b></span></section>
        </div>
      </div>
      <div class="card mt"><div class="card-head"><div><h3>${emoji('llave', 'h-ilus')}Tus autoridades</h3><p>Además, siempre puedes registrar pruebas y preparar las que registraste o tienes asignadas.</p></div></div>
        ${p.rol === 'admin' ? `<div class="notice">${icon('crown')}<span>Como <b>administrador</b> puedes realizar todas las acciones de las autoridades (definir, registrar, evaluar y dar veredicto por cualquier área, dictaminar y cerrar), por ejemplo para hacer pruebas o apoyar a un responsable.</span></div>` : ''}
        ${aut.length ? `<div class="list">${aut.map((a) => `<div class="list-item"><span class="pend-ico">${icon('key-round')}</span><div class="li-main"><b>${esc(a.lbl)}</b><span>${esc(a.tipos)}</span></div></div>`).join('')}</div>`
          : `<p class="hint">${p.puesto ? 'Tu puesto no tiene autoridades asignadas.' : 'Aún no tienes puesto asignado.'} Un administrador las configura en Usuarios › Autoridades.</p>`}</div>
      <div class="grid grid-2 mt">
        <div class="card">
          <div class="card-head"><div><h3>Cambiar contraseña</h3><p>Aplica a todas las aplicaciones de Pet's Table que usan esta cuenta.</p></div></div>
          <form id="pw-form" novalidate>
            <div class="field"><label for="pw1">Nueva contraseña <span class="req">*</span></label>
              <div class="pw-wrap"><input id="pw1" name="p1" type="password" autocomplete="new-password" minlength="8" maxlength="128" required>
              <button type="button" class="pw-toggle" data-action="toggle-pw" aria-label="Mostrar contraseña">${icon('eye')}</button></div></div>
            <div class="field"><label for="pw2">Confirmar contraseña <span class="req">*</span></label>
              <input id="pw2" name="p2" type="password" autocomplete="new-password" minlength="8" maxlength="128" required></div>
            <p class="hint">Mínimo 8 caracteres. Combina mayúsculas, minúsculas, números y símbolos.</p>
            <div class="form-error" role="alert"></div>
            <button type="submit" class="btn primary">${icon('key-round')} Actualizar contraseña</button>
          </form>
        </div>
        <div class="card">
          <div class="card-head"><div><h3>Apariencia</h3><p>Se guarda en este dispositivo.</p></div></div>
          <div class="seg" role="radiogroup" aria-label="Tema">
            <button data-theme-opt="light" class="${theme === 'light' ? 'active' : ''}">${icon('sun')} Claro</button>
            <button data-theme-opt="dark" class="${theme === 'dark' ? 'active' : ''}">${icon('moon')} Oscuro</button>
            <button data-theme-opt="system" class="${theme === 'system' ? 'active' : ''}">${icon('monitor-smartphone')} Sistema</button>
          </div>
          <div class="section-title" style="margin-top:22px">${icon('smartphone')} Instalar en la pantalla de inicio</div>
          ${standalone ? `<p class="hint">${icon('check-circle-2')} Ya estás usando la aplicación instalada.</p>` : `
          <button class="btn secondary hidden" id="install-btn">${icon('download')} Instalar aplicación</button>
          <p class="hint" style="margin:10px 0 6px"><b>iPhone / iPad (Safari):</b></p>
          <ol class="steps"><li>Toca el botón <b>Compartir</b>.</li><li>Elige <b>Agregar a pantalla de inicio</b>.</li><li>Confirma el nombre “Pruebas” y toca <b>Agregar</b>.</li></ol>
          <p class="hint" style="margin:10px 0 6px"><b>Android (Chrome):</b></p>
          <ol class="steps"><li>Abre el menú <b>⋮</b>.</li><li>Elige <b>Instalar aplicación</b> o <b>Agregar a pantalla principal</b>.</li></ol>`}
        </div>
      </div>
      <section class="cr mt" aria-labelledby="cr-t">
        <div class="cr-foto" id="cr-foto">${avatarHTML(AUTOR.nombre, null, 'xl')}</div>
        <div class="cr-cuerpo">
          <span class="cr-eyebrow">${icon('sparkles')} Desarrollado por</span>
          <h3 id="cr-t">${esc(AUTOR.nombre)}</h3>
          <p class="cr-rol">Creador y desarrollador de la plataforma</p>
          <p class="cr-txt">Concibió, diseñó, desarrolló e implementó Pruebas industriales: el flujo de las pruebas por etapas, la base de datos y sus permisos, los avisos y la experiencia en escritorio y móvil.</p>
          <ul class="cr-etapas" aria-label="Participación"><li>Conceptualización</li><li>Diseño</li><li>Desarrollo</li><li>Implementación</li></ul>
        </div>
        <figure class="cr-firma"><span class="cr-firma-img" role="img" aria-label="Firma de ${esc(AUTOR.nombre)}"></span>
          <figcaption><b>${esc(AUTOR.nombre)}</b><small>Autor de la plataforma</small></figcaption></figure>
      </section>`;
    refreshIcons();
    // Fotografía del autor: la de su cuenta (directorio de usuarios)
    getCat('usuarios').then((us) => {
      const a = us.find((u) => u.nombre === AUTOR.cuenta && u.foto_url);
      const caja = el.querySelector('#cr-foto');
      if (a && caja) caja.innerHTML = avatarHTML(AUTOR.nombre, a.foto_url, 'xl');
    }).catch(() => { /* sin fotografía */ });

    el.querySelectorAll('[data-theme-opt]').forEach((b) => b.addEventListener('click', () => {
      window.__prubindSetTheme?.(b.dataset.themeOpt);
      el.querySelectorAll('[data-theme-opt]').forEach((x) => x.classList.toggle('active', x === b));
    }));
    pintarNotificaciones(el.querySelector('#notif-box'));
    const ib = el.querySelector('#install-btn');
    if (ib && deferredPrompt) {
      ib.classList.remove('hidden');
      ib.addEventListener('click', async () => {
        deferredPrompt.prompt();
        const r = await deferredPrompt.userChoice.catch(() => null);
        if (r?.outcome === 'accepted') toast('Aplicación instalada.', 'success');
        deferredPrompt = null; ib.classList.add('hidden');
      });
    }

    const form = el.querySelector('#pw-form');
    let busy = false;
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      if (busy) return;
      form.querySelector('.form-error').textContent = '';
      if (!checkForm(form, { p2: (v, f) => (v !== f.p1.value ? 'Las contraseñas no coinciden.' : '') })) return;
      busy = true;
      const btn = form.querySelector('button[type=submit]'); btn.disabled = true;
      const { error } = await sb.auth.updateUser({ password: form.p1.value });
      busy = false; btn.disabled = false;
      if (error) {
        form.querySelector('.form-error').textContent = /same|different from the old/i.test(error.message)
          ? 'La nueva contraseña debe ser distinta de la actual.'
          : /weak|short|characters/i.test(error.message) ? 'La contraseña no cumple los requisitos de seguridad.'
          : /reauthentication|recent/i.test(error.message) ? 'Por seguridad, cierra sesión, vuelve a entrar e inténtalo de nuevo.'
          : errMsg(error);
        return;
      }
      form.reset();
      toast('Contraseña actualizada.', 'success');
    });
  },
};
