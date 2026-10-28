import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/apartado.dart';
import '../models/cita.dart';
import '../services/apartados_repository.dart';
import '../theme.dart';
import '../utils/formato.dart';
import '../utils/whatsapp.dart';
import '../widgets/estado_cita_badge.dart';
import '../widgets/etiqueta.dart';

/// Apartados de las citas: el cliente paga por transferencia, reporta la
/// referencia y aquí el dueño (o el barbero) valida el pago a mano.
class ApartadosPage extends StatefulWidget {
  const ApartadosPage({
    super.key,
    required this.negocioId,
    required this.repository,
    this.negocioNombre = '',
    this.moneda = 'DOP',
    this.empleadoId,
    this.hoy,
    this.abrirEnlace,
  });

  final String negocioId;
  final ApartadosRepository repository;
  final String negocioNombre;
  final String moneda;

  /// Si se indica, solo los apartados de las citas de ese empleado.
  final String? empleadoId;

  /// Inyectable en pruebas; por defecto la fecha del dispositivo.
  final DateTime? hoy;

  /// Inyectable en pruebas; por defecto abre el enlace fuera de la app.
  final Future<void> Function(Uri enlace)? abrirEnlace;

  @override
  State<ApartadosPage> createState() => _ApartadosPageState();
}

class _ApartadosPageState extends State<ApartadosPage> {
  final _buscador = TextEditingController();
  List<Apartado> _apartados = [];
  EstadoApartado _filtro = EstadoApartado.pendiente;
  bool _cargando = true;
  String? _error;
  String? _ocupadoId;
  bool _registrando = false;

  DateTime get _hoy => widget.hoy ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final apartados = await widget.repository.listar(
        negocioId: widget.negocioId,
        empleadoId: widget.empleadoId,
      );
      if (mounted) setState(() => _apartados = apartados);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudieron cargar los apartados.');
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _avisar(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  int _cuantos(EstadoApartado estado) =>
      _apartados.where((a) => a.estado == estado).length;

  List<Apartado> get _visibles {
    final consulta = _buscador.text.trim().toLowerCase();
    final lista = _apartados
        .where((a) => a.estado == _filtro)
        .where(
          (a) =>
              consulta.isEmpty ||
              a.clienteNombre.toLowerCase().contains(consulta) ||
              a.clienteTelefono.toLowerCase().contains(consulta),
        )
        .toList();

    switch (_filtro) {
      case EstadoApartado.pendiente:
        // Primero los que ya reportaron la transferencia; luego por cita.
        lista.sort((a, b) {
          if (a.tieneReferencia != b.tieneReferencia) {
            return a.tieneReferencia ? -1 : 1;
          }
          return a.momentoCita.compareTo(b.momentoCita);
        });
      case EstadoApartado.pagado:
        lista.sort((a, b) => b.fechaPago.compareTo(a.fechaPago));
      case EstadoApartado.cancelado:
        lista.sort((a, b) => b.momentoCita.compareTo(a.momentoCita));
    }
    return lista;
  }

  Future<void> _validar(Apartado apartado) async {
    final datos = await showDialog<_DatosValidacion>(
      context: context,
      builder: (context) =>
          _ValidarDialog(apartado: apartado, moneda: widget.moneda),
    );
    if (datos == null || !mounted) return;

    setState(() => _ocupadoId = apartado.id);
    try {
      await widget.repository.validar(
        negocioId: widget.negocioId,
        apartadoId: apartado.id,
        monto: datos.monto,
        metodo: datos.metodo,
        referencia: datos.referencia,
      );
      if (!mounted) return;
      _avisar('Pago validado. La cita quedó confirmada.');
      await _cargar();
    } catch (_) {
      if (mounted) _avisar('No se pudo validar el pago.');
    } finally {
      if (mounted) setState(() => _ocupadoId = null);
    }
  }

  Future<void> _cancelar(Apartado apartado) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rechazar apartado'),
        content: Text(
          '¿Cancelar el apartado de ${apartado.clienteNombre}? '
          'La cita no se cancela; podrás registrar otro apartado después.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Volver'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Marca.rojo),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sí, cancelar apartado'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _ocupadoId = apartado.id);
    try {
      await widget.repository.cancelar(
        negocioId: widget.negocioId,
        apartadoId: apartado.id,
      );
      if (!mounted) return;
      _avisar('Apartado cancelado.');
      await _cargar();
    } catch (_) {
      if (mounted) _avisar('No se pudo cancelar el apartado.');
    } finally {
      if (mounted) setState(() => _ocupadoId = null);
    }
  }

