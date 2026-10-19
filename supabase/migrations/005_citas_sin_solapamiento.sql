-- =========================================================================
-- Barbería PRO — Citas sin solapamiento
-- Requiere haber aplicado 001 a 004 sobre la misma base.
-- =========================================================================
--
-- Hasta ahora "uq_citas_empleado_horario" solo impedía dos citas del mismo
-- barbero que EMPEZARAN a la misma hora. Una cita de 10:00 a 10:45 y otra a
-- las 10:30 se podían crear. El criterio del Plan Maestro ("no hay dobles
-- reservas") exige comparar rangos de horas.
--
-- Esta restricción de exclusión rechaza cualquier cita del mismo empleado,
-- el mismo día, cuyo rango [hora_inicio, hora_fin) se cruce con otra cita
-- activa. Las citas CANCELADA y NO_VINO no ocupan horario. Los rangos son
-- semiabiertos: una cita de 10:00 a 10:45 y otra de 10:45 a 11:30 sí caben.
--
-- Error que verá el cliente: SQLSTATE 23P01 (exclusion_violation).
--
-- ANTES DE APLICAR: si ya hay datos, comprobar que no existan solapamientos
-- (la restricción no se puede crear si los hay):
--
--   select a.id, b.id
--   from citas a
--   join citas b
--     on a.empleado_id = b.empleado_id
--    and a.fecha = b.fecha
--    and a.id < b.id
--    and a.hora_inicio < b.hora_fin
--    and b.hora_inicio < a.hora_fin
--   where a.estado not in ('CANCELADA', 'NO_VINO')
--     and b.estado not in ('CANCELADA', 'NO_VINO');
-- =========================================================================

-- Necesaria para combinar "=" sobre uuid con "&&" sobre rangos en un índice GiST.
create extension if not exists btree_gist;

alter table citas
  add constraint citas_empleado_sin_solapamiento
  exclude using gist (
    empleado_id with =,
    tsrange(fecha + hora_inicio, fecha + hora_fin) with &&
  )
  where (estado not in ('CANCELADA', 'NO_VINO'));

-- La restricción de exclusión ya cubre el caso de misma hora de inicio.
drop index uq_citas_empleado_horario;
