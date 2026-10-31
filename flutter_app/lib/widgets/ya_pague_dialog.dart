import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/plataforma_repository.dart';
import '../utils/fotos.dart';
import '../utils/whatsapp.dart';

/// WhatsApp de Citabox donde llegan los pagos de los planes.
/// Se define al compilar: --dart-define=WHATSAPP_PLATAFORMA=1809XXXXXXX
const whatsappPlataforma = String.fromEnvironment('WHATSAPP_PLATAFORMA');

/// Planes que se pagan (migraciones 017 y 018).
const planesDePago = [
  (codigo: 'solo', nombre: 'Solo', precio: 400, detalle: '1 persona'),
  (
    codigo: 'barberia',
    nombre: 'Equipo',
    precio: 900,
    detalle: 'hasta 5 personas',
  ),
  (codigo: 'pro', nombre: 'Pro', precio: 1600, detalle: 'equipo sin límite'),
];

/// Texto del aviso de pago (WhatsApp y panel de administrador).
String mensajePago({
  required String negocio,
  required String plan,
  required int precio,
  String referencia = '',
  String reciboUrl = '',
}) => [
  'Hola, ya pagué Citabox.',
  'Negocio: $negocio',
  'Plan: $plan (RD\$$precio al mes)',
  if (referencia.trim().isNotEmpty) 'Referencia: ${referencia.trim()}',
  if (reciboUrl.isNotEmpty) 'Recibo: $reciboUrl',
].join('\n');

typedef SubirRecibo = Future<String> Function(FotoElegida foto);
typedef AbrirEnlace = Future<bool> Function(Uri enlace);

Future<void> mostrarYaPague(
  BuildContext context, {
  required SoporteRepository soporte,
  required String negocioId,
  required String negocioNombre,
  required SubirRecibo subirRecibo,
  Future<List<CuentaPago>> Function()? cargarCuentas,
  ElegirFoto elegirFoto = elegirFotoDelDispositivo,
  AbrirEnlace? abrirEnlace,
  String whatsapp = whatsappPlataforma,
}) => showDialog<void>(
  context: context,
  builder: (_) => _YaPagueDialog(
    soporte: soporte,
    negocioId: negocioId,
    negocioNombre: negocioNombre,
    subirRecibo: subirRecibo,
    cargarCuentas: cargarCuentas,
    elegirFoto: elegirFoto,
    abrirEnlace:
        abrirEnlace ??
        (enlace) => launchUrl(enlace, mode: LaunchMode.externalApplication),
    whatsapp: whatsapp,
  ),
);

class _YaPagueDialog extends StatefulWidget {
  const _YaPagueDialog({
    required this.soporte,
    required this.negocioId,
    required this.negocioNombre,
    required this.subirRecibo,
    this.cargarCuentas,
    required this.elegirFoto,
    required this.abrirEnlace,
    required this.whatsapp,
  });

  final SoporteRepository soporte;
  final String negocioId;
  final String negocioNombre;
  final SubirRecibo subirRecibo;
  final Future<List<CuentaPago>> Function()? cargarCuentas;
  final ElegirFoto elegirFoto;
  final AbrirEnlace abrirEnlace;
  final String whatsapp;

  @override
  State<_YaPagueDialog> createState() => _YaPagueDialogState();
}

class _YaPagueDialogState extends State<_YaPagueDialog> {
  final _referencia = TextEditingController();
  String _plan = 'barberia';
  FotoElegida? _recibo;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _referencia.dispose();
    super.dispose();
  }

  Future<void> _elegirRecibo() async {
    try {
      final foto = await widget.elegirFoto();
      if (foto == null || !mounted) return;
      if (foto.bytes.lengthInBytes > 2 * 1024 * 1024) {
        setState(() => _error = 'La foto del recibo pesa más de 2 MB.');
        return;
      }
      setState(() {
        _recibo = foto;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = 'No se pudo abrir la foto.');
    }
  }

  Future<void> _enviar() async {
    final plan = planesDePago.firstWhere((p) => p.codigo == _plan);
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final recibo = _recibo;
      final reciboUrl = recibo == null ? '' : await widget.subirRecibo(recibo);
      final mensaje = mensajePago(
        negocio: widget.negocioNombre,
        plan: plan.nombre,
        precio: plan.precio,
        referencia: _referencia.text,
        reciboUrl: reciboUrl,
      );
      // Queda en el panel de administrador aunque WhatsApp no se abra.
      await widget.soporte.enviar(
        negocioId: widget.negocioId,
        mensaje: mensaje,
        contexto: {'tipo': 'PAGO', 'plan': plan.codigo, 'recibo': reciboUrl},
      );
      if (widget.whatsapp.isNotEmpty) {
        await widget.abrirEnlace(
          Uri.parse(enlaceWhatsApp(widget.whatsapp, mensaje)),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Recibimos tu aviso de pago. Te confirmamos al validarlo.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo enviar el aviso. Intenta de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ya pagué'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CuentasDePago(cargar: widget.cargarCuentas),
              const Text('¿Qué plan pagaste?'),
              RadioGroup<String>(
                groupValue: _plan,
                onChanged: (valor) {
                  if (valor != null) setState(() => _plan = valor);
                },
                child: Column(
                  children: [
                    for (final plan in planesDePago)
                      RadioListTile<String>(
                        key: Key('plan-${plan.codigo}'),
                        value: plan.codigo,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${plan.nombre} · RD\$${plan.precio}/mes'),
                        subtitle: Text(plan.detalle),
                      ),
                  ],
                ),
              ),
              TextField(
                key: const Key('pago-referencia'),
                controller: _referencia,
                decoration: const InputDecoration(
                  labelText: 'Referencia de la transferencia (opcional)',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('pago-recibo'),
                onPressed: _enviando ? null : _elegirRecibo,
                icon: Icon(
                  _recibo == null ? Icons.receipt_long : Icons.check_circle,
                  size: 18,
                ),
                label: Text(
                  _recibo == null
                      ? 'Adjuntar foto del recibo'
                      : 'Recibo adjunto',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('pago-enviar'),
          onPressed: _enviando ? null : _enviar,
          child: Text(_enviando ? 'Enviando…' : 'Enviar aviso de pago'),
        ),
      ],
    );
  }
}

/// "Transfiere a:" con las cuentas de Citabox y botón para copiar.
class _CuentasDePago extends StatefulWidget {
  const _CuentasDePago({required this.cargar});

  final Future<List<CuentaPago>> Function()? cargar;

  @override
  State<_CuentasDePago> createState() => _CuentasDePagoState();
}

class _CuentasDePagoState extends State<_CuentasDePago> {
  late final Future<List<CuentaPago>> _cuentas =
      widget.cargar?.call() ?? Future.value(const []);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CuentaPago>>(
      future: _cuentas,
      builder: (context, snap) {
        final cuentas = snap.data ?? const [];
        if (cuentas.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Transfiere a:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              for (final c in cuentas)
                Card(
                  margin: const EdgeInsets.only(top: 6),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.account_balance),
                    title: Text('${c.banco} · ${c.tipo}'),
                    subtitle: Text('${c.numero}\n${c.titular}'),
                    isThreeLine: true,
                    trailing: IconButton(
                      key: Key('copiar-${c.numero}'),
                      tooltip: 'Copiar número',
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: c.numero));
                        if (!context.mounted) return;
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(content: Text('Copiado: ${c.numero}')),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
