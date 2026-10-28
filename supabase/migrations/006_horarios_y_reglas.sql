-- =========================================================================
-- Barbería PRO — Horarios, servicios por barbero, apartado y estados
-- Requiere haber aplicado 001–005 sobre la misma base.
-- =========================================================================
--
-- QUÉ AGREGA
--
-- 1. Configuración del apartado y de la reserva en "negocios".
-- 2. horarios_negocio: horario de apertura por día de la semana.
-- 3. horarios_empleado: horario propio de cada barbero (opcional).
-- 4. bloqueos_empleado: días libres o vacaciones de un barbero.
-- 5. empleado_servicios: servicios que hace cada barbero (opcional).
-- 6. Reglas en el servidor para los cambios de estado de una cita.
-- 7. Al marcar un apartado como PAGADO, la cita pasa a CONFIRMADA.
--
-- Días de la semana: 0 = domingo … 6 = sábado (igual que extract(dow)).
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1. Configuración del negocio
-- -------------------------------------------------------------------------

alter table negocios
  add column apartado_requerido boolean not null default true,
  add column apartado_monto numeric(12, 2) not null default 100,
  add column apartado_politica text not null default
    'El apartado se descuenta del total del servicio. Si cancelas con menos '
    || 'de 24 horas de anticipación o no te presentas, el apartado no se devuelve.',
  add column apartado_instrucciones text,
  add column cancelacion_horas_minimas integer not null default 24,
  add column intervalo_reserva_minutos integer not null default 15,
  add constraint negocios_apartado_monto_no_negativo check (apartado_monto >= 0),
  add constraint negocios_cancelacion_horas_validas
    check (cancelacion_horas_minimas between 0 and 168),
  add constraint negocios_intervalo_reserva_valido
    check (intervalo_reserva_minutos between 5 and 120);

-- -------------------------------------------------------------------------
-- 2. Horario del negocio (un rango por día; sin fila = cerrado)
-- -------------------------------------------------------------------------

create table horarios_negocio (
  id uuid primary key default gen_random_uuid(),
  negocio_id uuid not null references negocios (id) on delete cascade,
  dia_semana smallint not null,
  hora_apertura time not null,
  hora_cierre time not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint horarios_negocio_dia_valido check (dia_semana between 0 and 6),
  constraint horarios_negocio_rango_valido check (hora_cierre > hora_apertura),
  constraint horarios_negocio_un_rango_por_dia unique (negocio_id, dia_semana)
);

create trigger trg_horarios_negocio_updated_at
  before update on horarios_negocio
  for each row execute function set_updated_at();

-- -------------------------------------------------------------------------
-- 3. Horario de cada barbero
-- -------------------------------------------------------------------------
-- Si un barbero no tiene ninguna fila, trabaja en el horario del negocio.
-- Si tiene filas, trabaja solo esos días y dentro de esos rangos (siempre
-- recortado al horario del negocio).

create table horarios_empleado (
  id uuid primary key default gen_random_uuid(),
  negocio_id uuid not null references negocios (id) on delete cascade,
  empleado_id uuid not null,
  dia_semana smallint not null,
  hora_inicio time not null,
  hora_fin time not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint horarios_empleado_dia_valido check (dia_semana between 0 and 6),
  constraint horarios_empleado_rango_valido check (hora_fin > hora_inicio),
  constraint horarios_empleado_un_rango_por_dia unique (empleado_id, dia_semana),
  constraint horarios_empleado_empleado_negocio_fkey
    foreign key (empleado_id, negocio_id)
    references empleados (id, negocio_id) on delete cascade
);

create trigger trg_horarios_empleado_updated_at
  before update on horarios_empleado
  for each row execute function set_updated_at();

create index idx_horarios_empleado_negocio_id on horarios_empleado (negocio_id);

-- -------------------------------------------------------------------------
-- 4. Días libres / vacaciones de un barbero (rango de fechas inclusivo)
-- -------------------------------------------------------------------------

create table bloqueos_empleado (
  id uuid primary key default gen_random_uuid(),
  negocio_id uuid not null references negocios (id) on delete cascade,
  empleado_id uuid not null,
  fecha_inicio date not null,
  fecha_fin date not null,
  motivo text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint bloqueos_empleado_rango_valido check (fecha_fin >= fecha_inicio),
  constraint bloqueos_empleado_empleado_negocio_fkey
    foreign key (empleado_id, negocio_id)
    references empleados (id, negocio_id) on delete cascade
);

create trigger trg_bloqueos_empleado_updated_at
  before update on bloqueos_empleado
  for each row execute function set_updated_at();

create index idx_bloqueos_empleado_negocio_id on bloqueos_empleado (negocio_id);
create index idx_bloqueos_empleado_empleado_fechas
  on bloqueos_empleado (empleado_id, fecha_inicio, fecha_fin);

-- -------------------------------------------------------------------------
-- 5. Servicios que hace cada barbero
-- -------------------------------------------------------------------------
-- Si un barbero no tiene ninguna fila, hace todos los servicios activos.

create table empleado_servicios (
  negocio_id uuid not null references negocios (id) on delete cascade,
  empleado_id uuid not null,
  servicio_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (empleado_id, servicio_id),
  constraint empleado_servicios_empleado_negocio_fkey
    foreign key (empleado_id, negocio_id)
    references empleados (id, negocio_id) on delete cascade,
  constraint empleado_servicios_servicio_negocio_fkey
    foreign key (servicio_id, negocio_id)
    references servicios (id, negocio_id) on delete cascade
);

