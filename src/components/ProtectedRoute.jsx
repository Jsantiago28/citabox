import { Navigate, Outlet, useLocation } from 'react-router-dom';
import { useAuth } from '../hooks/useAuth.jsx';

// Mientras se determina si hay sesión, no renderiza nada (evita el
// parpadeo de mostrar una ruta privada y luego redirigir). Una vez
// resuelto: sin sesión → /login, con sesión → renderiza la ruta.
export default function ProtectedRoute() {
  const { session, perfil, loading } = useAuth();
  const location = useLocation();

  if (loading) {
    return null;
  }

  if (!session) {
    return <Navigate to="/login" replace state={{ from: location }} />;
  }

  if (!perfil) {
    return <Navigate to="/registro" replace />;
  }

  return <Outlet />;
}
