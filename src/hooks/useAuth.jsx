import { createContext, useContext, useEffect, useRef, useState } from 'react';
import { getSession, obtenerPerfilConNegocio, onAuthStateChange } from '../services/authService.js';

const AuthContext = createContext(null);

// Provee: session, user, perfil, negocio, rol, loading, refreshPerfil().
// Reacciona a SIGNED_IN / SIGNED_OUT / TOKEN_REFRESHED / USER_UPDATED.
// Evita llamadas duplicadas: solo vuelve a pedir el perfil cuando cambia
// el id de usuario, no en cada TOKEN_REFRESHED.
export function AuthProvider({ children }) {
  const [session, setSession] = useState(null);
  const [perfil, setPerfil] = useState(null);
  const [loading, setLoading] = useState(true);
  const perfilUserIdRef = useRef(null);

  async function cargarPerfil(userId) {
    if (!userId) {
      perfilUserIdRef.current = null;
      setPerfil(null);
      return;
    }
    if (perfilUserIdRef.current === userId) return; // ya cargado
    const { data, error } = await obtenerPerfilConNegocio(userId);
    if (!error && data) {
      perfilUserIdRef.current = userId;
      setPerfil(data);
    } else {
      // El usuario está autenticado pero todavía no tiene perfil/negocio
      // (por ejemplo, quedó a mitad del registro).
      perfilUserIdRef.current = userId;
      setPerfil(null);
    }
  }

  useEffect(() => {
    let activo = true;

    getSession().then(async (s) => {
      if (!activo) return;
      setSession(s);
      await cargarPerfil(s?.user?.id ?? null);
      setLoading(false);
    });

    const subscription = onAuthStateChange(async (_event, s) => {
      if (!activo) return;
      setSession(s);
      await cargarPerfil(s?.user?.id ?? null);
      setLoading(false);
    });

    return () => {
      activo = false;
      subscription.unsubscribe();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Fuerza recargar perfil/negocio/rol, ignorando la caché de
  // perfilUserIdRef. Acepta un userId explícito porque, justo después de
  // signUp() (registro), el evento SIGNED_IN puede llegar y disparar
  // cargarPerfil() ANTES de que el bootstrap (RPC) cree la fila en
  // "perfiles". Ese primer intento falla (perfil aún no existe) y marca
  // perfilUserIdRef con ese userId, por lo que un refreshPerfil() sin
  // argumentos que dependa del "session" del closure podría, en teoría,
  // ejecutarse antes de que el estado de React se actualice. Pasar el
  // userId explícitamente elimina esa dependencia de timing.
  async function refreshPerfil(userId) {
    const uid = userId ?? session?.user?.id ?? null;
    perfilUserIdRef.current = null;
    await cargarPerfil(uid);
  }

  const value = {
    session,
    user: session?.user ?? null,
    perfil,
    negocio: perfil?.negocios ?? null,
    rol: perfil?.rol ?? null,
    loading,
    refreshPerfil,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) {
    throw new Error('useAuth debe usarse dentro de <AuthProvider>');
  }
  return ctx;
}
