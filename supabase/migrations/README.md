# Migraciones de Supabase

## 001_initial_schema.sql

Esquema inicial multi-negocio de Barbería PRO. Pensado para ejecutarse
desde cero sobre una instancia limpia de Supabase (proyecto nuevo).

### Tablas creadas

| Tabla       | Descripción                                                        |
|-------------|---------------------------------------------------------------------|
| `negocios`  | Cada barbería/salón. Raíz del modelo multi-negocio (`slug` único). |
| `perfiles`  | 1:1 con `auth.users`. Guarda `negocio_id` y `rol` (OWNER/EMPLOYEE). |
| `empleados` | Barberos/estilistas de un negocio. Puede o no tener `perfil_id`.   |
| `servicios` | Catálogo de servicios de un negocio (precio, duración).            |
| `clientes`  | Clientes de un negocio.                                             |
| `citas`     | Citas: negocio + cliente + empleado + servicio + horario + estado. |
| `apartados` | Pago/adelanto asociado a una cita.                                  |

### Relaciones

- `negocios (1) → (N) perfiles / empleados / servicios / clientes / citas / apartados`
- `citas.cliente_id → clientes.id`
- `citas.empleado_id → empleados.id`
- `citas.servicio_id → servicios.id`
- `apartados.cita_id → citas.id` (una cita tiene como máximo un apartado
  "activo": se permite un apartado nuevo solo si el anterior quedó
  `CANCELADO`, gracias al índice único parcial `uq_apartados_cita_activo`)
- `perfiles.id → auth.users.id` (uno a uno)
- `empleados.perfil_id → perfiles.id` (opcional: un empleado puede no tener
  cuenta de usuario todavía)

### Roles

- **OWNER**: acceso administrativo completo dentro de su propio negocio
  (puede gestionar perfiles, empleados, servicios y borrar registros).
- **EMPLOYEE**: puede ver y operar (crear/editar) clientes, citas y
  apartados de su propio negocio, pero no puede borrar registros ni
  administrar perfiles/empleados/servicios. El detalle fino de permisos
  por función se ajustará en una fase posterior; por ahora la base ya
  distingue ambos roles a nivel de políticas.

### Estrategia de RLS (seguridad multi-negocio)

- RLS está **habilitado en las 7 tablas**.
- Se agregaron dos funciones `security definer`:
  - `auth_negocio_id()`: devuelve el `negocio_id` del perfil del usuario
    autenticado actual.
  - `auth_es_owner()`: indica si el usuario autenticado actual es OWNER
    activo.
- Todas las políticas comparan `negocio_id = auth_negocio_id()`. Un
  usuario nunca puede leer, insertar, actualizar o borrar filas de un
  `negocio_id` distinto al suyo, sin importar lo que envíe el frontend.
- Las operaciones de borrado (`DELETE`) y la gestión de `perfiles` /
  `empleados` / `servicios` (crear/editar/borrar) están restringidas a
  OWNER. `clientes`, `citas` y `apartados` permiten insert/update a
  cualquier miembro del negocio (OWNER o EMPLOYEE); el borrado sigue
  reservado a OWNER.
- La tabla `negocios` no tiene política pública de `INSERT`: la creación
  de un negocio nuevo se maneja fuera de estas políticas (flujo de
  registro controlado, típicamente con `service_role` desde un backend
  o función, no desde el cliente autenticado directo).
- **No se crearon políticas públicas (anon)** sobre ninguna tabla. La
  reserva pública, cuando se implemente, deberá exponer solo lo mínimo
  necesario (idealmente vistas o funciones RPC acotadas), nunca acceso
  directo a las tablas completas.

### Índices principales

`negocio_id` en todas las tablas hijas, `slug` único en `negocios`,
`cliente_id`/`empleado_id`/`servicio_id` en `citas`, `cita_id` en
`apartados`, `fecha` y `(negocio_id, fecha)` en `citas`.

### Constraints principales

