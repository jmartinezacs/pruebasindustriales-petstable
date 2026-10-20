-- =====================================================================
-- v4 · Los parámetros opcionales (de pruebas registradas antes de v4) que no
-- tienen resultado no se exigen en la evaluación Cumple / No cumple.
-- =====================================================================
create or replace function public.prubind_sin_evaluar(p_prueba uuid, p_area text default null)
returns integer language sql stable security definer set search_path = '' as $$
  select (select count(*) from public.plan_evaluacion_prubind pl join public.metodos_prubind m on m.id = pl.metodo_id
           join public.pruebas_prubind p on p.id = pl.prueba_id
          where pl.prueba_id = p_prueba and pl.incluido and (p_area is null or m.area = p_area)
            and (pl.obligatorio or exists (select 1 from public.resultados_prubind r where r.plan_id = pl.id and r.ejecucion = p.ejecucion_actual
                                           and (r.valor_num is not null or r.valor_opcion is not null)))
            and not exists (select 1 from public.evaluaciones_prubind e where e.plan_id = pl.id and e.ejecucion = p.ejecucion_actual))::int
       + (select count(*) from public.prueba_parametros_prubind x join public.pruebas_prubind p on p.id = x.prueba_id
          where x.prueba_id = p_prueba and (p_area is null or p_area = 'produccion')
            and not exists (select 1 from public.evaluaciones_prubind e where e.prueba_parametro_id = x.id and e.ejecucion = p.ejecucion_actual))::int
$$;
