-- =========================================================================
-- Pruebas de 025: tipo de negocio. Negocio propio (prefijo a3).
-- =========================================================================

\set ON_ERROR_STOP on

select set_config('request.jwt.claim.sub', '', false);

insert into negocios (id, nombre, slug) values
  ('a3a3a3a3-a3a3-a3a3-a3a3-a3a3a3a3a3a3', 'Negocio Tipo', 'negocio-tipo');

-- Por defecto, barbería (los negocios que ya existían).
do $$ begin
  if (select tipo from negocios where id = 'a3a3a3a3-a3a3-a3a3-a3a3-a3a3a3a3a3a3') <> 'barberia' then
    raise exception 'FALLO: el tipo no empieza en barberia';
  end if;
end $$;

-- Solo los tipos conocidos.
do $$ begin
  update negocios set tipo = 'taller' where id = 'a3a3a3a3-a3a3-a3a3-a3a3-a3a3a3a3a3a3';
  raise exception 'FALLO: aceptó un tipo desconocido';
exception when check_violation then null;
end $$;

-- La página de reservas recibe el tipo.
update negocios set tipo = 'spa' where id = 'a3a3a3a3-a3a3-a3a3-a3a3-a3a3a3a3a3a3';
do $$ begin
  if reserva_catalogo('negocio-tipo') -> 'negocio' ->> 'tipo' <> 'spa' then
    raise exception 'FALLO: el catálogo no trae el tipo';
  end if;
end $$;

-- Mensaje general para un enlace que no existe.
do $$ begin
  perform reserva_catalogo('no-existe-este-negocio');
  raise exception 'FALLO: aceptó un negocio inexistente';
exception when sqlstate 'P0001' then
  if sqlerrm <> 'No encontramos este negocio. Revisa el enlace.' then raise; end if;
end $$;

-- El plan intermedio ya no se llama "Barbería".
do $$ begin
  if (select nombre from planes where codigo = 'barberia') <> 'Equipo' then
    raise exception 'FALLO: el plan intermedio no se renombró';
  end if;
end $$;
