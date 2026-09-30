# Adaptación Supabase Publishable Key — Barbería PRO

Este parche adapta la conexión de Supabase de Barbería PRO a la clave pública recomendada actualmente:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`

Cambios:
- `src/services/supabaseClient.js`: reemplaza `VITE_SUPABASE_ANON_KEY` por `VITE_SUPABASE_PUBLISHABLE_KEY`.
- `.env.example`: actualizado al nuevo nombre de variable y con advertencia de no usar claves secretas.

No se modifican:
- autenticación
- RLS
- migraciones 001/002/003
- páginas de Fase 3
- dependencias
