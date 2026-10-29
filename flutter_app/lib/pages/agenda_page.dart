import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/cita.dart';
import '../services/agenda_repository.dart';
import '../services/citas_repository.dart';
import '../theme.dart';
import '../utils/citas_reglas.dart';
import '../utils/formato.dart';
import '../utils/whatsapp.dart';
import '../widgets/atender_ahora_dialog.dart';
import '../widgets/cita_form_dialog.dart';
import '../widgets/estado_cita_badge.dart';

/// Abre un enlace externo (WhatsApp). Devuelve false si no se pudo.
typedef AbrirEnlace = Future<bool> Function(Uri enlace);

Future<bool> _abrirEnlaceExterno(Uri enlace) =>
    launchUrl(enlace, mode: LaunchMode.externalApplication);

class AgendaPage extends StatefulWidget {
  const AgendaPage({
    super.key,
    required this.negocioId,
    required this.repository,
    this.agendaRepository,
    this.titulo = 'Agenda',
    this.moneda = 'DOP',
    this.negocioNombre = 'la barbería',
    this.empleadoId,
    this.esOwner = true,
    this.fechaInicial,
    this.reloj,
    this.abrirEnlace,
  });

  final String negocioId;
  final CitasRepository repository;

  /// Crear, editar y completar citas. Por defecto usa Supabase.
  final AgendaRepository? agendaRepository;
  final String titulo;
  final String moneda;

  /// Con empleado, es la vista "Mi agenda" y no repite el barbero.
  final String? empleadoId;

  /// El barbero no cambia el precio al editar una cita.
  final bool esOwner;
  final DateTime? fechaInicial;

  /// Nombre del negocio para el recordatorio por WhatsApp.
  final String negocioNombre;

  /// Hora actual; inyectable en pruebas.
  final DateTime Function()? reloj;

  /// Por defecto abre el enlace con url_launcher; inyectable en pruebas.
  final AbrirEnlace? abrirEnlace;

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

enum _AccionMenu { detalle, editar, recordar, cancelar }

class _AgendaPageState extends State<AgendaPage> {
  late DateTime _fecha;
  List<Cita> _citas = [];
  bool _cargando = true;
  String? _error;
  String? _actualizandoId;
  int _peticion = 0;

  // Filtro por barbero (solo agenda del dueño): id y nombre del elegido.
  String? _filtroId;
  String _filtroNombre = '';

  // Se crea solo cuando hace falta, para no exigir Supabase en pruebas.
  AgendaRepository get _agenda =>
      widget.agendaRepository ??
      SupabaseAgendaRepository(Supabase.instance.client);

  DateTime get _ahora => widget.reloj?.call() ?? DateTime.now();

  bool get _viendoHoy {
    final ahora = _ahora;
    return _fecha == DateTime(ahora.year, ahora.month, ahora.day);
  }

  @override
  void initState() {
    super.initState();
    final inicial = widget.fechaInicial ?? _ahora;
    _fecha = DateTime(inicial.year, inicial.month, inicial.day);
    _cargar();
  }

  Future<void> _cargar() async {
    // Al cambiar de día rápido, solo cuenta la respuesta de la última
    // petición: una respuesta vieja no debe sobrescribir la lista.
    final peticion = ++_peticion;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final citas = await widget.repository.listarDelDia(
        negocioId: widget.negocioId,
        fecha: _fecha,
        empleadoId: widget.empleadoId,
      );
      if (mounted && peticion == _peticion) setState(() => _citas = citas);
    } catch (_) {
      if (mounted && peticion == _peticion) {
        setState(() => _error = 'No se pudo cargar la agenda.');
      }
    } finally {
      if (mounted && peticion == _peticion) {
        setState(() => _cargando = false);
      }
    }
  }

  void _moverDia(int dias) {
    // Con DateTime(y, m, d + n) un cambio de horario (DST) no corre el día.
    setState(
      () => _fecha = DateTime(_fecha.year, _fecha.month, _fecha.day + dias),
    );
    _cargar();
  }

