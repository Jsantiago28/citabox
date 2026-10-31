# Procedimiento ante fallos

Qué hacer cuando algo falla en Citabox: cómo llega el aviso, cómo decidir qué
tan grave es, cómo arreglarlo o deshacerlo, y cómo avisar a los negocios.
Lo usa el administrador de la plataforma.

## 1. Cómo llegan los fallos

| Vía | Dónde se ve | Qué trae |
|---|---|---|
| **Botón "Reportar un problema"** (menú de la app) | `#/admin` → Soporte | Mensaje del dueño o barbero, negocio, pantalla, plataforma (web, Android…) y versión. Sin datos de clientes. |
| **Sentry** (errores automáticos) | sentry.io → organización `barberia-pro` | Error, pantalla y navegador. Sin datos personales. |
| **WhatsApp** de la plataforma | Tu WhatsApp | Lo que el negocio cuente. Pídele captura de pantalla y que también use el botón. |
| **GitHub Actions** | Repositorio → Actions | CI o publicación en rojo. |

Revisa `#/admin` y Sentry **cada mañana**, y siempre que alguien escriba.

## 2. Qué tan grave es

| Nivel | Ejemplos | Respuesta |
|---|---|---|
| **Crítico** | Nadie puede entrar. La reserva pública no carga. Se ven datos de otro negocio. Se pierden citas. | Empezar **de inmediato**. Si vino de una publicación reciente, **deshacerla primero** (paso 4) y después investigar. |
| **Alto** | Una función importante falla para todos (cobrar, crear citas, validar apartados) y no hay otra forma de hacerlo. | El **mismo día**. |
| **Medio** | Falla en un caso o un navegador; hay otra forma de hacerlo. | En **2–3 días**. |
| **Bajo** | Texto, diseño, sugerencias. | Se anota en el plan y entra con la próxima mejora. |

Un fallo de **seguridad o datos** (ver o cambiar datos de otro negocio) es
siempre **crítico**.

## 3. Reproducir y arreglar

1. **Reproducir**: con la cuenta del negocio o una de prueba, en el mismo
   navegador y tamaño de pantalla. Busca el error en Sentry por la hora.
2. **Escribir una prueba** que falle por el error (Flutter en
   `flutter_app/test/`, SQL en `supabase/tests/`).
3. **Corregir**, correr `flutter analyze` y `flutter test`.
4. **Un commit por arreglo**, con el mensaje en español que diga qué fallaba,
   y push a `master`. El CI tiene que quedar en verde; la publicación
   (Supabase y Cloudflare) sale sola después.
5. **Probar en la app publicada** (`citabox.pages.dev`, una recarga basta).
6. **Avisar al negocio** que ya está resuelto y marcarlo en el plan si aplica.

## 4. Deshacer una publicación que rompió algo

**La web (lo más común):**

1. Cloudflare → **Workers & Pages** → proyecto **citabox** → **Deployments**.
2. En la última publicación que funcionaba: **⋯ → Rollback to this
   deployment**. Toma segundos y no toca la base de datos.
3. Después, en el repositorio: `git revert <commit>` del cambio que falló y
   push, para que la próxima publicación no lo vuelva a subir.

**La base de datos (migraciones):**

- Las migraciones **no se deshacen** solas. Se escribe una **migración nueva**
  que corrija (por ejemplo, vuelve a crear la función como estaba).
- Si se perdieron o dañaron datos: ver [RESPALDOS.md](RESPALDOS.md). Con
  Supabase Pro hay copias diarias de 7 días.

**Las funciones de Supabase** (`invitar-barbero`, `enviar-recordatorios`):
`git revert` y push; `deploy-supabase.yml` las vuelve a publicar.

## 5. Avisar a los negocios

- **Crítico o alto que afecta a varios**: mensaje corto por WhatsApp a los
  dueños apenas se confirme, y otro cuando quede resuelto.
- **Mensaje de ejemplo**: "Hola, estamos resolviendo un problema que impide
  {qué}. Tus citas y datos están seguros. Te avisamos en cuanto quede
  listo." Y al terminar: "Ya quedó resuelto. Gracias por la paciencia."
- Nunca compartir datos de un negocio con otro, ni capturas con datos de
  clientes.

## 6. Después de un fallo crítico

Anota en el plan maestro, en una línea: qué pasó, a quién afectó, cuánto
duró, cómo se arregló y qué prueba se agregó para que no se repita. Si hizo
falta deshacer una publicación a mano, revisa por qué el CI no lo detectó.

## Contactos y accesos

| Servicio | Para qué | Dónde |
|---|---|---|
| Supabase | Base de datos, cuentas, correos | supabase.com → proyecto "Barberia PRO" |
| Cloudflare Pages | Web publicada y deshacer publicaciones | dash.cloudflare.com → citabox |
| GitHub | Código, CI y publicaciones | github.com/Jsantiago28/barberia-pro |
| Sentry | Errores automáticos | sentry.io → barberia-pro |