- `negocios.slug` único y con formato `kebab-case`.
- `servicios.precio >= 0`, `servicios.duracion_minutos > 0`.
- `citas.precio >= 0`, `citas.hora_fin > citas.hora_inicio`.
- `apartados.monto >= 0`.
- Índice único parcial `uq_citas_empleado_horario` sobre
  `(empleado_id, fecha, hora_inicio)` excluyendo citas `CANCELADA`/
  `NO_VINO`, como primera barrera contra doble reserva del mismo
  empleado en el mismo horario exacto. Reglas de solapamiento de rangos
  más finas (ej. una cita de 45 min que choca a la mitad con otra) se
  dejan para la fase de reservas/disponibilidad.
- Índice único parcial `uq_apartados_cita_activo` para evitar más de un
  apartado activo por cita.

### Cómo ejecutar la migración

1. Desde el SQL Editor del panel de Supabase: pegar y ejecutar el
   contenido completo de `001_initial_schema.sql`, y luego
   `002_hardening_multitenant.sql`, en ese orden, sobre un proyecto
   nuevo/limpio.
2. O bien, con la CLI de Supabase (`supabase db push` /
   `supabase migration up`), colocando ambos archivos en la carpeta de
   migraciones del proyecto vinculado (el prefijo numérico garantiza el
   orden de aplicación).
3. Las migraciones están pensadas para una base limpia; no incluyen
   `drop table` ni lógica de "si no existe", para evitar aplicarlas dos
   veces por error sobre datos reales.
4. Requisito: PostgreSQL 15 o superior (la versión actual de Supabase lo
   cumple), porque `002_hardening_multitenant.sql` usa la sintaxis
   `ON DELETE SET NULL (columna)` de una foreign key compuesta.

## 002_hardening_multitenant.sql (Fase 1.1)

Refuerza, a nivel de base de datos, que ninguna relación pueda cruzar
negocios — sin depender del frontend.

### Cómo se garantiza el aislamiento entre negocios

Se reemplazaron las foreign keys simples por **foreign keys compuestas**
que incluyen `negocio_id` en ambos lados de la relación:

- `citas (cliente_id, negocio_id) → clientes (id, negocio_id)`
- `citas (empleado_id, negocio_id) → empleados (id, negocio_id)`
- `citas (servicio_id, negocio_id) → servicios (id, negocio_id)`
- `apartados (cita_id, negocio_id) → citas (id, negocio_id)`
- `empleados (perfil_id, negocio_id) → perfiles (id, negocio_id)`
  (si `perfil_id` es `NULL`, la FK compuesta simplemente no se evalúa,
  que es el comportamiento esperado para un empleado sin cuenta)

Para que estas FKs compuestas sean posibles, se agregaron restricciones
`UNIQUE (id, negocio_id)` en `clientes`, `empleados`, `servicios`,
`perfiles` y `citas` (el `id` seguía siendo único por sí solo; esto no
lo cambia, solo habilita la referencia compuesta).

Con esto, es **físicamente imposible** en PostgreSQL crear, por ejemplo,
una cita del negocio A que apunte a un cliente del negocio B: la base de
datos rechaza el `INSERT`/`UPDATE` con un error de foreign key,
independientemente de lo que envíe el frontend.

### Cómo se evita el cruce de negocio_id vía RLS

Además de la integridad referencial de arriba, las políticas de
`UPDATE` ahora tienen `WITH CHECK` explícito (antes solo tenían
`USING`). Esto impide que un usuario autenticado "mueva" un registro
de su negocio hacia otro negocio cambiando su `negocio_id`, incluso si
en teoría pudiera ver la fila antes del cambio.

### Primer OWNER / bootstrap

En Fase 1.1 se dejó pendiente deliberadamente. Se resolvió en Fase 2
con `003_auth_bootstrap.sql` — ver esa sección más abajo.

## 003_auth_bootstrap.sql (Fase 2)

