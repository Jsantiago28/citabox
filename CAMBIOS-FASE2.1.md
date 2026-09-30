# Fase 2.1 — Corrección puntual sobre Fase 2

Fecha: 2026-09-13

## Archivos modificados (únicos incluidos en este ZIP)
- src/hooks/useAuth.jsx
- src/pages/Registro.jsx

## Problema encontrado y corregido
Race condition descrita en el punto 15 del pedido:

signUp() → evento SIGNED_IN → AuthProvider llama cargarPerfil(userId)
ANTES de que bootstrap_negocio_owner() (RPC) cree la fila en "perfiles"
→ esa primera consulta falla (perfil aún no existe) → perfilUserIdRef
queda marcado como "ya revisado" para ese userId con perfil = null →
el bootstrap crea el negocio/perfil OWNER correctamente en la base de
datos, pero el contexto de React nunca vuelve a pedirlo → Dashboard y
PrivateLayout reciben perfil/negocio/rol en null pese a que el registro
fue exitoso.

## Corrección aplicada
1. `useAuth.jsx`: `refreshPerfil()` ahora acepta un `userId` explícito
   opcional (`refreshPerfil(userId)`), en vez de depender únicamente del
   `session` del closure. Esto evita cualquier duda sobre si el estado
   de React ya reflejaba la sesión en el momento de llamarlo.
2. `Registro.jsx`: tras un bootstrap exitoso y antes de `navigate`, se
   llama `await refreshPerfil(signUpData.user.id)` para forzar una
   recarga real de perfil + negocio + rol.

No se tocó nada más: ni rutas, ni RLS, ni la función SECURITY DEFINER,
ni el resto del flujo de login/logout/recuperación de contraseña.
