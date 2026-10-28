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
