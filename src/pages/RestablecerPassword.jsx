import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../hooks/useAuth.jsx';
import { actualizarPassword } from '../services/authService.js';

// El usuario llega aquí desde el enlace de correo. El cliente de Supabase
// detecta el token en la URL (detectSessionInUrl, activado por defecto) y
// crea una sesión temporal de recuperación antes de que este componente
// se monte; esa sesión se refleja en useAuth() a través del listener
// global de onAuthStateChange.
export default function RestablecerPassword() {
  const { session, loading } = useAuth();
  const [password, setPassword] = useState('');
  const [confirmacion, setConfirmacion] = useState('');
  const [error, setError] = useState(null);
  const [exito, setExito] = useState(false);
  const [enviando, setEnviando] = useState(false);
  const navigate = useNavigate();

  async function handleSubmit(e) {
    e.preventDefault();
    setError(null);

    if (password.length < 8) {
      setError('La contraseña debe tener al menos 8 caracteres.');
      return;
    }
    if (password !== confirmacion) {
      setError('Las contraseñas no coinciden.');
      return;
    }

    setEnviando(true);
    const { error: updateError } = await actualizarPassword(password);
    setEnviando(false);

    if (updateError) {
      setError('No se pudo actualizar la contraseña. El enlace pudo haber expirado.');
      return;
    }

    setExito(true);
    setTimeout(() => navigate('/dashboard', { replace: true }), 1500);
  }

  if (loading) return null;

  if (!session) {
    return (
      <div className="auth-screen">
        <div className="auth-card">
          <h1 className="auth-card__title">Enlace inválido</h1>
          <div className="auth-error">
            Este enlace de recuperación no es válido o ya expiró. Solicita uno
            nuevo desde la pantalla de inicio de sesión.
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="auth-screen">
      <div className="auth-card">
        <h1 className="auth-card__title">Nueva contraseña</h1>

        {error && <div className="auth-error">{error}</div>}
        {exito && <div className="auth-success">Contraseña actualizada. Redirigiendo…</div>}

        {!exito && (
          <form onSubmit={handleSubmit} noValidate>
            <div className="auth-field">
              <label htmlFor="password">Nueva contraseña</label>
              <input
                id="password"
                type="password"
                autoComplete="new-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
            </div>

            <div className="auth-field">
              <label htmlFor="confirmacion">Confirmar contraseña</label>
              <input
                id="confirmacion"
                type="password"
                autoComplete="new-password"
                value={confirmacion}
                onChange={(e) => setConfirmacion(e.target.value)}
              />
            </div>

            <button type="submit" className="auth-submit" disabled={enviando}>
              {enviando ? 'Guardando…' : 'Guardar contraseña'}
            </button>
          </form>
        )}
      </div>
    </div>
  );
}
