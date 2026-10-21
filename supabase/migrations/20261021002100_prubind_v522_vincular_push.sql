-- =====================================================================
-- Pruebas industriales · v5.2.2 · Vincular el dispositivo a quien inicia sesión
-- Al cerrar sesión el dispositivo ya no se da de baja del navegador (no hay que
-- volver a dar permiso); solo se desvincula del usuario. Al iniciar sesión se
-- vuelve a vincular a quien entra, aunque la suscripción hubiera quedado
-- registrada a nombre de otra persona (quien tiene el endpoint y sus claves es
-- el propio dispositivo).
-- =====================================================================
create or replace function public.prubind_vincular_push(p_endpoint text, p_p256dh text, p_auth text, p_dispositivo text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := public.prubind_usuario_actual_id();
begin
  if uid is null then raise exception 'Usuario no autorizado.' using errcode = '42501'; end if;
  if p_endpoint !~ '^https://' or char_length(p_endpoint) > 1000 then raise exception 'Suscripción no válida.' using errcode = 'P0001'; end if;
  delete from public.push_subs_prubind where endpoint = p_endpoint and usuario_id <> uid;
  insert into public.push_subs_prubind (usuario_id, endpoint, p256dh, auth, dispositivo)
  values (uid, p_endpoint, p_p256dh, p_auth, left(p_dispositivo, 200))
  on conflict (endpoint) do update set p256dh = excluded.p256dh, auth = excluded.auth, dispositivo = excluded.dispositivo;
end $$;
revoke all on function public.prubind_vincular_push(text, text, text, text) from public, anon;
grant execute on function public.prubind_vincular_push(text, text, text, text) to authenticated;