Resuelve, de forma controlada, el problema de "huevo y gallina": un
usuario recién creado en `auth.users` no tiene todavía perfil, así que
`auth_negocio_id()` y `auth_es_owner()` no le dan ningún acceso, y no
existe ninguna política de `INSERT` pública sobre `negocios`/`perfiles`
(esto es correcto y se mantiene sin cambios).

### Función `bootstrap_negocio_owner(...)`

- `SECURITY DEFINER`: corre con los privilegios del rol que la creó
  (dueño de las tablas en Supabase), por lo que puede insertar en
  `negocios` y `perfiles` aunque el usuario que la invoca no tenga
  ninguna política de INSERT a su favor.
- Exige `auth.uid()` no nulo (usuario ya autenticado); revocada de
  `anon`, solo `authenticated` puede ejecutarla.
- Rechaza la llamada si el usuario ya tiene un perfil — impide que la
  misma cuenta cree negocios adicionales reutilizando la función.
- Fuerza `id = auth.uid()` y `rol = 'OWNER'` al crear el perfil: el
  usuario nunca puede elegir su propio rol ni suplantar otro id.
- Valida formato de slug y nombre antes de intentar el `INSERT`; el
  `UNIQUE` de `negocios.slug` sigue siendo la autoridad final ante
  condiciones de carrera (se captura `unique_violation` y se devuelve
  un mensaje claro).
- No expone ninguna otra operación (no hay forma de actualizar o
  borrar negocios/perfiles arbitrarios a través de esta función).

### Función `negocio_slug_disponible(slug)`

Función de solo lectura (`SECURITY DEFINER`, `stable`) para que el
formulario de registro pueda sugerir si un slug está libre antes de
enviarlo. Solo devuelve `true`/`false`, no expone filas de `negocios`.
Concedida a `anon` y `authenticated` porque se usa antes de iniciar
sesión, durante el registro.

### Limitación conocida (pendiente de decisión del arquitecto)

Si el proyecto de Supabase exige **confirmación de correo obligatoria**,
`signUp()` no entrega una sesión inmediata, y por lo tanto
`bootstrap_negocio_owner()` no puede ejecutarse hasta que el usuario
confirme su correo e inicie sesión por separado. El frontend de esta
fase detecta ese caso (`data.session` ausente tras `signUp`) y le pide
al usuario confirmar su correo e iniciar sesión, pero **no** persiste
en ningún lado los datos del negocio que ya había escrito en el
formulario (nombre, slug, teléfono) — tendría que volver a escribirlos
tras confirmar. Resolver esto (por ejemplo, guardando temporalmente esos
datos, o deshabilitando la confirmación de correo para este flujo)
requiere una decisión de producto del arquitecto y no se implementó
para no improvisar una solución de datos no solicitada.

> **Actualización:** la app Flutter ya resuelve esta limitación: guarda los
> datos del negocio en los metadatos de la cuenta (`signUp(data: ...)`) y
> completa el bootstrap después de confirmar el correo con un código.

### Qué queda pendiente para fases posteriores

- Invitaciones de empleados y administración avanzada de empleados
  (por ahora Fase 2 solo lee el rol existente, no gestiona invitaciones).
- Permisos más finos de `EMPLOYEE` por módulo (más allá de la
  separación por negocio ya garantizada).
- Políticas públicas acotadas para la reserva pública (vistas o RPC,
  nunca acceso directo a las tablas privadas completas).

## 004_seguridad_perfiles.sql

Corrige dos fallos de seguridad de la política de `perfiles`:

- **Escalada de privilegios:** `perfiles_update_propio_o_owner` dejaba que
  un EMPLOYEE cambiara su propio `rol` a `OWNER` o se reactivara. Ahora un
  trigger (`trg_perfiles_proteger_columnas`) exige ser OWNER activo para
  cambiar `rol` o `activo`, impide que el dueño se quite el rol o se
  desactive a sí mismo y bloquea cualquier cambio de `negocio_id`. Las
  operaciones del servidor (sin `auth.uid()`) no se ven afectadas.
