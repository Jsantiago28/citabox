import { Navigate, Route, Routes } from 'react-router-dom';
import PrivateLayout from './layouts/PrivateLayout.jsx';
import ProtectedRoute from './components/ProtectedRoute.jsx';
import PublicOnlyRoute from './components/PublicOnlyRoute.jsx';
import Login from './pages/Login.jsx';
import Registro from './pages/Registro.jsx';
import RecuperarPassword from './pages/RecuperarPassword.jsx';
import RestablecerPassword from './pages/RestablecerPassword.jsx';
import Dashboard from './pages/Dashboard.jsx';
import Agenda from './pages/Agenda.jsx';
import Clientes from './pages/Clientes.jsx';
import Servicios from './pages/Servicios.jsx';
import Empleados from './pages/Empleados.jsx';
import Reportes from './pages/Reportes.jsx';
import Configuracion from './pages/Configuracion.jsx';
import ReservaPublica from './pages/ReservaPublica.jsx';

export default function App() {
  return (
    <Routes>
      {/* Experiencia pública para clientes: nunca requiere sesión */}
      <Route path="/reservar/:negocioSlug" element={<ReservaPublica />} />

      {/* Auth: si ya hay sesión, se redirige a /dashboard */}
      <Route element={<PublicOnlyRoute />}>
        <Route path="/login" element={<Login />} />
        <Route path="/registro" element={<Registro />} />
        <Route path="/recuperar-password" element={<RecuperarPassword />} />
      </Route>

      {/* El enlace de recuperación crea una sesión temporal propia; no
          debe quedar detrás de PublicOnlyRoute (redirigiría a /dashboard
          antes de poder cambiar la contraseña) ni de ProtectedRoute. */}
      <Route path="/restablecer-password" element={<RestablecerPassword />} />

      {/* Zona administrativa: requiere sesión */}
      <Route element={<ProtectedRoute />}>
        <Route element={<PrivateLayout />}>
          <Route path="/dashboard" element={<Dashboard />} />
          <Route path="/agenda" element={<Agenda />} />
          <Route path="/clientes" element={<Clientes />} />
          <Route path="/servicios" element={<Servicios />} />
          <Route path="/empleados" element={<Empleados />} />
          <Route path="/reportes" element={<Reportes />} />
          <Route path="/configuracion" element={<Configuracion />} />
        </Route>
      </Route>

      <Route path="/" element={<Navigate to="/dashboard" replace />} />
      <Route path="*" element={<Navigate to="/dashboard" replace />} />
    </Routes>
  );
}
