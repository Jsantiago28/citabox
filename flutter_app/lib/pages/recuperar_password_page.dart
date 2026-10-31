import 'package:flutter/material.dart';

import '../services/password_repository.dart';
import '../theme.dart';
import '../widgets/logo_marca.dart';
import '../widgets/pantalla_desplazable.dart';

enum _Paso { correo, codigo }

class RecuperarPasswordPage extends StatefulWidget {
  /// Recuperación completa: pide el correo, envía un código y con ese
  /// código fija la nueva contraseña. Al terminar cierra la pantalla y
  /// AuthGate muestra el panel, porque el código abre sesión.
  const RecuperarPasswordPage({
    super.key,
    required this.repository,
    this.emailInicial = '',
  }) : fijando = false,
       onSalir = null,
       onListo = null,
       invitacion = false;

  /// Barbero invitado: escribe el correo y el código del correo de
  /// invitación (no se reenvía desde aquí) y elige su contraseña.
  const RecuperarPasswordPage.invitacion({
    super.key,
    required this.repository,
    this.emailInicial = '',
  }) : fijando = false,
       invitacion = true,
       onSalir = null,
       onListo = null;

  /// Cuenta con sesión pero sin contraseña (barbero invitado): solo pide
  /// la contraseña nueva.
  const RecuperarPasswordPage.fijar({
    super.key,
    required this.repository,
    this.onSalir,
    this.onListo,
  }) : fijando = true,
       emailInicial = '',
       invitacion = false;

  final PasswordRepository repository;
  final String emailInicial;
  final bool fijando;
  final bool invitacion;
  final VoidCallback? onSalir;
  final VoidCallback? onListo;

  @override
  State<RecuperarPasswordPage> createState() => _RecuperarPasswordPageState();
}