- **Perfiles inactivos con acceso:** `auth_negocio_id()` ahora solo devuelve
  el negocio si el perfil está activo, así que un perfil desactivado pierde
  el acceso a todas las tablas. La política nueva `perfiles_select_propio`
  le deja leer solo su propio perfil, para que la app muestre "perfil
  inactivo".

## 005_citas_sin_solapamiento.sql

Sustituye el índice `uq_citas_empleado_horario` (misma hora de inicio) por
la restricción de exclusión `citas_empleado_sin_solapamiento`
(`btree_gist`): un mismo empleado no puede tener dos citas activas cuyos
rangos `[hora_inicio, hora_fin)` se crucen el mismo día. `CANCELADA` y
`NO_VINO` no ocupan horario. El error para el cliente es `23P01`. El
archivo incluye una consulta para detectar solapamientos existentes antes
de aplicarla.

## 006_horarios_y_reglas.sql

- **Configuración en `negocios`:** `apartado_requerido`, `apartado_monto`
  (RD$100 por defecto), `apartado_politica`, `apartado_instrucciones` (datos
  para la transferencia), `cancelacion_horas_minimas` (24) e
  `intervalo_reserva_minutos` (15, cada cuánto se ofrecen horas).
- **`horarios_negocio`:** un rango por día (`dia_semana` 0 = domingo … 6 =
  sábado). Sin fila = cerrado ese día.
- **`horarios_empleado`:** horario propio del barbero. Si no tiene filas,
  trabaja en el horario del negocio; si tiene, solo esos días y rangos.
- **`bloqueos_empleado`:** días libres o vacaciones (rango de fechas inclusivo).
- **`empleado_servicios`:** servicios que hace cada barbero. Si no tiene
  filas, hace todos los servicios activos.
- Todo el negocio lee estas tablas; solo el OWNER las modifica.
- **Estados de la cita** (`trg_citas_validar_cambio_estado`): solo se permiten
  cambios válidos; `CANCELADA` es definitivo. Error `23514`.
- **Apartado pagado** (`trg_apartados_al_pagar`): guarda `fecha_pago` y pasa la
  cita de `PENDIENTE` a `CONFIRMADA`.

## 007_reserva_publica.sql

Reserva pública para visitantes sin cuenta (Fase 8) y reporte del pago del
apartado por transferencia (Fase 9). **No se abre ninguna política RLS
pública**: `anon` sigue sin poder leer ninguna tabla. Todo pasa por funciones
RPC `SECURITY DEFINER` (`search_path = public`) que validan cada dato en el
servidor y devuelven solo lo necesario. "Hoy" y "ahora" salen de
`negocios.zona_horaria`.

- **`citas.token_publico`** (uuid aleatorio, único): identifica la cita en el
  enlace "Mi cita" sin cuenta.
- **Clientes por teléfono:** al reservar se reutiliza el cliente del mismo
  negocio con el mismo teléfono (comparando solo dígitos; índice
  `idx_clientes_negocio_telefono_digitos`) o se crea uno nuevo.
- **Funciones internas `reserva_priv_*`:** revocadas de `public`, `anon` y
  `authenticated`. `reserva_priv_horarios_libres` es la única fuente de las
  reglas de disponibilidad (horario del negocio ∩ horario del barbero,
  bloqueos, servicios por barbero, pasos de `intervalo_reserva_minutos`,
  cabe antes del cierre, sin cruce con citas activas, solo horas futuras).

### Funciones públicas (`anon` y `authenticated`)

