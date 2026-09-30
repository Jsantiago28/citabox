-- =========================================================================
-- Barbería PRO — Migración inicial (Fase 1)
-- Esquema multi-negocio con Row Level Security.
-- Debe poder ejecutarse desde cero sobre una instancia limpia de Supabase.
-- =========================================================================

-- Extensión para generar UUIDs
create extension if not exists "pgcrypto";

-- -------------------------------------------------------------------------
-- Tipos enumerados
-- -------------------------------------------------------------------------

create type rol_perfil as enum ('OWNER', 'EMPLOYEE');

create type estado_cita as enum (
  'PENDIENTE',
  'CONFIRMADA',
  'LLEGO',
  'COMPLETADA',
  'NO_VINO',
  'CANCELADA'
);

create type estado_apartado as enum ('PENDIENTE', 'PAGADO', 'CANCELADO');

-- -------------------------------------------------------------------------
-- Función auxiliar: updated_at automático
-- -------------------------------------------------------------------------

create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- -------------------------------------------------------------------------
-- 1. negocios
-- -------------------------------------------------------------------------

create table negocios (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  slug text not null,
  telefono text,
  direccion text,
  logo text,
  imagen text,
  color_principal text,
  moneda text not null default 'DOP',
  zona_horaria text not null default 'America/Santo_Domingo',
  estado text not null default 'ACTIVO',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint negocios_slug_unique unique (slug),
  constraint negocios_slug_formato check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint negocios_estado_valido check (estado in ('ACTIVO', 'INACTIVO'))
);

create trigger trg_negocios_updated_at
  before update on negocios
  for each row execute function set_updated_at();

-- -------------------------------------------------------------------------
-- 2. perfiles (1:1 con auth.users)
-- -------------------------------------------------------------------------

