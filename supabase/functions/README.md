# Edge Functions

## `invitar-barbero`

Crea la cuenta de un barbero y la liga con su ficha de `empleados`.
Solo puede usarla un dueño (OWNER) activo, y solo con barberos de su negocio
que aún no tengan cuenta.

**Llamada desde Flutter** (el JWT de la sesión se envía solo):

```dart
await Supabase.instance.client.functions.invoke(
  'invitar-barbero',
  body: {'empleado_id': empleadoId, 'email': correo},
);
```

Respuesta `200 { "ok": true, "correo_enviado": true }`. Los errores llegan
como `4xx/5xx { "error": "mensaje en español" }` (en Flutter, `invoke` lanza
`FunctionException` con ese cuerpo en `details`).

Qué hace:

1. Comprueba con los permisos del propio usuario (RLS) que es OWNER activo y
   que el barbero es de su negocio y no tiene `perfil_id`.
2. Con la clave `service_role` llama a `auth.admin.inviteUserByEmail`.
   **El invitado recibe un correo para entrar y establecer su contraseña.**
   Si el correo ya era una cuenta sin negocio, se reutiliza (no se envía
   correo, `correo_enviado: false`: entra con su contraseña de siempre). Si
   ya pertenece a un negocio, devuelve error.
3. Crea el perfil `EMPLOYEE` y guarda `empleados.perfil_id`. Si algo falla,
   deshace la cuenta recién invitada para poder reintentar.

Al entrar por el enlace del correo, la app ve la marca
`debe_fijar_password` en la cuenta y le pide crear su contraseña; luego lo
lleva a su panel de barbero. Si el enlace no abre la app (por ejemplo en el
celular, mientras no haya deep links), el barbero puede usar
**"¿Olvidaste tu contraseña?"** con su correo: recibe un código y fija la
contraseña desde la app.

### Desplegar

```bash
npx supabase login
npx supabase link --project-ref <ref-del-proyecto>
npx supabase functions deploy invitar-barbero
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY` las inyecta
Supabase en la función; no hay que configurarlas. La clave `service_role`
nunca debe ir en la app.

### Configuración en el panel de Supabase
- **Authentication → URL Configuration:** `Site URL` (y `Redirect URLs`) con
  la dirección donde se publica la app web.
- **SMTP propio** (Emails → SMTP Settings): obligatorio, porque el correo de
  Supabase solo envía a los miembros del equipo. Hoy se usa Gmail con
  contraseña de aplicación.
- **Authentication → Email Templates → Reset Password:** la app pide un
  **código**, así que la plantilla debe mostrar `{{ .Token }}`, por ejemplo:

  ```html
  <h2>Restablece tu contraseña</h2>
  <p>Escribe este código en Barbería PRO:</p>
  <p style="font-size:24px;font-weight:bold">{{ .Token }}</p>
  ```

- **Invite user:** también con **código** `{{ .Token }}`. El barbero entra en
  la app por "Soy barbero: tengo un código de invitación", escribe su correo
  y el código (`verifyOTP` tipo `invite`) y crea su contraseña. Si el código
  venció, usa "¿Olvidaste tu contraseña?" con el mismo correo.

## `enviar-recordatorios`

Envía a los clientes el recordatorio de su cita por **WhatsApp (API de
Meta)**. No la usa la app: la llama cada 15 minutos el flujo
`.github/workflows/recordatorios.yml` con el encabezado `x-cron-secret`.
Se despliega con `--no-verify-jwt` (lo hace solo `deploy-supabase.yml`).

Qué hace:

1. `recordatorios_pendientes()` (migración 022) devuelve las citas
   PENDIENTE o CONFIRMADA de negocios con los recordatorios activos que
   empiezan dentro de las horas elegidas por el dueño (1–48, por defecto
   24). Omite las reservadas ya dentro de esa ventana, las de clientes sin
   teléfono y, en la prueba gratis, las que pasan del cupo del mes.
2. Envía la plantilla a cada cliente y anota el resultado con
   `registrar_recordatorio()`: lo enviado no se repite (salvo que la cita se
   reprograme) y lo fallido se reintenta hasta 3 veces.

Cupo mensual incluido (tabla `planes`): prueba 30, Solo 150, Barbería 400,
Pro 1000. En los planes pagos lo que pase del cupo se envía igual, se marca
`extra` y se cobra a RD$3 por mensaje (`planes.whatsapp_precio_extra`). El
dueño lo ve en Configuración y el administrador en `#/admin`.

### Activarla

1. **Meta:** crear la app de WhatsApp Business en developers.facebook.com,
   registrar el número y crear un **token permanente** (usuario del sistema
   con permiso `whatsapp_business_messaging`).
2. **Plantilla** en WhatsApp Manager, categoría *Utilidad*, idioma
   *Español*, nombre `recordatorio_cita`, con 6 variables en este orden:

   ```
   Hola {{1}}, te recordamos tu cita en {{2}} el {{3}} a las {{4}} para {{5}} con {{6}}. Si no puedes asistir, avísanos por aquí. ¡Te esperamos!
   ```

3. **Secretos de la función** (Supabase → Edge Functions → Secrets):
   `WHATSAPP_TOKEN`, `WHATSAPP_PHONE_ID` (identificador del número, no el
   número), `RECORDATORIOS_SECRETO` (una cadena larga al azar). Opcionales:
   `WHATSAPP_PLANTILLA` (por defecto `recordatorio_cita`) y
   `WHATSAPP_IDIOMA` (por defecto `es`).
4. **GitHub** → Settings → Secrets → Actions: `RECORDATORIOS_SECRETO` con
   el mismo valor.

Mientras falte el token o el número, la función responde
`{ ok: true, omitido }` sin enviar nada; si falta el secreto en GitHub, el
flujo termina en verde con un aviso.
