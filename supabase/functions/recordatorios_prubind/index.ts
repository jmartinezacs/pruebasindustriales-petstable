// Edge Function: recordatorios_prubind
// La invoca pg_cron de lunes a sábado a las 08:00 (Ciudad de México). Envía a
// cada persona con notificaciones activas un aviso con sus pendientes del día
// (iniciar, definir parámetros, registrar, evaluar, veredicto, dictamen o
// cierre), calculados con las mismas reglas que "Requieren tu intervención".
// Protegida con un secreto que vive en la base de datos (prubind_private.cron).
import webpush from 'npm:web-push@3.6.7';
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
function igual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json(405, { error: 'Método no permitido.' });
  try {
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: secreto } = await admin.rpc('prubind_cron_secreto');
    if (!secreto || !igual(req.headers.get('x-prubind-cron') || '', String(secreto))) return json(401, { error: 'No autorizado.' });

    const { data: pend, error } = await admin.rpc('prubind_pendientes_recordatorio');
    if (error) throw error;
    if (!pend?.length) return json(200, { ok: true, enviados: 0 });

    const { data: k } = await admin.rpc('prubind_vapid_claves');
    const claves = k?.[0];
    if (!claves) return json(200, { ok: true, enviados: 0, motivo: 'Sin claves de notificación' });
    webpush.setVapidDetails(claves.contacto, claves.vapid_publica, claves.vapid_privada);

    let push = 0;
    for (const p of pend as { usuario_id: string; nombre: string; total: number; pruebas: number; detalle: string }[]) {
      const nombre = String(p.nombre || '').split(' ')[0];
      const title = `Tienes ${p.total} pendiente${p.total === 1 ? '' : 's'} en Pruebas industriales`;
      const body = `Buen día, ${nombre}. ${p.pruebas === 1 ? 'Prueba' : 'Pruebas'}: ${p.detalle}. Toca para ver qué te corresponde.`;
      const { data: subs } = await admin.from('push_subs_prubind').select('id, endpoint, p256dh, auth').eq('usuario_id', p.usuario_id);
      for (const s of subs || []) {
        try {
          await webpush.sendNotification(
            { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
            JSON.stringify({ title, body, url: '/#/panel', tag: `pendientes-${p.usuario_id}` }),
            { TTL: 60 * 60 * 10, urgency: 'normal' },
          );
          push++;
        } catch (e) {
          const code = (e as { statusCode?: number }).statusCode;
          if (code === 404 || code === 410) await admin.from('push_subs_prubind').delete().eq('id', s.id);
          else console.error('push', code, (e as Error).message);
        }
      }
    }
    return json(200, { ok: true, personas: pend.length, push });
  } catch (e) {
    console.error('recordatorios_prubind', e);
    return json(500, { error: 'No se pudieron enviar los recordatorios.' });
  }
});
