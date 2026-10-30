-- 020: comisión por barbero (porcentaje sobre lo que atiende).
-- Solo el dueño puede cambiarla: la política empleados_update_owner (001/002)
-- limita UPDATE al OWNER del negocio.
alter table empleados
  add column if not exists comision_pct numeric(5,2) not null default 0
  constraint empleados_comision_pct_rango check (comision_pct >= 0 and comision_pct <= 100);
