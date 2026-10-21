-- v5.8 · El trigger del responsable debe correr después de pruebas_prubind_validar (que asigna
-- registrado_por); los triggers BEFORE corren en orden alfabético.
drop trigger if exists prubind_zz_responsable on public.pruebas_prubind;
drop trigger if exists pruebas_prubind_zz_responsable on public.pruebas_prubind;
create trigger pruebas_prubind_zz_responsable before insert or update of responsable_inicial_id on public.pruebas_prubind
  for each row execute function public.prubind_responsable_prueba();
