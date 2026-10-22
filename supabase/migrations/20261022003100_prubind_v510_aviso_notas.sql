-- v5.10 · Aviso push cuando alguien escribe una nota en Seguimiento.
-- Destinatarios ("involucrados"): quien registró, el responsable, los responsables de las áreas
-- con parámetros en la prueba y toda persona que haya registrado algo en ella (notas, datos,
-- evaluaciones, veredictos o dictamen). La Edge Function excluye a quien escribió la nota.
alter table public.avisos_prubind drop constraint if exists avisos_prubind_evento_check;
alter table public.avisos_prubind add constraint avisos_prubind_evento_check
  check (evento = any (array['nueva_prueba', 'iniciada', 'terminada', 'lista_dictamen', 'dictamen', 'nota']));

create or replace function public.prubind_destinatarios_aviso(p_prueba uuid, p_evento text)
returns table(id uuid, nombre text) language sql stable security definer set search_path = '' as $$
  with p as (select * from public.pruebas_prubind where id = p_prueba),
  acc as (
    select unnest(case p_evento
      when 'nueva_prueba' then array['evaluar_calidad','evaluar_produccion','evaluar_seguridad','evaluar_mantenimiento',
                                     'capturar_calidad','capturar_produccion','capturar_seguridad','capturar_mantenimiento','dictaminar']
      when 'iniciada' then array['evaluar_calidad','evaluar_produccion','evaluar_seguridad','evaluar_mantenimiento',
                                 'capturar_calidad','capturar_produccion','capturar_seguridad','capturar_mantenimiento']
      when 'terminada' then (select coalesce(array_agg('evaluar_' || a), '{}') from unnest(public.prubind_areas_participantes(p_prueba)) a)
      when 'lista_dictamen' then array['dictaminar']
      when 'dictamen' then array['evaluar_calidad','evaluar_produccion','evaluar_seguridad','evaluar_mantenimiento','cerrar']
      when 'nota' then (select coalesce(array_agg('evaluar_' || a), '{}') from unnest(public.prubind_areas_prueba(p_prueba)) a)
      else array[]::text[] end) accion
  ),
  autores as (
    select s.usuario_id uid from public.seguimiento_prubind s where s.prueba_id = p_prueba
    union select r.capturado_por from public.resultados_prubind r where r.prueba_id = p_prueba
    union select e.evaluado_por from public.evaluaciones_prubind e where e.prueba_id = p_prueba
    union select x.emitido_por from public.recomendaciones_prubind x where x.prueba_id = p_prueba
    union select d.emitido_por from public.dictamenes_prubind d where d.prueba_id = p_prueba
  )
  select distinct u.id, u.nombre
    from public.usuarios_prubind u, p
   where u.activo
     and (exists (select 1 from public.autoridades_prubind a join acc on acc.accion = a.accion
                  where a.activo and (a.tipo is null or a.tipo = p.tipo)
                    and (a.usuario_id = u.id or (a.puesto_id is not null and a.puesto_id = u.puesto_id)))
          or (p_evento = 'dictamen' and u.id = p.registrado_por)
          or (p_evento = 'nota' and (u.id = p.registrado_por or u.id = p.responsable_inicial_id
                                     or u.id in (select uid from autores where uid is not null))))
$$;
revoke all on function public.prubind_destinatarios_aviso(uuid, text) from public, anon, authenticated;
grant execute on function public.prubind_destinatarios_aviso(uuid, text) to service_role;