class _RecuperarPasswordPageState extends State<RecuperarPasswordPage> {
  final _correoForm = GlobalKey<FormState>();
  final _passwordForm = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.emailInicial);
  final _codigo = TextEditingController();
  final _password = TextEditingController();
  final _confirmacion = TextEditingController();

  _Paso _paso = _Paso.correo;
  // Si el código ya abrió sesión pero falló el cambio de contraseña, el
  // reintento no vuelve a usar el código (ya quedó consumido).
  bool _codigoVerificado = false;
  bool _enviando = false;
  String? _error;
  String? _aviso;

  @override
  void dispose() {
    for (final controller in [_email, _codigo, _password, _confirmacion]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _ejecutar(
    Future<void> Function() accion,
    String errorGenerico,
  ) async {
    setState(() {
      _enviando = true;
      _error = null;
      _aviso = null;
    });
    try {
      await accion();
    } on PasswordException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = errorGenerico);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _enviarCodigo() async {
    if (!_correoForm.currentState!.validate()) return;
    if (widget.invitacion) {
      setState(() {
        _error = null;
        _paso = _Paso.codigo;
      });
      return;
    }
    await _ejecutar(() async {
      await widget.repository.enviarCodigo(_email.text.trim());
      if (mounted) setState(() => _paso = _Paso.codigo);
    }, 'No se pudo enviar el código. Intenta de nuevo.');
  }

  Future<void> _reenviarCodigo() => _ejecutar(() async {
    await widget.repository.enviarCodigo(_email.text.trim());
    if (mounted) setState(() => _aviso = 'Te enviamos un código nuevo.');
  }, 'No se pudo enviar el código. Intenta de nuevo.');

  Future<void> _guardar() async {
    setState(() => _error = null);
    if (!_passwordForm.currentState!.validate()) return;

    await _ejecutar(() async {
      if (!widget.fijando && !_codigoVerificado) {
        final email = _email.text.trim();
        final codigo = _codigo.text.trim();
        if (widget.invitacion) {
          await widget.repository.verificarInvitacion(
            email: email,
            codigo: codigo,
          );
        } else {
          await widget.repository.verificarCodigo(email: email, codigo: codigo);
        }
        _codigoVerificado = true;
      }
      await widget.repository.cambiarPassword(_password.text);
      if (!mounted) return;

      if (widget.fijando) {
        widget.onListo?.call();
      } else {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              widget.invitacion
                  ? '¡Listo! Ya puedes usar la app.'
                  : 'Contraseña actualizada.',
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    }, 'No se pudo guardar la contraseña. Intenta de nuevo.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Marca.negro,
      appBar: widget.fijando
          ? null
          : AppBar(
              backgroundColor: Marca.negro,
              foregroundColor: Colors.white,
              title: const LogoCitabox(tamano: 18),
            ),
      body: SafeArea(
        child: PantallaDesplazable(
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: widget.fijando || _paso == _Paso.codigo
                      ? _formularioPassword(context)
                      : _formularioCorreo(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _mensajes(BuildContext context) => [
    if (_error != null) ...[
      Text(
        _error!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      const SizedBox(height: 16),
    ],
    if (_aviso != null) ...[Text(_aviso!), const SizedBox(height: 16)],
  ];

  Widget _formularioCorreo(BuildContext context) {
    return Form(
      key: _correoForm,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Icon(Icons.lock_reset_outlined, size: 34),
          ),
          const SizedBox(height: 20),
          Text(
            widget.invitacion ? 'Activar invitación' : 'Recuperar contraseña',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            widget.invitacion
                ? 'Escribe el correo donde recibiste la invitación de tu negocio.'
                : 'Escribe el correo de tu cuenta y te enviaremos un código para '
                      'crear una contraseña nueva.',
          ),
          const SizedBox(height: 24),
          ..._mensajes(context),
          TextFormField(
            key: const Key('recuperar-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _enviando ? null : _enviarCodigo(),
            decoration: const InputDecoration(labelText: 'Correo'),
            validator: (value) =>
                RegExp(r'^\S+@\S+\.\S+$').hasMatch(value?.trim() ?? '')
                ? null
                : 'Ingresa un correo válido.',
          ),
          const SizedBox(height: 20),
          BotonDorado(
            onPressed: _enviando ? null : _enviarCodigo,
            etiqueta: _enviando
                ? 'Enviando…'
                : (widget.invitacion ? 'Continuar' : 'Enviar código'),
          ),
        ],
      ),
    );
  }

  Widget _formularioPassword(BuildContext context) {
    final fijando = widget.fijando;
    final pideCodigo = !fijando && !_codigoVerificado;

    return Form(
      key: _passwordForm,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Icon(
              fijando ? Icons.key_outlined : Icons.mark_email_read_outlined,
              size: 34,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            fijando ? 'Crea tu contraseña' : 'Revisa tu correo',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            fijando
                ? 'Tu cuenta ya está lista. Elige una contraseña para entrar '
                      'la próxima vez.'
                : widget.invitacion
                ? 'Escribe el código del correo de invitación y elige tu '
                      'contraseña.'
                : 'Te enviamos un código a ${_email.text.trim()}. '
                      'Escríbelo junto con tu contraseña nueva.',
          ),
          const SizedBox(height: 24),
          ..._mensajes(context),
          if (pideCodigo) ...[
            TextFormField(
              key: const Key('recuperar-codigo'),
              controller: _codigo,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: 10,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Código',
                counterText: '',
              ),
              validator: (value) =>
                  RegExp(r'^\d{6,10}$').hasMatch(value?.trim() ?? '')
                  ? null
                  : 'Escribe el código que te enviamos por correo.',
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            key: const Key('recuperar-password'),
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Contraseña nueva',
              helperText: 'Mínimo 8 caracteres.',
            ),
            validator: (value) => (value?.length ?? 0) < 8
                ? 'La contraseña debe tener al menos 8 caracteres.'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('recuperar-confirmacion'),
            controller: _confirmacion,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _enviando ? null : _guardar(),
            decoration: const InputDecoration(
              labelText: 'Repite la contraseña',
            ),
            validator: (value) => value != _password.text
                ? 'Las contraseñas no coinciden.'
                : null,
          ),
          const SizedBox(height: 20),
          BotonDorado(
            onPressed: _enviando ? null : _guardar,
            etiqueta: _enviando ? 'Guardando…' : 'Guardar contraseña',
          ),
          if (pideCodigo && widget.invitacion) ...[
            const SizedBox(height: 12),
            const Text(
              'Si el código venció, usa "¿Olvidaste tu contraseña?" con este '
              'mismo correo.',
            ),
          ],
          if (pideCodigo && !widget.invitacion) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: _enviando ? null : _reenviarCodigo,
              child: const Text('Reenviar código'),
            ),
          ],
          if (fijando && widget.onSalir != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: _enviando ? null : widget.onSalir,
              child: const Text('Cerrar sesión'),
            ),
          ],
        ],
      ),
    );
  }
}
