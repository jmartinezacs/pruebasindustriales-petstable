-- =====================================================================
-- v3 · "Mis pendientes": la preparación aparece como pendiente solo para
-- quien tiene esa autoridad (Gerente de Producción) o es responsable
-- inicial; quien registra la prueba (Compras) ya no la ve como pendiente,
-- aunque conserva la posibilidad de ajustar la planeación.
-- =====================================================================
create or replace function public.prubind_mis_pendientes()
 returns table (prueba_id uuid, folio text, cambio text, tipo_nombre text, estado text, accion text)
 language plpgsql stable security definer set search_path = '' as $function$
#variable_conflict use_column
declare uid uuid := public.prubind_usuario_actual_id();
begin
  if uid is null then raise exception 'Usuario no autorizado.' using errcode = '42501'; end if;
  return query
  with p as (
    select x.*, t.nombre as tnom, t.requiere_aut_ejecucion as req_aut, public.prubind_eval_estado(x.id) as e
    from public.pruebas_prubind x join public.tipos_prueba_prubind t on t.codigo = x.tipo
    where x.estado not in ('cerrada_rechazada', 'cancelada')
  )
  select p.id, p.folio, p.cambio, p.tnom, p.estado, a.accion
  from p cross join lateral (values
    ('preparar'), ('abastecer'), ('autorizar_ejecucion'), ('ejecutar'), ('evaluar'), ('revisar'), ('dictaminar'), ('cerrar'), ('autorizar_implementacion')) a(accion)
  where case a.accion
    when 'preparar' then p.estado in ('registrada', 'en_preparacion', 'requiere_repeticion')
         and (public.prubind_tiene_autoridad(p.tipo, 'preparar') or uid is not distinct from p.responsable_inicial_id)
    when 'abastecer' then p.estado in ('en_preparacion', 'preparada') and public.prubind_tiene_autoridad(p.tipo, 'abastecer')
         and exists (select 1 from public.prueba_materiales_prubind m where m.prueba_id = p.id and m.disponibilidad in ('pendiente', 'en_compra'))
    when 'autorizar_ejecucion' then p.estado = 'preparada' and p.req_aut and not (p.e ->> 'aut_ejecucion')::boolean
         and public.prubind_puede(p.id, 'autorizar_ejecucion')
    when 'ejecutar' then (p.estado = 'en_ejecucion' or (p.estado = 'preparada' and public.prubind_ejecucion_abierta(p.id))) and public.prubind_puede(p.id, 'ejecutar')
    when 'evaluar' then p.estado in ('en_evaluacion', 'pendiente_resultados') and public.prubind_puede(p.id, 'evaluar')
    when 'revisar' then p.estado in ('en_ejecucion', 'en_evaluacion', 'pendiente_resultados', 'pendiente_dictamen')
         and exists (select 1 from public.resultados_prubind r join public.metodos_prubind m on m.id = r.metodo_id
                     where r.prueba_id = p.id and r.ejecucion = p.ejecucion_actual and r.estado <> 'pendiente' and r.revisado_por is null
                       and m.revisa_puesto_id = public.prubind_puesto_actual())
    when 'dictaminar' then p.estado = 'pendiente_dictamen' and public.prubind_puede(p.id, 'dictaminar')
    when 'cerrar' then p.estado in ('aprobada', 'rechazada') and public.prubind_puede(p.id, 'cerrar')
    when 'autorizar_implementacion' then p.estado = 'cerrada_aprobada' and public.prubind_puede(p.id, 'autorizar_implementacion')
         and not exists (select 1 from public.autorizaciones_prubind z where z.prueba_id = p.id and z.tipo = 'implementacion'
                         and (z.autorizado_por = uid or (z.puesto_id is not null and z.puesto_id = public.prubind_puesto_actual())))
    else false end
  order by p.created_at;
end $function$;