  Future<void> _registrar() async {
    setState(() => _registrando = true);
    List<Cita> citas;
    num monto;
    try {
      final hoy = _hoy;
      final resultados = await Future.wait([
        widget.repository.citasSinApartado(
          negocioId: widget.negocioId,
          desde: DateTime(hoy.year, hoy.month, hoy.day),
          empleadoId: widget.empleadoId,
        ),
        widget.repository.montoPorDefecto(widget.negocioId),
      ]);
      citas = resultados[0] as List<Cita>;
      monto = resultados[1] as num;
    } catch (_) {
      if (mounted) {
        setState(() => _registrando = false);
        _avisar('No se pudieron cargar las citas próximas.');
      }
      return;
    }
    if (!mounted) return;

    final datos = await showDialog<_DatosRegistro>(
      context: context,
      builder: (context) => _RegistrarDialog(
        citas: citas,
        montoPorDefecto: monto,
        moneda: widget.moneda,
      ),
    );
    if (datos == null || !mounted) {
      if (mounted) setState(() => _registrando = false);
      return;
    }

    try {
      await widget.repository.registrar(
        negocioId: widget.negocioId,
        citaId: datos.cita.id,
        monto: datos.monto,
      );
      if (!mounted) return;
      _avisar('Apartado registrado.');
      setState(() => _filtro = EstadoApartado.pendiente);
      await _cargar();
    } catch (_) {
      if (mounted) {
        _avisar(
          'No se pudo registrar el apartado. '
          'Revisa que la cita no tenga ya uno activo.',
        );
      }
    } finally {
      if (mounted) setState(() => _registrando = false);
    }
  }

  String _mensajeWhatsApp(Apartado a) {
    final nombre = a.clienteNombre.trim().split(' ').first;
    final negocio = widget.negocioNombre.isEmpty
        ? ''
        : ' de ${widget.negocioNombre}';
    final fecha = DateTime.tryParse(a.fecha);
    final cuando = [
      if (fecha != null) 'el ${formatoFechaLarga(fecha).toLowerCase()}',
      if (a.horaInicio.isNotEmpty) 'a las ${formatoHora(a.horaInicio)}',
    ].join(' ');
    final servicio = a.servicioNombre.isEmpty ? '' : ' de ${a.servicioNombre}';
    final monto = formatoMoneda(a.monto, widget.moneda);
    final cita = 'tu cita$servicio $cuando'.trim();

    return switch (a.estado) {
      EstadoApartado.pendiente =>
        'Hola $nombre, te escribimos$negocio sobre $cita. '
            'Para confirmarla falta el apartado de $monto. '
            '¿Nos envías la referencia de la transferencia?',
      EstadoApartado.pagado =>
        'Hola $nombre, te escribimos$negocio: recibimos tu apartado de '
            '$monto. ¡T${cita.substring(1)} está confirmada!',
      EstadoApartado.cancelado =>
        'Hola $nombre, te escribimos$negocio sobre $cita. '
            'No pudimos validar el apartado de $monto.',
    };
  }