  void _irAHoy() {
    final ahora = _ahora;
    setState(() => _fecha = DateTime(ahora.year, ahora.month, ahora.day));
    _cargar();
  }

  void _avisar(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  /// Botones Llegó / No vino / Completada: tocar el estado activo lo deshace.
  Future<void> _marcar(Cita cita, EstadoCita estado) async {
    final nuevo = cita.estado == estado ? cita.estado.deshacer : estado;
    if (nuevo == null || !cita.estado.puedePasarA(nuevo)) return;

    if (nuevo == EstadoCita.completada) {
      final cobro = await _pedirCobro(cita);
      if (cobro == null) return;
      await _guardarEstado(cita, nuevo, cobro: cobro);
      return;
    }
    // Al deshacer Completada → Llegó el cobro queda guardado como dato.
    await _guardarEstado(cita, nuevo);
  }

  Future<void> _guardarEstado(
    Cita cita,
    EstadoCita nuevo, {
    _Cobro? cobro,
  }) async {
    final indice = _citas.indexWhere((item) => item.id == cita.id);
    if (indice < 0) return;

    setState(() {
      _actualizandoId = cita.id;
      _citas = [..._citas]
        ..[indice] = cita.copyWith(
          estado: nuevo,
          precio: cobro?.precio,
          metodoPago: cobro?.metodo,
          propina: cobro?.propina,
        );
    });

    try {
      if (nuevo == EstadoCita.completada && cobro != null) {
        await _agenda.completar(
          negocioId: widget.negocioId,
          citaId: cita.id,
          precio: cobro.precio,
          metodoPago: cobro.metodo,
          propina: cobro.propina,
        );
      } else {
        await widget.repository.cambiarEstado(
          negocioId: widget.negocioId,
          citaId: cita.id,
          estado: nuevo,
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _citas = [..._citas]..[indice] = cita);
      _avisar(
        mensajeErrorCita(error, porDefecto: 'No se pudo actualizar la cita.'),
      );
    } finally {
      if (mounted) setState(() => _actualizandoId = null);
    }
  }

  Future<_Cobro?> _pedirCobro(Cita cita) {
    return showDialog<_Cobro>(
      context: context,
      builder: (_) => _DialogoCompletar(cita: cita, moneda: widget.moneda),
    );
  }

  Future<void> _atenderAhora() async {
    final creada = await mostrarAtenderAhora(
      context,
      negocioId: widget.negocioId,
      repository: _agenda,
      ahora: _ahora,
      citasDelDia: _citas,
      moneda: widget.moneda,
      empleadoFijo: widget.empleadoId,
    );
    if (creada != true || !mounted) return;
    _avisar('Cliente en atención.');
    await _cargar();
  }

  Future<void> _recordar(Cita cita) async {
    if (cita.clienteTelefono.trim().isEmpty) return;
    final mensaje = mensajeRecordatorio(
      cliente: cita.clienteNombre,
      negocio: widget.negocioNombre,
      fecha: DateTime.tryParse(cita.fecha) ?? _fecha,
      hora: cita.horaInicio,
      servicio: cita.servicioNombre,
      barbero: cita.empleadoNombre,
    );
    final enlace = Uri.parse(enlaceWhatsApp(cita.clienteTelefono, mensaje));
    var abierto = false;
    try {
      abierto = await (widget.abrirEnlace ?? _abrirEnlaceExterno)(enlace);
    } catch (_) {
      abierto = false;
    }
    if (!abierto && mounted) _avisar('No se pudo abrir WhatsApp.');
  }

  Future<void> _cancelar(Cita cita) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cancelar la cita?'),
        content: Text(
          'La cita de ${cita.clienteNombre} a las '
          '${formatoHora(cita.horaInicio)} quedará cancelada y el horario '
          'se liberará. Una cita cancelada no se puede reactivar: para '
          'volver a agendarla hay que crear una cita nueva.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Volver'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Marca.rojo),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancelar cita'),
          ),
        ],
      ),
    );
    if (confirmar == true) await _guardarEstado(cita, EstadoCita.cancelada);
  }

  Future<void> _abrirFormulario([Cita? cita]) async {
    final datos = await mostrarFormularioCita(
      context,
      negocioId: widget.negocioId,
      repository: _agenda,
      fecha: _fecha,
      moneda: widget.moneda,
      empleadoFijo: widget.empleadoId,
      cita: cita,
      esOwner: widget.esOwner,
    );
    if (datos == null || !mounted) return;

    _avisar(cita == null ? 'Cita creada.' : 'Cita actualizada.');
    // Lleva la agenda al día de la cita guardada.
    setState(() => _fecha = datos.fecha);
    await _cargar();
  }

  Future<void> _verDetalle(Cita cita) async {
    final editar = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogoDetalle(
        cita: cita,
        moneda: widget.moneda,
        apartado: _agenda.apartadoDeCita(
          negocioId: widget.negocioId,
          citaId: cita.id,
        ),
      ),
    );
    if (editar == true && mounted) await _abrirFormulario(cita);
  }

  void _menu(Cita cita, _AccionMenu accion) {
    switch (accion) {
      case _AccionMenu.detalle:
        _verDetalle(cita);
      case _AccionMenu.editar:
        _abrirFormulario(cita);
      case _AccionMenu.recordar:
        _recordar(cita);
      case _AccionMenu.cancelar:
        _cancelar(cita);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth >= 860;
        return Padding(
          padding: EdgeInsets.all(ancho ? 28 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.titulo,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (_viendoHoy) ...[
                    OutlinedButton.icon(
                      onPressed: _cargando ? null : _atenderAhora,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 42),
                      ),
                      icon: const Icon(Icons.directions_walk, size: 18),
                      label: const Text('Atender ahora'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FilledButton.icon(
                    onPressed: () => _abrirFormulario(),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Nueva cita'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SelectorDia(
                fecha: _fecha,
                onAnterior: () => _moverDia(-1),
                onSiguiente: () => _moverDia(1),
                onHoy: _irAHoy,
              ),
              if (widget.empleadoId == null &&
                  (_citas.isNotEmpty || _filtroId != null))
                _FiltroBarberos(
                  barberos: _barberosDelDia(),
                  seleccionado: _filtroId,
                  onElegir: (id, nombre) => setState(() {
                    _filtroId = id;
                    _filtroNombre = nombre;
                  }),
                ),
              const SizedBox(height: 16),
              Expanded(child: _contenido()),
            ],
          ),
        );
      },
    );
  }

  /// Barberos con citas en el día cargado. Si el filtro activo no tiene
  /// citas ese día, se conserva con total 0.
  List<({String id, String nombre, int total})> _barberosDelDia() {
    final conteo = <String, ({String nombre, int total})>{};
    for (final cita in _citas) {
      final previo = conteo[cita.empleadoId];
      conteo[cita.empleadoId] = (
        nombre: previo?.nombre ?? cita.empleadoNombre,
        total: (previo?.total ?? 0) + 1,
      );
    }
    final id = _filtroId;
    if (id != null && !conteo.containsKey(id)) {
      conteo[id] = (nombre: _filtroNombre, total: 0);
    }
    return [
      for (final e in conteo.entries)
        (id: e.key, nombre: e.value.nombre, total: e.value.total),
    ]..sort((a, b) => a.nombre.compareTo(b.nombre));
  }

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
    final filtro = widget.empleadoId == null ? _filtroId : null;
    final visibles = filtro == null
        ? _citas
        : _citas.where((c) => c.empleadoId == filtro).toList();
    if (visibles.isEmpty) {
      return Center(
        child: Text(
          filtro == null
              ? 'No hay citas para este día.'
              : '$_filtroNombre no tiene citas este día.',
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        itemCount: visibles.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, index) {
          final cita = visibles[index];
          return _FilaCita(
            cita: cita,
            moneda: widget.moneda,
            mostrarBarbero: widget.empleadoId == null,
            ocupada: _actualizandoId == cita.id,
            onMarcar: (estado) => _marcar(cita, estado),
            onMenu: (accion) => _menu(cita, accion),
          );
        },
      ),
    );
  }
}

