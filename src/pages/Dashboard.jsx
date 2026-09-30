import { useAuth } from '../hooks/useAuth.jsx';
import PagePlaceholder from '../components/PagePlaceholder.jsx';

export default function Dashboard() {
  const { user, perfil, negocio, rol } = useAuth();

  return (
    <PagePlaceholder
      title={`Hola, ${perfil?.nombre || user?.email || ''}`}
      description={
        negocio
          ? `${negocio.nombre} · rol ${rol}`
          : 'Resumen del negocio: citas de hoy, llegaron, no-show, ventas del día.'
      }
    />
  );
}
