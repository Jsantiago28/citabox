import 'package:flutter/material.dart';

import '../models/catalogo_servicios.dart';
import '../models/servicio.dart';
import '../services/servicios_repository.dart';
import '../services/sin_permiso.dart';
import '../theme.dart';
import '../utils/formato.dart';
import '../utils/iconos_servicio.dart';
import '../widgets/etiqueta.dart';

class ServiciosPage extends StatefulWidget {
  const ServiciosPage({
    super.key,
    required this.negocioId,
    required this.repository,
    this.moneda = 'DOP',
  });

  final String negocioId;
  final ServiciosRepository repository;
  final String moneda;

  @override
  State<ServiciosPage> createState() => _ServiciosPageState();
}

class _ServiciosPageState extends State<ServiciosPage> {
  final _searchController = TextEditingController();
  List<Servicio> _servicios = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _changingStatusId;

  @override
  void initState() {
    super.initState();
    _cargarServicios();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cargarServicios() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final servicios = await widget.repository.listar(widget.negocioId);
      if (mounted) setState(() => _servicios = servicios);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudieron cargar los servicios.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _abrirFormulario([Servicio? servicio]) async {
    final datos = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) =>
          _ServicioFormDialog(servicio: servicio, moneda: widget.moneda),
    );
    if (datos == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.repository.guardar(
        negocioId: widget.negocioId,
        servicioId: servicio?.id,
        datos: datos,
      );
      await _cargarServicios();
    } catch (error) {
      if (mounted) {
        _mostrarError(mensajeDeError(error, 'No se pudo guardar el servicio.'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _seleccionarServicios() async {
    final elegidos = await showDialog<List<Map<String, Object?>>>(
      context: context,
      builder: (context) => _SeleccionarServiciosDialog(
        existentes: {for (final s in _servicios) _clave(s.nombre)},
        moneda: widget.moneda,
      ),
    );
    if (elegidos == null || elegidos.isEmpty || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.repository.crearVarios(
        negocioId: widget.negocioId,
        servicios: elegidos,
      );
      await _cargarServicios();
      if (mounted) {
        final n = elegidos.length;
        _mostrarError(
          n == 1 ? 'Se agregó 1 servicio.' : 'Se agregaron $n servicios.',
        );
      }
    } catch (error) {
      if (mounted) {
        _mostrarError(
          mensajeDeError(error, 'No se pudieron agregar los servicios.'),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cambiarEstado(Servicio servicio) async {
    setState(() => _changingStatusId = servicio.id);
    try {
      await widget.repository.cambiarEstado(
        negocioId: widget.negocioId,
        servicioId: servicio.id,
        activo: !servicio.activo,
      );
      await _cargarServicios();
    } catch (error) {
      if (mounted) {
        _mostrarError(
          mensajeDeError(
            error,
            'No se pudo actualizar el estado del servicio.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _changingStatusId = null);
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  List<Servicio> get _serviciosFiltrados {
    final consulta = _searchController.text.trim().toLowerCase();
    if (consulta.isEmpty) return _servicios;

    return _servicios
        .where((servicio) {
          return servicio.nombre.toLowerCase().contains(consulta) ||
              servicio.descripcion.toLowerCase().contains(consulta);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final servicios = _serviciosFiltrados;
        final isWide = constraints.maxWidth >= 860;
        final activos = _servicios.where((servicio) => servicio.activo).length;

        final buscador = SizedBox(
          width: isWide ? 280 : double.infinity,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar servicio…',
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
          label: const Text('Nuevo servicio'),
        );

        final seleccionar = OutlinedButton.icon(
          key: const Key('seleccionar-servicios'),
          onPressed: _saving ? null : _seleccionarServicios,
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
          icon: const Icon(Icons.checklist, size: 18),
          label: const Text('Seleccionar servicios'),
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
                          'Servicios',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$activos activos de ${_servicios.length}',
                          style: const TextStyle(color: Marca.textoSuave),
                        ),
                      ],
                    ),
                  ),
                  if (isWide) ...[
                    buscador,
                    const SizedBox(width: 12),
                    seleccionar,
                    const SizedBox(width: 12),
                  ],
                  nuevo,
                ],
              ),
              if (!isWide) ...[
                const SizedBox(height: 12),
                seleccionar,
                const SizedBox(height: 12),
                buscador,
              ],
              const SizedBox(height: 16),
              Expanded(child: _buildContent(servicios, isWide)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(List<Servicio> servicios, bool isWide) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _cargarServicios,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (servicios.isEmpty) {
      return Center(
        child: Text(
          _servicios.isEmpty
              ? 'Todavía no hay servicios.\nUsa "Seleccionar servicios" para '
                    'elegirlos de una lista,\no "Nuevo servicio" para crear el tuyo.'
              : 'No hay coincidencias.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        itemCount: servicios.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, index) => _fila(servicios[index], isWide),
      ),
    );
  }

  Widget _fila(Servicio servicio, bool isWide) {
    final precio = formatoMoneda(servicio.precio, widget.moneda);
    final duracion = formatoDuracion(servicio.duracionMinutos);

    final nombre = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                servicio.nombre,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: servicio.activo ? Marca.texto : Marca.textoSuave,
                ),
              ),
            ),
            if (!servicio.activo) ...[
              const SizedBox(width: 8),
              const Etiqueta(texto: 'Inactivo', color: Marca.textoSuave),
            ],
          ],
        ),
        if (servicio.descripcion.isNotEmpty || !isWide) ...[
          const SizedBox(height: 2),
          Text(
            isWide
                ? servicio.descripcion
                : [
                    duracion,
                    if (servicio.descripcion.isNotEmpty) servicio.descripcion,
                  ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Marca.textoSuave, fontSize: 12),
          ),
        ],
      ],
    );

    return InkWell(
      onTap: () => _abrirFormulario(servicio),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Marca.negro,
              child: Icon(
                iconoServicio(servicio.icono),
                size: 18,
                color: Marca.doradoClaro,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(flex: 3, child: nombre),
            if (isWide)
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.schedule,
                      size: 16,
                      color: Marca.textoSuave,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      duracion,
                      style: const TextStyle(color: Marca.textoSuave),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: isWide ? 120 : null,
              child: Text(
                precio,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            _acciones(servicio),
          ],
        ),
      ),
    );
  }

  Widget _acciones(Servicio servicio) {
    final busy = _changingStatusId == servicio.id;
    return PopupMenuButton<String>(
      tooltip: 'Acciones de ${servicio.nombre}',
      enabled: !busy,
      onSelected: (accion) {
        if (accion == 'editar') _abrirFormulario(servicio);
        if (accion == 'estado') _cambiarEstado(servicio);
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'editar', child: Text('Editar')),
        PopupMenuItem(
          value: 'estado',
          child: Text(servicio.activo ? 'Desactivar' : 'Activar'),
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

/// '1,500.50' → 1500.5 · acepta la coma como separador de miles.
num? _leerPrecio(String texto) =>
    num.tryParse(texto.trim().replaceAll(',', '').replaceAll(' ', ''));

/// 500.0 → '500' · 99.5 → '99.5'
String _precioTexto(num precio) =>
    precio == precio.truncate() ? precio.truncate().toString() : '$precio';

class _ServicioFormDialog extends StatefulWidget {
  const _ServicioFormDialog({this.servicio, required this.moneda});

  final Servicio? servicio;
  final String moneda;

  @override
  State<_ServicioFormDialog> createState() => _ServicioFormDialogState();
}

class _ServicioFormDialogState extends State<_ServicioFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreController;
  late final TextEditingController _descripcionController;
  late final TextEditingController _precioController;
  late final TextEditingController _duracionController;
  late bool _activo;
  late String _icono;

  @override
  void initState() {
    super.initState();
    final servicio = widget.servicio;
    _icono = servicio?.icono ?? iconoServicioPorDefecto;
    _nombreController = TextEditingController(text: servicio?.nombre ?? '');
    _descripcionController = TextEditingController(
      text: servicio?.descripcion ?? '',
    );
    _precioController = TextEditingController(
      text: servicio == null ? '' : _precioTexto(servicio.precio),
    );
    _duracionController = TextEditingController(
      text: servicio == null ? '30' : servicio.duracionMinutos.toString(),
    );
    _activo = servicio?.activo ?? true;
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _descripcionController.dispose();
    _precioController.dispose();
    _duracionController.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    final descripcion = _descripcionController.text.trim();
    Navigator.of(context).pop(<String, Object?>{
      'nombre': _nombreController.text.trim(),
      'descripcion': descripcion.isEmpty ? null : descripcion,
      'precio': _leerPrecio(_precioController.text),
      'duracion_minutos': int.parse(_duracionController.text.trim()),
      'activo': _activo,
      'icono': _icono,
    });
  }

  @override
  Widget build(BuildContext context) {
    final esNuevo = widget.servicio == null;
    return AlertDialog(
      title: Text(esNuevo ? 'Nuevo servicio' : 'Editar servicio'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('servicio-nombre'),
                  controller: _nombreController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'El nombre es obligatorio.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('servicio-descripcion'),
                  controller: _descripcionController,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('servicio-precio'),
                        controller: _precioController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Precio',
                          prefixText: simboloMoneda(widget.moneda),
                        ),
                        validator: (value) {
                          if (value?.trim().isEmpty ?? true) {
                            return 'El precio es obligatorio.';
                          }
                          final precio = _leerPrecio(value!);
                          if (precio == null) return 'Ingresa un número.';
                          if (precio < 0) {
                            return 'No puede ser negativo.';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const Key('servicio-duracion'),
                        controller: _duracionController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Duración',
                          suffixText: 'min',
                        ),
                        validator: (value) {
                          final minutos = int.tryParse(value?.trim() ?? '');
                          if (minutos == null) {
                            return 'Ingresa los minutos.';
                          }
                          if (minutos <= 0) return 'Debe ser mayor que 0.';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Ícono',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final entrada in iconosServicio.entries)
                      ChoiceChip(
                        key: Key('icono-${entrada.key}'),
                        showCheckmark: false,
                        label: Icon(entrada.value, size: 18),
                        selected: _icono == entrada.key,
                        onSelected: (_) => setState(() => _icono = entrada.key),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  key: const Key('servicio-activo'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Visible en reservas'),
                  subtitle: const Text(
                    'Los clientes pueden elegirlo al reservar.',
                  ),
                  value: _activo,
                  onChanged: (value) => setState(() => _activo = value),
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
          child: Text(esNuevo ? 'Crear servicio' : 'Guardar cambios'),
        ),
      ],
    );
  }
}

/// Nombre normalizado para no agregar dos veces el mismo servicio.
String _clave(String nombre) => nombre.trim().toLowerCase();

/// Catálogo sugerido: el dueño marca los servicios que ofrece y les pone
/// precio. Devuelve las filas a crear.
class _SeleccionarServiciosDialog extends StatefulWidget {
  const _SeleccionarServiciosDialog({
    required this.existentes,
    required this.moneda,
  });

  final Set<String> existentes;
  final String moneda;

  @override
  State<_SeleccionarServiciosDialog> createState() =>
      _SeleccionarServiciosDialogState();
}

class _SeleccionarServiciosDialogState
    extends State<_SeleccionarServiciosDialog> {
  final _formKey = GlobalKey<FormState>();
  final _precios = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final controller in _precios.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _alternar(ServicioSugerido sugerido) {
    setState(() {
      final quitado = _precios.remove(sugerido.nombre);
      if (quitado != null) {
        quitado.dispose();
      } else {
        _precios[sugerido.nombre] = TextEditingController();
      }
    });
  }

  void _agregar() {
    if (_precios.isEmpty || !_formKey.currentState!.validate()) return;
    Navigator.of(context).pop([
      for (final sugerido in catalogoSalon)
        if (_precios[sugerido.nombre] case final precio?)
          <String, Object?>{
            'nombre': sugerido.nombre,
            'precio': _leerPrecio(precio.text),
            'duracion_minutos': sugerido.duracionMinutos,
            'icono': sugerido.icono,
            'activo': true,
          },
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final n = _precios.length;
    return AlertDialog(
      title: const Text('Seleccionar servicios'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Marca los servicios que ofreces y escribe tu precio. '
                'La duración la puedes cambiar después.',
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final sugerido in catalogoSalon) _sugerido(sugerido),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('agregar-seleccionados'),
          onPressed: n == 0 ? null : _agregar,
          child: Text(n == 0 ? 'Agregar' : 'Agregar $n'),
        ),
      ],
    );
  }

  Widget _sugerido(ServicioSugerido sugerido) {
    final yaExiste = widget.existentes.contains(_clave(sugerido.nombre));
    final precio = _precios[sugerido.nombre];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Checkbox(
            key: Key('sugerido-${sugerido.nombre}'),
            value: yaExiste || precio != null,
            onChanged: yaExiste ? null : (_) => _alternar(sugerido),
          ),
          CircleAvatar(
            radius: 16,
            backgroundColor: Marca.negro,
            child: Icon(
              iconoServicio(sugerido.icono),
              size: 16,
              color: Marca.doradoClaro,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sugerido.nombre),
                Text(
                  yaExiste
                      ? 'Ya está en tus servicios'
                      : formatoDuracion(sugerido.duracionMinutos),
                  style: const TextStyle(color: Marca.textoSuave, fontSize: 12),
                ),
              ],
            ),
          ),
          if (precio != null)
            SizedBox(
              width: 120,
              child: TextFormField(
                key: Key('precio-${sugerido.nombre}'),
                controller: precio,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Precio',
                  prefixText: simboloMoneda(widget.moneda),
                ),
                validator: (value) {
                  final numero = _leerPrecio(value ?? '');
                  if (numero == null) return 'Escribe el precio';
                  if (numero < 0) return 'No negativo';
                  return null;
                },
              ),
            ),
        ],
      ),
    );
  }
}
