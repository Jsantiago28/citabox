# Publicar Citabox en internet (Cloudflare Pages)

Esta guía es para dejar la app en una dirección como
`https://citabox.pages.dev` o en tu propio dominio (por ejemplo
`https://reservas.tubarberia.com`). No hace falta saber programar: son
pasos en páginas web. Calcula unos 30 minutos la primera vez.

Al terminar:

- La app se publica sola cada vez que se guarda un cambio en `master`.
- Los clientes pueden abrir el enlace de reservas desde WhatsApp.
- Desde el celular se puede "instalar" como una app (ver el final).

---

## Antes de empezar

Necesitas:

1. Una cuenta de **Cloudflare** (gratis): <https://dash.cloudflare.com/sign-up>.
2. Acceso de administrador al repositorio en **GitHub**.
3. Acceso al proyecto en **Supabase**, con las migraciones de
   `supabase/migrations/` ya aplicadas.

Vas a copiar **4 datos** y guardarlos en GitHub como "secretos". Ten a mano
un bloc de notas para irlos apuntando:

| Nombre del secreto | De dónde sale |
|---|---|
| `SUPABASE_URL` | Supabase (paso 1) |
| `SUPABASE_PUBLISHABLE_KEY` | Supabase (paso 1) |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare (paso 2) |
| `CLOUDFLARE_API_TOKEN` | Cloudflare (paso 3) |

---

## Paso 1 — Copiar los datos de Supabase

1. Entra a <https://supabase.com/dashboard> y abre tu proyecto.
2. Ve a **Project Settings** (engranaje, abajo a la izquierda).
3. En **Data API** (o **API**) copia la **Project URL**. Se ve así:
   `https://abcdefghijklmno.supabase.co` → es tu `SUPABASE_URL`.
4. En **API Keys** copia la **Publishable key** (empieza por
   `sb_publishable_...`) → es tu `SUPABASE_PUBLISHABLE_KEY`.

> **Nunca** uses la *secret key* ni la *service_role key*: esas dan acceso
> total a la base. La *publishable* sí puede ir en la web, porque la
> seguridad la ponen las reglas (RLS) de la base de datos.

## Paso 2 — Copiar el Account ID de Cloudflare

1. Entra a <https://dash.cloudflare.com>.
2. En el menú de la izquierda abre **Workers & Pages**.
3. A la derecha verás **Account ID**. Pulsa **Copiar** → es tu
   `CLOUDFLARE_ACCOUNT_ID`.
   (También aparece en la dirección del navegador:
   `dash.cloudflare.com/<ESTE-NÚMERO>/...`.)

## Paso 3 — Crear el token de Cloudflare

El token es como una llave que solo sirve para publicar páginas.

