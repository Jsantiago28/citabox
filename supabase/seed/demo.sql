-- =========================================================================
-- Barbería PRO — Datos de demostración
-- =========================================================================
-- Llena un negocio QUE YA EXISTE con datos de ejemplo para enseñar la app:
--   * 6 servicios típicos de barbería (precios en RD$)
--   * 3 barberos (sin cuenta de acceso)
--   * horario lunes a sábado de 9:00 a 19:00 (domingo cerrado)
--   * 15 clientes con teléfonos ficticios (809/829/849-555-01xx)
--   * ~40 citas: últimas 2 semanas, hoy y próximos 7 días, con estados
--     variados y algunos apartados
--
-- CÓMO USARLO
--   1. Supabase → SQL Editor → New query.
--   2. Pega este archivo completo.
--   3. Cambia 'mi-barberia' (línea marcada con  <<<  ) por el slug de tu
--      negocio (el que aparece en el enlace de reservas).
--   4. Pulsa Run. Al final verás un resumen en "Messages"/"Notices".
--
-- Se puede ejecutar más de una vez: lo que ya existe (mismo nombre o
-- teléfono) no se duplica, y si ya hay citas de demostración no se crean
-- otras. Las citas y clientes de demostración llevan "[demo]" en las notas
-- para poder borrarlos (ver supabase/seed/README.md).
--
-- Requiere las migraciones 001–006.
-- =========================================================================

do $$
declare
  v_slug text := 'mi-barberia';   -- <<< CAMBIA ESTO por el slug de tu negocio

  v_tag constant text := '[demo]';

  v_negocio uuid;
  v_tz text;
  v_apartado_monto numeric(12, 2);
  v_hoy date;
  v_ahora time;

  -- Servicios: nombre, precio (RD$), duración (min), descripción
  s_nombre text[] := array[
    'Corte de cabello', 'Corte + barba', 'Barba', 'Cerquillo', 'Tinte', 'Corte de niño'];
  s_precio numeric[] := array[400, 600, 250, 150, 800, 300];
  s_duracion int[] := array[30, 45, 20, 15, 60, 25];
  s_descripcion text[] := array[
    'Corte a máquina y tijera, con lavado y peinado.',
    'Corte completo más arreglo de barba con toalla caliente.',
    'Perfilado y arreglo de barba con navaja.',
    'Retoque de cerquillo y patillas.',
    'Tinte de cabello o barba.',
    'Corte para niños hasta 12 años.'];

  b_nombre text[] := array['Carlos Peña', 'Luis Martínez', 'José "Junior" Rodríguez'];
  b_telefono text[] := array['809-555-0201', '829-555-0202', '849-555-0203'];

  c_nombre text[] := array[
    'Juan Pérez', 'Pedro Almonte', 'Miguel Ángel Reyes', 'Rafael Santana',
    'Francisco Guzmán', 'Wilson Batista', 'Ramón Tavárez', 'Yohan De la Cruz',
    'Starlin Mejía', 'Anderson Rosario', 'Jefferson Polanco', 'Luis Manuel Féliz',
    'Kelvin Vásquez', 'Edward Castillo', 'Ángel Cuevas'];
  c_telefono text[] := array[
    '809-555-0101', '829-555-0102', '849-555-0103', '809-555-0104',
    '829-555-0105', '849-555-0106', '809-555-0107', '829-555-0108',
    '849-555-0109', '809-555-0110', '829-555-0111', '849-555-0112',
    '809-555-0113', '829-555-0114', '849-555-0115'];

  v_servicios uuid[] := '{}';
  v_barberos uuid[] := '{}';
  v_clientes uuid[] := '{}';

  v_id uuid;
  v_cita uuid;
  v_fecha date;
  v_por_dia int;
  v_n int := 0;
  v_si int;
  v_hora time;
  v_fin time;
  v_estado estado_cita;
  v_emp uuid;

  n_servicios int := 0;
  n_barberos int := 0;
  n_clientes int := 0;
  n_horario int := 0;
  n_citas int := 0;
  n_apartados int := 0;
  n_omitidas int := 0;
  v_rows int;
