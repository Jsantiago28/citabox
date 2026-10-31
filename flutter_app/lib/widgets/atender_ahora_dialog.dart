import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cita.dart';
import '../models/cliente.dart';
import '../services/agenda_repository.dart';
import '../theme.dart';
import '../utils/citas_reglas.dart';
import '../utils/formato.dart';
import '../utils/vocabulario.dart';

/// Abre "Atender ahora": crea una cita de hoy, que empieza ya y queda en
/// LLEGO. Devuelve true si se creó.
Future<bool?> mostrarAtenderAhora(
  BuildContext context, {
  required String negocioId,
  required AgendaRepository repository,
  required DateTime ahora,
  required List<Cita> citasDelDia,
  String moneda = 'DOP',
  String? empleadoFijo,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AtenderAhoraDialog(
      negocioId: negocioId,
      repository: repository,
      ahora: ahora,
      citasDelDia: citasDelDia,
      moneda: moneda,
      empleadoFijo: empleadoFijo,
    ),
  );
}

enum _ModoCliente { buscar, nuevo, dePaso }

class AtenderAhoraDialog extends StatefulWidget {
  const AtenderAhoraDialog({
    super.key,
    required this.negocioId,
    required this.repository,
    required this.ahora,
    required this.citasDelDia,
    this.moneda = 'DOP',
    this.empleadoFijo,
  });

  final String negocioId;
  final AgendaRepository repository;

  /// Momento actual; la cita empieza aquí redondeado hacia abajo a 5 min.
  final DateTime ahora;

  /// Citas de hoy ya cargadas en la agenda, para sugerir la hora libre
  /// siguiente si el barbero está ocupado.
  final List<Cita> citasDelDia;
  final String moneda;

  /// En "Mi agenda" el barbero es siempre el usuario.
  final String? empleadoFijo;

  @override
  State<AtenderAhoraDialog> createState() => _AtenderAhoraDialogState();
}

class _AtenderAhoraDialogState extends State<AtenderAhoraDialog> {
  final _formKey = GlobalKey<FormState>();
  final _busqueda = TextEditingController();
  final _nuevoNombre = TextEditingController();
  final _nuevoTelefono = TextEditingController();

  CatalogoAgenda? _catalogo;
  bool _cargando = true;
  String? _errorCarga;

  _ModoCliente _modo = _ModoCliente.buscar;
  String? _clienteId;
  String _clienteNombre = '';
  String? _servicioId;
  String? _empleadoId;
  late int _inicio;

