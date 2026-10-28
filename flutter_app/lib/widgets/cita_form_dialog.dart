import 'package:flutter/material.dart';

import '../models/cita.dart';
import '../models/cliente.dart';
import '../services/agenda_repository.dart';
import '../theme.dart';
import '../utils/citas_reglas.dart';
import '../utils/formato.dart';

/// Abre el formulario para crear (sin [cita]) o editar una cita.
///
/// Guarda por su cuenta y devuelve los datos guardados, o null si se cerró.
Future<DatosCita?> mostrarFormularioCita(
  BuildContext context, {
  required String negocioId,
  required AgendaRepository repository,
  required DateTime fecha,
  String moneda = 'DOP',
  String? empleadoFijo,
  Cita? cita,
  bool esOwner = true,
}) {
  return showDialog<DatosCita>(
    context: context,
    barrierDismissible: false,
    builder: (_) => CitaFormDialog(
      negocioId: negocioId,
      repository: repository,
      fecha: fecha,
      moneda: moneda,
      empleadoFijo: empleadoFijo,
      cita: cita,
      esOwner: esOwner,
    ),
  );
}

class CitaFormDialog extends StatefulWidget {
  const CitaFormDialog({
    super.key,
    required this.negocioId,
    required this.repository,
    required this.fecha,
    this.moneda = 'DOP',
    this.empleadoFijo,
    this.cita,
    this.esOwner = true,
  });

  final String negocioId;
  final AgendaRepository repository;
  final DateTime fecha;
  final String moneda;

  /// En "Mi agenda" el barbero es siempre el usuario.
  final String? empleadoFijo;

  /// Con cita, el formulario edita en vez de crear.
  final Cita? cita;

  /// El barbero no cambia el precio de una cita ya creada (010: solo el
  /// dueño, salvo al completarla).
  final bool esOwner;

  @override
  State<CitaFormDialog> createState() => _CitaFormDialogState();
}

