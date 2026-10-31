import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/cliente.dart';
import '../services/clientes_repository.dart';
import '../services/sin_permiso.dart';
import '../theme.dart';
import '../utils/formato.dart';
import '../utils/whatsapp.dart';
import '../widgets/estado_cita_badge.dart';
import '../utils/fidelidad.dart';
import 'cliente_ficha.dart';

class ClientesPage extends StatefulWidget {
  const ClientesPage({
    super.key,
    required this.negocioId,
    required this.repository,
    this.moneda = 'DOP',
    this.abrirEnlace,
    this.negocioNombre = '',
    this.enlaceReservas = '',
    this.hoy,
    this.fidelidad,
  });

  final String negocioId;
  final ClientesRepository repository;
  final String moneda;

  /// Abre enlaces de llamada, WhatsApp o correo; por defecto, url_launcher.
  final AbrirEnlace? abrirEnlace;

  /// Para el mensaje a los clientes que no vuelven.
  final String negocioNombre;
  final String enlaceReservas;

  /// Inyectable en pruebas; por defecto la fecha del dispositivo.
  final DateTime? hoy;

  /// Programa "la décima gratis"; null si el negocio no lo tiene.
  final Fidelidad? fidelidad;

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  final _searchController = TextEditingController();
  List<Cliente> _clientes = [];
  Map<String, ResumenCliente> _resumen = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _changingStatusId;
  String? _seleccionadoId;

  /// Clientes que llevan tiempo sin venir (ver [ResumenCliente.noVuelve]).
  bool _soloNoVuelven = false;

  /// Clientes que cumplen años este mes.
  bool _soloCumple = false;

  int get _cantidadCumple =>
      _clientes.where((c) => c.activo && c.cumpleEnMes(_hoy)).length;

  DateTime get _hoy => widget.hoy ?? DateTime.now();

  ResumenCliente _resumenDe(Cliente cliente) =>
      _resumen[cliente.id] ?? const ResumenCliente();

  int get _cantidadNoVuelven =>
      _clientes.where((c) => c.activo && _resumenDe(c).noVuelve(_hoy)).length;

