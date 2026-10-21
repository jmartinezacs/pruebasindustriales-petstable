-- v5.8 · Un dictamen "Rechazada" se justifica con el motivo del catálogo (dictámenes anteriores)
-- o con la explicación escrita en la conclusión (desde v5.8, sin catálogo de motivos).
alter table public.dictamenes_prubind drop constraint if exists dictamenes_prubind_rech_ck;
alter table public.dictamenes_prubind add constraint dictamenes_prubind_rech_ck
  check (dictamen <> 'rechazada' or motivo_id is not null or descripcion is not null);
