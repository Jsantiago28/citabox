-- 021: avisos en vivo (Supabase Realtime, respeta RLS).
-- Solo si existe la publicación (en CI no existe): añade citas y apartados.
-- REPLICA IDENTITY FULL para que los UPDATE traigan la fila anterior
-- (así se detecta "pasó a CANCELADA" y "referencia de null a valor").
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table public.citas;
    exception when duplicate_object then null;
    end;
    begin
      alter publication supabase_realtime add table public.apartados;
    exception when duplicate_object then null;
    end;
    alter table public.citas replica identity full;
    alter table public.apartados replica identity full;
  end if;
end
$$;