/// Chips horizontales: "Todos" y un chip por barbero con citas ese día.
class _FiltroBarberos extends StatelessWidget {
  const _FiltroBarberos({
    required this.barberos,
    required this.seleccionado,
    required this.onElegir,
  });

  final List<({String id, String nombre, int total})> barberos;
  final String? seleccionado;
  final void Function(String? id, String nombre) onElegir;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('Todos'),
              selected: seleccionado == null,
              showCheckmark: false,
              selectedColor: Marca.doradoClaro,
              onSelected: (_) => onElegir(null, ''),
            ),
            for (final b in barberos) ...[
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text('${b.nombre} · ${b.total}'),
                selected: seleccionado == b.id,
                showCheckmark: false,
                selectedColor: Marca.doradoClaro,
                onSelected: (_) => onElegir(b.id, b.nombre),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SelectorDia extends StatelessWidget {
  const _SelectorDia({
    required this.fecha,
    required this.onAnterior,
    required this.onSiguiente,
    required this.onHoy,
  });

  final DateTime fecha;
  final VoidCallback onAnterior;
  final VoidCallback onSiguiente;
  final VoidCallback onHoy;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Día anterior',
              onPressed: onAnterior,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                formatoFechaLarga(fecha),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'Día siguiente',
              onPressed: onSiguiente,
              icon: const Icon(Icons.chevron_right),
            ),
            const SizedBox(width: 4),
            OutlinedButton(
              onPressed: onHoy,
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
              child: const Text('Hoy'),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

class _FilaCita extends StatelessWidget {
  const _FilaCita({
    required this.cita,
    required this.moneda,
    required this.mostrarBarbero,
    required this.ocupada,
    required this.onMarcar,
    required this.onMenu,
  });

  final Cita cita;
  final String moneda;
  final bool mostrarBarbero;
  final bool ocupada;
  final ValueChanged<EstadoCita> onMarcar;
  final ValueChanged<_AccionMenu> onMenu;

  /// Botón de estado: activo si la cita ya lo tiene (tocar deshace).
  Widget _boton(String etiqueta, Color color, EstadoCita estado) {
    final activo = cita.estado == estado;
    final destino = activo ? cita.estado.deshacer : estado;
    final permitido = destino != null && cita.estado.puedePasarA(destino);
    return _BotonEstado(
      etiqueta: etiqueta,
      color: color,
      activo: activo,
      onPressed: ocupada || !permitido ? null : () => onMarcar(estado),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detalle = [
      cita.servicioNombre,
      formatoMoneda(cita.precio, moneda),
      if (mostrarBarbero && cita.empleadoNombre.isNotEmpty) cita.empleadoNombre,
    ].where((texto) => texto.isNotEmpty).join(' · ');
    final cancelada = cita.estado == EstadoCita.cancelada;

    final info = InkWell(
      onTap: () => onMenu(_AccionMenu.detalle),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatoHora(cita.horaInicio),
                  style: const TextStyle(fontSize: 13),
                ),
                if (cita.horaFin.isNotEmpty)
                  Text(
                    formatoHora(cita.horaFin),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Marca.textoSuave,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cita.clienteNombre,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  detalle,
                  style: const TextStyle(color: Marca.textoSuave, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final menu = PopupMenuButton<_AccionMenu>(
      tooltip: 'Más acciones',
      enabled: !ocupada,
      onSelected: onMenu,
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _AccionMenu.detalle,
          child: Text('Ver detalle'),
        ),
        if (!cancelada)
          const PopupMenuItem(value: _AccionMenu.editar, child: Text('Editar')),
        if (cita.estado == EstadoCita.pendiente ||
            cita.estado == EstadoCita.confirmada)
          PopupMenuItem(
            value: _AccionMenu.recordar,
            enabled: cita.clienteTelefono.trim().isNotEmpty,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.chat_outlined),
              title: const Text('Recordar por WhatsApp'),
              subtitle: cita.clienteTelefono.trim().isEmpty
                  ? const Text('El cliente no tiene teléfono registrado.')
                  : null,
            ),
          ),
        if (cita.estado.puedePasarA(EstadoCita.cancelada) && !cancelada)
          const PopupMenuItem(
            value: _AccionMenu.cancelar,
            child: Text('Cancelar cita'),
          ),
      ],
    );

    final acciones = cancelada
        ? <Widget>[EstadoCitaBadge(estado: cita.estado)]
        : <Widget>[
            _boton('Llegó', Marca.verde, EstadoCita.llego),
            _boton('No vino', Marca.rojo, EstadoCita.noVino),
            _boton('Completada', Marca.azul, EstadoCita.completada),
          ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // En teléfono los botones van debajo para no apretar el nombre.
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: info),
                    menu,
                  ],
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 72),
                  child: Wrap(spacing: 8, runSpacing: 8, children: acciones),
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 8),
              for (final accion in acciones) ...[
                accion,
                const SizedBox(width: 8),
              ],
              menu,
            ],
          );
        },
      ),
    );
  }
}