create table perfiles (
  id uuid primary key references auth.users (id) on delete cascade,
  negocio_id uuid not null references negocios (id) on delete cascade,
  nombre text not null,
  telefono text,
  rol rol_perfil not null default 'EMPLOYEE',
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_perfiles_updated_at
  before update on perfiles
  for each row execute function set_updated_at();

create index idx_perfiles_negocio_id on perfiles (negocio_id);

-- -------------------------------------------------------------------------
-- 3. empleados
-- -------------------------------------------------------------------------

create table empleados (
  id uuid primary key default gen_random_uuid(),
  negocio_id uuid not null references negocios (id) on delete cascade,
  perfil_id uuid references perfiles (id) on delete set null,
  nombre text not null,
  telefono text,
  foto text,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_empleados_updated_at
  before update on empleados
  for each row execute function set_updated_at();

create index idx_empleados_negocio_id on empleados (negocio_id);
create index idx_empleados_perfil_id on empleados (perfil_id);

-- -------------------------------------------------------------------------
-- 4. servicios
-- -------------------------------------------------------------------------

create table servicios (
  id uuid primary key default gen_random_uuid(),
  negocio_id uuid not null references negocios (id) on delete cascade,
  nombre text not null,
  descripcion text,
  precio numeric(12, 2) not null,
  duracion_minutos integer not null,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint servicios_precio_no_negativo check (precio >= 0),
  constraint servicios_duracion_positiva check (duracion_minutos > 0)
);

create trigger trg_servicios_updated_at
  before update on servicios
  for each row execute function set_updated_at();

create index idx_servicios_negocio_id on servicios (negocio_id);

-- -------------------------------------------------------------------------
-- 5. clientes
-- -------------------------------------------------------------------------

create table clientes (
  id uuid primary key default gen_random_uuid(),
  negocio_id uuid not null references negocios (id) on delete cascade,
  nombre text not null,
  telefono text,
  email text,
  notas text,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_clientes_updated_at
  before update on clientes
  for each row execute function set_updated_at();

create index idx_clientes_negocio_id on clientes (negocio_id);

-- -------------------------------------------------------------------------
-- 6. citas
-- -------------------------------------------------------------------------

create table citas (
  id uuid primary key default gen_random_uuid(),
  negocio_id uuid not null references negocios (id) on delete cascade,
  cliente_id uuid not null references clientes (id) on delete restrict,
  empleado_id uuid not null references empleados (id) on delete restrict,
  servicio_id uuid not null references servicios (id) on delete restrict,
  fecha date not null,
  hora_inicio time not null,
  hora_fin time not null,
  precio numeric(12, 2) not null,
  estado estado_cita not null default 'PENDIENTE',
  notas text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint citas_precio_no_negativo check (precio >= 0),
  constraint citas_horario_valido check (hora_fin > hora_inicio)
);

create trigger trg_citas_updated_at
  before update on citas
  for each row execute function set_updated_at();

create index idx_citas_negocio_id on citas (negocio_id);
create index idx_citas_cliente_id on citas (cliente_id);
create index idx_citas_empleado_id on citas (empleado_id);
create index idx_citas_servicio_id on citas (servicio_id);
create index idx_citas_fecha on citas (fecha);
create index idx_citas_negocio_fecha on citas (negocio_id, fecha);

-- Preparación para impedir doble reserva del mismo empleado en el mismo
-- horario. Se deja el índice único básico por ahora (mismo empleado,
-- misma fecha, misma hora de inicio); reglas de solapamiento más finas
-- (traslape de rangos) se definirán en una fase posterior si se requieren.
create unique index uq_citas_empleado_horario
  on citas (empleado_id, fecha, hora_inicio)
  where estado not in ('CANCELADA', 'NO_VINO');

-- -------------------------------------------------------------------------
-- 7. apartados
-- -------------------------------------------------------------------------

create table apartados (
  id uuid primary key default gen_random_uuid(),
  negocio_id uuid not null references negocios (id) on delete cascade,
  cita_id uuid not null references citas (id) on delete cascade,
  monto numeric(12, 2) not null,
  estado estado_apartado not null default 'PENDIENTE',
  metodo_pago text,
  referencia text,
  fecha_pago timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint apartados_monto_no_negativo check (monto >= 0)
);

create trigger trg_apartados_updated_at
  before update on apartados
  for each row execute function set_updated_at();

create index idx_apartados_negocio_id on apartados (negocio_id);
create index idx_apartados_cita_id on apartados (cita_id);

-- Una cita solo puede tener un apartado activo (no cancelado)
create unique index uq_apartados_cita_activo
  on apartados (cita_id)
  where estado <> 'CANCELADO';

-- =========================================================================
-- FUNCIONES AUXILIARES PARA RLS
-- =========================================================================

-- Devuelve el negocio_id del perfil del usuario autenticado actual.
create or replace function auth_negocio_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select negocio_id from perfiles where id = auth.uid();
$$;

-- Devuelve true si el usuario autenticado actual es OWNER de su negocio.
create or replace function auth_es_owner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from perfiles
    where id = auth.uid() and rol = 'OWNER' and activo = true
  );
$$;

-- =========================================================================
-- ROW LEVEL SECURITY
-- =========================================================================

alter table negocios enable row level security;
alter table perfiles enable row level security;
alter table empleados enable row level security;
alter table servicios enable row level security;
alter table clientes enable row level security;
alter table citas enable row level security;
alter table apartados enable row level security;

-- --- negocios ---
-- Cualquier miembro del negocio puede ver los datos de su propio negocio.
create policy negocios_select_propio on negocios
  for select using (id = auth_negocio_id());

-- Solo el OWNER puede actualizar los datos de su propio negocio.
create policy negocios_update_owner on negocios
  for update using (id = auth_negocio_id() and auth_es_owner());

-- La creación de negocios se maneja mediante un flujo de registro
-- controlado (server-side / service role), no se abre INSERT público
-- todavía.

-- --- perfiles ---
create policy perfiles_select_mismo_negocio on perfiles
  for select using (negocio_id = auth_negocio_id());

create policy perfiles_update_propio_o_owner on perfiles
  for update using (
    negocio_id = auth_negocio_id()
    and (id = auth.uid() or auth_es_owner())
  );

create policy perfiles_insert_owner on perfiles
  for insert with check (negocio_id = auth_negocio_id() and auth_es_owner());

create policy perfiles_delete_owner on perfiles
  for delete using (negocio_id = auth_negocio_id() and auth_es_owner());

-- --- empleados ---
create policy empleados_select_mismo_negocio on empleados
  for select using (negocio_id = auth_negocio_id());

create policy empleados_insert_owner on empleados
  for insert with check (negocio_id = auth_negocio_id() and auth_es_owner());

create policy empleados_update_owner on empleados
  for update using (negocio_id = auth_negocio_id() and auth_es_owner());

create policy empleados_delete_owner on empleados
  for delete using (negocio_id = auth_negocio_id() and auth_es_owner());

-- --- servicios ---
create policy servicios_select_mismo_negocio on servicios
  for select using (negocio_id = auth_negocio_id());

create policy servicios_insert_owner on servicios
  for insert with check (negocio_id = auth_negocio_id() and auth_es_owner());

create policy servicios_update_owner on servicios
  for update using (negocio_id = auth_negocio_id() and auth_es_owner());

create policy servicios_delete_owner on servicios
  for delete using (negocio_id = auth_negocio_id() and auth_es_owner());

-- --- clientes ---
create policy clientes_select_mismo_negocio on clientes
  for select using (negocio_id = auth_negocio_id());

create policy clientes_insert_mismo_negocio on clientes
  for insert with check (negocio_id = auth_negocio_id());

create policy clientes_update_mismo_negocio on clientes
  for update using (negocio_id = auth_negocio_id());

create policy clientes_delete_owner on clientes
  for delete using (negocio_id = auth_negocio_id() and auth_es_owner());

-- --- citas ---
create policy citas_select_mismo_negocio on citas
  for select using (negocio_id = auth_negocio_id());

create policy citas_insert_mismo_negocio on citas
  for insert with check (negocio_id = auth_negocio_id());

create policy citas_update_mismo_negocio on citas
  for update using (negocio_id = auth_negocio_id());

create policy citas_delete_owner on citas
  for delete using (negocio_id = auth_negocio_id() and auth_es_owner());

-- --- apartados ---
create policy apartados_select_mismo_negocio on apartados
  for select using (negocio_id = auth_negocio_id());

create policy apartados_insert_mismo_negocio on apartados
  for insert with check (negocio_id = auth_negocio_id());

create policy apartados_update_mismo_negocio on apartados
  for update using (negocio_id = auth_negocio_id());

create policy apartados_delete_owner on apartados
  for delete using (negocio_id = auth_negocio_id() and auth_es_owner());

-- =========================================================================
-- NOTA SOBRE RESERVA PÚBLICA (futura fase)
-- =========================================================================
-- No se crean políticas públicas de SELECT/INSERT en esta fase. Cuando se
-- implemente la reserva pública, se recomienda exponer únicamente vistas o
-- funciones RPC de "security definer" muy acotadas (ej. disponibilidad de
-- horarios, catálogo de servicios activos) en lugar de abrir políticas
-- públicas directas sobre las tablas privadas completas.
