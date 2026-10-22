// Edge Function: notificar_prubind
// Envía avisos push (Web Push) de Pruebas industriales. La invoca el sitio después
// de registrar, iniciar, terminar, enviar a dictamen o dictaminar una prueba, y al escribir una nota en Seguimiento; la función
// valida en la base de datos que el evento sea real, reciente y no duplicado.
// Las claves VAPID se generan aquí la primera vez y viven en prubind_private.
import webpush from 'npm:web-push@3.6.7';
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
const b64u = (buf: ArrayBuffer) =>
  btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const corto = (s: string, n = 90) => (s.length > n ? `${s.slice(0, n - 1)}…` : s);

const EVENTOS = ['nueva_prueba', 'iniciada', 'terminada', 'lista_dictamen', 'dictamen', 'nota'];
const DICTAMEN: Record<string, string> = {
  aprobada: 'APROBADA', rechazada: 'RECHAZADA', requiere_repeticion: 'REQUIERE REPETICIÓN', pendiente_resultados: 'PENDIENTE DE RESULTADOS',
};

// deno-lint-ignore no-explicit-any
async function asegurarClaves(admin: any) {
  const r = await admin.rpc('prubind_vapid_claves');
  if (r.data?.[0]) return r.data[0];
  const kp = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const pub = b64u(await crypto.subtle.exportKey('raw', kp.publicKey));
  const jwk = await crypto.subtle.exportKey('jwk', kp.privateKey);
  const g = await admin.rpc('prubind_vapid_guardar', { p_publica: pub, p_privada: jwk.d });
  if (g.error) throw g.error;
  return (await admin.rpc('prubind_vapid_claves')).data[0];
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json(405, { error: 'Método no permitido.' });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const caller = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: perfil, error: pErr } = await caller.rpc('prubind_mi_perfil');
    const yo = perfil?.[0];
    if (pErr || !yo) return json(403, { error: 'Usuario no autorizado.' });

    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false, autoRefreshToken: false } });
    const body = await req.json().catch(() => ({}));

    // Inicializa las claves VAPID (cualquier miembro; idempotente)
    if (body.accion === 'init') {
      const k = await asegurarClaves(admin);
      return json(200, { publica: k.vapid_publica });
    }
    if (body.accion !== 'aviso') return json(400, { error: 'Acción no válida.' });

    const evento = String(body.evento || '');
    if (!EVENTOS.includes(evento)) return json(400, { error: 'Evento no válido.' });
    const { data: p, error: e1 } = await admin.from('pruebas_prubind')
      .select('id, folio, cambio, tipo, estado, prioridad, ejecucion_actual, registrado_por, created_at, updated_at, tipos:tipos_prueba_prubind(nombre)')
      .eq('id', String(body.prueba_id || '')).maybeSingle();
    if (e1) throw e1;
    if (!p) return json(404, { error: 'Prueba no encontrada.' });

    // Validación del evento contra el estado real de la prueba
    const reciente = (ts: string) => Date.now() - new Date(ts).getTime() < 15 * 60 * 1000;
    const puede = async (accion: string) => (await caller.rpc('prubind_puede', { p_prueba: p.id, p_accion: accion })).data === true;
    let ok = false;
    if (evento === 'nueva_prueba') ok = p.registrado_por === yo.id && reciente(p.created_at);
    if (evento === 'iniciada') ok = p.estado === 'en_ejecucion' && reciente(p.updated_at) && await puede('responsable');
    if (evento === 'terminada') ok = ['en_evaluacion', 'pendiente_resultados'].includes(p.estado) && reciente(p.updated_at) && await puede('responsable');
    if (evento === 'lista_dictamen') ok = p.estado === 'pendiente_dictamen' && reciente(p.updated_at);
    if (evento === 'dictamen') ok = !!DICTAMEN[p.estado] && reciente(p.updated_at) && await puede('dictaminar');
    // Nota de seguimiento: debe existir, ser de esta prueba, de quien avisa y reciente
    let nota: { id: number; texto: string } | null = null;
    if (evento === 'nota') {
      const { data: s } = await admin.from('seguimiento_prubind').select('id, prueba_id, tipo, texto, usuario_id, created_at')
        .eq('id', Number(body.seguimiento_id) || 0).maybeSingle();
      ok = !!s && s.prueba_id === p.id && s.tipo === 'nota' && s.usuario_id === yo.id && reciente(s.created_at);
      if (ok) nota = { id: s!.id, texto: String(s!.texto || '') };
    }
    if (!ok) return json(409, { error: 'El evento no corresponde al estado actual de la prueba.' });

    const { data: dest, error: e2 } = await admin.rpc('prubind_destinatarios_aviso', { p_prueba: p.id, p_evento: evento });
    if (e2) throw e2;
    const ids = (dest || []).map((d: { id: string }) => d.id).filter((id: string) => id !== yo.id);
    if (!ids.length) return json(200, { ok: true, enviados: 0, motivo: 'Sin destinatarios' });

    // Evita duplicados (misma prueba, evento y ejecución)
    const clave = evento === 'dictamen' ? `${p.ejecucion_actual}-${p.estado}` : evento === 'nota' ? `nota-${nota!.id}` : String(p.ejecucion_actual);
    const ins = await admin.from('avisos_prubind').insert({ prueba_id: p.id, evento, clave }).select('id').maybeSingle();
    if (ins.error) {
      if (ins.error.code === '23505') return json(200, { ok: true, duplicado: true });
      throw ins.error;
    }

    const nombre = String(yo.nombre || '').split(' ').slice(0, 2).join(' ');
    const urg = p.prioridad === 'urgente' ? 'URGENTE · ' : p.prioridad === 'alta' ? 'Prioridad alta · ' : '';
    const tipo = (p.tipos as { nombre?: string } | null)?.nombre || 'Prueba';
    const prueba = `«${corto(p.cambio)}»`;
    const txt: Record<string, [string, string]> = {
      nueva_prueba: [`${urg}Nueva prueba ${p.folio}`, `${nombre} registró ${prueba} (${tipo}). Defina los parámetros que evaluará su área.`],
      iniciada: [`${urg}Prueba ${p.folio} en proceso`, `${nombre} inició ${prueba}. Ya puede registrar los parámetros de su área.`],
      terminada: [`Prueba ${p.folio} terminada: evalúe su área`, `${nombre} terminó ${prueba}. Evalúe los resultados de su área (Cumple / No cumple) y registre su veredicto.`],
      lista_dictamen: [`Prueba ${p.folio} lista para dictamen`, `Las áreas que participaron ya evaluaron ${prueba}. Pendiente su dictamen.`],
      dictamen: [`Dictamen de ${p.folio}: ${DICTAMEN[p.estado] || ''}`, `${nombre} emitió el dictamen de ${prueba}.`],
      nota: [`Nota en ${p.folio}`, `${nombre}: ${corto(nota?.texto || '', 140)}`],
    };
    const [title, msg] = txt[evento];
    // Foto de quien genera el aviso (solo fotos públicas del Storage de este proyecto);
    // el service worker la muestra como ícono con la insignia de la app
    const foto = typeof yo.foto_url === 'string' && yo.foto_url.startsWith(`${url}/storage/v1/object/public/`) ? yo.foto_url : null;

    let push = 0;
    const k = await asegurarClaves(admin);
    webpush.setVapidDetails(k.contacto, k.vapid_publica, k.vapid_privada);
    const { data: subs } = await admin.from('push_subs_prubind').select('id, endpoint, p256dh, auth').in('usuario_id', ids);
    for (const s of subs || []) {
      try {
        await webpush.sendNotification(
          { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
          JSON.stringify({ title, body: msg, url: `/#/pruebas?id=${p.id}`, tag: evento === 'nota' ? `${p.id}-nota-${nota!.id}` : `${p.id}-${evento}`, foto }),
          { TTL: 60 * 60 * 24, urgency: 'high' },
        );
        push++;
      } catch (e) {
        const code = (e as { statusCode?: number }).statusCode;
        if (code === 404 || code === 410) await admin.from('push_subs_prubind').delete().eq('id', s.id);
        else console.error('push', code, (e as Error).message);
      }
    }
    await admin.from('avisos_prubind').update({ enviados_push: push }).eq('id', ins.data!.id);
    return json(200, { ok: true, push });
  } catch (e) {
    console.error('notificar_prubind', e);
    return json(500, { error: 'No se pudo enviar el aviso.' });
  }
});
