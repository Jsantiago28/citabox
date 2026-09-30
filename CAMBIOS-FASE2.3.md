# Fase 2.3 — Registro con confirmación de correo

- Guarda temporalmente los datos del negocio en localStorage por 24 horas, sin contraseña.
- Tras login, completa automáticamente `bootstrap_negocio_owner` si el correo coincide.
- Permite completar `/registro` a una cuenta Auth autenticada que aún no tiene perfil, sin volver a pedir contraseña.
- Las rutas privadas exigen sesión y perfil.
- Mantiene 001/002/003 sin cambios.
- Mantiene `VITE_SUPABASE_PUBLISHABLE_KEY`.