| Función | Qué hace |
|---|---|
| `reserva_catalogo(p_slug)` | Negocio activo, servicios activos, barberos activos (sin teléfonos) y horario. |
| `reserva_horas_disponibles(p_slug, p_servicio_id, p_fecha, p_empleado_id = null)` | `[{hora_inicio, empleado_id}]` libres; sin barbero, una entrada por hora. Fecha entre hoy y hoy + 60. |
| `reserva_crear(...)` | Revalida, crea/reutiliza cliente, cita `PENDIENTE` con el precio del servicio y, si `apartado_requerido` y `apartado_monto > 0`, apartado `PENDIENTE`. Máx. 3 citas futuras activas por teléfono. |
| `reserva_consultar(p_token)` | Datos de "Mi cita" (sin datos del cliente), `puede_cancelar`, `puede_reprogramar`. |
| `reserva_cancelar(p_token)` | Solo `PENDIENTE`/`CONFIRMADA` y con `cancelacion_horas_minimas` de anticipación. Cancela el apartado `PENDIENTE`; uno `PAGADO` queda igual (la devolución la decide el dueño). |
| `reserva_reprogramar(p_token, p_fecha, p_hora_inicio)` | Misma regla de anticipación; mismo servicio y barbero; revalida excluyendo la propia cita. |
| `reserva_reportar_pago(p_token, p_referencia)` | Guarda la referencia y `metodo_pago = 'TRANSFERENCIA'` del apartado `PENDIENTE`. No lo marca `PAGADO`: eso lo hace el dueño (y la cita pasa a `CONFIRMADA` por 006). |

### Errores

- `P0001`: regla de negocio (slug o token inexistente, dato inválido, fuera
  de plazo, límite de citas…). El mensaje está en español y se puede mostrar
  tal cual.
- `23P01`: la hora no está disponible (ocupada, ya pasó o fuera de horario),
  ya sea por la validación previa o por la restricción de 005 en una
  carrera. La app debe recargar las horas.

Pruebas: `supabase/tests/30_reserva_publica.sql` (negocio `negocio-d`, rol
`anon` sin JWT).

## 008_cobro_de_citas.sql

Agrega a `citas`: `metodo_pago` (`EFECTIVO`, `TRANSFERENCIA`, `TARJETA`, `OTRO`),
`propina` (aparte del precio, para no inflar los ingresos del negocio) y
`cobrada_en`, que se guarda sola la primera vez que la cita pasa a `COMPLETADA`.

## 010_seguridad_reservas_y_roles.sql

Correcciones de la revisión de seguridad del 28-oct-2026:

- **`citas.origen`** (`INTERNA` / `PUBLICA`): las reservas hechas por el enlace
  público quedan marcadas.
- **`reserva_crear`** (misma firma): máximo 30 reservas públicas pendientes por
  hora y negocio; un cliente desactivado no puede reservar en línea; el
  visitante ya no cambia el correo de una ficha existente; mensaje genérico al
  llegar al límite por teléfono.
- **`vencer_reservas_sin_pago()`**: cancela las reservas públicas cuyo apartado
  no se reportó en 3 horas. Se programa cada 15 minutos con `pg_cron` si está
  disponible.
- **Perfiles:** se elimina `perfiles_insert_owner` (los perfiles solo se crean
  con `bootstrap_negocio_owner` o la Edge Function) y el trigger impide cambiar
  el `id` de un perfil.
- **Barbero (EMPLOYEE)** (`trg_citas_limitar_empleado`): solo crea y modifica
  citas de su propia agenda y solo cambia el precio al completarla.
- **Apartados:** solo el dueño los registra y valida.
- **Cancelar una cita** cancela su apartado `PENDIENTE` (`trg_citas_cancelar_apartado`).
- **Zona horaria** del negocio validada contra `pg_timezone_names`.

Pruebas: `supabase/tests/50_seguridad_reservas_y_roles.sql`.

## 011_reserva_ajustes.sql

- **`reserva_horas_disponibles(p_slug, p_servicio_id, p_fecha, p_empleado_id = null, p_token = null)`**:
  nuevo parámetro opcional `p_token`. Al reprogramar "Mi cita", la app pasa el
  token: la función usa el barbero de la cita y no cuenta la propia cita como
  ocupada (mismas reglas que `reserva_reprogramar`). El token debe ser de una
  cita del mismo negocio y del mismo servicio; si se manda otro barbero, otro
  servicio o un token inválido → `P0001`. Se borra la firma vieja de 4
  parámetros (PostgREST no queda con dos versiones); llamar sin `p_token`
  funciona igual que antes. Mismos permisos (`anon`, `authenticated`).
