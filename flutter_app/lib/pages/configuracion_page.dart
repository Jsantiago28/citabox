import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show StorageException;

import '../models/configuracion_negocio.dart';
import '../services/configuracion_repository.dart';
import '../services/mfa_repository.dart';
import '../services/sin_permiso.dart';
import '../theme.dart';
import '../utils/enlace_publico.dart';
import '../utils/fotos.dart';
import '../widgets/reserva_publica.dart' show ImagenRed;
import '../widgets/seguridad_cuenta_card.dart';

/// Configuración del negocio (solo el dueño): perfil, horario de apertura,
/// reglas de apartado/reserva y enlace público de reservas.
class ConfiguracionPage extends StatefulWidget {
  const ConfiguracionPage({
    super.key,
    required this.negocioId,
    required this.repository,
    this.baseEnlace,
    this.elegirFoto = elegirFotoDelDispositivo,
    this.mfaRepository,
  });

  final String negocioId;
  final ConfiguracionRepository repository;

  /// Base para armar el enlace público. Si es null, en web se usa
  /// `Uri.base`; fuera de web se muestra solo la ruta.
  final Uri? baseEnlace;

  /// Inyectable en pruebas; por defecto la galería o cámara del dispositivo.
  final ElegirFoto elegirFoto;

  /// Verificación en dos pasos; por defecto la de Supabase (si no hay
  /// backend iniciado, la tarjeta no se muestra).
  final MfaRepository? mfaRepository;

  @override
  State<ConfiguracionPage> createState() => _ConfiguracionPageState();
}

class _DiaEditable {
  _DiaEditable(this.diaSemana, HorarioDia? horario)
    : abierto = horario != null,
      apertura = TextEditingController(
        text: textoDesdeMinutos(horario?.apertura ?? 9 * 60),
      ),
      cierre = TextEditingController(
        text: textoDesdeMinutos(horario?.cierre ?? 18 * 60),
      );

  final int diaSemana;
  bool abierto;
  final TextEditingController apertura;
  final TextEditingController cierre;

  void dispose() {
    apertura.dispose();
    cierre.dispose();
  }
}

class _ConfiguracionPageState extends State<ConfiguracionPage> {
  late final MfaRepository? _mfa =
      widget.mfaRepository ?? mfaRepositoryPredeterminado();

  final _perfilKey = GlobalKey<FormState>();
  final _horarioKey = GlobalKey<FormState>();
  final _reservasKey = GlobalKey<FormState>();

  final _nombre = TextEditingController();
  final _telefono = TextEditingController();
  final _direccion = TextEditingController();
  final _logo = TextEditingController();
  final _imagen = TextEditingController();
  final _color = TextEditingController();

  final _monto = TextEditingController();
  final _politica = TextEditingController();
  final _instrucciones = TextEditingController();
  final _cancelacion = TextEditingController();
  final _intervalo = TextEditingController();
  bool _apartadoRequerido = true;

  List<_DiaEditable> _dias = [];
  ConfiguracionNegocio? _config;
  bool _loading = true;
  String? _error;

  /// Sección que se está guardando ('perfil', 'horario' o 'reservas').
  String? _guardando;