  static Future<bool> _abrirExterno(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  void initState() {
    super.initState();
    _cargarClientes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cargarClientes() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final clientes = await widget.repository.listar(widget.negocioId);
      if (mounted) setState(() => _clientes = clientes);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudieron cargar los clientes.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    // El resumen es complementario: si falla, la lista sigue usable.
    try {
      final resumen = await widget.repository.resumen(widget.negocioId);
      if (mounted) setState(() => _resumen = resumen);
    } catch (_) {}
  }

  Future<void> _abrirFormulario([Cliente? cliente]) async {
    final datos = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => _ClienteFormDialog(cliente: cliente),
    );
    if (datos == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.repository.guardar(
        negocioId: widget.negocioId,
        clienteId: cliente?.id,
        datos: datos,
      );
      await _cargarClientes();
    } catch (error) {
      if (mounted) {
        _mostrarError(mensajeDeError(error, 'No se pudo guardar el cliente.'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cambiarEstado(Cliente cliente) async {
    setState(() => _changingStatusId = cliente.id);
    try {
      await widget.repository.cambiarEstado(
        negocioId: widget.negocioId,
        clienteId: cliente.id,
        activo: !cliente.activo,
      );
      await _cargarClientes();
    } catch (error) {
      if (mounted) {
        _mostrarError(
          mensajeDeError(error, 'No se pudo actualizar el estado del cliente.'),
        );
      }
    } finally {
      if (mounted) setState(() => _changingStatusId = null);
    }
  }

  Future<void> _felicitar(Cliente cliente) async {
    final mensaje = mensajeCumpleanos(
      cliente: cliente.nombre,
      negocio: widget.negocioNombre,
    );
    var abierto = false;
    try {
      abierto = await (widget.abrirEnlace ?? _abrirExterno)(
        Uri.parse(enlaceWhatsApp(cliente.telefono, mensaje)),
      );
    } catch (_) {}
    if (!abierto && mounted) _mostrarError('No se pudo abrir WhatsApp.');
  }

  Future<void> _invitar(Cliente cliente) async {
    final mensaje = mensajeVuelve(
      cliente: cliente.nombre,
      negocio: widget.negocioNombre,
      enlace: widget.enlaceReservas,
    );
    var abierto = false;
    try {
      abierto = await (widget.abrirEnlace ?? _abrirExterno)(
        Uri.parse(enlaceWhatsApp(cliente.telefono, mensaje)),
      );
    } catch (_) {}
    if (!abierto && mounted) _mostrarError('No se pudo abrir WhatsApp.');
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  List<Cliente> get _clientesFiltrados {
    final consulta = _searchController.text.trim().toLowerCase();
    var base = _clientes;
    if (_soloCumple) {
      base = _clientes.where((c) => c.activo && c.cumpleEnMes(_hoy)).toList()
        ..sort((a, b) => a.cumpleDia!.compareTo(b.cumpleDia!));
    }
    if (_soloNoVuelven) {
      // Los que llevan más tiempo sin venir, primero.
      base =
          _clientes
              .where((c) => c.activo && _resumenDe(c).noVuelve(_hoy))
              .toList()
            ..sort(
              (a, b) => (_resumenDe(b).diasSinVenir(_hoy) ?? 0).compareTo(
                _resumenDe(a).diasSinVenir(_hoy) ?? 0,
              ),
            );
    }
    if (consulta.isEmpty) return base;

    return base
        .where((cliente) {
          return cliente.nombre.toLowerCase().contains(consulta) ||
              cliente.telefono.toLowerCase().contains(consulta) ||
              cliente.email.toLowerCase().contains(consulta);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final seleccionado = _clientes
        .where((cliente) => cliente.id == _seleccionadoId)
        .firstOrNull;
    if (seleccionado != null) {
      return ClienteFicha(
        key: ValueKey('cliente-${seleccionado.id}'),
        negocioId: widget.negocioId,
        cliente: seleccionado,
        repository: widget.repository,
        moneda: widget.moneda,
        abrirEnlace: widget.abrirEnlace ?? _abrirExterno,
        onVolver: () => setState(() => _seleccionadoId = null),
        onEditar: () => _abrirFormulario(seleccionado),
        onCambio: _cargarClientes,
        fidelidad: widget.fidelidad,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final clientes = _clientesFiltrados;
        final isWide = constraints.maxWidth >= 860;

        final buscador = SizedBox(
          width: isWide ? 280 : double.infinity,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar cliente…',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpiar búsqueda',
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close, size: 18),
                    ),
            ),
          ),
        );

        final nuevo = FilledButton.icon(
          onPressed: _saving ? null : () => _abrirFormulario(),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Nuevo cliente'),
        );

        return Padding(
          padding: EdgeInsets.all(isWide ? 28 : 16),
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
                          'Clientes',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_clientes.length} registrados',
                          style: const TextStyle(color: Marca.textoSuave),
                        ),
                      ],
                    ),
                  ),
                  if (isWide) ...[buscador, const SizedBox(width: 12)],
                  nuevo,
                ],
              ),
              if (!isWide) ...[const SizedBox(height: 16), buscador],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    key: const Key('filtro-cumple'),
                    avatar: const Icon(Icons.cake_outlined, size: 18),
                    label: Text('Cumpleaños del mes ($_cantidadCumple)'),
                    selected: _soloCumple,
                    showCheckmark: false,
                    selectedColor: Marca.doradoClaro,
                    onSelected: (valor) => setState(() {
                      _soloCumple = valor;
                      if (valor) _soloNoVuelven = false;
                    }),
                  ),
                  Tooltip(
                    message:
                        'Más de ${ResumenCliente.diasNoVuelve} días sin venir y '
                        'sin otra cita reservada.',
                    child: FilterChip(
                      key: const Key('filtro-no-vuelven'),
                      avatar: const Icon(Icons.history, size: 18),
                      label: Text('No vuelven ($_cantidadNoVuelven)'),
                      selected: _soloNoVuelven,
                      showCheckmark: false,
                      selectedColor: Marca.doradoClaro,
                      onSelected: (valor) => setState(() {
                        _soloNoVuelven = valor;
                        if (valor) _soloCumple = false;
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildContent(clientes, isWide)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(List<Cliente> clientes, bool isWide) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _cargarClientes,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (clientes.isEmpty) {
      return Center(
        child: Text(
          _clientes.isEmpty
              ? 'Todavía no hay clientes.'
              : _soloCumple
              ? 'Nadie cumple años este mes, o aún no anotas sus cumpleaños '
                    '(Editar cliente).'
              : _soloNoVuelven
              ? 'Ningún cliente lleva más de ${ResumenCliente.diasNoVuelve} días '
                    'sin venir. ¡Bien!'
              : 'No hay coincidencias.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        itemCount: clientes.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, index) => _fila(clientes[index], isWide),
      ),
    );
  }

  Widget _fila(Cliente cliente, bool isWide) {
    final resumen = _resumen[cliente.id] ?? const ResumenCliente();
    final visitas =
        '${resumen.visitas} ${resumen.visitas == 1 ? 'visita' : 'visitas'}';
    final gastado = formatoMoneda(resumen.gastado, widget.moneda);
    final contacto = cliente.telefono.isNotEmpty
        ? cliente.telefono
        : (cliente.email.isNotEmpty ? cliente.email : 'Sin contacto');

    final nombre = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                cliente.nombre,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: cliente.activo ? Marca.texto : Marca.textoSuave,
                ),
              ),
            ),
            if (!cliente.activo) ...[
              const SizedBox(width: 8),
              const _Etiqueta(texto: 'Inactivo', color: Marca.textoSuave),
            ],
            if (resumen.conFaltas) ...[
              const SizedBox(width: 8),
              const _Etiqueta(texto: 'Faltas', color: Marca.rojo),
            ],
            if (cliente.activo &&
                (widget.fidelidad?.proximaEsPremio(resumen.visitas) ??
                    false)) ...[
              const SizedBox(width: 8),
              const _Etiqueta(texto: 'Próxima gratis', color: Marca.verde),
            ],
            if (cliente.activo && cliente.cumpleEnMes(_hoy)) ...[
              const SizedBox(width: 8),
              _Etiqueta(
                texto: cliente.cumpleHoy(_hoy)
                    ? 'Cumple hoy'
                    : 'Cumple el ${cliente.cumpleDia}',
                color: cliente.cumpleHoy(_hoy) ? Marca.dorado : Marca.azul,
              ),
            ],
            if (cliente.activo && resumen.noVuelve(_hoy)) ...[
              const SizedBox(width: 8),
              _Etiqueta(
                texto: 'Hace ${resumen.diasSinVenir(_hoy)} días',
                color: Marca.naranja,
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          isWide ? contacto : '$contacto · $visitas',
          style: const TextStyle(color: Marca.textoSuave, fontSize: 12),
        ),
      ],
    );

    return InkWell(
      onTap: () => setState(() => _seleccionadoId = cliente.id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          children: [
            AvatarIniciales(texto: iniciales(cliente.nombre)),
            const SizedBox(width: 12),
            Expanded(flex: 3, child: nombre),
            if (isWide) ...[
              Expanded(
                child: Text(
                  visitas,
                  style: const TextStyle(color: Marca.textoSuave),
                ),
              ),
              SizedBox(
                width: 110,
                child: Text(
                  gastado,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(
                width: 110,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: resumen.frecuente
                      ? const _Etiqueta(texto: 'Frecuente', color: Marca.verde)
                      : null,
                ),
              ),
            ] else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    gastado,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (resumen.frecuente) ...[
                    const SizedBox(height: 4),
                    const _Etiqueta(texto: 'Frecuente', color: Marca.verde),
                  ],
                ],
              ),
            if (_soloCumple && cliente.telefono.trim().isNotEmpty)
              IconButton(
                key: Key('felicitar-${cliente.id}'),
                tooltip: 'Felicitar por WhatsApp',
                onPressed: () => _felicitar(cliente),
                icon: const Icon(Icons.cake_outlined, color: Marca.verde),
              ),
            if (_soloNoVuelven && cliente.telefono.trim().isNotEmpty)
              IconButton(
                key: Key('invitar-${cliente.id}'),
                tooltip: 'Invitar a volver por WhatsApp',
                onPressed: () => _invitar(cliente),
                icon: const Icon(Icons.chat_outlined, color: Marca.verde),
              ),
            _acciones(cliente),
          ],
        ),
      ),
    );
  }

  Widget _acciones(Cliente cliente) {
    final busy = _changingStatusId == cliente.id;
    return PopupMenuButton<String>(
      tooltip: 'Acciones de ${cliente.nombre}',
      enabled: !busy,
      onSelected: (accion) {
        if (accion == 'ver') setState(() => _seleccionadoId = cliente.id);
        if (accion == 'editar') _abrirFormulario(cliente);
        if (accion == 'estado') _cambiarEstado(cliente);
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'ver', child: Text('Ver ficha')),
        const PopupMenuItem(value: 'editar', child: Text('Editar')),
        PopupMenuItem(
          value: 'estado',
          child: Text(cliente.activo ? 'Desactivar' : 'Activar'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.more_vert, color: Marca.textoSuave),
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ClienteFormDialog extends StatefulWidget {
  const _ClienteFormDialog({this.cliente});

  final Cliente? cliente;

  @override
  State<_ClienteFormDialog> createState() => _ClienteFormDialogState();
}

class _ClienteFormDialogState extends State<_ClienteFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreController;
  late final TextEditingController _telefonoController;
  late final TextEditingController _emailController;
  late final TextEditingController _notasController;
  late int? _cumpleDia = widget.cliente?.cumpleDia;
  late int? _cumpleMes = widget.cliente?.cumpleMes;

  /// Días que tiene [_cumpleMes] (febrero con 29: sin año, puede ser bisiesto).
  int get _diasDelMes => switch (_cumpleMes) {
    2 => 29,
    4 || 6 || 9 || 11 => 30,
    _ => 31,
  };

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(
      text: widget.cliente?.nombre ?? '',
    );
    _telefonoController = TextEditingController(
      text: widget.cliente?.telefono ?? '',
    );
    _emailController = TextEditingController(text: widget.cliente?.email ?? '');
    _notasController = TextEditingController(text: widget.cliente?.notas ?? '');
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _notasController.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(<String, Object?>{
      'nombre': _nombreController.text.trim(),
      'telefono': _telefonoController.text.trim().isEmpty
          ? null
          : _telefonoController.text.trim(),
      'email': _emailController.text.trim().isEmpty
          ? null
          : _emailController.text.trim(),
      'notas': _notasController.text.trim().isEmpty
          ? null
          : _notasController.text.trim(),
      'cumple_mes': _cumpleMes,
      'cumple_dia': _cumpleMes == null ? null : _cumpleDia,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.cliente == null ? 'Nuevo cliente' : 'Editar cliente'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('cliente-nombre'),
                  controller: _nombreController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'El nombre es obligatorio.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('cliente-telefono'),
                  controller: _telefonoController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('cliente-email'),
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isNotEmpty &&
                        !RegExp(r'^\S+@\S+\.\S+$').hasMatch(email)) {
                      return 'Ingresa un email válido.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        key: const Key('cliente-cumple-dia'),
                        initialValue: _cumpleDia,
                        decoration: const InputDecoration(
                          labelText: 'Cumpleaños: día',
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('—')),
                          for (var d = 1; d <= 31; d++)
                            DropdownMenuItem(value: d, child: Text('$d')),
                        ],
                        onChanged: (d) => setState(() => _cumpleDia = d),
                        validator: (d) {
                          if (_cumpleMes != null && d == null) {
                            return 'Elige el día.';
                          }
                          if (d != null && _cumpleMes == null) {
                            return 'Elige el mes.';
                          }
                          if (d != null && d > _diasDelMes) {
                            return 'Ese mes no tiene $d días.';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        key: const Key('cliente-cumple-mes'),
                        initialValue: _cumpleMes,
                        decoration: const InputDecoration(labelText: 'Mes'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('—')),
                          for (var m = 1; m <= 12; m++)
                            DropdownMenuItem(
                              value: m,
                              child: Text(nombresMeses[m - 1]),
                            ),
                        ],
                        onChanged: (m) => setState(() => _cumpleMes = m),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('cliente-notas'),
                  controller: _notasController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notas'),
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
          onPressed: _guardar,
          child: Text(
            widget.cliente == null ? 'Crear cliente' : 'Guardar cambios',
          ),
        ),
      ],
    );
  }
}
