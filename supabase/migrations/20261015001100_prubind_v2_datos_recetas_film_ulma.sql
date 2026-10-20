-- =====================================================================
-- Datos maestros entregados por el usuario (hoja de Google "Recetas,
-- empaque y equipo", 15/10/2026):
--   · 3 recetas vigentes (v1) con cantidades estándar por batch en kg
--   · especificaciones del film de empaque primario (estándar, mín., máx.)
--   · parámetros de operación de la ULMA
-- Solo inserta (no modifica ni borra). Se puede volver a ejecutar.
-- Normalización de nombres de ingredientes (misma materia prima):
--   "Espinacas" → "Espinaca"; se acentuaron "corazón" y "pulmón".
-- =====================================================================
do $$
declare
  kg uuid := (select id from public.unidades_prubind where simbolo = 'kg');
  ref constant text := 'Hoja "Recetas, empaque y equipo" entregada por Procesos y Mejora Continua (15/10/2026)';
  r record; v_prod uuid; v_rec uuid; v_ver uuid; v_eq uuid; v_un uuid; v_met uuid; n int;
begin
  -- ---------- Recetas ----------
  for r in
    select * from (values
      ('Chicken Chase', 1, 'Filete de pollo', 24.5), ('Chicken Chase', 2, 'Recorte de pollo', 52.2),
      ('Chicken Chase', 3, 'Hígado y corazón de pollo', 34.8), ('Chicken Chase', 4, 'Molleja de pollo', 34.9),
      ('Chicken Chase', 5, 'Zanahoria', 41.2), ('Chicken Chase', 6, 'Papa', 20.6), ('Chicken Chase', 7, 'Plátano', 25.0),
      ('Chicken Chase', 8, 'Chícharo', 3.0), ('Chicken Chase', 9, 'Espinaca', 2.1), ('Chicken Chase', 10, 'Arándanos', 2.9),
      ('Chicken Chase', 11, 'Chía', 0.25), ('Chicken Chase', 12, 'Calcio', 0.8), ('Chicken Chase', 13, 'Aceite de pescado', 0.10),
      ('Chicken Chase', 14, 'Vitamina E', 0.01), ('Chicken Chase', 15, 'Levadura', 2.0), ('Chicken Chase', 16, 'Tapioca', 0.64),
      ('Chicken Chase', 17, 'Sal', 0.25), ('Chicken Chase', 18, 'Inulina', 1.23), ('Chicken Chase', 19, 'Fibra', 2.1),
      ('Meat Festival', 1, 'Molida de res', 35.50), ('Meat Festival', 2, 'Corazón de res', 57.60), ('Meat Festival', 3, 'Hígado de res', 13.50),
      ('Meat Festival', 4, 'Pulmón de res', 31.90), ('Meat Festival', 5, 'Bazo de res', 14.70), ('Meat Festival', 6, 'Zanahoria', 38.70),
      ('Meat Festival', 7, 'Camote', 9.80), ('Meat Festival', 8, 'Plátano', 20.00), ('Meat Festival', 9, 'Papa', 6.10),
      ('Meat Festival', 10, 'Lentejas', 1.90), ('Meat Festival', 11, 'Espinaca', 0.74), ('Meat Festival', 12, 'Brócoli', 10.60),
      ('Meat Festival', 13, 'Chía', 0.25), ('Meat Festival', 14, 'Calcio', 1.10), ('Meat Festival', 15, 'Fibra', 2.0),
      ('Meat Festival', 16, 'Aceite de pescado', 0.12), ('Meat Festival', 17, 'Vitamina E', 0.01), ('Meat Festival', 18, 'Levadura', 2.0),
      ('Meat Festival', 19, 'Tapioca', 0.64), ('Meat Festival', 20, 'Sal', 0.25), ('Meat Festival', 21, 'Inulina', 1.23),
      ('Tasty Piggy', 1, 'Pierna de cerdo', 52.7), ('Tasty Piggy', 2, 'Hígado de cerdo', 12.3), ('Tasty Piggy', 3, 'Corazón de cerdo', 63.0),
      ('Tasty Piggy', 4, 'Bazo de cerdo', 17.2), ('Tasty Piggy', 5, 'Camote', 14.7), ('Tasty Piggy', 6, 'Papa', 7.1),
      ('Tasty Piggy', 7, 'Brócoli', 5.9), ('Tasty Piggy', 8, 'Zanahoria', 40.3), ('Tasty Piggy', 9, 'Espinaca', 1.2),
      ('Tasty Piggy', 10, 'Garbanzo', 2.45), ('Tasty Piggy', 11, 'Plátano', 25), ('Tasty Piggy', 12, 'Chía', 0.25),
      ('Tasty Piggy', 13, 'Calcio', 1.1), ('Tasty Piggy', 14, 'Fibra', 2.0), ('Tasty Piggy', 15, 'Aceite de pescado', 0.12),
      ('Tasty Piggy', 16, 'Vitamina E', 0.01), ('Tasty Piggy', 17, 'Levadura', 2.0), ('Tasty Piggy', 18, 'Sal', 0.25),
      ('Tasty Piggy', 19, 'Inulina', 1.23), ('Tasty Piggy', 20, 'Tapioca', 0.64)
    ) x(receta, orden, ingrediente, cantidad)
  loop
    insert into public.materias_primas_prubind (nombre, categoria, unidad_id)
    values (r.ingrediente, 'ingrediente', kg) on conflict (lower(btrim(nombre))) do nothing;
    insert into public.productos_prubind (nombre) values (r.receta) on conflict (lower(btrim(nombre))) do nothing;
    select id into v_prod from public.productos_prubind where lower(nombre) = lower(r.receta);
    insert into public.recetas_prubind (producto_id, nombre) values (v_prod, r.receta) on conflict (lower(btrim(nombre))) do nothing;
    select id into v_rec from public.recetas_prubind where lower(nombre) = lower(r.receta);
    -- Solo se capturan ingredientes si la receta aún no tiene versión v1
    select id into v_ver from public.receta_versiones_prubind where receta_id = v_rec and version = 'v1';
    if v_ver is null then
      insert into public.receta_versiones_prubind (receta_id, version, notas) values (v_rec, 'v1', 'Carga inicial: ' || ref) returning id into v_ver;
    end if;
    if (select estado from public.receta_versiones_prubind where id = v_ver) = 'borrador'
       and not exists (select 1 from public.receta_ingredientes_prubind i join public.materias_primas_prubind m on m.id = i.materia_prima_id
                       where i.version_id = v_ver and lower(m.nombre) = lower(r.ingrediente)) then
      insert into public.receta_ingredientes_prubind (version_id, materia_prima_id, cantidad, unidad_id, orden)
      values (v_ver, (select id from public.materias_primas_prubind where lower(nombre) = lower(r.ingrediente)), r.cantidad, kg, r.orden);
    end if;
  end loop;
  update public.receta_versiones_prubind v set estado = 'vigente'
  where v.version = 'v1' and v.estado = 'borrador'
    and v.receta_id in (select id from public.recetas_prubind where nombre in ('Chicken Chase', 'Meat Festival', 'Tasty Piggy'));

  -- ---------- Unidades nuevas ----------
  insert into public.unidades_prubind (simbolo, nombre)
  select x.s, x.n from (values ('galgas', 'Galgas (calibre)'), ('cm', 'Centímetro')) x(s, n)
  where not exists (select 1 from public.unidades_prubind u where u.simbolo = x.s);

  -- ---------- Especificaciones del film (empaque primario) ----------
  n := (select coalesce(max(orden), 0) from public.plantilla_evaluacion_prubind where tipo = 'material_empaque');
  for r in
    select * from (values
      ('EP-CALIBRE', 'Calibre total del film', 'galgas', 292::numeric, 262.8::numeric, 321.2::numeric),
      ('EP-ANCHO', 'Ancho total del film', 'cm', 41.6, 41.5, 41.7),
      ('EP-REPET', 'Repetición del film', 'cm', 29.9, 29.7, 30.1),
      ('EP-BOBINA', 'Peso final de la bobina', 'kg', 24, 23, 25)
    ) x(codigo, nombre, unidad, estandar, minimo, maximo)
  loop
    v_un := (select id from public.unidades_prubind where simbolo = r.unidad);
    insert into public.metodos_prubind (codigo, nombre, categoria, tipo_resultado, unidad_id, procedimiento_ref)
    values (r.codigo, r.nombre, 'empaque_primario', 'numerico', v_un, 'Especificación del film · ' || ref)
    on conflict (codigo) do nothing;
    v_met := (select id from public.metodos_prubind where codigo = r.codigo);
    if not exists (select 1 from public.especificaciones_prubind where metodo_id = v_met and vigente) then
      insert into public.especificaciones_prubind (metodo_id, minimo, maximo, criterio_texto, referencia, version, vigente)
      values (v_met, r.minimo, r.maximo, 'Estándar ' || r.estandar || ' ' || r.unidad || ' (mín. ' || r.minimo || ', máx. ' || r.maximo || ')', ref, '1', true);
    end if;
    if not exists (select 1 from public.plantilla_evaluacion_prubind where tipo = 'material_empaque' and metodo_id = v_met) then
      n := n + 1;
      insert into public.plantilla_evaluacion_prubind (tipo, metodo_id, nivel, obligatorio, orden)
      values ('material_empaque', v_met, 'corrida', true, n);
    end if;
  end loop;

  -- ---------- Equipo ULMA y sus parámetros ----------
  insert into public.equipos_prubind (nombre) values ('ULMA') on conflict (lower(btrim(nombre))) do nothing;
  v_eq := (select id from public.equipos_prubind where lower(nombre) = 'ulma');
  insert into public.equipo_parametros_prubind (equipo_id, nombre, unidad_id, minimo, maximo, referencia)
  select v_eq, x.nombre, (select id from public.unidades_prubind where simbolo = x.un), x.mn, x.mx, x.ref_txt
  from (values
    ('Avance', 'mm', null::numeric, null::numeric, '299.8 mm · ' || ref),
    ('Termoformado', '°C', 95, 100, '95–100 °C · ' || ref),
    ('Termosellado', '°C', 135, 145, '135–145 °C · ' || ref)
  ) x(nombre, un, mn, mx, ref_txt)
  where not exists (select 1 from public.equipo_parametros_prubind p where p.equipo_id = v_eq and lower(p.nombre) = lower(x.nombre));
end $$;