  List<TextEditingController> get _controladores => [
    _nombre,
    _telefono,
    _direccion,
    _logo,
    _imagen,
    _color,
    _monto,
    _politica,
    _instrucciones,
    _cancelacion,
    _intervalo,
  ];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final controlador in _controladores) {
      controlador.dispose();
    }
    for (final dia in _dias) {
      dia.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final config = await widget.repository.cargar(widget.negocioId);
      final horarios = await widget.repository.horarios(widget.negocioId);
      if (!mounted) return;
      setState(() => _aplicar(config, horarios));
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo cargar la configuración.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _aplicar(ConfiguracionNegocio config, List<HorarioDia> horarios) {
    _config = config;
    _nombre.text = config.nombre;
    _telefono.text = config.telefono;
    _direccion.text = config.direccion;
    _logo.text = config.logo;
    _imagen.text = config.imagen;
    _color.text = config.colorPrincipal;

    _apartadoRequerido = config.apartadoRequerido;
    _monto.text = _textoMonto(config.apartadoMonto);
    _politica.text = config.apartadoPolitica;
    _instrucciones.text = config.apartadoInstrucciones;
    _cancelacion.text = config.cancelacionHorasMinimas.toString();
    _intervalo.text = config.intervaloReservaMinutos.toString();

    for (final dia in _dias) {
      dia.dispose();
    }
    _dias = [
      for (var dia = 0; dia < 7; dia++)
        _DiaEditable(
          dia,
          horarios.where((h) => h.diaSemana == dia).firstOrNull,
        ),
    ];
  }

  static String _textoMonto(num monto) =>
      monto == monto.roundToDouble() ? monto.round().toString() : '$monto';

  static String? _opcional(TextEditingController controlador) {
    final texto = controlador.text.trim();
    return texto.isEmpty ? null : texto;
  }

  Future<void> _guardar(
    String seccion,
    Future<void> Function() accion,
    String exito,
  ) async {
    setState(() => _guardando = seccion);
    try {
      await accion();
      if (mounted) _mensaje(exito);
    } catch (error) {
      if (mounted) {
        _mensaje(mensajeDeError(error, 'No se pudieron guardar los cambios.'));
      }
    } finally {
      if (mounted) setState(() => _guardando = null);
    }
  }

  void _mensaje(String texto) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _guardarPerfil() async {
    if (!_perfilKey.currentState!.validate()) return;
    final color = _opcional(_color)?.toUpperCase();
    await _guardar(
      'perfil',
      () => widget.repository.guardarNegocio(
        negocioId: widget.negocioId,
        datos: {
          'nombre': _nombre.text.trim(),
          'telefono': _opcional(_telefono),
          'direccion': _opcional(_direccion),
          'logo': _opcional(_logo),
          'imagen': _opcional(_imagen),
          'color_principal': color,
        },
      ),
      'Perfil guardado.',
    );
  }

  Future<void> _guardarHorario() async {
    if (!_horarioKey.currentState!.validate()) return;
    final abiertos = [
      for (final dia in _dias)
        if (dia.abierto)
          HorarioDia(
            diaSemana: dia.diaSemana,
            apertura: minutosDesdeTexto(dia.apertura.text)!,
            cierre: minutosDesdeTexto(dia.cierre.text)!,
          ),
    ];
    await _guardar(
      'horario',
      () => widget.repository.guardarHorarios(
        negocioId: widget.negocioId,
        abiertos: abiertos,
      ),
      'Horario guardado.',
    );
  }

  Future<void> _guardarReservas() async {
    if (!_reservasKey.currentState!.validate()) return;
    await _guardar(
      'reservas',
      () => widget.repository.guardarNegocio(
        negocioId: widget.negocioId,
        datos: {
          'apartado_requerido': _apartadoRequerido,
          'apartado_monto': num.parse(_monto.text.trim()),
          'apartado_politica': _politica.text.trim(),
          'apartado_instrucciones': _opcional(_instrucciones),
          'cancelacion_horas_minimas': int.parse(_cancelacion.text.trim()),
          'intervalo_reserva_minutos': int.parse(_intervalo.text.trim()),
        },
      ),
      'Reglas de reserva guardadas.',
    );
  }

  String get _enlace {
    final base = widget.baseEnlace ?? (kIsWeb ? Uri.base : null);
    return enlaceReserva(_config?.slug ?? '', base: base);
  }

  Future<void> _copiarEnlace() async {
    await Clipboard.setData(ClipboardData(text: _enlace));
    if (mounted) _mensaje('Enlace copiado.');
  }

  @override
  Widget build(BuildContext context) {
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 860;
        return SingleChildScrollView(
          padding: EdgeInsets.all(isWide ? 28 : 16),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Configuración',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Datos del negocio, horarios y enlace de reservas.',
                    style: TextStyle(color: Marca.textoSuave),
                  ),
                  const SizedBox(height: 16),
                  _enlaceCard(),
                  const SizedBox(height: 16),
                  _perfilCard(isWide),
                  const SizedBox(height: 16),
                  _horarioCard(isWide),
                  const SizedBox(height: 16),
                  _reservasCard(isWide),
                  if (_mfa case final mfa?) ...[
                    const SizedBox(height: 16),
                    SeguridadCuentaCard(repository: mfa),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _filas(bool isWide, List<Widget> campos) {
    if (!isWide) {
      return Column(
        children: [
          for (var i = 0; i < campos.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            campos[i],
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < campos.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: campos[i]),
        ],
      ],
    );
  }

  Widget _botonGuardar(String seccion, String texto, VoidCallback onPressed) {
    final ocupado = _guardando == seccion;
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton.icon(
        onPressed: _guardando != null ? null : onPressed,
        style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
        icon: ocupado
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save_outlined, size: 18),
        label: Text(texto),
      ),
    );
  }

  Widget _enlaceCard() {
    return _Seccion(
      titulo: 'Enlace público de reservas',
      descripcion: 'Compártelo con tus clientes para que reserven en línea.',
      icono: Icons.link,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          decoration: BoxDecoration(
            color: Marca.fondo,
            border: Border.all(color: Marca.borde),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  _enlace,
                  key: const Key('config-enlace'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _copiarEnlace,
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copiar'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _perfilCard(bool isWide) {
    return _Seccion(
      titulo: 'Perfil del negocio',
      descripcion: 'Así verán tus clientes tu barbería.',
      icono: Icons.storefront_outlined,
      children: [
        Form(
          key: _perfilKey,
          child: Column(
            children: [
              _filas(isWide, [
                TextFormField(
                  key: const Key('config-nombre'),
                  controller: _nombre,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'El nombre es obligatorio.'
                      : null,
                ),
                TextFormField(
                  key: const Key('config-slug'),
                  initialValue: _config?.slug ?? '',
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: 'Identificador (slug)',
                    helperText: 'No se puede cambiar.',
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              _filas(isWide, [
                TextFormField(
                  key: const Key('config-telefono'),
                  controller: _telefono,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                ),
                TextFormField(
                  key: const Key('config-direccion'),
                  controller: _direccion,
                  decoration: const InputDecoration(labelText: 'Dirección'),
                ),
              ]),
              const SizedBox(height: 12),
              _filas(isWide, [
                _campoImagen(
                  campo: 'logo',
                  titulo: 'Logo',
                  ayuda: 'Se ve redondo en tu página de reservas.',
                  controller: _logo,
                ),
                _campoImagen(
                  campo: 'imagen',
                  titulo: 'Imagen de portada',
                  ayuda: 'Foto de tu local o de tu trabajo.',
                  controller: _imagen,
                ),
              ]),
              const SizedBox(height: 12),
              _filas(isWide, [
                TextFormField(
                  key: const Key('config-color'),
                  controller: _color,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Color principal (opcional)',
                    hintText: '#C9A24B',
                    prefixIcon: Padding(
                      padding: const EdgeInsets.all(12),
                      child: CircleAvatar(
                        radius: 9,
                        backgroundColor:
                            colorDesdeHex(_color.text) ?? Marca.borde,
                      ),
                    ),
                  ),
                  validator: (value) {
                    final texto = value?.trim() ?? '';
                    if (texto.isEmpty || colorDesdeHex(texto) != null) {
                      return null;
                    }
                    return 'Usa el formato #RRGGBB.';
                  },
                ),
                if (isWide) const SizedBox.shrink(),
              ]),
              const SizedBox(height: 16),
              _botonGuardar('perfil', 'Guardar perfil', _guardarPerfil),
            ],
          ),
        ),
      ],
    );
  }

  /// Sube el logo o la portada y lo guarda al momento (no hace falta pulsar
  /// "Guardar perfil").
  Future<void> _subirImagen(String campo, TextEditingController destino) async {
    final FotoElegida? foto;
    try {
      foto = await widget.elegirFoto();
    } catch (_) {
      _mensaje('No se pudo abrir la foto.');
      return;
    }
    if (foto == null || !mounted) return;
    if (foto.bytes.lengthInBytes > 2 * 1024 * 1024) {
      _mensaje('La foto pesa más de 2 MB.');
      return;
    }

    setState(() => _guardando = campo);
    try {
      final url = await widget.repository.subirImagen(
        negocioId: widget.negocioId,
        campo: campo,
        bytes: foto.bytes,
        tipo: foto.tipo,
      );
      destino.text = url;
      _mensaje(campo == 'logo' ? 'Logo actualizado.' : 'Portada actualizada.');
    } catch (error) {
      final motivo = error is StorageException ? ' (${error.message})' : '';
      _mensaje(mensajeDeError(error, 'No se pudo subir la imagen.$motivo'));
    } finally {
      if (mounted) setState(() => _guardando = null);
    }
  }

  Future<void> _quitarImagen(String campo, TextEditingController destino) =>
      _guardar(campo, () async {
        await widget.repository.guardarNegocio(
          negocioId: widget.negocioId,
          datos: {campo: null},
        );
        destino.clear();
      }, campo == 'logo' ? 'Logo quitado.' : 'Portada quitada.');

  Widget _campoImagen({
    required String campo,
    required String titulo,
    required String ayuda,
    required TextEditingController controller,
  }) {
    final ocupado = _guardando == campo;
    final tiene = controller.text.isNotEmpty;
    final respaldo = Container(
      color: Marca.negro,
      alignment: Alignment.center,
      child: Icon(
        campo == 'logo' ? Icons.storefront : Icons.image_outlined,
        color: Marca.doradoClaro,
      ),
    );
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(campo == 'logo' ? 40 : 12),
          child: SizedBox(
            width: campo == 'logo' ? 72 : 112,
            height: 72,
            child: ImagenRed(url: controller.text, respaldo: respaldo),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                ayuda,
                style: const TextStyle(color: Marca.textoSuave, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton.icon(
                    key: Key('config-subir-$campo'),
                    onPressed: _guardando != null
                        ? null
                        : () => _subirImagen(campo, controller),
                    icon: ocupado
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text(tiene ? 'Cambiar' : 'Subir'),
                  ),
                  if (tiene)
                    TextButton(
                      key: Key('config-quitar-$campo'),
                      onPressed: _guardando != null
                          ? null
                          : () => _quitarImagen(campo, controller),
                      child: const Text('Quitar'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _horarioCard(bool isWide) {
    // Lunes primero, domingo al final, como se lee una semana laboral.
    final orden = [1, 2, 3, 4, 5, 6, 0];
    return _Seccion(
      titulo: 'Horario de apertura',
      descripcion: 'Los clientes solo podrán reservar dentro de este horario.',
      icono: Icons.schedule,
      children: [
        Form(
          key: _horarioKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final dia in orden) ...[
                _filaDia(_dias[dia], isWide),
                if (dia != 0) const Divider(height: 1),
              ],
              const SizedBox(height: 16),
              _botonGuardar('horario', 'Guardar horario', _guardarHorario),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filaDia(_DiaEditable dia, bool isWide) {
    final nombre = nombresDiaSemana[dia.diaSemana];
    final interruptor = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            nombre,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Switch(
          key: Key('dia-${dia.diaSemana}-abierto'),
          value: dia.abierto,
          onChanged: (valor) => setState(() => dia.abierto = valor),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: Text(
            dia.abierto ? 'Abierto' : 'Cerrado',
            style: TextStyle(
              color: dia.abierto ? Marca.verde : Marca.textoSuave,
            ),
          ),
        ),
      ],
    );

    final horas = dia.abierto
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _campoHora(
                  key: Key('dia-${dia.diaSemana}-apertura'),
                  controlador: dia.apertura,
                  etiqueta: 'Apertura',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _campoHora(
                  key: Key('dia-${dia.diaSemana}-cierre'),
                  controlador: dia.cierre,
                  etiqueta: 'Cierre',
                  validarExtra: (cierre) {
                    final apertura = minutosDesdeTexto(dia.apertura.text);
                    if (apertura != null && cierre <= apertura) {
                      return 'Debe ser después de la apertura.';
                    }
                    return null;
                  },
                ),
              ),
            ],
          )
        : const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: interruptor,
                ),
                const SizedBox(width: 16),
                Expanded(child: horas),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                interruptor,
                if (dia.abierto) ...[const SizedBox(height: 8), horas],
              ],
            ),
    );
  }

  Widget _campoHora({
    required Key key,
    required TextEditingController controlador,
    required String etiqueta,
    String? Function(int minutos)? validarExtra,
  }) {
    return TextFormField(
      key: key,
      controller: controlador,
      keyboardType: TextInputType.datetime,
      decoration: InputDecoration(
        labelText: etiqueta,
        hintText: 'HH:MM',
        isDense: true,
        errorMaxLines: 2,
        suffixIcon: IconButton(
          tooltip: 'Elegir hora',
          icon: const Icon(Icons.access_time, size: 18),
          onPressed: () => _elegirHora(controlador),
        ),
      ),
      validator: (value) {
        final minutos = minutosDesdeTexto(value ?? '');
        if (minutos == null) return 'Hora inválida (HH:MM).';
        return validarExtra?.call(minutos);
      },
    );
  }

  Future<void> _elegirHora(TextEditingController controlador) async {
    final actual = minutosDesdeTexto(controlador.text) ?? 9 * 60;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: actual ~/ 60, minute: actual % 60),
    );
    if (hora == null || !mounted) return;
    setState(() {
      controlador.text = textoDesdeMinutos(hora.hour * 60 + hora.minute);
    });
  }

  Widget _reservasCard(bool isWide) {
    return _Seccion(
      titulo: 'Apartado y reservas',
      descripcion: 'Reglas para las citas que se reservan en línea.',
      icono: Icons.event_available_outlined,
      children: [
        Form(
          key: _reservasKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                key: const Key('config-apartado-requerido'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Pedir apartado para reservar'),
                subtitle: const Text(
                  'El cliente transfiere un monto para confirmar su cita.',
                ),
                value: _apartadoRequerido,
                onChanged: (valor) =>
                    setState(() => _apartadoRequerido = valor),
              ),
              const SizedBox(height: 8),
              _filas(isWide, [
                TextFormField(
                  key: const Key('config-monto'),
                  controller: _monto,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Monto del apartado',
                  ),
                  validator: (value) {
                    final monto = num.tryParse(value?.trim() ?? '');
                    if (monto == null || monto < 0) {
                      return 'Ingresa un monto de 0 o más.';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  key: const Key('config-cancelacion'),
                  controller: _cancelacion,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Cancelar con (horas de anticipación)',
                  ),
                  validator: (value) =>
                      _validarEntero(value, 0, 168, 'Entre 0 y 168 horas.'),
                ),
                TextFormField(
                  key: const Key('config-intervalo'),
                  controller: _intervalo,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Intervalo de reserva (minutos)',
                  ),
                  validator: (value) =>
                      _validarEntero(value, 5, 120, 'Entre 5 y 120 minutos.'),
                ),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('config-politica'),
                controller: _politica,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Política del apartado',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('config-instrucciones'),
                controller: _instrucciones,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Datos para la transferencia',
                  hintText: 'Banco: …\nCuenta: …\nA nombre de: …',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              _botonGuardar('reservas', 'Guardar reservas', _guardarReservas),
            ],
          ),
        ),
      ],
    );
  }

  static String? _validarEntero(
    String? value,
    int minimo,
    int maximo,
    String mensaje,
  ) {
    final numero = int.tryParse(value?.trim() ?? '');
    if (numero == null || numero < minimo || numero > maximo) return mensaje;
    return null;
  }
}

/// '#C9A24B' o 'C9A24B' → Color. Devuelve null si el formato no es válido.
Color? colorDesdeHex(String texto) {
  final limpio = texto.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(limpio)) return null;
  return Color(int.parse('FF$limpio', radix: 16));
}

class _Seccion extends StatelessWidget {
  const _Seccion({
    required this.titulo,
    required this.descripcion,
    required this.icono,
    required this.children,
  });

  final String titulo;
  final String descripcion;
  final IconData icono;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Marca.negro,
                  child: Icon(icono, color: Marca.doradoClaro, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        descripcion,
                        style: const TextStyle(
                          color: Marca.textoSuave,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}
