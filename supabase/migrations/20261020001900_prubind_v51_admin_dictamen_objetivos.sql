-- =====================================================================
-- Pruebas industriales · v5.1
--  1. El rol Administrador puede hacer todo lo que hacen los responsables
--     de Autoridades (para probar y apoyar sin usar cuentas ajenas).
--  2. Dictamen y aprobación en un solo paso: el dictamen "Aprobada" de Alta
--     Dirección autoriza implementar el cambio; después la Gerencia de
--     Procesos y Mejora Continua cierra. La autorización separada de
--     implementación se desactiva (los registros anteriores se conservan).
--  3. Objetivos según el tipo de prueba.
-- Solo objetos *_prubind. No destructiva.
-- =====================================================================

-- ---------- 1. Administrador con todas las autoridades ----------
create or replace function public.prubind_tiene_autoridad(p_tipo text, p_accion text)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.prubind_es_admin() or exists (
    select 1 from public.autoridades_prubind a
    where a.activo and a.accion = p_accion and (a.tipo is null or a.tipo = p_tipo)
      and ((a.usuario_id is not null and a.usuario_id = public.prubind_usuario_actual_id())
        or (a.puesto_id is not null and a.puesto_id = public.prubind_puesto_actual())))
$$;

do $$
declare d text; o text;
begin
  -- Mismo criterio en las variantes por prefijo y "alguna"
  d := pg_get_functiondef('public.prubind_tiene_autoridad_prefijo(text,text)'::regprocedure); o := d;
  d := regexp_replace(d, 'select exists', 'select public.prubind_es_admin() or exists');
  if d = o then raise exception 'No se pudo ajustar prubind_tiene_autoridad_prefijo'; end if;
  execute d;
  d := pg_get_functiondef('public.prubind_tiene_autoridad_alguna(text)'::regprocedure); o := d;
  d := regexp_replace(d, 'select exists', 'select public.prubind_es_admin() or exists');
  if d = o then raise exception 'No se pudo ajustar prubind_tiene_autoridad_alguna'; end if;
  execute d;

  -- ---------- 2. Dictamen = aprobación ----------
  d := pg_get_functiondef('public.prubind_accion(uuid,text,jsonb)'::regprocedure); o := d;
  d := replace(d, $q$when 'aprobada' then 'APROBADA'$q$, $q$when 'aprobada' then 'APROBADA (se autoriza implementar el cambio)'$q$);
  d := replace(d, $q$' La aprobación no libera producto ni autoriza por sí misma el cambio en producción.'$q$,
                  $q$' El cambio quedó autorizado en el dictamen de Alta Dirección.'$q$);
  if d = o then raise exception 'No se pudo ajustar prubind_accion'; end if;
  execute d;

  -- Sin pendiente de "autorizar implementación"
  d := pg_get_functiondef('public.prubind_mis_pendientes()'::regprocedure); o := d;
  d := regexp_replace(d, '\s+union all\s+select p\.id, p\.folio, p\.cambio, p\.tnom, p\.estado, ''autorizar_implementacion''.*?public\.prubind_puesto_actual\(\)\)\)\);',
                      ';', 's');
  if d = o then raise exception 'No se pudo ajustar prubind_mis_pendientes'; end if;
  execute d;
end $$;

update public.autoridades_prubind set activo = false where accion = 'autorizar_implementacion' and activo;

-- ---------- 3. Objetivos por tipo de prueba ----------
-- Se conservan "Cumplir un requisito de cliente o regulatorio" y "Otro (describir)" para todos los tipos;
-- los demás generales se desactivan (las pruebas que ya los usan los conservan).
update public.objetivos_prubind set tipo = 'producto_nuevo', orden = 1 where nombre = 'Validar una receta nueva' and tipo is null;
update public.objetivos_prubind set activo = false
 where tipo is null and nombre not in ('Cumplir un requisito de cliente o regulatorio', 'Otro (describir)');
update public.objetivos_prubind set orden = 50 where tipo is null and nombre = 'Cumplir un requisito de cliente o regulatorio';

insert into public.objetivos_prubind (tipo, nombre, orden)
select v.tipo, v.nombre, v.orden from (values
  ('producto_nuevo', 'Validar el proceso de fabricación del producto nuevo', 2),
  ('producto_nuevo', 'Confirmar que el producto nuevo cumple con calidad e inocuidad', 3),
  ('cambio_formulacion', 'Evaluar el cambio de ingredientes o proporciones de la receta', 1),
  ('cambio_formulacion', 'Mejorar la calidad del producto', 2),
  ('cambio_formulacion', 'Reducir el costo de la formulación', 3),
  ('cambio_proveedor', 'Evaluar la materia prima de un proveedor nuevo', 1),
  ('cambio_proveedor', 'Asegurar el abasto con un proveedor alterno', 2),
  ('cambio_proveedor', 'Reducir el costo de la materia prima', 3),
  ('material_empaque', 'Evaluar un material de empaque nuevo', 1),
  ('material_empaque', 'Validar el desempeño del empaque en el equipo', 2),
  ('material_empaque', 'Reducir el costo del empaque', 3),
  ('cambio_proceso', 'Evaluar un cambio en las condiciones del proceso', 1),
  ('cambio_proceso', 'Mejorar el desempeño del proceso o del equipo', 2),
  ('cambio_proceso', 'Mejorar la inocuidad o la calidad del producto', 3)
) v(tipo, nombre, orden)
where not exists (select 1 from public.objetivos_prubind o where o.tipo = v.tipo and lower(o.nombre) = lower(v.nombre));
