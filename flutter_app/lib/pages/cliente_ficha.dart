import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/cita.dart';
import '../models/cliente.dart';
import '../services/clientes_repository.dart';
import '../services/ficha_cliente.dart';
import '../services/sin_permiso.dart';
import '../theme.dart';
import '../utils/formato.dart';
import '../utils/navegador.dart';
import '../utils/whatsapp.dart';
import '../widgets/estado_cita_badge.dart';
import '../widgets/etiqueta.dart';
import '../utils/vocabulario.dart';

/// Abre un enlace externo (llamada, WhatsApp, correo).
typedef AbrirEnlace = Future<bool> Function(Uri uri);

/// Ficha del cliente: contacto, indicadores, preferencias e historial.
/// Se muestra dentro de la sección Clientes (como la ficha del empleado).
class ClienteFicha extends StatefulWidget {
  const ClienteFicha({
    super.key,
    required this.negocioId,
    required this.cliente,
    required this.repository,
    required this.onVolver,
    required this.onEditar,
    required this.onCambio,
    required this.abrirEnlace,
    this.moneda = 'DOP',
    this.ahora,
  });

  final String negocioId;
  final Cliente cliente;
  final ClientesRepository repository;
  final VoidCallback onVolver;
  final VoidCallback onEditar;

  /// Recarga la lista de clientes (por ejemplo, tras guardar las notas).
  final Future<void> Function() onCambio;
  final AbrirEnlace abrirEnlace;
  final String moneda;

  /// Reloj inyectable para las pruebas.
  final DateTime Function()? ahora;

  @override
  State<ClienteFicha> createState() => _ClienteFichaState();
}

class _ClienteFichaState extends State<ClienteFicha> {
  static const _porPagina = 10;

