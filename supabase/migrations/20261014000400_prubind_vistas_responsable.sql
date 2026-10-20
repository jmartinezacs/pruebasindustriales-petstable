-- =====================================================================
-- Pruebas industriales · Migración 4
-- Agrega el responsable de la prueba (prueba_creado_por) a las vistas de
-- batches e insumos, para que la interfaz muestre las acciones correctas.
-- (Solo se agregan columnas al final; las consultas existentes no cambian.)
-- =====================================================================
create or replace view public.v_batches_prubind with (security_invoker = true) as
select b.id, b.prueba_id, b.numero, b.fecha_programada, b.fecha_real, b.lote, b.cantidad, b.unidad, b.estado,
       b.observaciones, b.motivo_cancelacion, b.registrado_por, u.nombre as registrado_por_nombre, b.updated_at,
       t.prefijo || '-' || lpad(p.folio::text, 4, '0') as folio_txt, p.titulo, p.tipo, t.nombre as tipo_nombre,
       p.estado as prueba_estado, p.producto, p.num_batches,
       (select count(*) from public.resultados_prubind r where r.batch_id = b.id)::int as resultados_total,
       (select count(*) from public.resultados_prubind r where r.batch_id = b.id and r.resultado = 'no_cumple')::int as resultados_no_cumple,
       p.creado_por as prueba_creado_por
from public.batches_prubind b
join public.pruebas_prubind p on p.id = b.prueba_id
join public.tipos_prueba_prubind t on t.codigo = p.tipo
left join public.usuarios_prubind u on u.id = b.registrado_por;

create or replace view public.v_insumos_prubind with (security_invoker = true) as
select i.*, t.prefijo || '-' || lpad(p.folio::text, 4, '0') as folio_txt, p.titulo, p.tipo, t.nombre as tipo_nombre,
       p.estado as prueba_estado, p.num_batches,
       s.nombre as solicitado_por_nombre, v.nombre as validado_por_nombre, c.nombre as compras_por_nombre,
       p.creado_por as prueba_creado_por
from public.insumos_prubind i
join public.pruebas_prubind p on p.id = i.prueba_id
join public.tipos_prueba_prubind t on t.codigo = p.tipo
join public.usuarios_prubind s on s.id = i.solicitado_por
left join public.usuarios_prubind v on v.id = i.validado_por
left join public.usuarios_prubind c on c.id = i.compras_por;

revoke all on public.v_batches_prubind, public.v_insumos_prubind from anon, public;
grant select on public.v_batches_prubind, public.v_insumos_prubind to authenticated;
