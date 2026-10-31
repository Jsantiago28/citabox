import 'package:flutter/material.dart';

import '../services/mfa_repository.dart';
import '../theme.dart';
import '../widgets/pantalla_desplazable.dart';

/// Muestra [child] solo cuando la sesión ya pasó la verificación en dos
/// pasos; si la cuenta la tiene activa y falta el código, lo pide antes.
class MfaGate extends StatefulWidget {
  const MfaGate({
    super.key,
    required this.repository,
    required this.onSalir,
    required this.child,
  });

  final MfaRepository repository;
  final VoidCallback onSalir;
  final Widget child;

  @override
  State<MfaGate> createState() => _MfaGateState();
}

class _MfaGateState extends State<MfaGate> {
  bool _verificado = false;

  @override
  Widget build(BuildContext context) {
    final factorId = _verificado ? null : widget.repository.factorPendiente();
    if (factorId == null) return widget.child;
    return VerificacionMfaPage(
      repository: widget.repository,
      factorId: factorId,
      onSalir: widget.onSalir,
      onVerificado: () => setState(() => _verificado = true),
    );
  }
}

class VerificacionMfaPage extends StatefulWidget {
  const VerificacionMfaPage({
    super.key,
    required this.repository,
    required this.factorId,
    required this.onSalir,
    required this.onVerificado,
  });

  final MfaRepository repository;
  final String factorId;
  final VoidCallback onSalir;
  final VoidCallback onVerificado;

  @override
  State<VerificacionMfaPage> createState() => _VerificacionMfaPageState();
}

class _VerificacionMfaPageState extends State<VerificacionMfaPage> {
  final _codigo = TextEditingController();
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _verificar() async {
    final codigo = _codigo.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(codigo)) {
      setState(() => _error = 'Escribe los 6 dígitos del código.');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await widget.repository.verificar(
        factorId: widget.factorId,
        codigo: codigo,
      );
      if (mounted) widget.onVerificado();
    } on MfaException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo verificar el código.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PantallaDesplazable(
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Escribe el código de tu app de autenticación',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Abre Google Authenticator o Microsoft Authenticator y '
                  'copia el código de 6 dígitos de Citabox.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Marca.textoSuave),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _codigo,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(labelText: 'Código'),
                  onSubmitted: (_) => _verificar(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _enviando ? null : _verificar,
                  child: Text(_enviando ? 'Verificando…' : 'Verificar'),
                ),
                TextButton(
                  onPressed: _enviando ? null : widget.onSalir,
                  child: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