class _CitaFormDialogState extends State<CitaFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _busqueda = TextEditingController();
  final _nuevoNombre = TextEditingController();
  final _nuevoTelefono = TextEditingController();
  final _hora = TextEditingController();
  final _precio = TextEditingController();
  final _notas = TextEditingController();

  CatalogoAgenda? _catalogo;
  bool _cargando = true;
  String? _errorCarga;

  String? _clienteId;
  String _clienteNombre = '';
  bool _nuevoCliente = false;
  String? _servicioId;
  String? _empleadoId;
  late DateTime _fecha;
  bool _guardando = false;
  String? _error;

  bool get _editando => widget.cita != null;

  bool get _precioBloqueado => _editando && !widget.esOwner;

  @override
  void initState() {
    super.initState();
    final cita = widget.cita;
    _fecha = DateTime(widget.fecha.year, widget.fecha.month, widget.fecha.day);
    _empleadoId = widget.empleadoFijo;
    if (cita != null) {
      _clienteId = cita.clienteId;
      _clienteNombre = cita.clienteNombre;
      _servicioId = cita.servicioId;
      _empleadoId = widget.empleadoFijo ?? cita.empleadoId;
      _fecha = DateTime.tryParse(cita.fecha) ?? _fecha;
      final inicio = minutosDesdeHora(cita.horaInicio);
      if (inicio != null) _hora.text = horaDesdeMinutos(inicio).substring(0, 5);
      _precio.text = _textoPrecio(cita.precio);
      _notas.text = cita.notas;
    }
    _hora.addListener(_refrescar);
    _busqueda.addListener(_refrescar);
    _cargar();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    _nuevoNombre.dispose();
    _nuevoTelefono.dispose();
    _hora.dispose();
    _precio.dispose();
    _notas.dispose();
    super.dispose();
  }

  void _refrescar() {
    if (mounted) setState(() {});
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

  static String _textoPrecio(num precio) =>
      precio == precio.roundToDouble() ? precio.round().toString() : '$precio';

  /// Servicios activos; al editar se conserva el actual aunque esté inactivo.
  List<ServicioAgenda> get _servicios {
    final catalogo = _catalogo!;
    final fijo = widget.empleadoFijo;
    final lista = [
      for (final servicio in catalogo.servicios)
        if (fijo == null || catalogo.barberoHace(fijo, servicio.id)) servicio,
    ];
    final cita = widget.cita;
    if (cita != null &&
        cita.servicioId.isNotEmpty &&
        !lista.any((s) => s.id == cita.servicioId)) {
      final inicio = minutosDesdeHora(cita.horaInicio);
      final fin = minutosDesdeHora(cita.horaFin);
      lista.add(
        ServicioAgenda(
          id: cita.servicioId,
          nombre: cita.servicioNombre,
          precio: cita.precio,
          duracionMinutos: inicio != null && fin != null && fin > inicio
              ? fin - inicio
              : 30,
        ),
      );
    }
    return lista;
  }

  /// Barberos activos que hacen el servicio elegido.
  List<BarberoAgenda> get _barberos {
    final catalogo = _catalogo!;
    final servicioId = _servicioId;
    final lista = [
      for (final barbero in catalogo.barberos)
        if (servicioId == null || catalogo.barberoHace(barbero.id, servicioId))
          barbero,
    ];
    final cita = widget.cita;
    if (cita != null &&
        cita.empleadoId.isNotEmpty &&
        servicioId == cita.servicioId &&
        !lista.any((b) => b.id == cita.empleadoId)) {
      lista.add(
        BarberoAgenda(id: cita.empleadoId, nombre: cita.empleadoNombre),
      );
    }
    return lista;
  }

  ServicioAgenda? get _servicio {
    for (final servicio in _servicios) {
      if (servicio.id == _servicioId) return servicio;
    }
    return null;
  }

  String? get _horaFin {
    final servicio = _servicio;
    if (servicio == null) return null;
    return calcularHoraFin(_hora.text, servicio.duracionMinutos);
  }

  void _elegirServicio(String? id) {
    setState(() {
      _servicioId = id;
      final servicio = _servicio;
      if (servicio != null && !_precioBloqueado) {
        _precio.text = _textoPrecio(servicio.precio);
      }
      if (widget.empleadoFijo == null &&
          _empleadoId != null &&
          !_barberos.any((b) => b.id == _empleadoId)) {
        _empleadoId = null;
      }
    });
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (elegida != null) setState(() => _fecha = elegida);
  }

  Future<void> _elegirHora() async {
    final minutos = minutosDesdeHora(_hora.text) ?? 9 * 60;
    final elegida = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutos ~/ 60, minute: minutos % 60),
    );
    if (elegida != null) {
      _hora.text = horaDesdeMinutos(elegida.hour * 60 + elegida.minute)
          .substring(0, 5);
    }
  }

  Future<void> _guardar() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    if (!_nuevoCliente && _clienteId == null) {
      setState(() => _error = 'Elige un cliente.');
      return;
    }
    final horaFin = _horaFin;
    if (horaFin == null) {
      setState(() => _error = 'La cita debe terminar antes de medianoche.');
      return;
    }

    setState(() => _guardando = true);
    try {
      if (_nuevoCliente) {
        final Cliente cliente;
        try {
          cliente = await widget.repository.crearCliente(
            negocioId: widget.negocioId,
            nombre: _nuevoNombre.text.trim(),
            telefono: _nuevoTelefono.text.trim(),
          );
        } catch (_) {
          if (mounted) setState(() => _error = 'No se pudo crear el cliente.');
          return;
        }
        // Si la cita falla después, no se vuelve a crear el cliente.
        if (!mounted) return;
        setState(() {
          _clienteId = cliente.id;
          _clienteNombre = cliente.nombre;
          _nuevoCliente = false;
        });
      }

      final datos = DatosCita(
        clienteId: _clienteId!,
        empleadoId: _empleadoId!,
        servicioId: _servicioId!,
        fecha: _fecha,
        horaInicio: horaDesdeMinutos(minutosDesdeHora(_hora.text)!),
        horaFin: horaFin,
        precio: _precioBloqueado
            ? widget.cita!.precio
            : num.parse(_precio.text.trim().replaceAll(',', '')),
        notas: _notas.text,
      );

      if (_editando) {
        await widget.repository.editarCita(
          negocioId: widget.negocioId,
          citaId: widget.cita!.id,
          datos: datos,
        );
      } else {
        await widget.repository.crearCita(
          negocioId: widget.negocioId,
          datos: datos,
        );
      }
      if (mounted) Navigator.of(context).pop(datos);
    } catch (error) {
      if (mounted) setState(() => _error = mensajeErrorCita(error));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _editando ? 'Editar cita' : 'Nueva cita',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              Flexible(child: _cuerpo()),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Marca.rojo)),
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
                    child: Text(_guardando ? 'Guardando…' : 'Guardar cita'),
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

    final servicios = _servicios;
    final barberos = _barberos;
    final horaFin = _horaFin;
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
              key: ValueKey('servicio-$_servicioId'),
              initialValue: _servicioId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Servicio'),
              items: [
                for (final servicio in servicios)
                  DropdownMenuItem(
                    value: servicio.id,
                    child: Text(
                      '${servicio.nombre} · ${servicio.duracionMinutos} min',
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
                decoration: const InputDecoration(labelText: 'Barbero'),
                child: Text(barberoFijo ?? 'Tú'),
              )
            else
              DropdownButtonFormField<String>(
                key: ValueKey('barbero-$_servicioId-$_empleadoId'),
                initialValue: barberos.any((b) => b.id == _empleadoId)
                    ? _empleadoId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Barbero'),
                items: [
                  for (final barbero in barberos)
                    DropdownMenuItem(
                      value: barbero.id,
                      child: Text(barbero.nombre),
                    ),
                ],
                onChanged: _guardando
                    ? null
                    : (id) => setState(() => _empleadoId = id),
                validator: (valor) =>
                    valor == null ? 'Elige un barbero.' : null,
              ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _guardando ? null : _elegirFecha,
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text('${formatoFechaLarga(_fecha)} ${_fecha.year}'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _hora,
              enabled: !_guardando,
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                labelText: 'Hora de inicio',
                hintText: 'Ej. 14:30',
                helperText: horaFin == null
                    ? null
                    : 'Termina a las ${formatoHora(horaFin)}',
                suffixIcon: IconButton(
                  tooltip: 'Elegir hora',
                  onPressed: _guardando ? null : _elegirHora,
                  icon: const Icon(Icons.schedule),
                ),
              ),
              validator: (valor) => minutosDesdeHora(valor ?? '') == null
                  ? 'Escribe la hora como 14:30.'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const ValueKey('precio-cita'),
              controller: _precio,
              enabled: !_guardando,
              readOnly: _precioBloqueado,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Precio',
                prefixText: simboloMoneda(widget.moneda),
                helperText: _precioBloqueado
                    ? 'Solo el dueño cambia el precio.'
                    : null,
              ),
              validator: (valor) {
                final precio = num.tryParse(
                  (valor ?? '').trim().replaceAll(',', ''),
                );
                return precio == null || precio < 0
                    ? 'Escribe un precio válido.'
                    : null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notas,
              enabled: !_guardando,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notas (opcional)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seccionCliente() {
    if (_editando) {
      return InputDecorator(
        decoration: const InputDecoration(labelText: 'Cliente'),
        child: Text(_clienteNombre),
      );
    }

    if (_clienteId != null) {
      return InputDecorator(
        decoration: const InputDecoration(labelText: 'Cliente'),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _clienteNombre,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: _guardando
                  ? null
                  : () => setState(() {
                      _clienteId = null;
                      _clienteNombre = '';
                    }),
              child: const Text('Cambiar'),
            ),
          ],
        ),
      );
    }

    if (_nuevoCliente) {
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
            decoration: const InputDecoration(labelText: 'Teléfono'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _guardando
                  ? null
                  : () => setState(() => _nuevoCliente = false),
              child: const Text('Buscar un cliente existente'),
            ),
          ),
        ],
      );
    }

    final texto = _busqueda.text.trim().toLowerCase();
    final encontrados = _catalogo!.clientes
        .where(
          (cliente) =>
              texto.isEmpty ||
              cliente.nombre.toLowerCase().contains(texto) ||
              cliente.telefono.contains(texto),
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
        if (encontrados.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No hay clientes con ese nombre.',
              style: TextStyle(color: Marca.textoSuave),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() {
              _nuevoCliente = true;
              _nuevoNombre.text = _busqueda.text.trim();
            }),
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: const Text('Nuevo cliente'),
          ),
        ),
      ],
    );
  }
}
