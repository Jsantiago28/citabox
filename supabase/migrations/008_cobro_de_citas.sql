-- =========================================================================
-- Barbería PRO — Cobro de la cita (método de pago y propina)
-- Requiere haber aplicado 001–006 sobre la misma base.
-- =========================================================================
--
-- Al completar una cita se registra cómo pagó el cliente y la propina.
-- "precio" sigue siendo lo cobrado por el servicio; la propina va aparte
-- para que los reportes de ingresos del negocio no la mezclen.
-- =========================================================================

alter table citas
  add column metodo_pago text,
  add column propina numeric(12, 2) not null default 0,
  add column cobrada_en timestamptz,
  add constraint citas_metodo_pago_valido
    check (metodo_pago is null or metodo_pago in ('EFECTIVO', 'TRANSFERENCIA', 'TARJETA', 'OTRO')),
  add constraint citas_propina_no_negativa check (propina >= 0);

-- Guarda la hora del cobro la primera vez que la cita pasa a COMPLETADA.
create or replace function citas_registrar_cobro()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.estado = 'COMPLETADA' and old.estado is distinct from 'COMPLETADA'
     and new.cobrada_en is null then
    new.cobrada_en := now();
  end if;
  return new;
end;
$$;

create trigger trg_citas_registrar_cobro
  before update of estado on citas
  for each row execute function citas_registrar_cobro();
