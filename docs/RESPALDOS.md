# Copias de seguridad de la base de datos

El workflow `.github/workflows/respaldo-db.yml` corre cada domingo (06:17 UTC)
y también a mano (Actions → "Copia de seguridad de la base de datos" → Run
workflow). Hace un `pg_dump` (PostgreSQL 17, `--no-owner --no-privileges`) de
los esquemas `public` y `auth`, lo comprime y lo cifra con `gpg` (AES256). El
resultado queda como artefacto `respaldo-db` durante **90 días**.

De `auth` no se guardan tokens de sesión, refresh tokens, factores MFA ni
registros de auditoría; sí los usuarios, para poder restaurar las cuentas.

Si faltan los secretos, el workflow termina en verde con un aviso y no hace nada.

## 1. Crear los secretos (una sola vez)

En GitHub: Settings → Secrets and variables → Actions → New repository secret.

- `SUPABASE_DB_URL`: cadena de conexión de Postgres. En Supabase: Project
  Settings → Database → Connection string → **Session pooler** (puerto 5432,
  funciona con IPv4 en GitHub Actions). Cambia `[YOUR-PASSWORD]` por la
  contraseña de la base. Forma: `postgresql://postgres.<ref>:<clave>@aws-0-<region>.pooler.supabase.com:5432/postgres`.
- `RESPALDO_CLAVE`: una frase larga y aleatoria (mínimo 24 caracteres).
  **Guárdala también en tu gestor de contraseñas**: sin ella no se puede
  abrir ninguna copia. No se puede recuperar desde GitHub.

## 2. Descargar una copia

1. GitHub → Actions → "Copia de seguridad de la base de datos" → la corrida
   que quieras → sección *Artifacts* → `respaldo-db` (un .zip).
2. Descomprime el zip: dentro está `respaldo-AAAA-MM-DD.sql.gz.gpg`.

Con GitHub CLI: `gh run download <id-de-corrida> -n respaldo-db`.

## 3. Descifrar

```bash
gpg --batch --pinentry-mode loopback --passphrase "TU_RESPALDO_CLAVE" \
    -o respaldo.sql.gz -d respaldo-AAAA-MM-DD.sql.gz.gpg
gunzip respaldo.sql.gz        # deja respaldo.sql
```

(Sin `--passphrase`, gpg te pedirá la clave de forma interactiva.)

## 4. Restaurar

**Haz la restauración primero en un proyecto de prueba**, nunca directamente en
producción sin haber verificado la copia.

1. Crea un proyecto Supabase nuevo y vacío (o una base local con
   `supabase start`). Si es proyecto nuevo, aplica antes las migraciones de
   `supabase/migrations/` o restaura sobre una base completamente vacía (el
   volcado ya trae el esquema `public`).
2. Obtén su cadena de conexión (Session pooler) como `DESTINO_URL`.
3. Instala el cliente PostgreSQL 17 (`psql`).
4. Restaura deteniendo ante el primer error:

   ```bash
   psql "$DESTINO_URL" -v ON_ERROR_STOP=0 -f respaldo.sql 2> errores.txt
   ```

   Los avisos de "already exists" sobre objetos que Supabase ya trae en `auth`
   son normales; revisa `errores.txt` buscando cualquier otro error.
5. Verifica: cuenta filas de `negocios`, `citas` y `auth.users` y compáralas con
   producción; entra a la app apuntando al proyecto de prueba.
6. Para recuperar producción: repite los pasos 2-5 con la base de producción
   (tras exportar su estado actual, por si acaso) o, mejor, migra la app al
   proyecto restaurado cambiando `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY` en
   los secretos del repositorio.
7. Las sesiones no se respaldan: todos los usuarios tendrán que iniciar sesión
   de nuevo.

## Buenas prácticas

- Prueba una restauración completa al menos una vez al trimestre.
- Descarga de vez en cuando una copia a un lugar fuera de GitHub (la retención
  del artefacto es de 90 días).
- Si cambias `RESPALDO_CLAVE`, las copias antiguas siguen necesitando la clave
  con la que se hicieron.
