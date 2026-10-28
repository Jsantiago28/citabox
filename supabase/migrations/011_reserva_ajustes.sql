-- =========================================================================
-- Barbería PRO — Ajustes de la reserva pública
-- Requiere haber aplicado 001–010 sobre la misma base.
-- =========================================================================
--
-- 1. reserva_horas_disponibles acepta p_token (opcional). Al reprogramar
--    "Mi cita", la app pasa el token y la función:
--      - usa el barbero de la cita (reprogramar mantiene barbero y servicio),
--      - no cuenta la propia cita como ocupada (la hora actual y las que
--        se cruzan con ella aparecen libres), igual que reserva_reprogramar.
-- 2. El texto por defecto de negocios.apartado_politica ya no dice
--    "24 horas" fijo: el plazo real es cancelacion_horas_minimas, que el
--    dueño puede cambiar. Se actualizan las filas que aún tienen el texto
--    viejo exacto (las que el dueño editó se respetan).
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1. Horas disponibles excluyendo la propia cita
-- -------------------------------------------------------------------------

-- Cambia la firma: se borra la de 4 parámetros para que PostgREST no tenga
-- dos versiones ambiguas.
drop function reserva_horas_disponibles(text, uuid, date, uuid);

create function reserva_horas_disponibles(
  p_slug text,
  p_servicio_id uuid,
  p_fecha date,
  p_empleado_id uuid default null,
  p_token uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_neg negocios;
  v_srv servicios;
  v_cita citas;
  v_empleado_id uuid := p_empleado_id;
  v_excluir uuid;
  v_res jsonb;
begin
  v_neg := reserva_priv_negocio(p_slug);
  v_srv := reserva_priv_servicio(v_neg.id, p_servicio_id);
  perform reserva_priv_validar_fecha(v_neg.zona_horaria, p_fecha);

  if p_token is not null then
    select * into v_cita
      from citas c
     where c.token_publico = p_token
       and c.negocio_id = v_neg.id;

    if not found then
      raise exception 'No encontramos esta cita. Revisa el enlace.' using errcode = 'P0001';
    end if;

    if v_cita.servicio_id <> v_srv.id then
      raise exception 'Al reprogramar se mantiene el mismo servicio.' using errcode = 'P0001';
    end if;

    if v_empleado_id is not null and v_empleado_id <> v_cita.empleado_id then
      raise exception 'Al reprogramar se mantiene el mismo barbero.' using errcode = 'P0001';
    end if;

    v_empleado_id := v_cita.empleado_id;
    v_excluir := v_cita.id;
  end if;

  if v_empleado_id is not null then
    perform reserva_priv_validar_empleado(v_neg.id, v_empleado_id, v_srv.id);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'hora_inicio', left(x.hora_inicio::text, 5),
           'empleado_id', x.empleado_id
         ) order by x.hora_inicio), '[]'::jsonb)
    into v_res
    from (
      select distinct on (l.hora_inicio) l.hora_inicio, l.empleado_id
        from reserva_priv_horarios_libres(v_neg.id, v_srv.id, p_fecha, v_empleado_id, v_excluir) l
       order by l.hora_inicio, l.carga, l.empleado_id
    ) x;

  return v_res;
end;
$$;

revoke all on function reserva_horas_disponibles(text, uuid, date, uuid, uuid) from public;
grant execute on function reserva_horas_disponibles(text, uuid, date, uuid, uuid) to anon, authenticated;

-- -------------------------------------------------------------------------
-- 2. Política del apartado sin "24 horas" fijo
-- -------------------------------------------------------------------------

alter table negocios
  alter column apartado_politica set default
    'El apartado se descuenta del total del servicio. Si cancelas fuera del '
    || 'plazo permitido o no te presentas, el apartado no se devuelve.';

update negocios
   set apartado_politica =
         'El apartado se descuenta del total del servicio. Si cancelas fuera del '
         || 'plazo permitido o no te presentas, el apartado no se devuelve.'
 where apartado_politica =
         'El apartado se descuenta del total del servicio. Si cancelas con menos '
         || 'de 24 horas de anticipación o no te presentas, el apartado no se devuelve.';