1. Arriba a la derecha, pulsa tu perfil → **My Profile** → **API Tokens**.
   (O ve directo a <https://dash.cloudflare.com/profile/api-tokens>.)
2. Pulsa **Create Token**.
3. Baja hasta **Custom token** y pulsa **Get started**.
4. Rellena:
   - **Token name**: `GitHub - Citabox`
   - **Permissions**: `Account` · `Cloudflare Pages` · `Edit`
   - **Account Resources**: `Include` · *(tu cuenta)*
   - Lo demás déjalo como está.
5. Pulsa **Continue to summary** → **Create Token**.
6. Copia el token que aparece → es tu `CLOUDFLARE_API_TOKEN`.
   **Solo se muestra una vez.** Si lo pierdes, crea otro.

> No hace falta crear el proyecto en Cloudflare a mano: la primera
> publicación crea el proyecto `citabox` sola. Si prefieres crearlo
> tú, llámalo exactamente `citabox` y pon `master` como rama de
> producción (**Settings → Builds & deployments → Production branch**).

## Paso 4 — Guardar los 4 secretos en GitHub

1. Abre el repositorio en GitHub.
2. Ve a **Settings** → **Secrets and variables** → **Actions**.
3. En la pestaña **Secrets**, pulsa **New repository secret** y crea uno por
   cada fila de la tabla de arriba:
   - **Name**: el nombre exacto, en mayúsculas (por ejemplo `SUPABASE_URL`).
   - **Secret**: el valor que copiaste, sin espacios al principio ni al final.
4. Al terminar debes ver los 4 nombres en la lista.

Mientras falte alguno, la publicación se salta sola (aparece en verde con
el aviso *"Publicación omitida: faltan secretos"*) y no rompe nada.

## Paso 5 — Publicar

1. En GitHub, abre la pestaña **Actions**.
2. A la izquierda, elige **Publicar web (Cloudflare Pages)**.
3. Pulsa **Run workflow** → rama `master` → **Run workflow**.
4. Espera unos 5 minutos hasta que salga el círculo verde.
5. Abre <https://citabox.pages.dev>. ¡Ya está en internet!

Desde ahora, cada cambio que llegue a `master` se publica solo.

## Paso 6 — Conectar tu propio dominio (opcional)

1. En Cloudflare → **Workers & Pages** → proyecto **citabox** →
   pestaña **Custom domains** → **Set up a custom domain**.
2. Escribe tu dominio, por ejemplo `reservas.tubarberia.com`, y pulsa
   **Continue**.
3. - Si tu dominio ya está en Cloudflare, pulsa **Activate domain** y listo.
   - Si está en otro proveedor (GoDaddy, Namecheap, etc.), Cloudflare te
     dirá que crees un registro **CNAME**: en tu proveedor crea
     `reservas` → `citabox.pages.dev`.
4. Espera a que el estado diga **Active** (de minutos a unas horas).

**Recomendado:** para que la vista previa de WhatsApp muestre bien el logo,
en GitHub → **Settings** → **Secrets and variables** → **Actions** →
pestaña **Variables** → **New repository variable**:

- **Name**: `SITE_URL`
- **Value**: `https://reservas.tubarberia.com` (tu dominio, sin `/` al final)

y vuelve a ejecutar el paso 5.

## Paso 7 — Decirle a Supabase cuál es tu dirección

Así los correos de confirmar cuenta y de recuperar contraseña llevan a tu
web y no a `localhost`.

1. Supabase → tu proyecto → **Authentication** → **URL Configuration**.
2. **Site URL**: tu dirección principal, por ejemplo
   `https://reservas.tubarberia.com`
   (o `https://citabox.pages.dev` si no tienes dominio).
   Pulsa **Save**.
3. **Redirect URLs** → **Add URL** y agrega (una por una):
   - `https://reservas.tubarberia.com/**`
   - `https://citabox.pages.dev/**`
   - `http://localhost:*/**` (solo si se prueba la app en una computadora)
4. Guarda.

---

## Instalar la app en el celular

- **Android (Chrome):** abre la dirección → menú ⋮ → **Instalar app** (o
  **Agregar a la pantalla principal**).
- **iPhone (Safari):** abre la dirección → botón **Compartir** →
  **Agregar a inicio**.

## Si algo sale mal

| Qué ves | Qué hacer |
|---|---|
| La publicación sale verde pero dice *"faltan secretos"* | Revisa en el paso 4 que estén los 4 nombres, bien escritos. |
| *Cloudflare respondió 403* o *Authentication error* | El token no tiene permiso `Cloudflare Pages · Edit` o el Account ID no es de la misma cuenta. Repite los pasos 2 y 3. |
| La web abre pero dice que falta configurar Supabase | Revisa `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY` y vuelve a publicar. |
| El correo de confirmación lleva a `localhost` | Revisa el paso 7. |
| Veo la versión vieja | Recarga la página (en el celular, cierra y vuelve a abrir la app). |

## Detalles técnicos (para quien mantenga el código)

- Workflow: `.github/workflows/deploy-web.yml`. Se ejecuta con
  `workflow_dispatch` y en cada push a `master`; si falta algún secreto, el
  job `publicar` se salta y el workflow queda en verde.
- Compila con `flutter build web --release` y los `--dart-define`
  `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY`; publica
  `flutter_app/build/web` con `wrangler pages deploy` (proyecto
  `citabox`, rama `master`).
- `flutter_app/web/_headers`: cabeceras de seguridad (`nosniff`,
  `Referrer-Policy`, `frame-ancestors 'self'`) y caché (`no-cache` para
  `index.html`, `main.dart.js` y el service worker, que no llevan versión
  en el nombre).
- No hay `_redirects`: las rutas usan `#` (`/#/reservar/<slug>`) y, al no
  existir `404.html`, Cloudflare Pages sirve `index.html` para cualquier
  ruta.

## Supabase automático (migraciones y funciones)

El workflow **"Publicar Supabase (migraciones y funciones)"** se ejecuta cuando
el CI termina en verde en master: aplica en el Supabase real las migraciones
nuevas de `supabase/migrations/` y despliega las Edge Functions de
`supabase/functions/`. Si no hay nada nuevo, no cambia nada.

Necesita un solo secreto en GitHub:

1. En Supabase → **Account → Access Tokens** crea un token para el proyecto
   Citabox con acceso completo al proyecto. Ponle una caducidad larga
   (por ejemplo 1 año) y anota cuándo vence para renovarlo.
2. En GitHub → **Settings → Secrets and variables → Actions** crea
   `SUPABASE_ACCESS_TOKEN` con ese token.
3. Para probarlo: **Actions → "Publicar Supabase…" → Run workflow**.

## Vista previa al compartir (WhatsApp/redes)

El enlace que comparte el dueño es `<sitio>/r/<slug>`. La función de Pages `flutter_app/functions/r/[slug].js` lee el negocio con `reserva_catalogo` y devuelve las etiquetas Open Graph antes de redirigir a `/#/reservar/<slug>`. El workflow publica desde `flutter_app` (para que Pages tome `./functions`) y, antes de publicar, guarda `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY` como secretos del proyecto Pages con `wrangler pages secret put`. No hace falta nada más. Copias de seguridad: ver `docs/RESPALDOS.md`.

## Dirección anterior (`barberia-pro.pages.dev`)

La app se llamó Barbería PRO hasta el 30-oct-2026. El proyecto de Pages
`barberia-pro` ya no tiene la app: cada publicación le sube solo una
redirección 301 a `https://citabox.pages.dev` con la misma ruta, para que
los enlaces de reserva y de "Mi cita" ya compartidos sigan funcionando. No
lo borres mientras haya enlaces viejos circulando.
