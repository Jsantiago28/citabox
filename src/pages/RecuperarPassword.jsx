import { useState } from 'react';
import { Link } from 'react-router-dom';
import { enviarCorreoRecuperacion } from '../services/authService.js';

export default function RecuperarPassword() {
  const [email, setEmail] = useState('');
  const [error, setError] = useState(null);
  const [enviado, setEnviado] = useState(false);
  const [enviando, setEnviando] = useState(false);

  async function handleSubmit(e) {
    e.preventDefault();
    setError(null);

    if (!/^\S+@\S+\.\S+$/.test(email.trim())) {
      setError('Ingresa un correo válido.');
      return;
    }

    setEnviando(true);
    const { error: reqError } = await enviarCorreoRecuperacion(email.trim());
    setEnviando(false);

    if (reqError) {
      setError('No se pudo enviar el correo. Intenta de nuevo.');
      return;
    }

    setEnviado(true);
  }

  return (
    <div className="auth-screen">
      <div className="auth-card">
        <h1 className="auth-card__title">Recuperar contraseña</h1>
        <p className="auth-card__subtitle">
          Te enviaremos un enlace para establecer una nueva contraseña.
        </p>

        {error && <div className="auth-error">{error}</div>}
        {enviado && (
          <div className="auth-success">
            Si el correo existe, te llegará un enlace de recuperación en unos
            minutos.
          </div>
        )}

        {!enviado && (
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

            <button type="submit" className="auth-submit" disabled={enviando}>
              {enviando ? 'Enviando…' : 'Enviar enlace'}
            </button>
          </form>
        )}

        <div className="auth-links">
          <Link to="/login">Volver a iniciar sesión</Link>
        </div>
      </div>
    </div>
  );
}
