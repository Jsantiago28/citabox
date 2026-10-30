-- =========================================================================
-- Pruebas de 020: comisión por barbero. Negocio propio (G).
-- =========================================================================

\set ON_ERROR_STOP on

select set_config('request.jwt.claim.sub', '', false);

insert into auth.users (id) values
  ('90000000-0000-0000-0000-00000000000a'),
  ('90000000-0000-0000-0000-0000000000b1');

insert into negocios (id, nombre, slug) values
  ('99999999-9999-9999-9999-999999999999', 'Negocio Comisiones', 'negocio-comisiones');

insert into perfiles (id, negocio_id, nombre, rol) values
  ('90000000-0000-0000-0000-00000000000a', '99999999-9999-9999-9999-999999999999', 'Dueño G', 'OWNER'),
  ('90000000-0000-0000-0000-0000000000b1', '99999999-9999-9999-9999-999999999999', 'Barbero G1', 'EMPLOYEE');

insert into empleados (id, negocio_id, perfil_id, nombre) values
  ('95555555-0000-0000-0000-000000000001', '99999999-9999-9999-9999-999999999999',
   '90000000-0000-0000-0000-0000000000b1', 'Barbero G1');

-- Por defecto 0.
do $$ begin
  if (select comision_pct from empleados where id = '95555555-0000-0000-0000-000000000001') <> 0 then
    raise exception 'FALLO: la comisión no empieza en 0';
  end if;
end $$;

-- Rango 0..100.
do $$ begin
  update empleados set comision_pct = 100.01 where id = '95555555-0000-0000-0000-000000000001';
  raise exception 'FALLO: aceptó comisión mayor a 100';
exception when check_violation then null;
end $$;
do $$ begin
  update empleados set comision_pct = -1 where id = '95555555-0000-0000-0000-000000000001';
  raise exception 'FALLO: aceptó comisión negativa';
exception when check_violation then null;
end $$;

-- El barbero no puede cambiarla (la fila no es visible para UPDATE: 0 filas).
set role authenticated;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-0000000000b1', false);
do $$ declare n int; begin
  update empleados set comision_pct = 90 where id = '95555555-0000-0000-0000-000000000001';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FALLO: el barbero cambió su comisión'; end if;
exception when insufficient_privilege then null;
end $$;

-- El dueño sí, con decimales.
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-00000000000a', false);
update empleados set comision_pct = 32.5 where id = '95555555-0000-0000-0000-000000000001';
do $$ begin
  if (select comision_pct from empleados where id = '95555555-0000-0000-0000-000000000001') <> 32.5 then
    raise exception 'FALLO: el dueño no pudo fijar la comisión';
  end if;
end $$;
reset role;

\echo 'Pruebas de comisiones pasaron.'
