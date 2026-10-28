import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/password_repository.dart';
import '../services/registro_repository.dart';
import '../theme.dart';
import '../widgets/logo_barberia.dart';
import 'recuperar_password_page.dart';
import 'registro_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    this.registroRepository,
    this.passwordRepository,
  });

  final RegistroRepository? registroRepository;
  final PasswordRepository? passwordRepository;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on AuthException {
      if (mounted) {
        setState(() => _error = 'Correo o contraseña incorrectos.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo iniciar sesión. Intenta de nuevo.');
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _abrirRegistro() {
    final repository =
        widget.registroRepository ??
        SupabaseRegistroRepository(Supabase.instance.client);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RegistroPage(repository: repository),
      ),
    );
  }

  PasswordRepository get _passwordRepository =>
      widget.passwordRepository ??
      SupabasePasswordRepository(Supabase.instance.client);

  void _abrirRecuperacion() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecuperarPasswordPage(
          repository: _passwordRepository,
          emailInicial: _emailController.text.trim(),
        ),
      ),
    );
  }

  void _abrirInvitacion() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecuperarPasswordPage.invitacion(
          repository: _passwordRepository,
          emailInicial: _emailController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Marca.negro,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const EncabezadoMarca(),
                  const SizedBox(height: 28),
                  _tarjeta(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tarjeta(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Iniciar sesión',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text('Accede al panel de tu negocio.'),
              const SizedBox(height: 24),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Correo'),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(email)) {
                    return 'Ingresa un correo válido.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _signIn(),
                decoration: const InputDecoration(labelText: 'Contraseña'),
                validator: (value) => (value == null || value.isEmpty)
                    ? 'Ingresa tu contraseña.'
                    : null,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _submitting ? null : _abrirRecuperacion,
                  child: const Text('¿Olvidaste tu contraseña?'),
                ),
              ),
              const SizedBox(height: 8),
              BotonDorado(
                onPressed: _submitting ? null : _signIn,
                etiqueta: _submitting ? 'Ingresando…' : 'Ingresar',
              ),
              const SizedBox(height: 4),
              TextButton(
                key: const Key('login-invitacion'),
                onPressed: _submitting ? null : _abrirInvitacion,
                child: const Text('Soy barbero: tengo un código de invitación'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _submitting ? null : _abrirRegistro,
                child: const Text('Registrar mi negocio'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
