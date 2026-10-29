import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/mfa_repository.dart';
import '../theme.dart';

/// Tarjeta "Seguridad de tu cuenta": activar o desactivar la verificación
/// en dos pasos con una app de autenticación.
class SeguridadCuentaCard extends StatefulWidget {
  const SeguridadCuentaCard({super.key, required this.repository});

  final MfaRepository repository;

  @override
  State<SeguridadCuentaCard> createState() => _SeguridadCuentaCardState();
}

class _SeguridadCuentaCardState extends State<SeguridadCuentaCard> {
  final _codigo = TextEditingController();
  bool _cargando = true;
  bool _ocupado = false;
  String? _factorActivo;
  MfaEnrolamiento? _enrolamiento;
  bool _desactivando = false;
  String? _error;
  String? _aviso;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final id = await widget.repository.factorActivo();
      if (mounted) setState(() => _factorActivo = id);
    } on MfaException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _ejecutar(Future<void> Function() accion) async {
    setState(() {
      _ocupado = true;
      _error = null;
      _aviso = null;
    });
    try {
      await accion();
    } on MfaException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Algo salió mal. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  bool _codigoValido() {
    if (RegExp(r'^\d{6}$').hasMatch(_codigo.text.trim())) return true;
    setState(() => _error = 'Escribe los 6 dígitos del código.');
    return false;
  }

  Future<void> _activar() => _ejecutar(() async {
    final datos = await widget.repository.iniciarActivacion();
    if (mounted) {
      setState(() {
        _enrolamiento = datos;
        _codigo.clear();
      });
    }
  });

  Future<void> _confirmarActivacion() async {
    if (!_codigoValido()) return;
    await _ejecutar(() async {
      final datos = _enrolamiento!;
      await widget.repository.verificar(
        factorId: datos.factorId,
        codigo: _codigo.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _factorActivo = datos.factorId;
        _enrolamiento = null;
        _codigo.clear();
        _aviso = 'Verificación en dos pasos activada.';
      });
    });
  }

  Future<void> _confirmarDesactivacion() async {
    if (!_codigoValido()) return;
    await _ejecutar(() async {
      final id = _factorActivo!;
      await widget.repository.verificar(
        factorId: id,
        codigo: _codigo.text.trim(),
      );
      await widget.repository.desactivar(id);
      if (!mounted) return;
      setState(() {
        _factorActivo = null;
        _desactivando = false;
        _codigo.clear();
        _aviso = 'Verificación en dos pasos desactivada.';
      });
    });
  }

  void _cancelar() => setState(() {
    _enrolamiento = null;
    _desactivando = false;
    _codigo.clear();
    _error = null;
  });

  Widget _campoCodigo(String boton, VoidCallback alConfirmar) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('mfa-codigo'),
          controller: _codigo,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(labelText: 'Código de 6 dígitos'),
        ),
        Row(
          children: [
            FilledButton(
              onPressed: _ocupado ? null : alConfirmar,
              child: Text(boton),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _ocupado ? null : _cancelar,
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _contenido() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    final enrolamiento = _enrolamiento;
    if (enrolamiento != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Ábrelo en Google Authenticator o Microsoft Authenticator → '
            'Agregar → Ingresar clave. Escribe este código secreto:',
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            decoration: BoxDecoration(
              color: Marca.fondo,
              border: Border.all(color: Marca.borde),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    _enGrupos(enrolamiento.secreto),
                    key: const Key('mfa-secreto'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copiar código secreto',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: enrolamiento.secreto),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Después escribe el código de 6 dígitos que muestra la app.',
          ),
          _campoCodigo('Activar', _confirmarActivacion),
        ],
      );
    }
    if (_factorActivo != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_user, color: Colors.green, size: 20),
              SizedBox(width: 8),
              Text('Activa', style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          if (_desactivando) ...[
            const Text('Escribe un código válido de tu app para desactivarla.'),
            _campoCodigo('Confirmar y desactivar', _confirmarDesactivacion),
          ] else
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: _ocupado
                    ? null
                    : () => setState(() {
                        _desactivando = true;
                        _error = null;
                        _aviso = null;
                      }),
                child: const Text('Desactivar'),
              ),
            ),
        ],
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton(
        onPressed: _ocupado ? null : _activar,
        child: const Text('Activar verificación en dos pasos'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: Marca.negro,
                  child: Icon(
                    Icons.shield_outlined,
                    color: Marca.doradoClaro,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Seguridad de tu cuenta',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const Text(
                        'Pide un código de tu celular al iniciar sesión.',
                        style: TextStyle(color: Marca.textoSuave, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _contenido(),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_aviso != null) ...[const SizedBox(height: 8), Text(_aviso!)],
          ],
        ),
      ),
    );
  }
}

String _enGrupos(String secreto) {
  final limpio = secreto.replaceAll(RegExp(r'\s'), '');
  final partes = <String>[];
  for (var i = 0; i < limpio.length; i += 4) {
    partes.add(
      limpio.substring(i, i + 4 > limpio.length ? limpio.length : i + 4),
    );
  }
  return partes.join(' ');
}
