-- =========================================================================
-- Barbería PRO — Fase 1.1: Hardening de aislamiento multi-negocio
-- Requiere haberse aplicado 001_initial_schema.sql sobre la misma base.
-- Requiere PostgreSQL 15+ (Supabase actual) por el uso de
-- "ON DELETE SET NULL (columna)" en una FK compuesta.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1. Claves únicas compuestas (id, negocio_id) en las tablas "padre"
--    referenciadas por FKs. Son la base para poder construir foreign keys
--    compuestas que obliguen a que negocio_id coincida en ambos lados de
--    la relación. El id por sí solo ya es único (PK); esto no cambia esa
--    garantía, solo agrega el índice necesario para la FK compuesta.
-- -------------------------------------------------------------------------

alter table clientes add constraint clientes_id_negocio_key unique (id, negocio_id);
alter table empleados add constraint empleados_id_negocio_key unique (id, negocio_id);
alter table servicios add constraint servicios_id_negocio_key unique (id, negocio_id);
alter table perfiles add constraint perfiles_id_negocio_key unique (id, negocio_id);
alter table citas add constraint citas_id_negocio_key unique (id, negocio_id);

-- -------------------------------------------------------------------------
-- 2. Reemplazo de foreign keys simples por foreign keys COMPUESTAS
--    (columna_id, negocio_id). Esto obliga a PostgreSQL a rechazar
--    cualquier fila donde el negocio del hijo no coincida con el negocio
--    del padre referenciado, sin depender del frontend ni de triggers.
-- -------------------------------------------------------------------------

-- citas → clientes (mismo negocio obligatorio)
alter table citas drop constraint citas_cliente_id_fkey;
alter table citas
  add constraint citas_cliente_negocio_fkey
  foreign key (cliente_id, negocio_id)
  references clientes (id, negocio_id)
  on delete restrict;

-- citas → empleados (mismo negocio obligatorio)
alter table citas drop constraint citas_empleado_id_fkey;
alter table citas
  add constraint citas_empleado_negocio_fkey
  foreign key (empleado_id, negocio_id)
  references empleados (id, negocio_id)
  on delete restrict;

-- citas → servicios (mismo negocio obligatorio)
alter table citas drop constraint citas_servicio_id_fkey;
alter table citas
  add constraint citas_servicio_negocio_fkey
  foreign key (servicio_id, negocio_id)
  references servicios (id, negocio_id)
  on delete restrict;

-- apartados → citas (mismo negocio obligatorio)
alter table apartados drop constraint apartados_cita_id_fkey;
alter table apartados
  add constraint apartados_cita_negocio_fkey
  foreign key (cita_id, negocio_id)
  references citas (id, negocio_id)
  on delete cascade;

-- empleados → perfiles (mismo negocio obligatorio; perfil_id sigue
-- siendo opcional: si es NULL, la FK compuesta no se evalúa, que es el
-- comportamiate esperado para un empleado sin cuenta todavía)
alter table empleados drop constraint empleados_perfil_id_fkey;
alter table empleados
  add constraint empleados_perfil_negocio_fkey
  foreign key (perfil_id, negocio_id)
  references perfiles (id, negocio_id)
  on delete set null (perfil_id);

-- -------------------------------------------------------------------------
-- 3. RLS — reforzar WITH CHECK en políticas de UPDATE
--    Aunque Postgres ya reutiliza USING como WITH CHECK implícito cuando
--    no se especifica uno, lo hacemos explícito para que quede
--    documentado y a prueba de futuros cambios: ningún UPDATE puede dejar
--    la fila con un negocio_id distinto al del usuario autenticado.
-- -------------------------------------------------------------------------

alter policy negocios_update_owner on negocios
  with check (id = auth_negocio_id() and auth_es_owner());

alter policy perfiles_update_propio_o_owner on perfiles
  with check (
    negocio_id = auth_negocio_id()
    and (id = auth.uid() or auth_es_owner())
  );

alter policy empleados_update_owner on empleados
  with check (negocio_id = auth_negocio_id() and auth_es_owner());

alter policy servicios_update_owner on servicios
  with check (negocio_id = auth_negocio_id() and auth_es_owner());

alter policy clientes_update_mismo_negocio on clientes
  with check (negocio_id = auth_negocio_id());

alter policy citas_update_mismo_negocio on citas
  with check (negocio_id = auth_negocio_id());

alter policy apartados_update_mismo_negocio on apartados
  with check (negocio_id = auth_negocio_id());

-- -------------------------------------------------------------------------
-- 4. Bootstrap del primer OWNER
-- -------------------------------------------------------------------------
-- Deliberadamente NO se crea aquí ninguna política pública (anon) de
-- INSERT sobre "negocios" ni "perfiles", y NO se crea todavía una función
-- de bootstrap. El alta de un negocio nuevo (registro → negocio →
-- auth.users → perfil OWNER) requiere una decisión de producto sobre el
-- flujo exacto de registro, y se implementará en FASE 2 mediante un
-- mecanismo controlado (p. ej. una función SECURITY DEFINER muy acotada,
-- o un paso server-side con service_role fuera del cliente). El
-- service_role NUNCA debe usarse ni exponerse desde el frontend.

-- -------------------------------------------------------------------------
-- 5. Doble reserva
-- -------------------------------------------------------------------------
-- Sin cambios: se mantiene el índice único parcial de la Fase 1
-- (empleado_id, fecha, hora_inicio) excluyendo CANCELADA/NO_VINO. El
-- solapamiento de rangos de horario se abordará en la fase de
-- disponibilidad/reservas.