  List<Cita> _historial = [];
  FichaCliente _ficha = const FichaCliente();
  int _visibles = _porPagina;
  bool _loading = true;
  bool _guardandoNotas = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final citas = await widget.repository.historial(
        negocioId: widget.negocioId,
        clienteId: widget.cliente.id,
      );
      if (!mounted) return;
      setState(() {
        _historial = ordenarHistorial(citas);
        _ficha = calcularFichaCliente(
          citas,
          ahora: (widget.ahora ?? DateTime.now)(),
        );
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo cargar el historial del cliente.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editarNotas() async {
    final notas = await showDialog<String>(
      context: context,
      builder: (context) => _NotasDialog(notas: widget.cliente.notas),
    );
    if (notas == null || !mounted) return;

    setState(() => _guardandoNotas = true);
    try {
      await widget.repository.guardar(
        negocioId: widget.negocioId,
        clienteId: widget.cliente.id,
        datos: {'notas': notas.isEmpty ? null : notas},
      );
      await widget.onCambio();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mensajeDeError(error, 'No se pudieron guardar las notas.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _guardandoNotas = false);
    }
  }

  /// Derecho de acceso: descarga un JSON con el cliente y sus citas.
  void _exportarDatos() {
    final cliente = widget.cliente;
    final datos = {
      'exportado_en': DateTime.now().toIso8601String(),
      'cliente': {
        'id': cliente.id,
        'nombre': cliente.nombre,
        'telefono': cliente.telefono,
        'email': cliente.email,
        'notas': cliente.notas,
        'activo': cliente.activo,
      },
      'citas': [
        for (final c in _historial)
          {
            'id': c.id,
            'fecha': c.fecha,
            'hora_inicio': c.horaInicio,
            'hora_fin': c.horaFin,
            'precio': c.precio,
            'estado': c.estado.valor,
            'notas': c.notas,
          },
      ],
    };
    final ok = descargarArchivo(
      'cliente-${cliente.id}.json',
      const JsonEncoder.withIndent('  ').convert(datos),
      'application/json',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Datos exportados.' : 'No se pudo descargar el archivo.',
        ),
      ),
    );
  }

  /// Derecho de cancelación: anonimiza al cliente (las citas se conservan).
  Future<void> _anonimizar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Anonimizar cliente'),
        content: Text(
          'Se borrarán el nombre, teléfono, correo y notas de '
          '${widget.cliente.nombre}. Sus citas se conservan sin datos '
          'personales. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('confirmar-anonimizar'),
            style: FilledButton.styleFrom(backgroundColor: Marca.rojo),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Anonimizar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    try {
      await widget.repository.anonimizar(widget.cliente.id);
      await widget.onCambio();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Cliente anonimizado.')));
      widget.onVolver();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mensajeDeError(error, 'No se pudo anonimizar al cliente.'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _abrir(Uri uri) async {
    var abierto = false;
    try {
      abierto = await widget.abrirEnlace(uri);
    } catch (_) {}
    if (!abierto && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el enlace.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 860;
        return Padding(
          padding: EdgeInsets.all(isWide ? 28 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _encabezado(),
              const SizedBox(height: 16),
              Expanded(child: _contenido(isWide)),
            ],
          ),
        );
      },
    );
  }

  Widget _encabezado() {
    final cliente = widget.cliente;
    final telefono = _digitosTelefono(cliente.telefono);
    final resumen = ResumenCliente(
      visitas: _ficha.visitas,
      faltas: _ficha.faltas,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          tooltip: 'Volver a clientes',
          onPressed: widget.onVolver,
          icon: const Icon(Icons.arrow_back),
        ),
        const SizedBox(width: 4),
        AvatarIniciales(texto: iniciales(cliente.nombre), radio: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    cliente.nombre,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (!cliente.activo)
                    const Etiqueta(texto: 'Inactivo', color: Marca.textoSuave),
                  if (!_loading && resumen.frecuente)
                    const Etiqueta(texto: 'Frecuente', color: Marca.verde),
                  if (!_loading && resumen.conFaltas)
                    const Etiqueta(texto: 'Faltas', color: Marca.rojo),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                cliente.telefono.isEmpty ? 'Sin teléfono' : cliente.telefono,
                style: const TextStyle(color: Marca.textoSuave),
              ),
              if (cliente.email.isNotEmpty)
                Text(
                  cliente.email,
                  style: const TextStyle(color: Marca.textoSuave),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (telefono.isNotEmpty) ...[
                    OutlinedButton.icon(
                      onPressed: () => _abrir(Uri.parse('tel:$telefono')),
                      icon: const Icon(Icons.call_outlined, size: 18),
                      label: const Text('Llamar'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _abrir(
                        Uri.parse(
                          enlaceWhatsApp(
                            cliente.telefono,
                            _saludo(cliente.nombre),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.chat_outlined, size: 18),
                      label: const Text('WhatsApp'),
                    ),
                  ],
                  if (cliente.email.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () =>
                          _abrir(Uri(scheme: 'mailto', path: cliente.email)),
                      icon: const Icon(Icons.mail_outline, size: 18),
                      label: const Text('Correo'),
                    ),
                  OutlinedButton.icon(
                    onPressed: widget.onEditar,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Editar'),
                  ),
                ],
              ),
            ],
          ),
        ),
        PopupMenuButton<String>(
          key: const Key('ficha-menu-datos'),
          tooltip: 'Datos del cliente',
          onSelected: (valor) {
            if (valor == 'exportar') _exportarDatos();
            if (valor == 'anonimizar') _anonimizar();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'exportar', child: Text('Exportar datos')),
            PopupMenuItem(
              value: 'anonimizar',
              child: Text('Anonimizar cliente'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _contenido(bool isWide) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      );
    }

    final izquierda = [
      if (_ficha.conFaltas) _avisoFaltas(),
      _tarjetaIndicadores(),
      _tarjetaNotas(),
      _tarjetaFavoritos(),
    ];

    if (!isWide) {
      final tarjetas = [...izquierda, _tarjetaHistorial()];
      return ListView.separated(
        itemCount: tarjetas.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => tarjetas[index],
      );
    }

    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Column(
              children: [
                for (var i = 0; i < izquierda.length; i++) ...[
                  if (i > 0) const SizedBox(height: 16),
                  izquierda[i],
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(flex: 3, child: _tarjetaHistorial()),
        ],
      ),
    );
  }

  Widget _avisoFaltas() {
    final faltas = _ficha.faltas;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Marca.rojo.withValues(alpha: 0.08),
        border: Border.all(color: Marca.rojo.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Marca.rojo),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cliente con faltas: pide apartado',
                  style: TextStyle(
                    color: Marca.rojo,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'No se presentó a $faltas ${faltas == 1 ? 'cita' : 'citas'}.',
                  style: const TextStyle(color: Marca.textoSuave, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaIndicadores() {
    final ficha = _ficha;
    final ultima = ficha.ultimaVisita;
    final proxima = ficha.proximaCita;

    return _Tarjeta(
      titulo: 'Indicadores',
      icono: Icons.insights_outlined,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _Indicador(etiqueta: 'Visitas', valor: '${ficha.visitas}'),
          _Indicador(
            etiqueta: 'Gasto total',
            valor: formatoMoneda(ficha.gastoTotal, widget.moneda),
          ),
          _Indicador(
            etiqueta: 'Ticket promedio',
            valor: formatoMoneda(ficha.ticketPromedio, widget.moneda),
          ),
          _Indicador(
            etiqueta: 'No vino',
            valor: '${ficha.faltas}',
            color: ficha.conFaltas ? Marca.rojo : null,
          ),
          _Indicador(etiqueta: 'Canceladas', valor: '${ficha.cancelaciones}'),
          _Indicador(
            etiqueta: 'Última visita',
            valor: ultima == null ? 'Nunca' : _fechaCorta(ultima.fecha),
          ),
          _Indicador(
            etiqueta: 'Próxima cita',
            valor: proxima == null
                ? 'Sin cita'
                : '${_fechaCorta(proxima.fecha)} · '
                      '${formatoHora(proxima.horaInicio)}',
          ),
        ],
      ),
    );
  }

  Widget _tarjetaNotas() {
    final notas = widget.cliente.notas;
    return _Tarjeta(
      titulo: 'Preferencias y notas',
      icono: Icons.sticky_note_2_outlined,
      accion: _guardandoNotas
          ? const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : TextButton(
              onPressed: _editarNotas,
              child: Text(notas.isEmpty ? 'Agregar notas' : 'Editar notas'),
            ),
      child: Text(
        notas.isEmpty
            ? 'Sin notas. Anota cómo le gusta el corte (p. ej. "fade 1.5, '
                  'sin navaja").'
            : notas,
        style: TextStyle(color: notas.isEmpty ? Marca.textoSuave : Marca.texto),
      ),
    );
  }

  Widget _tarjetaFavoritos() {
    return _Tarjeta(
      titulo: 'Favoritos',
      icono: Icons.star_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fila('Servicio favorito', _ficha.servicioFavorito ?? '—'),
          const SizedBox(height: 6),
          _fila(
            '${Vocabulario.of(context).profesional} favorito',
            _ficha.barberoFavorito ?? '—',
          ),
        ],
      ),
    );
  }

  Widget _fila(String etiqueta, String valor) {
    return Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(
            etiqueta,
            style: const TextStyle(color: Marca.textoSuave),
          ),
        ),
        Expanded(
          child: Text(
            valor,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _tarjetaHistorial() {
    final visibles = _historial.take(_visibles).toList(growable: false);
    final restantes = _historial.length - visibles.length;

    return _Tarjeta(
      titulo: 'Historial de citas (${_historial.length})',
      icono: Icons.history,
      child: _historial.isEmpty
          ? const Text(
              'Todavía no tiene citas.',
              style: TextStyle(color: Marca.textoSuave),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < visibles.length; i++) ...[
                  if (i > 0) const Divider(height: 16),
                  _citaHistorial(visibles[i]),
                ],
                if (restantes > 0) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () => setState(() => _visibles += _porPagina),
                      child: Text('Ver más ($restantes)'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _citaHistorial(Cita cita) {
    final detalle = [
      formatoHora(cita.horaInicio),
      if (cita.empleadoNombre.isNotEmpty) cita.empleadoNombre,
    ].join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_fechaCorta(cita.fecha)} · '
                '${cita.servicioNombre.isEmpty ? 'Servicio' : cita.servicioNombre}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                detalle,
                style: const TextStyle(color: Marca.textoSuave, fontSize: 12),
              ),
              if (cita.notas.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    cita.notas,
                    style: const TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatoMoneda(cita.precio, widget.moneda),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            EstadoCitaBadge(estado: cita.estado),
          ],
        ),
      ],
    );
  }

  /// '2026-09-18' → '18/9/2026'
  static String _fechaCorta(String fecha) {
    final dia = DateTime.tryParse(fecha);
    if (dia == null) return fecha;
    return '${formatoDiaMes(dia)}/${dia.year}';
  }
}

/// Solo los dígitos del teléfono ('809-555-1234' → '8095551234').
String _digitosTelefono(String telefono) =>
    telefono.replaceAll(RegExp(r'\D'), '');

/// 'Ana Pérez' → 'Hola Ana' (mensaje inicial del chat de WhatsApp).
String _saludo(String nombre) {
  final primero = nombre.trim().split(RegExp(r'\s+')).first;
  return primero.isEmpty ? 'Hola' : 'Hola $primero';
}

class _Indicador extends StatelessWidget {
  const _Indicador({required this.etiqueta, required this.valor, this.color});

  final String etiqueta;
  final String valor;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Marca.fondo,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            etiqueta,
            style: const TextStyle(color: Marca.textoSuave, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            valor,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: color ?? Marca.texto,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({
    required this.titulo,
    required this.icono,
    required this.child,
    this.accion,
  });

  final String titulo;
  final IconData icono;
  final Widget child;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icono, size: 18, color: Marca.dorado),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                ?accion,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _NotasDialog extends StatefulWidget {
  const _NotasDialog({required this.notas});

  final String notas;

  @override
  State<_NotasDialog> createState() => _NotasDialogState();
}

class _NotasDialogState extends State<_NotasDialog> {
  late final _controller = TextEditingController(text: widget.notas);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Preferencias y notas'),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const Key('cliente-ficha-notas'),
          controller: _controller,
          autofocus: true,
          minLines: 4,
          maxLines: 8,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Ej.: fade 1.5, sin navaja, prefiere a Carlos',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Guardar notas'),
        ),
      ],
    );
  }
}
