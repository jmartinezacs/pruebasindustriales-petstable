-- v5.6: quien dictamina puede crear la muestra general al completar un valor pendiente
create or replace function public.prubind_validar_muestra()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v     public.pruebas_prubind%rowtype;
  v_pid uuid;
  v_n   integer;
  v_dic boolean;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return coalesce(new, old); end if;
  if tg_table_name = 'muestra_batches_prubind' then
    select m.prueba_id into v_pid from public.muestras_prubind m where m.id = case when tg_op = 'DELETE' then old.muestra_id else new.muestra_id end;
  else
    v_pid := case when tg_op = 'DELETE' then old.prueba_id else new.prueba_id end;
  end if;
  select * into v from public.pruebas_prubind where id = v_pid;
  if v.id is null then return coalesce(new, old); end if;
  v_dic := v.estado = 'pendiente_dictamen' and public.prubind_puede(v_pid, 'dictaminar');
  if not (public.prubind_puede(v_pid, 'ejecutar') or public.prubind_puede(v_pid, 'evaluar') or v_dic) then
    raise exception 'No tiene autoridad para registrar muestras.' using errcode = '42501';
  end if;
  if not (public.prubind_ejecucion_abierta(v_pid) or v.estado in ('en_evaluacion', 'pendiente_resultados') or v_dic) then
    raise exception 'Las muestras se registran durante el proceso o mientras se completan resultados.' using errcode = 'P0001';
  end if;
  if tg_op = 'DELETE' then return old; end if;

  if tg_table_name = 'muestra_batches_prubind' then
    if not exists (select 1 from public.muestras_prubind m join public.batches_prubind b on b.prueba_id = m.prueba_id and b.ejecucion = m.ejecucion
                   where m.id = (to_jsonb(new) ->> 'muestra_id')::uuid and b.id = (to_jsonb(new) ->> 'batch_id')::uuid and m.nivel = 'compuesta') then
      raise exception 'Solo se componen muestras compuestas con batches de la misma prueba y ejecución.' using errcode = 'P0001';
    end if;
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.ejecucion := v.ejecucion_actual;
    new.tomada_por := coalesce(new.tomada_por, public.prubind_usuario_actual_id());
    if nullif(btrim(new.codigo), '') is null then
      select count(*) + 1 into v_n from public.muestras_prubind where prueba_id = v_pid and ejecucion = new.ejecucion;
      new.codigo := 'M' || new.ejecucion || '-' || lpad(v_n::text, 2, '0');
    end if;
  elsif new.prueba_id is distinct from old.prueba_id or new.ejecucion is distinct from old.ejecucion then
    raise exception 'No se puede mover la muestra.' using errcode = 'P0001';
  end if;
  new.codigo := upper(btrim(new.codigo));
  if new.batch_id is not null and not exists (select 1 from public.batches_prubind b where b.id = new.batch_id and b.prueba_id = v_pid and b.ejecucion = new.ejecucion) then
    raise exception 'El batch no pertenece a esta prueba y ejecución.' using errcode = 'P0001';
  end if;
  if new.lote_diario_id is not null and not exists (select 1 from public.lotes_diarios_prubind l where l.id = new.lote_diario_id and l.prueba_id = v_pid and l.ejecucion = new.ejecucion) then
    raise exception 'El lote diario no pertenece a esta prueba y ejecución.' using errcode = 'P0001';
  end if;
  if new.punto_id is not null and not exists (select 1 from public.puntos_muestreo_prubind p where p.id = new.punto_id and p.prueba_id = v_pid) then
    raise exception 'El punto de muestreo no pertenece a esta prueba.' using errcode = 'P0001';
  end if;
  if new.fecha_muestreo > public.prubind_hoy() then
    raise exception 'La fecha de muestreo no puede ser futura.' using errcode = 'P0001';
  end if;
  perform public.prubind_iniciar_captura(v_pid);
  return new;
end $$;
