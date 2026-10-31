-- =========================================================================
-- Pruebas de 028: fidelización. Negocio propio (prefijo a6).
-- =========================================================================

\set ON_ERROR_STOP on

select set_config('request.jwt.claim.sub', '', false);

insert into negocios (id, nombre, slug) values
  ('a6a6a6a6-a6a6-a6a6-a6a6-a6a6a6a6a6a6', 'Negocio Fiel', 'negocio-fiel');

-- Sin programa por defecto.
do $$ begin
  if reserva_catalogo('negocio-fiel') -> 'negocio' ->> 'fidelidad_visitas' is not null then
    raise exception 'FALLO: el programa no debería venir activo';
  end if;
end $$;

-- Rango y premio.
do $$ begin
  update negocios set fidelidad_visitas = 1 where slug = 'negocio-fiel';
  raise exception 'FALLO: aceptó premio en cada visita';
exception when check_violation then null;
end $$;
do $$ begin
  update negocios set fidelidad_premio = '  ' where slug = 'negocio-fiel';
  raise exception 'FALLO: aceptó un premio vacío';
exception when check_violation then null;
end $$;

update negocios set fidelidad_visitas = 10, fidelidad_premio = 'Corte gratis'
 where slug = 'negocio-fiel';
do $$
declare
  n jsonb := reserva_catalogo('negocio-fiel') -> 'negocio';
begin
  if (n ->> 'fidelidad_visitas')::int <> 10 or n ->> 'fidelidad_premio' <> 'Corte gratis' then
    raise exception 'FALLO: el catálogo no trae el programa: %', n;
  end if;
end $$;