- **`negocios.apartado_politica`**: el texto por defecto ya no dice "24 horas"
  (el plazo real es `cancelacion_horas_minimas`, que el dueño puede cambiar):
  *"…Si cancelas fuera del plazo permitido o no te presentas, el apartado no
  se devuelve."* Se actualizan solo las filas que conservaban el texto viejo
  exacto; las que el dueño editó no se tocan.

Pruebas: `supabase/tests/60_reserva_ajustes.sql` (negocio `negocio-g`, rol
`anon` sin JWT).

## 012_iconos_de_servicios.sql

Agrega `servicios.icono`, una clave corta opcional (`secador`, `tijera`,
`tinte`…) que la app convierte en ícono, y la devuelve en `reserva_catalogo`
para que el cliente vea el ícono al reservar.

## 013_fotos_de_servicios.sql

Agrega `servicios.imagen_url` y el bucket público de Storage `servicios`
(máx. 2 MB, JPEG/PNG/WebP). Solo el dueño activo sube, cambia o borra fotos,
y solo dentro de la carpeta de su negocio (`servicios/<negocio_id>/…`).
`reserva_catalogo` devuelve `imagen_url`; sin foto, la app muestra el ícono.

## 014_barbero_solo_sus_citas.sql

El barbero (EMPLOYEE) solo puede leer **sus propias citas** y los apartados
de esas citas; el dueño sigue viendo todo su negocio. Agrega
`auth_empleado_id()` (ficha de empleado del usuario actual). Los clientes
siguen visibles para todo el negocio, para poder darles cita.

## 015_auditoria_y_cobro_seguro.sql

Correcciones de la auditoría de seguridad del 29-oct-2026:

- **Cobro cerrado para el barbero:** no puede sacar una cita de `COMPLETADA`
  ni cambiar precio, propina o método después de cobrar; al crear una cita
  el precio es el del servicio y no puede crearla ya cobrada ni "pública".
- **`auditoria`:** registro de INSERT/UPDATE/DELETE (antes y después, usuario
  y fecha) en citas, apartados, clientes, servicios, empleados y perfiles.
  Solo el dueño la lee; nadie la modifica desde la API.
- **Reservas públicas:** también vencen las que reportaron pago y el dueño no
  validó en 24 h; un único mensaje para límite por teléfono y cliente
  bloqueado (no revela nada).
- Solo el dueño activa/desactiva clientes; el dueño no puede borrar su perfil.
- `negocios.logo` e `imagen` solo con `https://`.
- Sin `TRUNCATE`/`REFERENCES`/`TRIGGER` para `anon` y `authenticated`.

Pruebas: `supabase/tests/50_seguridad_reservas_y_roles.sql`.

## 016_consentimiento_y_datos.sql

Ley 172-13 (protección de datos, RD):

- `clientes.consentimiento_at`: cuándo el cliente aceptó la política de privacidad.
- `reserva_crear(..., p_acepta_privacidad boolean default false)` (firma nueva,
  se elimina la de 9 parámetros): sin aceptar falla con P0001; al crear o
  reutilizar cliente guarda `consentimiento_at = now()`.
- `anonimizar_cliente(p_cliente_id)`: solo el OWNER del negocio del cliente; borra
  nombre/teléfono/correo/notas, desactiva y limpia el consentimiento. Las citas se conservan.

## 017 - Suscripciones, administrador de plataforma y soporte

Cobro manual por transferencia. Cada negocio nace en PRUEBA (30 dias); el servicio sigue activo 7 dias despues de vencer. Sin servicio activo no entran citas ni reservas en linea, y el plan limita los barberos activos (planes.max_barberos). Los precios de planes estan en 0: definir.

Alta de administrador (SQL editor): insert into plataforma_admins (user_id) values ('<uuid de auth.users>'); y abrir #/admin. RPC: admin_listar_negocios, admin_activar, admin_suspender, admin_listar_soporte. Job pg_cron barberia-vencer-suscripciones (diario).
