-- =========================================================================
-- Barbería PRO — Cuentas bancarias para pagar los planes
-- Requiere haber aplicado 001–018 sobre la misma base.
-- =========================================================================
--
-- Las ven los DUEÑOS con sesión (en el aviso de pago y en "Ya pagué"),
-- nunca los visitantes de la reserva pública. Solo el administrador de la
-- plataforma las crea, cambia o borra (RPC admin_*). No se guarda la cédula.
-- =========================================================================

create table cuentas_pago (
  id uuid primary key default gen_random_uuid(),
  banco text not null check (char_length(btrim(banco)) between 2 and 60),
  tipo text not null check (tipo in ('Ahorros', 'Corriente')),
  numero text not null check (numero ~ '^[0-9-]{4,30}$'),
  titular text not null check (char_length(btrim(titular)) between 2 and 80),
  orden integer not null default 0,
  activa boolean not null default true,
  created_at timestamptz not null default now()
);

alter table cuentas_pago enable row level security;

create policy cuentas_pago_select_duenos on cuentas_pago
  for select to authenticated
  using (activa and (auth_es_owner() or es_admin_plataforma()));

revoke insert, update, delete, truncate, references, trigger on cuentas_pago from anon, authenticated;
revoke all on cuentas_pago from anon;

create or replace function admin_guardar_cuenta_pago(
  p_id uuid,
  p_banco text,
  p_tipo text,
  p_numero text,
  p_titular text,
  p_orden integer default 0
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not es_admin_plataforma() then
    raise exception 'No autorizado.' using errcode = '42501';
  end if;

  if p_id is null then
    insert into cuentas_pago (banco, tipo, numero, titular, orden)
    values (btrim(p_banco), p_tipo, btrim(p_numero), btrim(p_titular), coalesce(p_orden, 0))
    returning id into v_id;
  else
    update cuentas_pago
       set banco = btrim(p_banco), tipo = p_tipo, numero = btrim(p_numero),
           titular = btrim(p_titular), orden = coalesce(p_orden, 0)
     where id = p_id
    returning id into v_id;
  end if;

  return v_id;
end;
$$;

create or replace function admin_borrar_cuenta_pago(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not es_admin_plataforma() then
    raise exception 'No autorizado.' using errcode = '42501';
  end if;
  delete from cuentas_pago where id = p_id;
end;
$$;

revoke all on function admin_guardar_cuenta_pago(uuid, text, text, text, text, integer) from public, anon;
revoke all on function admin_borrar_cuenta_pago(uuid) from public, anon;
grant execute on function admin_guardar_cuenta_pago(uuid, text, text, text, text, integer) to authenticated;
grant execute on function admin_borrar_cuenta_pago(uuid) to authenticated;
