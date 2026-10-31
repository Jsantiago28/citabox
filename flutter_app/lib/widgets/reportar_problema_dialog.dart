import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/plataforma_repository.dart';

const versionApp = '1.0.0+1';

/// Diálogo para reportar un problema al equipo de Citabox.
Future<void> mostrarReportarProblema(
  BuildContext context, {
  required SoporteRepository repository,
  required String negocioId,
  required String pantalla,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ReportarProblemaDialog(
      repository: repository,
      negocioId: negocioId,
      pantalla: pantalla,
    ),
  );
}

class _ReportarProblemaDialog extends StatefulWidget {
  const _ReportarProblemaDialog({
    required this.repository,
    required this.negocioId,
    required this.pantalla,
  });

  final SoporteRepository repository;
  final String negocioId;
  final String pantalla;

  @override
  State<_ReportarProblemaDialog> createState() =>
      _ReportarProblemaDialogState();
}

class _ReportarProblemaDialogState extends State<_ReportarProblemaDialog> {
  final _mensaje = TextEditingController();
  var _enviando = false;
  String? _error;
  var _enviado = false;

  @override
  void dispose() {
    _mensaje.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final texto = _mensaje.text.trim();
    if (texto.length < 5) {
      setState(() => _error = 'Cuéntanos un poco más (mínimo 5 letras).');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await widget.repository.enviar(
        negocioId: widget.negocioId,
        mensaje: texto,
        contexto: {
          'pantalla': widget.pantalla,
          'plataforma': kIsWeb ? 'web' : defaultTargetPlatform.name,
          'version': versionApp,
        },
      );
      if (mounted) setState(() => _enviado = true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _enviando = false;
          _error = 'No se pudo enviar. Intenta de nuevo.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_enviado) {
      return AlertDialog(
        title: const Text('Gracias'),
        content: const Text('Recibimos tu reporte. Te contactaremos pronto.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      );
    }
    return AlertDialog(
      title: const Text('Reportar un problema'),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _mensaje,
          minLines: 4,
          maxLines: 8,
          maxLength: 2000,
          decoration: InputDecoration(
            labelText: '¿Qué pasó?',
            errorText: _error,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _enviando ? null : _enviar,
          child: Text(_enviando ? 'Enviando…' : 'Enviar'),
        ),
      ],
    );
  }
}
