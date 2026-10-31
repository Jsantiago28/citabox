-- 024: la app pasa a llamarse Citabox. Mismo trigger de 017, solo cambia el
-- nombre en el mensaje.
create or replace function trg_citas_servicio_activo()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not negocio_servicio_activo(new.negocio_id) then
    raise exception 'El servicio de este negocio está pausado. Contacta a Citabox.'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;