begin
  -- ---------------------------------------------------------------------
  -- Negocio
  -- ---------------------------------------------------------------------
  select id, zona_horaria, apartado_monto
    into v_negocio, v_tz, v_apartado_monto
    from negocios
   where slug = v_slug;

  if v_negocio is null then
    raise exception 'No existe ningún negocio con el slug "%". Cambia v_slug al inicio del script (Table Editor → negocios → columna slug).', v_slug;
  end if;

  v_hoy := (now() at time zone v_tz)::date;
  v_ahora := (now() at time zone v_tz)::time;
  if coalesce(v_apartado_monto, 0) <= 0 then
    v_apartado_monto := 100;
  end if;

  -- ---------------------------------------------------------------------
  -- Servicios
  -- ---------------------------------------------------------------------
  for i in 1 .. array_length(s_nombre, 1) loop
    select id into v_id
      from servicios
     where negocio_id = v_negocio and lower(nombre) = lower(s_nombre[i])
     order by created_at
     limit 1;

    if v_id is null then
      insert into servicios (negocio_id, nombre, descripcion, precio, duracion_minutos)
      values (v_negocio, s_nombre[i], s_descripcion[i], s_precio[i], s_duracion[i])
      returning id into v_id;
      n_servicios := n_servicios + 1;
    end if;

    v_servicios := v_servicios || v_id;
  end loop;

  -- ---------------------------------------------------------------------
  -- Barberos (sin cuenta: perfil_id vacío)
  -- ---------------------------------------------------------------------
  for i in 1 .. array_length(b_nombre, 1) loop
    select id into v_id
      from empleados
     where negocio_id = v_negocio and lower(nombre) = lower(b_nombre[i])
     order by created_at
     limit 1;

    if v_id is null then
      insert into empleados (negocio_id, nombre, telefono)
      values (v_negocio, b_nombre[i], b_telefono[i])
      returning id into v_id;
      n_barberos := n_barberos + 1;
    end if;

    v_barberos := v_barberos || v_id;
  end loop;

  -- ---------------------------------------------------------------------
  -- Horario del negocio: lunes (1) a sábado (6), 9:00–19:00.
  -- Si un día ya tiene horario, se respeta el que hay.
  -- ---------------------------------------------------------------------
  for d in 1 .. 6 loop
    insert into horarios_negocio (negocio_id, dia_semana, hora_apertura, hora_cierre)
    values (v_negocio, d, time '09:00', time '19:00')
    on conflict (negocio_id, dia_semana) do nothing;
    get diagnostics v_rows = row_count;
    n_horario := n_horario + v_rows;
  end loop;

  -- ---------------------------------------------------------------------
  -- Clientes (se reconocen por teléfono)
  -- ---------------------------------------------------------------------
  for i in 1 .. array_length(c_nombre, 1) loop
    select id into v_id
      from clientes
     where negocio_id = v_negocio and telefono = c_telefono[i]
     order by created_at
     limit 1;

    if v_id is null then
      insert into clientes (negocio_id, nombre, telefono, notas)
      values (v_negocio, c_nombre[i], c_telefono[i], v_tag || ' Cliente de demostración.')
      returning id into v_id;
      n_clientes := n_clientes + 1;
    end if;

    v_clientes := v_clientes || v_id;
  end loop;

  -- ---------------------------------------------------------------------
  -- Citas
  -- ---------------------------------------------------------------------
  if exists (
    select 1 from citas where negocio_id = v_negocio and notas like v_tag || '%'
  ) then
    raise notice 'Ya hay citas de demostración en "%": no se crean otras. Bórralas primero si quieres generarlas de nuevo (ver supabase/seed/README.md).', v_slug;
  else
    for d in -14 .. 7 loop
      v_fecha := v_hoy + d;
      continue when extract(dow from v_fecha) = 0;   -- domingo cerrado

      v_por_dia := case when extract(dow from v_fecha) = 6 then 3 else 2 end;

      for k in 0 .. v_por_dia - 1 loop
        v_n := v_n + 1;

        -- En un mismo día cada cita va con un barbero distinto, así que
        -- las citas de demostración nunca se cruzan entre sí.
        v_emp := v_barberos[((k + d + 15) % 3) + 1];
        v_si := ((v_n * 7 + k) % 6) + 1;
        v_hora := time '09:00' + make_interval(mins => 30 * ((v_n * 5 + k * 3 + d + 14) % 17));
        v_fin := v_hora + make_interval(mins => s_duracion[v_si]);

        if d < 0 then
          v_estado := case
            when v_n % 9 = 4 then 'NO_VINO'
            when v_n % 10 = 7 then 'CANCELADA'
            else 'COMPLETADA'
          end;
        elsif d = 0 then
          v_estado := case
            when v_fin <= v_ahora then 'COMPLETADA'
            when v_hora <= v_ahora then 'LLEGO'
            else 'CONFIRMADA'
          end;
        else
          v_estado := case
            when v_n % 8 = 3 then 'CANCELADA'
            when v_n % 2 = 0 then 'CONFIRMADA'
            else 'PENDIENTE'
          end;
        end if;

        -- Si el barbero ya existía y tiene una cita real a esa hora, se
        -- salta esta (la base no permite citas cruzadas).
        if v_estado not in ('CANCELADA', 'NO_VINO') and exists (
          select 1
            from citas
           where empleado_id = v_emp
             and fecha = v_fecha
             and estado not in ('CANCELADA', 'NO_VINO')
             and hora_inicio < v_fin
             and v_hora < hora_fin
        ) then
          n_omitidas := n_omitidas + 1;
          continue;
        end if;

        insert into citas (
          negocio_id, cliente_id, empleado_id, servicio_id,
          fecha, hora_inicio, hora_fin, precio, estado, notas
        )
        values (
          v_negocio,
          v_clientes[((v_n * 4) % 15) + 1],
          v_emp,
          v_servicios[v_si],
          v_fecha, v_hora, v_fin,
          s_precio[v_si],
          v_estado,
          v_tag || ' Cita de demostración.'
        )
        returning id into v_cita;
        n_citas := n_citas + 1;

        -- Apartados: pagados en las confirmadas y en parte de las ya
        -- atendidas; pendiente de validar en las pendientes.
        if v_estado = 'CONFIRMADA' or (v_estado = 'COMPLETADA' and v_n % 3 = 0) then
          insert into apartados (negocio_id, cita_id, monto, estado, metodo_pago, referencia, fecha_pago)
          values (
            v_negocio, v_cita, v_apartado_monto, 'PAGADO', 'Transferencia',
            'DEMO-' || lpad(v_n::text, 4, '0'),
            least(now(), ((v_fecha - 1) + time '18:00') at time zone v_tz)
          );
          n_apartados := n_apartados + 1;
        elsif v_estado = 'PENDIENTE' then
          insert into apartados (negocio_id, cita_id, monto, estado, metodo_pago, referencia)
          values (
            v_negocio, v_cita, v_apartado_monto, 'PENDIENTE', 'Transferencia',
            'DEMO-' || lpad(v_n::text, 4, '0')
          );
          n_apartados := n_apartados + 1;
        end if;
      end loop;
    end loop;
  end if;

  raise notice 'Datos de demostración en "%": % servicios, % barberos, % días de horario, % clientes, % citas y % apartados nuevos (% citas omitidas por choque de horario).',
    v_slug, n_servicios, n_barberos, n_horario, n_clientes, n_citas, n_apartados, n_omitidas;
end;
$$;