class _BotonEstado extends StatelessWidget {
  const _BotonEstado({
    required this.etiqueta,
    required this.color,
    required this.activo,
    required this.onPressed,
  });

  final String etiqueta;
  final Color color;
  final bool activo;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // Deshabilitado y sin marcar: el cambio no está permitido desde aquí.
    final apagado = onPressed == null && !activo;
    final tono = apagado ? Marca.textoSuave.withValues(alpha: 0.6) : color;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(74, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: activo ? Colors.white : tono,
        disabledForegroundColor: activo ? Colors.white : tono,
        backgroundColor: activo ? color : tono.withValues(alpha: 0.06),
        disabledBackgroundColor: activo ? color : tono.withValues(alpha: 0.04),
        side: BorderSide(color: tono.withValues(alpha: activo ? 1 : 0.5)),
        textStyle: Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
      ),
      child: Text(etiqueta),
    );
  }
}

/// Lo cobrado al completar una cita.
typedef _Cobro = ({num precio, MetodoPago metodo, num propina});

/// Pide el cobro al completar una cita: precio final, método y propina.
class _DialogoCompletar extends StatefulWidget {
  const _DialogoCompletar({required this.cita, required this.moneda});

  final Cita cita;
  final String moneda;

  @override
  State<_DialogoCompletar> createState() => _DialogoCompletarState();
}