  /// Hora libre siguiente que se ofrece tras un choque.
  int? _sugerencia;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _empleadoId = widget.empleadoFijo;
    _inicio = redondearACincoMinutos(widget.ahora);
    _busqueda.addListener(() {
      if (mounted) setState(() {});
    });
    _cargar();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    _nuevoNombre.dispose();
    _nuevoTelefono.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _errorCarga = null;
    });
    try {
      final catalogo = await widget.repository.catalogo(widget.negocioId);
      if (mounted) setState(() => _catalogo = catalogo);
    } catch (_) {
      if (mounted) {
        setState(() => _errorCarga = 'No se pudieron cargar los datos.');
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<ServicioAgenda> get _servicios {
    final catalogo = _catalogo!;
    final fijo = widget.empleadoFijo;
    return [
      for (final servicio in catalogo.servicios)
        if (fijo == null || catalogo.barberoHace(fijo, servicio.id)) servicio,
    ];
  }

  List<BarberoAgenda> get _barberos {
    final catalogo = _catalogo!;
    final servicioId = _servicioId;
    return [
      for (final barbero in catalogo.barberos)
        if (servicioId == null || catalogo.barberoHace(barbero.id, servicioId))
          barbero,
    ];
  }

  ServicioAgenda? get _servicio {
    for (final servicio in _servicios) {
      if (servicio.id == _servicioId) return servicio;
    }
    return null;
  }

  /// Vuelve a empezar "ahora" al cambiar servicio o barbero.
  void _reiniciarHora() {
    _inicio = redondearACincoMinutos(widget.ahora);
    _sugerencia = null;
  }

  void _elegirServicio(String? id) {
    setState(() {
      _servicioId = id;
      _reiniciarHora();
      if (widget.empleadoFijo == null &&
          _empleadoId != null &&
          !_barberos.any((b) => b.id == _empleadoId)) {
        _empleadoId = null;
      }
    });
  }

  /// Citas del barbero que ocupan horario (005: no cuentan canceladas ni
  /// no-shows).
  Iterable<(int, int)> _ocupadosDe(String empleadoId) sync* {
    for (final cita in widget.citasDelDia) {
      if (cita.empleadoId != empleadoId ||
          cita.estado == EstadoCita.cancelada ||
          cita.estado == EstadoCita.noVino) {
        continue;
      }
      final inicio = minutosDesdeHora(cita.horaInicio);
      final fin = minutosDesdeHora(cita.horaFin);
      if (inicio != null && fin != null && fin > inicio) yield (inicio, fin);
    }
  }

  Future<String?> _resolverCliente() async {
    if (_clienteId != null) return _clienteId;
    final Cliente cliente;
    try {
      cliente = _modo == _ModoCliente.dePaso
          ? await widget.repository.clienteDePaso(widget.negocioId)
          : await widget.repository.crearCliente(
              negocioId: widget.negocioId,
              nombre: _nuevoNombre.text.trim(),
              telefono: _nuevoTelefono.text.trim(),
            );
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo preparar el cliente.');
      return null;
    }
    // Si la cita falla después, no se vuelve a crear el cliente.
    if (mounted) {
      setState(() {
        _clienteId = cliente.id;
        _clienteNombre = cliente.nombre;
      });
    }
    return cliente.id;
  }

  Future<void> _guardar() async {
    setState(() {
      _error = null;
      _sugerencia = null;
    });
    if (!_formKey.currentState!.validate()) return;
    if (_modo == _ModoCliente.buscar && _clienteId == null) {
      setState(() => _error = 'Elige un cliente.');
      return;
    }
    final servicio = _servicio!;
    final empleadoId = _empleadoId!;
    final horaInicio = horaDesdeMinutos(_inicio);
    final horaFin = calcularHoraFin(horaInicio, servicio.duracionMinutos);
    if (horaFin == null) {
      setState(() => _error = 'La cita debe terminar antes de medianoche.');
      return;
    }

    setState(() => _guardando = true);
    try {
      final clienteId = await _resolverCliente();
      if (clienteId == null || !mounted) return;

      final hoy = widget.ahora;
      await widget.repository.crearCita(
        negocioId: widget.negocioId,
        estado: EstadoCita.llego,
        datos: DatosCita(
          clienteId: clienteId,
          empleadoId: empleadoId,
          servicioId: servicio.id,
          fecha: DateTime(hoy.year, hoy.month, hoy.day),
          horaInicio: horaInicio,
          horaFin: horaFin,
          precio: servicio.precio,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      int? sugerencia;
      if (error is PostgrestException && error.code == '23P01') {
        final libre = siguienteHoraLibre(
          ocupados: _ocupadosDe(empleadoId),
          desde: _inicio,
          duracionMinutos: servicio.duracionMinutos,
        );
        if (libre != null && libre != _inicio) sugerencia = libre;
      }
      setState(() {
        _error = mensajeErrorCita(error);
        _sugerencia = sugerencia;
      });
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _empezarAlTerminar() async {
    final sugerencia = _sugerencia;
    if (sugerencia == null) return;
    setState(() => _inicio = sugerencia);
    await _guardar();
  }

  @override
  Widget build(BuildContext context) {
    final sugerencia = _sugerencia;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Atender ahora',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Cliente sin cita: queda en la agenda de hoy como "Llegó".',
                style: TextStyle(color: Marca.textoSuave, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Flexible(child: _cuerpo()),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Marca.rojo)),
              ],
              if (sugerencia != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _guardando ? null : _empezarAlTerminar,
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text(
                    'Empezar a las '
                    '${formatoHora(horaDesdeMinutos(sugerencia))}, '
                    'al terminar su cita',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _guardando
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cerrar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _guardando || _catalogo == null
                        ? null
                        : _guardar,
                    child: Text(_guardando ? 'Guardando…' : 'Empezar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_errorCarga != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_errorCarga!),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
        ],
      );
    }

    final servicio = _servicio;
    final horaInicio = horaDesdeMinutos(_inicio);
    final horaFin = servicio == null
        ? null
        : calcularHoraFin(horaInicio, servicio.duracionMinutos);
    final barberoFijo = widget.empleadoFijo == null
        ? null
        : _catalogo!.barberos
              .where((b) => b.id == widget.empleadoFijo)
              .map((b) => b.nombre)
              .firstOrNull;

    return SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _seccionCliente(),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: ValueKey('ahora-servicio-$_servicioId'),
              initialValue: _servicioId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Servicio'),
              items: [
                for (final s in _servicios)
                  DropdownMenuItem(
                    value: s.id,
                    child: Text(
                      '${s.nombre} · ${s.duracionMinutos} min · '
                      '${formatoMoneda(s.precio, widget.moneda)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _guardando ? null : _elegirServicio,
              validator: (valor) => valor == null ? 'Elige un servicio.' : null,
            ),
            const SizedBox(height: 14),
            if (widget.empleadoFijo != null)
              InputDecorator(
                decoration: InputDecoration(
                  labelText: Vocabulario.of(context).profesional,
                ),
                child: Text(barberoFijo ?? 'Tú'),
              )
            else
              DropdownButtonFormField<String>(
                key: ValueKey('ahora-barbero-$_servicioId-$_empleadoId'),
                initialValue: _barberos.any((b) => b.id == _empleadoId)
                    ? _empleadoId
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: Vocabulario.of(context).profesional,
                ),
                items: [
                  for (final b in _barberos)
                    DropdownMenuItem(value: b.id, child: Text(b.nombre)),
                ],
                onChanged: _guardando
                    ? null
                    : (id) => setState(() {
                        _empleadoId = id;
                        _reiniciarHora();
                      }),
                validator: (valor) =>
                    valor == null ? 'Elige quién atiende.' : null,
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.schedule, size: 18, color: Marca.textoSuave),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    horaFin == null
                        ? 'Empieza a las ${formatoHora(horaInicio)}'
                        : 'De ${formatoHora(horaInicio)} a '
                              '${formatoHora(horaFin)}',
                    key: const ValueKey('ahora-horario'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _clienteElegido(String nombre) {
    return InputDecorator(
      decoration: const InputDecoration(labelText: 'Cliente'),
      child: Row(
        children: [
          Expanded(
            child: Text(
              nombre,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: _guardando
                ? null
                : () => setState(() {
                    _modo = _ModoCliente.buscar;
                    _clienteId = null;
                    _clienteNombre = '';
                  }),
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );
  }

  Widget _seccionCliente() {
    if (_clienteId != null) return _clienteElegido(_clienteNombre);
    if (_modo == _ModoCliente.dePaso) {
      return _clienteElegido(nombreClienteDePaso);
    }

    if (_modo == _ModoCliente.nuevo) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _nuevoNombre,
            enabled: !_guardando,
            decoration: const InputDecoration(labelText: 'Nombre del cliente'),
            validator: (valor) => (valor ?? '').trim().isEmpty
                ? 'Escribe el nombre del cliente.'
                : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _nuevoTelefono,
            enabled: !_guardando,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Teléfono (opcional)'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _guardando
                  ? null
                  : () => setState(() => _modo = _ModoCliente.buscar),
              child: const Text('Buscar un cliente existente'),
            ),
          ),
        ],
      );
    }

    final texto = _busqueda.text.trim().toLowerCase();
    final encontrados = texto.isEmpty
        ? const <Cliente>[]
        : _catalogo!.clientes
              .where(
                (c) =>
                    c.nombre.toLowerCase().contains(texto) ||
                    c.telefono.contains(texto),
              )
              .take(5)
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _busqueda,
          decoration: const InputDecoration(
            labelText: 'Buscar cliente',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        for (final cliente in encontrados)
          ListTile(
            dense: true,
            title: Text(cliente.nombre),
            subtitle: cliente.telefono.isEmpty ? null : Text(cliente.telefono),
            onTap: () => setState(() {
              _clienteId = cliente.id;
              _clienteNombre = cliente.nombre;
            }),
          ),
        if (texto.isNotEmpty && encontrados.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No hay clientes con ese nombre.',
              style: TextStyle(color: Marca.textoSuave),
            ),
          ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => setState(() {
                _modo = _ModoCliente.nuevo;
                _nuevoNombre.text = _busqueda.text.trim();
              }),
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Nuevo cliente'),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _modo = _ModoCliente.dePaso),
              icon: const Icon(Icons.directions_walk, size: 18),
              label: const Text('Cliente sin registrar'),
            ),
          ],
        ),
      ],
    );
  }
}
