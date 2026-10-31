-- =========================================================================
-- Pruebas de 027: cumpleaños del cliente. Negocio propio (prefijo a5).
-- =========================================================================

\set ON_ERROR_STOP on

select set_config('request.jwt.claim.sub', '', false);

insert into auth.users (id) values ('a5000000-0000-0000-0000-00000000000a');
insert into negocios (id, nombre, slug) values
  ('a5a5a5a5-a5a5-a5a5-a5a5-a5a5a5a5a5a5', 'Negocio Cumple', 'negocio-cumple');
insert into perfiles (id, negocio_id, nombre, rol) values
  ('a5000000-0000-0000-0000-00000000000a', 'a5a5a5a5-a5a5-a5a5-a5a5-a5a5a5a5a5a5', 'Dueño', 'OWNER');
insert into clientes (id, negocio_id, nombre, cumple_mes, cumple_dia) values
  ('a5000000-0000-0000-0000-0000000000c1', 'a5a5a5a5-a5a5-a5a5-a5a5-a5a5a5a5a5a5', 'Ana', 2, 29);

-- Fechas imposibles o a medias.
do $$ begin
  update clientes set cumple_mes = 4, cumple_dia = 31
   where id = 'a5000000-0000-0000-0000-0000000000c1';
  raise exception 'FALLO: aceptó el 31 de abril';
exception when check_violation then null;
end $$;
do $$ begin
  update clientes set cumple_mes = 5, cumple_dia = null
   where id = 'a5000000-0000-0000-0000-0000000000c1';
  raise exception 'FALLO: aceptó un cumpleaños sin día';
exception when check_violation then null;
end $$;
do $$ begin
  update clientes set cumple_mes = null, cumple_dia = 3
   where id = 'a5000000-0000-0000-0000-0000000000c1';
  raise exception 'FALLO: aceptó un cumpleaños sin mes';
exception when check_violation then null;
end $$;
do $$ begin
  update clientes set cumple_mes = 13, cumple_dia = 1
   where id = 'a5000000-0000-0000-0000-0000000000c1';
  raise exception 'FALLO: aceptó el mes 13';
exception when check_violation then null;
end $$;

-- El dueño lo cambia; al anonimizar se borra.
set role authenticated;
select set_config('request.jwt.claim.sub', 'a5000000-0000-0000-0000-00000000000a', false);
update clientes set cumple_mes = 12, cumple_dia = 25
 where id = 'a5000000-0000-0000-0000-0000000000c1';
select anonimizar_cliente('a5000000-0000-0000-0000-0000000000c1');
do $$ begin
  if exists (select 1 from clientes
              where id = 'a5000000-0000-0000-0000-0000000000c1'
                and (cumple_mes is not null or cumple_dia is not null)) then
    raise exception 'FALLO: anonimizar no borró el cumpleaños';
  end if;
end $$;

reset role;
select set_config('request.jwt.claim.sub', '', false);