class _DialogoCompletarState extends State<_DialogoCompletar> {
  static String _texto(num monto) =>
      monto == monto.roundToDouble() ? monto.round().toString() : '$monto';

  late final _precio = TextEditingController(text: _texto(widget.cita.precio));
  late final _propina = TextEditingController(
    text: widget.cita.propina > 0 ? _texto(widget.cita.propina) : '',
  );
  late MetodoPago _metodo = widget.cita.metodoPago ?? MetodoPago.efectivo;
  String? _error;
  String? _errorPropina;

  @override
  void dispose() {
    _precio.dispose();
    _propina.dispose();
    super.dispose();
  }

  static num? _leer(String texto) =>
      num.tryParse(texto.trim().replaceAll(',', ''));

  void _confirmar() {
    final precio = _leer(_precio.text);
    final textoPropina = _propina.text.trim();
    final propina = textoPropina.isEmpty ? 0 : _leer(textoPropina);
    setState(() {
      _error = precio == null || precio < 0
          ? 'Escribe un precio válido.'
          : null;
      _errorPropina = propina == null || propina < 0
          ? 'Escribe una propina válida (o déjala vacía).'
          : null;
    });
    if (_error != null || _errorPropina != null) return;
    Navigator.of(context)
        .pop<_Cobro>((precio: precio!, metodo: _metodo, propina: propina!));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Completar cita'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.cita.clienteNombre} · ${widget.cita.servicioNombre}'),
          const SizedBox(height: 14),
          TextField(
            controller: _precio,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Precio final cobrado',
              prefixText: simboloMoneda(widget.moneda),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Método de pago',
            style: TextStyle(color: Marca.textoSuave, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final metodo in MetodoPago.values)
                ChoiceChip(
                  label: Text(metodo.etiqueta),
                  selected: metodo == _metodo,
                  showCheckmark: false,
                  selectedColor: Marca.doradoClaro,
                  onSelected: (_) => setState(() => _metodo = metodo),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _propina,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Propina (opcional)',
              helperText: 'Va aparte: no suma a los ingresos.',
              prefixText: simboloMoneda(widget.moneda),
              errorText: _errorPropina,
            ),
            onSubmitted: (_) => _confirmar(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Volver'),
        ),
        FilledButton(onPressed: _confirmar, child: const Text('Completar')),
      ],
    );
  }
}

