import { Navigate, Outlet, useLocation } from 'react-router-dom';
import { useAuth } from '../hooks/useAuth.jsx';

// Si el usuario ya tiene sesión, no tiene sentido mostrarle login/registro:
// se le redirige directo al Dashboard.
export default function PublicOnlyRoute() {
  const { session, perfil, loading } = useAuth();
  const location = useLocation();

  if (loading) {
    return null;
  }

  if (session && perfil) {
    return <Navigate to="/dashboard" replace />;
  }

  if (session && !perfil && location.pathname !== '/registro') {
    return <Navigate to="/registro" replace />;
  }

  return <Outlet />;
}
