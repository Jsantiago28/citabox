import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import { useAuth } from '../hooks/useAuth.jsx';
import { signOut } from '../services/authService.js';

const menuItems = [
  { label: 'Inicio', to: '/dashboard' },
  { label: 'Agenda', to: '/agenda' },
  { label: 'Clientes', to: '/clientes' },
  { label: 'Servicios', to: '/servicios' },
  { label: 'Empleados', to: '/empleados' },
  { label: 'Reportes', to: '/reportes' },
  { label: 'Configuración', to: '/configuracion' },
];

// Layout base para todas las pantallas administrativas (OWNER / EMPLOYEE).
// Los permisos granulares por módulo se agregarán cuando se implemente
// cada módulo; por ahora solo se muestra el nombre del negocio y el rol.
export default function PrivateLayout() {
  const { negocio, rol } = useAuth();
  const navigate = useNavigate();

  async function handleLogout() {
    await signOut();
    navigate('/login', { replace: true });
  }

  return (
    <div className="private-layout">
      <aside className="private-layout__sidebar">
        <div className="private-layout__brand">
          {negocio?.nombre || 'Barbería PRO'}
          {rol && <span className="private-layout__rol">{rol}</span>}
        </div>
        <nav className="private-layout__nav">
          {menuItems.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              className={({ isActive }) =>
                isActive ? 'private-layout__link is-active' : 'private-layout__link'
              }
            >
              {item.label}
            </NavLink>
          ))}
        </nav>
        <button type="button" className="private-layout__logout" onClick={handleLogout}>
          Cerrar sesión
        </button>
      </aside>
      <main className="private-layout__content">
        <Outlet />
      </main>
    </div>
  );
}
