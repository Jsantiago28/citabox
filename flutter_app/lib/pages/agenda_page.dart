import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cita.dart';
import '../services/agenda_repository.dart';
import '../services/citas_repository.dart';
import '../theme.dart';
import '../utils/citas_reglas.dart';
import '../utils/formato.dart';
import '../widgets/cita_form_dialog.dart';
import '../widgets/estado_cita_badge.dart';

class AgendaPage extends StatefulWidget {
  const AgendaPage({
    super.key,
    required this.negocioId,
    required this.repository,
    this.agendaRepository,
    this.titulo = 'Agenda',
    this.moneda = 'DOP',
    this.empleadoId,
    this.fechaInicial,
  });

  final String negocioId;
  final CitasRepository repository;

  /// Crear, editar y completar citas. Por defecto usa Supabase.
  final AgendaRepository? agendaRepository;
  final String titulo;
  final String moneda;

  /// Con empleado, es la vista "Mi agenda" y no repite el barbero.
  final String? empleadoId;
  final DateTime? fechaInicial;

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

enum _AccionMenu { detalle, editar, cancelar }

class _AgendaPageState extends State<AgendaPage> {
  late DateTime _fecha;
  List<Cita> _citas = [];
  bool _cargando = true;
  String? _error;
  String? _actualizandoId;

  // Se crea solo cuando hace falta, para no exigir Supabase en pruebas.
  AgendaRepository get _agenda =>
      widget.agendaRepository ??
      SupabaseAgendaRepository(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    final inicial = widget.fechaInicial ?? DateTime.now();
    _fecha = DateTime(inicial.year, inicial.month, inicial.day);
    _cargar();
  }

  Future<void> _cargar() async {
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
      if (mounted) setState(() => _citas = citas);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar la agenda.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _moverDia(int dias) {
    setState(() => _fecha = _fecha.add(Duration(days: dias)));
    _cargar();
  }

  void _irAHoy() {
    final ahora = DateTime.now();
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
      final precio = await _pedirPrecioFinal(cita);
      if (precio == null) return;
      await _guardarEstado(cita, nuevo, precio: precio);
      return;
    }
    await _guardarEstado(cita, nuevo);
  }

  Future<void> _guardarEstado(
    Cita cita,
    EstadoCita nuevo, {
    num? precio,
  }) async {
    final indice = _citas.indexWhere((item) => item.id == cita.id);
    if (indice < 0) return;

    setState(() {
      _actualizandoId = cita.id;
      _citas = [..._citas]
        ..[indice] = cita.copyWith(estado: nuevo, precio: precio);
    });

    try {
      if (nuevo == EstadoCita.completada && precio != null) {
        await _agenda.completar(
          negocioId: widget.negocioId,
          citaId: cita.id,
          precio: precio,
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

  Future<num?> _pedirPrecioFinal(Cita cita) {
    return showDialog<num>(
      context: context,
      builder: (_) => _DialogoCompletar(cita: cita, moneda: widget.moneda),
    );
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
              const SizedBox(height: 16),
              Expanded(child: _contenido()),
            ],
          ),
        );
      },
    );
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
    if (_citas.isEmpty) {
      return const Center(child: Text('No hay citas para este día.'));
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        itemCount: _citas.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, index) {
          final cita = _citas[index];
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

/// Pide el precio final cobrado al completar una cita.
class _DialogoCompletar extends StatefulWidget {
  const _DialogoCompletar({required this.cita, required this.moneda});

  final Cita cita;
  final String moneda;

  @override
  State<_DialogoCompletar> createState() => _DialogoCompletarState();
}

class _DialogoCompletarState extends State<_DialogoCompletar> {
  late final _precio = TextEditingController(
    text: widget.cita.precio == widget.cita.precio.roundToDouble()
        ? widget.cita.precio.round().toString()
        : '${widget.cita.precio}',
  );
  String? _error;

  @override
  void dispose() {
    _precio.dispose();
    super.dispose();
  }

  void _confirmar() {
    final precio = num.tryParse(_precio.text.trim().replaceAll(',', ''));
    if (precio == null || precio < 0) {
      setState(() => _error = 'Escribe un precio válido.');
      return;
    }
    Navigator.of(context).pop(precio);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Completar cita'),
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
