-- =====================================================================
-- Pruebas industriales · Migración 3/3: datos iniciales proporcionados
-- por el usuario (áreas, tipos de prueba, usuarios y responsables).
-- =====================================================================

insert into public.areas_prubind (nombre) values
  ('Procesos y mejora continua'), ('Producción'), ('Compras'), ('Alta dirección'), ('Material de empaque')
on conflict do nothing;

insert into public.tipos_prueba_prubind (codigo, nombre, descripcion, prefijo, usa_proveedor, usa_empaque, usa_envasadora, orden) values
  ('producto_nuevo',     'Producto nuevo (innovación)',    'Desarrollo e introducción de un producto o receta nueva.', 'PN', false, false, false, 1),
  ('cambio_formulacion', 'Cambio en la formulación',       'Ajuste de cantidades o ingredientes de una fórmula existente.', 'CF', false, false, false, 2),
  ('cambio_proveedor',   'Cambio de proveedor',            'Evaluación de un insumo de un proveedor nuevo.', 'CP', true, false, false, 3),
  ('material_empaque',   'Cambio de material de empaque',  'Evaluación de un material de empaque nuevo en la envasadora.', 'ME', false, true, true, 4)
on conflict (codigo) do nothing;

-- Usuarios iniciales (rol según lo indicado; funciones según la descripción del proceso)
insert into public.usuarios_prubind (email, nombre, area_id, rol, funciones)
select v.email, v.nombre, a.id, v.rol, v.funciones
from (values
  ('javier.martinez@petstable.mx', 'Javier Martínez', 'Procesos y mejora continua', 'admin',   '{}'::text[]),
  ('nelisa.ramirez@petstable.mx',  'Nelisa Ramírez',  'Procesos y mejora continua', 'admin',   '{}'::text[]),
  ('abigail.ordaz@petstable.mx',   'Abigail Ordaz',   'Procesos y mejora continua', 'usuario', '{calidad}'::text[]),
  ('juan.rodriguez@petstable.mx',  'Juan Rodríguez',  'Producción',                 'usuario', '{produccion}'::text[]),
  ('laura.vasquez@petstable.mx',   'Laura Vásquez',   'Compras',                    'usuario', '{compras}'::text[]),
  ('camila@petstable.mx',          'Camila',          'Alta dirección',             'admin',   '{direccion}'::text[]),
  ('rafa@petstable.mx',            'Rafa',            'Material de empaque',        'usuario', '{}'::text[])
) as v(email, nombre, area, rol, funciones)
join public.areas_prubind a on lower(a.nombre) = lower(v.area)
on conflict do nothing;

-- Fotos existentes del bucket público "avatares" (solo se enlazan; no se copian ni modifican)
update public.usuarios_prubind u set foto_url = 'https://domumnsezocubigfqwry.supabase.co/storage/v1/object/public/avatares/' || v.archivo
from (values
  ('javier.martinez@petstable.mx', 'Javier.png'),
  ('nelisa.ramirez@petstable.mx',  'Nelisa.png'),
  ('abigail.ordaz@petstable.mx',   'Abigail.png'),
  ('camila@petstable.mx',          'Camila.png'),
  ('rafa@petstable.mx',            'Rafael.png')
) as v(email, archivo)
where u.email = v.email and u.foto_url is null
  and exists (select 1 from storage.objects o where o.bucket_id = 'avatares' and o.name = v.archivo);

-- Responsables que detonan cada tipo de prueba (los administradores pueden registrar cualquiera)
insert into public.tipo_responsables_prubind (tipo, usuario_id)
select v.tipo, u.id
from (values
  ('producto_nuevo',     'camila@petstable.mx'),
  ('cambio_formulacion', 'camila@petstable.mx'),
  ('cambio_proveedor',   'laura.vasquez@petstable.mx'),
  ('material_empaque',   'rafa@petstable.mx')
) as v(tipo, email)
join public.usuarios_prubind u on u.email = v.email
on conflict do nothing;