create index idx_empleado_servicios_negocio_id on empleado_servicios (negocio_id);
create index idx_empleado_servicios_servicio_id on empleado_servicios (servicio_id);

-- -------------------------------------------------------------------------
-- RLS de las tablas nuevas: todo el negocio lee; solo el OWNER modifica.
-- -------------------------------------------------------------------------

alter table horarios_negocio enable row level security;
alter table horarios_empleado enable row level security;
alter table bloqueos_empleado enable row level security;
alter table empleado_servicios enable row level security;

create policy horarios_negocio_select_mismo_negocio on horarios_negocio
  for select using (negocio_id = auth_negocio_id());
create policy horarios_negocio_insert_owner on horarios_negocio
  for insert with check (negocio_id = auth_negocio_id() and auth_es_owner());
create policy horarios_negocio_update_owner on horarios_negocio
  for update using (negocio_id = auth_negocio_id() and auth_es_owner())
  with check (negocio_id = auth_negocio_id() and auth_es_owner());
create policy horarios_negocio_delete_owner on horarios_negocio
  for delete using (negocio_id = auth_negocio_id() and auth_es_owner());

create policy horarios_empleado_select_mismo_negocio on horarios_empleado
  for select using (negocio_id = auth_negocio_id());
create policy horarios_empleado_insert_owner on horarios_empleado
  for insert with check (negocio_id = auth_negocio_id() and auth_es_owner());
create policy horarios_empleado_update_owner on horarios_empleado
  for update using (negocio_id = auth_negocio_id() and auth_es_owner())
  with check (negocio_id = auth_negocio_id() and auth_es_owner());
create policy horarios_empleado_delete_owner on horarios_empleado
  for delete using (negocio_id = auth_negocio_id() and auth_es_owner());

create policy bloqueos_empleado_select_mismo_negocio on bloqueos_empleado
  for select using (negocio_id = auth_negocio_id());
create policy bloqueos_empleado_insert_owner on bloqueos_empleado
  for insert with check (negocio_id = auth_negocio_id() and auth_es_owner());
create policy bloqueos_empleado_update_owner on bloqueos_empleado
  for update using (negocio_id = auth_negocio_id() and auth_es_owner())
  with check (negocio_id = auth_negocio_id() and auth_es_owner());
create policy bloqueos_empleado_delete_owner on bloqueos_empleado
  for delete using (negocio_id = auth_negocio_id() and auth_es_owner());

create policy empleado_servicios_select_mismo_negocio on empleado_servicios
  for select using (negocio_id = auth_negocio_id());
create policy empleado_servicios_insert_owner on empleado_servicios
  for insert with check (negocio_id = auth_negocio_id() and auth_es_owner());
create policy empleado_servicios_delete_owner on empleado_servicios
  for delete using (negocio_id = auth_negocio_id() and auth_es_owner());

-- -------------------------------------------------------------------------
-- 6. Cambios de estado válidos de una cita
-- -------------------------------------------------------------------------
-- Permitidos (incluye "deshacer" desde la agenda):
--   PENDIENTE  → CONFIRMADA, LLEGO, COMPLETADA, NO_VINO, CANCELADA
--   CONFIRMADA → PENDIENTE, LLEGO, COMPLETADA, NO_VINO, CANCELADA
--   LLEGO      → PENDIENTE, CONFIRMADA, COMPLETADA
--   NO_VINO    → PENDIENTE, CONFIRMADA
--   COMPLETADA → LLEGO
--   CANCELADA  → (ninguno: es definitivo; se crea una cita nueva)
-- Error 23514 (check_violation) si el cambio no es válido.

create or replace function citas_validar_cambio_estado()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.estado = old.estado then
    return new;
  end if;

  if not (
    (old.estado = 'PENDIENTE' and new.estado in ('CONFIRMADA', 'LLEGO', 'COMPLETADA', 'NO_VINO', 'CANCELADA'))
    or (old.estado = 'CONFIRMADA' and new.estado in ('PENDIENTE', 'LLEGO', 'COMPLETADA', 'NO_VINO', 'CANCELADA'))
    or (old.estado = 'LLEGO' and new.estado in ('PENDIENTE', 'CONFIRMADA', 'COMPLETADA'))
    or (old.estado = 'NO_VINO' and new.estado in ('PENDIENTE', 'CONFIRMADA'))
    or (old.estado = 'COMPLETADA' and new.estado = 'LLEGO')
  ) then
    raise exception 'No se puede pasar una cita de % a %.', old.estado, new.estado
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger trg_citas_validar_cambio_estado
  before update of estado on citas
  for each row execute function citas_validar_cambio_estado();

-- -------------------------------------------------------------------------
-- 7. Apartado pagado → cita confirmada
-- -------------------------------------------------------------------------
-- Al pasar un apartado a PAGADO se guarda la fecha de pago (si falta) y la
-- cita PENDIENTE pasa a CONFIRMADA. Corre como dueño de la función para que
-- también funcione cuando lo llama una función pública de reserva.

create or replace function apartados_al_pagar()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.estado = 'PAGADO' and (tg_op = 'INSERT' or old.estado is distinct from 'PAGADO') then
    if new.fecha_pago is null then
      new.fecha_pago := now();
    end if;

    update citas
       set estado = 'CONFIRMADA'
     where id = new.cita_id
       and negocio_id = new.negocio_id
       and estado = 'PENDIENTE';
  end if;

  return new;
end;
$$;

create trigger trg_apartados_al_pagar
  before insert or update of estado on apartados
  for each row execute function apartados_al_pagar();
