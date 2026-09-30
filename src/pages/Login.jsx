import { useState } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { completarRegistroPendiente, signIn } from '../services/authService.js';
import { useAuth } from '../hooks/useAuth.jsx';

export default function Login() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState(null);
  const [enviando, setEnviando] = useState(false);
  const navigate = useNavigate();
  const location = useLocation();
  const { refreshPerfil } = useAuth();

  const destino = location.state?.from?.pathname || '/dashboard';

  async function handleSubmit(e) {
    e.preventDefault();
    setError(null);

    if (!email.trim() || !password) {
      setError('Correo y contraseña son obligatorios.');
      return;
    }

    setEnviando(true);
    const { data: signInData, error: authError } = await signIn(email.trim(), password);

    if (authError) {
      setEnviando(false);
      setError('Correo o contraseña incorrectos.');
      return;
    }

    const { error: bootstrapError, completado } = await completarRegistroPendiente(signInData?.user);
    if (bootstrapError) {
      setEnviando(false);
      setError(
        bootstrapError.message?.toLowerCase().includes('slug')
          ? 'Ese slug ya está en uso. Completa el registro con otro slug.'
          : 'La cuenta inició sesión, pero no se pudo completar el registro del negocio.'
      );
      return;
    }

    if (completado && signInData?.user?.id) {
      await refreshPerfil(signInData.user.id);
    }

    setEnviando(false);
    navigate(destino, { replace: true });
  }

  return (
    <div className="auth-screen">
      <div className="auth-card">
        <h1 className="auth-card__title">Iniciar sesión</h1>
        <p className="auth-card__subtitle">Accede al panel de tu negocio.</p>

        {error && <div className="auth-error">{error}</div>}

        <form onSubmit={handleSubmit} noValidate>
          <div className="auth-field">
            <label htmlFor="email">Correo</label>
            <input
              id="email"
              type="email"
              autoComplete="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </div>

          <div className="auth-field">
            <label htmlFor="password">Contraseña</label>
            <input
              id="password"
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </div>

          <button type="submit" className="auth-submit" disabled={enviando}>
            {enviando ? 'Ingresando…' : 'Ingresar'}
          </button>
        </form>

        <div className="auth-links">
          <Link to="/recuperar-password">¿Olvidaste tu contraseña?</Link>
          <Link to="/registro">Registrar mi negocio</Link>
        </div>
      </div>
    </div>
  );
}