class _DialogoDetalle extends StatelessWidget {
  const _DialogoDetalle({
    required this.cita,
    required this.moneda,
    required this.apartado,
  });

  final Cita cita;
  final String moneda;
  final Future<ApartadoCita?> apartado;

  @override
  Widget build(BuildContext context) {
    final fecha = DateTime.tryParse(cita.fecha);
    final horario = cita.horaFin.isEmpty
        ? formatoHora(cita.horaInicio)
        : '${formatoHora(cita.horaInicio)} – ${formatoHora(cita.horaFin)}';

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(cita.clienteNombre)),
          EstadoCitaBadge(estado: cita.estado),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Dato('Servicio', cita.servicioNombre),
            _Dato('Barbero', cita.empleadoNombre),
            _Dato(
              'Fecha',
              fecha == null ? cita.fecha : formatoFechaLarga(fecha),
            ),
            _Dato('Horario', horario),
            _Dato('Precio', formatoMoneda(cita.precio, moneda)),
            if (cita.metodoPago != null || cita.propina > 0) ...[
              _Dato('Pago', cita.metodoPago?.etiqueta ?? 'Sin registrar'),
              _Dato('Propina', formatoMoneda(cita.propina, moneda)),
            ],
            _Dato('Notas', cita.notas.isEmpty ? 'Sin notas' : cita.notas),
            FutureBuilder<ApartadoCita?>(
              future: apartado,
              builder: (context, snapshot) {
                final String texto;
                if (snapshot.connectionState != ConnectionState.done) {
                  texto = 'Cargando…';
                } else if (snapshot.hasError) {
                  texto = 'No se pudo consultar.';
                } else if (snapshot.data == null) {
                  texto = 'Sin apartado';
                } else {
                  final a = snapshot.data!;
                  texto = [
                    formatoMoneda(a.monto, moneda),
                    a.estadoEtiqueta,
                    if (a.metodoPago.isNotEmpty) a.metodoPago,
                    if (a.referencia.isNotEmpty) 'Ref. ${a.referencia}',
                  ].join(' · ');
                }
                return _Dato('Apartado', texto);
              },
            ),
          ],
        ),
      ),
      actions: [
        if (cita.estado != EstadoCita.cancelada)
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Editar'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.etiqueta, this.valor);

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              etiqueta,
              style: const TextStyle(color: Marca.textoSuave, fontSize: 13),
            ),
          ),
          Expanded(child: Text(valor)),
        ],
      ),
    );
  }
}
