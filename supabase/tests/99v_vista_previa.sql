-- =========================================================================
-- Pruebas de 029: vista previa del enlace. Negocio propio (prefijo a7).
-- =========================================================================

\set ON_ERROR_STOP on

select set_config('request.jwt.claim.sub', '', false);

insert into auth.users (id) values
  ('a7000000-0000-0000-0000-00000000000a'),
  ('a7000000-0000-0000-0000-0000000000b0');

insert into negocios (id, nombre, slug, tipo) values
  ('a7a7a7a7-a7a7-a7a7-a7a7-a7a7a7a7a7a7', 'Salón Brillo', 'salon-brillo', 'salon');

-- Sin dueño todavía: el nombre del negocio basta.
do $$
declare
  v jsonb := reserva_vista_previa('salon-brillo');
begin
  if v ->> 'nombre' <> 'Salón Brillo' or v ->> 'tipo' <> 'salon' or v ->> 'dueno' is not null then
    raise exception 'FALLO: vista previa sin dueño: %', v;
  end if;
end $$;

insert into perfiles (id, negocio_id, nombre, rol) values
  ('a7000000-0000-0000-0000-00000000000a', 'a7a7a7a7-a7a7-a7a7-a7a7-a7a7a7a7a7a7', '  María José Peña ', 'OWNER'),
  ('a7000000-0000-0000-0000-0000000000b0', 'a7a7a7a7-a7a7-a7a7-a7a7-a7a7a7a7a7a7', 'Ana Ruiz', 'EMPLOYEE');

-- Solo el primer nombre del dueño, y sin datos privados.
do $$
declare
  v jsonb := reserva_vista_previa('  SALON-BRILLO ');
begin
  if v ->> 'dueno' <> 'María' then
    raise exception 'FALLO: debería dar el primer nombre del dueño: %', v;
  end if;
  if v ? 'telefono' or v ? 'email' or v ? 'id' then
    raise exception 'FALLO: la vista previa expone datos de más: %', v;
  end if;
end $$;

-- Enlace que no existe o negocio inactivo: null.
do $$ begin
  if reserva_vista_previa('no-existe') is not null then
    raise exception 'FALLO: un enlace inexistente debería dar null';
  end if;
end $$;

update negocios set estado = 'INACTIVO' where slug = 'salon-brillo';
do $$ begin
  if reserva_vista_previa('salon-brillo') is not null then
    raise exception 'FALLO: un negocio inactivo no debería tener vista previa';
  end if;
end $$;