  Future<void> _whatsApp(Apartado apartado) async {
    if (telefonoWhatsApp(apartado.clienteTelefono).isEmpty) return;
    final enlace = Uri.parse(
      enlaceWhatsApp(apartado.clienteTelefono, _mensajeWhatsApp(apartado)),
    );
    try {
      final abrir = widget.abrirEnlace;
      if (abrir != null) {
        await abrir(enlace);
      } else if (!await launchUrl(
        enlace,
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError('no abrió');
      }
    } catch (_) {
      if (mounted) _avisar('No se pudo abrir WhatsApp.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth >= 860;

        final buscador = SizedBox(
          width: ancho ? 280 : double.infinity,
          child: TextField(
            key: const Key('apartados-buscar'),
            controller: _buscador,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar cliente…',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _buscador.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpiar búsqueda',
                      onPressed: () {
                        _buscador.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close, size: 18),
                    ),
            ),
          ),
        );

        final registrar = FilledButton.icon(
          onPressed: _registrando ? null : _registrar,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Registrar apartado'),
        );

        final porValidar = _cuantos(EstadoApartado.pendiente);

        return Padding(
          padding: EdgeInsets.all(ancho ? 28 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Apartados',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          porValidar == 1
                              ? '1 por validar'
                              : '$porValidar por validar',
                          style: const TextStyle(color: Marca.textoSuave),
                        ),
                      ],
                    ),
                  ),
                  if (ancho) ...[buscador, const SizedBox(width: 12)],
                  registrar,
                ],
              ),
              if (!ancho) ...[const SizedBox(height: 16), buscador],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final estado in EstadoApartado.values)
                    ChoiceChip(
                      key: Key('filtro-${estado.valor}'),
                      label: Text(
                        '${_tituloFiltro(estado)} (${_cuantos(estado)})',
                      ),
                      selected: _filtro == estado,
                      onSelected: (_) => setState(() => _filtro = estado),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(child: _contenido()),
            ],
          ),
        );
      },
    );
  }

  String _tituloFiltro(EstadoApartado estado) => switch (estado) {
    EstadoApartado.pendiente => 'Por validar',
    EstadoApartado.pagado => 'Pagados',
    EstadoApartado.cancelado => 'Cancelados',
  };

  Widget _contenido() {
    if (_cargando) return const Center(child: CircularProgressIndicator());

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

    final apartados = _visibles;
    if (apartados.isEmpty) {
      final texto = _buscador.text.trim().isNotEmpty
          ? 'No hay coincidencias.'
          : switch (_filtro) {
              EstadoApartado.pendiente => 'No hay apartados por validar.',
              EstadoApartado.pagado => 'Todavía no hay apartados pagados.',
              EstadoApartado.cancelado => 'No hay apartados cancelados.',
            };
      return Center(child: Text(texto, textAlign: TextAlign.center));
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListView.separated(
          itemCount: apartados.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) => _fila(apartados[index]),
        ),
      ),
    );
  }

  Widget _fila(Apartado a) {
    final fecha = DateTime.tryParse(a.fecha);
    final cuando = [
      if (fecha != null) formatoFechaLarga(fecha),
      if (a.horaInicio.isNotEmpty) formatoHora(a.horaInicio),
    ].join(' · ');
    final detalle = [
      if (a.clienteTelefono.isNotEmpty) a.clienteTelefono,
      if (a.servicioNombre.isNotEmpty) a.servicioNombre,
      if (a.empleadoNombre.isNotEmpty) a.empleadoNombre,
    ].join(' · ');
    final metodo =
        MetodoPagoApartado.desde(a.metodoPago)?.etiqueta ?? a.metodoPago;
    final ocupado = _ocupadoId == a.id;
    final tieneTelefono = telefonoWhatsApp(a.clienteTelefono).isNotEmpty;

    return Padding(
      key: Key('apartado-${a.id}'),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AvatarIniciales(texto: iniciales(a.clienteNombre)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.clienteNombre.isEmpty ? 'Cliente' : a.clienteNombre,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (detalle.isNotEmpty)
                      Text(
                        detalle,
                        style: const TextStyle(
                          color: Marca.textoSuave,
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (cuando.isNotEmpty)
                          Text(cuando, style: const TextStyle(fontSize: 13)),
                        EstadoCitaBadge(estado: a.estadoCita),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatoMoneda(a.monto, widget.moneda),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Etiqueta(texto: a.estado.etiqueta, color: _color(a.estado)),
                ],
              ),
            ],
          ),
          if (a.tieneReferencia || metodo.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Text(
                [
                  if (metodo.isNotEmpty) metodo,
                  if (a.tieneReferencia) 'Ref. ${a.referencia}',
                ].join(' · '),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ] else if (a.estado == EstadoApartado.pendiente) ...[
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.only(left: 48),
              child: Text(
                'El cliente aún no reporta el pago.',
                style: TextStyle(color: Marca.textoSuave, fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (a.estado == EstadoApartado.pendiente) ...[
                  FilledButton.icon(
                    onPressed: ocupado ? null : () => _validar(a),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Validar pago'),
                  ),
                  TextButton(
                    onPressed: ocupado ? null : () => _cancelar(a),
                    style: TextButton.styleFrom(foregroundColor: Marca.rojo),
                    child: const Text('Rechazar'),
                  ),
                ],
                IconButton(
                  tooltip: tieneTelefono
                      ? 'Escribir por WhatsApp'
                      : 'Cliente sin teléfono',
                  onPressed: tieneTelefono ? () => _whatsApp(a) : null,
                  icon: const Icon(Icons.chat_outlined),
                  color: Marca.verde,
                ),
                if (ocupado)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _color(EstadoApartado estado) => switch (estado) {
    EstadoApartado.pendiente => Marca.naranja,
    EstadoApartado.pagado => Marca.verde,
    EstadoApartado.cancelado => Marca.textoSuave,
  };
}

num? _leerMonto(String texto) => num.tryParse(texto.trim().replaceAll(',', ''));

String _montoInicial(num monto) =>
    monto == monto.roundToDouble() ? monto.round().toString() : '$monto';

class _DatosValidacion {
  const _DatosValidacion(this.monto, this.metodo, this.referencia);

  final num monto;
  final MetodoPagoApartado metodo;
  final String referencia;
}

class _ValidarDialog extends StatefulWidget {
  const _ValidarDialog({required this.apartado, required this.moneda});

  final Apartado apartado;
  final String moneda;

  @override
  State<_ValidarDialog> createState() => _ValidarDialogState();
}

class _ValidarDialogState extends State<_ValidarDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _monto = TextEditingController(
    text: _montoInicial(widget.apartado.monto),
  );
  late final _referencia = TextEditingController(
    text: widget.apartado.referencia,
  );
  late MetodoPagoApartado _metodo =
      MetodoPagoApartado.desde(widget.apartado.metodoPago) ??
      MetodoPagoApartado.transferencia;

  @override
  void dispose() {
    _monto.dispose();
    _referencia.dispose();
    super.dispose();
  }

  void _confirmar() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _DatosValidacion(
        _leerMonto(_monto.text)!,
        _metodo,
        _referencia.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.apartado;
    return AlertDialog(
      title: const Text('Validar pago'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${a.clienteNombre} · '
                  'apartado de ${formatoMoneda(a.monto, widget.moneda)}',
                  style: const TextStyle(color: Marca.textoSuave),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('validar-monto'),
                  controller: _monto,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Monto recibido',
                    prefixText: simboloMoneda(widget.moneda),
                  ),
                  validator: (valor) {
                    final monto = _leerMonto(valor ?? '');
                    if (monto == null || monto <= 0) {
                      return 'Escribe el monto que recibiste.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                const Text('Método', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 6),
                SegmentedButton<MetodoPagoApartado>(
                  showSelectedIcon: false,
                  segments: [
                    for (final metodo in MetodoPagoApartado.values)
                      ButtonSegment(
                        value: metodo,
                        label: Text(metodo.etiqueta),
                      ),
                  ],
                  selected: {_metodo},
                  onSelectionChanged: (seleccion) =>
                      setState(() => _metodo = seleccion.first),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('validar-referencia'),
                  controller: _referencia,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Referencia (opcional)',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _confirmar,
          child: const Text('Confirmar pago'),
        ),
      ],
    );
  }
}

class _DatosRegistro {
  const _DatosRegistro(this.cita, this.monto);

  final Cita cita;
  final num monto;
}

class _RegistrarDialog extends StatefulWidget {
  const _RegistrarDialog({
    required this.citas,
    required this.montoPorDefecto,
    required this.moneda,
  });

  final List<Cita> citas;
  final num montoPorDefecto;
  final String moneda;

  @override
  State<_RegistrarDialog> createState() => _RegistrarDialogState();
}

class _RegistrarDialogState extends State<_RegistrarDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _monto = TextEditingController(
    text: _montoInicial(widget.montoPorDefecto),
  );
  Cita? _cita;

  @override
  void dispose() {
    _monto.dispose();
    super.dispose();
  }

  void _guardar() {
    if (_cita == null || !_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_DatosRegistro(_cita!, _leerMonto(_monto.text)!));
  }

  @override
  Widget build(BuildContext context) {
    final citas = widget.citas;
    return AlertDialog(
      title: const Text('Registrar apartado'),
      content: SizedBox(
        width: 460,
        child: citas.isEmpty
            ? const Text('No hay citas próximas pendientes sin apartado.')
            : Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Elige la cita', style: TextStyle(fontSize: 13)),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: citas.length,
                          itemBuilder: (context, index) {
                            final cita = citas[index];
                            final fecha = DateTime.tryParse(cita.fecha);
                            final seleccionada = _cita?.id == cita.id;
                            return ListTile(
                              key: Key('registrar-cita-${cita.id}'),
                              dense: true,
                              selected: seleccionada,
                              onTap: () => setState(() => _cita = cita),
                              leading: Icon(
                                seleccionada
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                color: seleccionada
                                    ? Marca.dorado
                                    : Marca.textoSuave,
                              ),
                              title: Text(cita.clienteNombre),
                              subtitle: Text(
                                [
                                  if (fecha != null) formatoDiaMes(fecha),
                                  formatoHora(cita.horaInicio),
                                  if (cita.servicioNombre.isNotEmpty)
                                    cita.servicioNombre,
                                  if (cita.empleadoNombre.isNotEmpty)
                                    cita.empleadoNombre,
                                ].join(' · '),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('registrar-monto'),
                      controller: _monto,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Monto del apartado',
                        prefixText: simboloMoneda(widget.moneda),
                      ),
                      validator: (valor) {
                        final monto = _leerMonto(valor ?? '');
                        if (monto == null || monto <= 0) {
                          return 'Escribe un monto mayor que cero.';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(citas.isEmpty ? 'Cerrar' : 'Cancelar'),
        ),
        if (citas.isNotEmpty)
          FilledButton(
            onPressed: _cita == null ? null : _guardar,
            child: const Text('Registrar apartado'),
          ),
      ],
    );
  }
}
