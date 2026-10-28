import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/reserva.dart';
import '../services/reserva_repository.dart';
import '../theme.dart';
import '../utils/enlace_publico.dart';
import '../utils/formato.dart';
import '../utils/navegador.dart';
import '../widgets/reserva_publica.dart';
import 'mi_cita_page.dart';

/// Clave de localStorage con el token de la última cita reservada en un negocio.
String claveCitaGuardada(String slug) => 'barberiapro.cita.$slug';

enum _Paso { portada, servicio, barbero, fechaHora, datos, resumen, listo }

const _pasosConIndicador = [
  _Paso.servicio,
  _Paso.barbero,
  _Paso.fechaHora,
  _Paso.datos,
  _Paso.resumen,
];

/// Reserva pública (sin cuenta): `#/reservar/<slug>`.
class ReservaPage extends StatefulWidget {
  const ReservaPage({
    super.key,
    required this.slug,
    required this.repository,
    this.baseEnlace,
  });

  final String slug;
  final ReservaRepository repository;

  /// Origen para armar el enlace de "Mi cita"; en web, `Uri.base`.
  final Uri? baseEnlace;

  @override
  State<ReservaPage> createState() => _ReservaPageState();
}

class _ReservaPageState extends State<ReservaPage> {
  final _formulario = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();
  final _correo = TextEditingController();
  final _nota = TextEditingController();

  CatalogoReserva? _catalogo;
  String? _errorCarga;
  bool _cargando = true;

  _Paso _paso = _Paso.portada;
  ServicioPublico? _servicio;
  BarberoPublico? _barbero; // null = cualquiera disponible
  DateTime? _fecha;
  HoraDisponible? _hora;
  int _versionHoras = 0;
  bool _enviando = false;
  CitaPublica? _cita;
  String? _citaGuardada;

  @override
  void initState() {
    super.initState();
    _citaGuardada = leerLocal(claveCitaGuardada(widget.slug));
    _cargar();
  }

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    _correo.dispose();
    _nota.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _errorCarga = null;
    });
    try {
      final catalogo = await widget.repository.catalogo(widget.slug);
      if (!mounted) return;
      setState(() => _catalogo = catalogo);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorCarga = errorDeReserva(error).mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String get _moneda => _catalogo?.negocio.moneda ?? 'DOP';

  String _enlaceMiCita(String token) =>
      enlaceCita(token, base: widget.baseEnlace ?? (kIsWeb ? Uri.base : null));

  void _ir(_Paso paso) => setState(() => _paso = paso);

  void _atras() {
    final anterior = switch (_paso) {
      _Paso.portada || _Paso.listo => null,
      _Paso.servicio => _Paso.portada,
      _Paso.barbero => _Paso.servicio,
      _Paso.fechaHora => _Paso.barbero,
      _Paso.datos => _Paso.fechaHora,
      _Paso.resumen => _Paso.datos,
    };
    if (anterior != null) _ir(anterior);
  }

  void _elegirServicio(ServicioPublico servicio) {
    setState(() {
      if (_servicio?.id != servicio.id) {
        _barbero = null;
        _fecha = null;
        _hora = null;
      }
      _servicio = servicio;
      _paso = _Paso.barbero;
    });
  }

  void _elegirBarbero(BarberoPublico? barbero) {
    setState(() {
      if (_barbero?.id != barbero?.id) _hora = null;
      _barbero = barbero;
      _paso = _Paso.fechaHora;
    });
  }

  Future<List<HoraDisponible>> _cargarHoras(DateTime fecha) =>
      widget.repository.horasDisponibles(
        slug: widget.slug,
        servicioId: _servicio!.id,
        fecha: fecha,
        empleadoId: _barbero?.id,
      );

  void _continuarDatos() {
    if (_formulario.currentState?.validate() ?? false) {
      FocusScope.of(context).unfocus();
      _ir(_Paso.resumen);
    }
  }

  Future<void> _confirmar() async {
    final catalogo = _catalogo!;
    final servicio = _servicio!;
    setState(() => _enviando = true);
    try {
      final respuesta = await widget.repository.crear(
        slug: widget.slug,
        servicioId: servicio.id,
        empleadoId: _barbero?.id,
        fecha: _fecha!,
        horaInicio: _hora!.horaInicio,
        nombre: _nombre.text.trim(),
        telefono: _telefono.text.trim(),
        email: _correo.text.trim().isEmpty ? null : _correo.text.trim(),
        notas: _nota.text.trim().isEmpty ? null : _nota.text.trim(),
      );
      final cita = CitaPublica.desdeReserva(
        respuesta: respuesta,
        catalogo: catalogo,
        servicio: servicio,
      );
      guardarLocal(claveCitaGuardada(widget.slug), cita.token);
      if (!mounted) return;
      setState(() {
        _cita = cita;
        _citaGuardada = cita.token;
        _paso = _Paso.listo;
      });
    } catch (error) {
      if (!mounted) return;
      final fallo = errorDeReserva(error);
      if (fallo.horaNoDisponible) {
        // 23P01: alguien tomó la hora; se recargan las horas de ese día.
        setState(() {
          _hora = null;
          _versionHoras++;
          _paso = _Paso.fechaHora;
        });
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(fallo.mensaje)));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _verMiCita(String token) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/cita/$token'),
        builder: (_) => MiCitaPage(
          token: token,
          repository: widget.repository,
          baseEnlace: widget.baseEnlace,
        ),
      ),
    );
  }

  void _nuevaReserva() {
    setState(() {
      _paso = _Paso.portada;
      _servicio = null;
      _barbero = null;
      _fecha = null;
      _hora = null;
      _cita = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando && _catalogo == null) {
      return const MarcoPublico(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_catalogo == null) {
      return MarcoPublico(
        child: ErrorPublico(
          mensaje: _errorCarga ?? mensajeSinConexion,
          alReintentar: _cargar,
        ),
      );
    }

    return PopScope(
      canPop: _paso == _Paso.portada || _paso == _Paso.listo,
      onPopInvokedWithResult: (hecho, _) {
        if (!hecho) _atras();
      },
      child: switch (_paso) {
        _Paso.portada => _portada(),
        _Paso.listo => _listo(),
        _ => _pasoConIndicador(),
      },
    );
  }

  // ---------------------------------------------------------------------
  // Portada del negocio
  // ---------------------------------------------------------------------

  Widget _portada() {
    final catalogo = _catalogo!;
    final negocio = catalogo.negocio;
    return MarcoPublico(
      pie: BotonPrincipal(
        key: const Key('reservar-cita'),
        texto: 'Reservar cita',
        icono: Icons.event_available,
        onPressed: catalogo.servicios.isEmpty
            ? null
            : () => _ir(_Paso.servicio),
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Encabezado(negocio: negocio),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_citaGuardada != null) ...[
                  TarjetaPublica(
                    color: const Color(0xFFFFFBF2),
                    child: Row(
                      children: [
                        const Icon(Icons.event_note, color: Marca.dorado),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('Ya tienes una cita reservada aquí.'),
                        ),
                        TextButton(
                          onPressed: () => _verMiCita(_citaGuardada!),
                          child: const Text('Ver mi cita'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text(
                  'Nuestros servicios',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (catalogo.servicios.isEmpty)
                  const Text(
                    'Este negocio todavía no tiene servicios para reservar.',
                    style: TextStyle(color: Marca.textoSuave),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (final (i, servicio)
                            in catalogo.servicios.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          ListTile(
                            title: Text(
                              servicio.nombre,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text('${servicio.duracionMinutos} min'),
                            trailing: Text(
                              formatoMoneda(servicio.precio, _moneda),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (catalogo.horarios.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Horario',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  TarjetaPublica(child: _Horario(horarios: catalogo.horarios)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Pasos 1–5
  // ---------------------------------------------------------------------

  Widget _pasoConIndicador() {
    final numero = _pasosConIndicador.indexOf(_paso) + 1;
    final (titulo, contenido, pie) = switch (_paso) {
      _Paso.servicio => ('Elige un servicio', _pasoServicio(), null),
      _Paso.barbero => ('¿Con quién?', _pasoBarbero(), null),
      _Paso.fechaHora => (
        '¿Cuándo?',
        _pasoFechaHora(),
        BotonPrincipal(
          key: const Key('continuar-hora'),
          texto: 'Continuar',
          onPressed: _hora == null ? null : () => _ir(_Paso.datos),
        ),
      ),
      _Paso.datos => (
        'Tus datos',
        _pasoDatos(),
        BotonPrincipal(
          key: const Key('continuar-datos'),
          texto: 'Continuar',
          onPressed: _continuarDatos,
        ),
      ),
      _ => (
        'Confirma tu cita',
        _pasoResumen(),
        BotonPrincipal(
          key: const Key('confirmar-reserva'),
          texto: 'Confirmar reserva',
          icono: Icons.check,
          cargando: _enviando,
          onPressed: _confirmar,
        ),
      ),
    };

    return MarcoPublico(
      titulo: titulo,
      alVolver: _atras,
      pie: pie,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _IndicadorPasos(actual: numero, total: _pasosConIndicador.length),
          Expanded(child: contenido),
        ],
      ),
    );
  }

  Widget _pasoServicio() {
    final servicios = _catalogo!.servicios;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: servicios.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final servicio = servicios[i];
        return _Opcion(
          key: Key('servicio-${servicio.id}'),
          elegida: servicio.id == _servicio?.id,
          titulo: servicio.nombre,
          subtitulo: [
            '${formatoMoneda(servicio.precio, _moneda)} · '
                '${servicio.duracionMinutos} min',
            if (servicio.descripcion.isNotEmpty) servicio.descripcion,
          ].join('\n'),
          icono: Icons.content_cut,
          onTap: () => _elegirServicio(servicio),
        );
      },
    );
  }

  Widget _pasoBarbero() {
    final barberos = _catalogo!.barberosPara(_servicio!.id);
    if (barberos.isEmpty) {
      return const ErrorPublico(
        mensaje:
            'Ahora mismo nadie está haciendo este servicio. '
            'Elige otro o escríbenos.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Opcion(
          key: const Key('barbero-cualquiera'),
          elegida: _barbero == null && _fecha != null,
          titulo: 'Cualquiera disponible',
          subtitulo: 'Te mostramos todas las horas libres',
          icono: Icons.groups_outlined,
          onTap: () => _elegirBarbero(null),
        ),
        for (final barbero in barberos) ...[
          const SizedBox(height: 10),
          _Opcion(
            key: Key('barbero-${barbero.id}'),
            elegida: barbero.id == _barbero?.id,
            titulo: barbero.nombre,
            foto: barbero.foto,
            onTap: () => _elegirBarbero(barbero),
          ),
        ],
      ],
    );
  }

  Widget _pasoFechaHora() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ResumenCorto(
          texto: [
            _servicio!.nombre,
            _barbero?.nombre ?? 'Cualquier barbero',
          ].join(' · '),
        ),
        const SizedBox(height: 16),
        SelectorFechaHora(
          // Si cambia el servicio o el barbero, se arma de nuevo.
          key: ValueKey('${_servicio!.id}-${_barbero?.id}'),
          catalogo: _catalogo!,
          version: _versionHoras,
          fechaInicial: _fecha,
          horaInicial: _hora?.horaInicio,
          cargarHoras: _cargarHoras,
          alCambiar: (fecha, hora) => setState(() {
            _fecha = fecha;
            _hora = hora;
          }),
        ),
      ],
    );
  }

  Widget _pasoDatos() {
    return Form(
      key: _formulario,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            key: const Key('reserva-nombre'),
            controller: _nombre,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            decoration: const InputDecoration(
              labelText: 'Nombre y apellido',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (valor) {
              final texto = valor?.trim() ?? '';
              if (texto.length < 2) return 'Escribe tu nombre.';
              if (texto.length > 80) return 'Máximo 80 caracteres.';
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const Key('reserva-telefono'),
            controller: _telefono,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: const InputDecoration(
              labelText: 'Teléfono (WhatsApp)',
              hintText: '809-555-1234',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            validator: (valor) {
              final digitos = (valor ?? '').replaceAll(RegExp(r'\D'), '');
              if (digitos.length < 7 || digitos.length > 15) {
                return 'Escribe un teléfono válido.';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const Key('reserva-correo'),
            controller: _correo,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Correo (opcional)',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            validator: (valor) {
              final texto = valor?.trim() ?? '';
              if (texto.isEmpty) return null;
              final valido = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
              return valido.hasMatch(texto) ? null : 'Correo no válido.';
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const Key('reserva-nota'),
            controller: _nota,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Nota para el barbero (opcional)',
              alignLabelWithHint: true,
            ),
          ),
          const Text(
            'Usamos tu teléfono solo para tu cita.',
            style: TextStyle(color: Marca.textoSuave, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _pasoResumen() {
    final negocio = _catalogo!.negocio;
    final servicio = _servicio!;
    final barberoHora = _catalogo!.barberos
        .where((b) => b.id == (_barbero?.id ?? _hora!.empleadoId))
        .firstOrNull;
    final horas = negocio.cancelacionHorasMinimas;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TarjetaPublica(
          child: Column(
            children: [
              FilaDato(
                icono: Icons.content_cut,
                etiqueta: 'Servicio',
                valor: '${servicio.nombre} · ${servicio.duracionMinutos} min',
              ),
              FilaDato(
                icono: Icons.person_outline,
                etiqueta: 'Barbero',
                valor: barberoHora?.nombre ?? 'Cualquiera disponible',
              ),
              FilaDato(
                icono: Icons.event_outlined,
                etiqueta: 'Fecha',
                valor: formatoFechaLarga(_fecha!),
              ),
              FilaDato(
                icono: Icons.schedule,
                etiqueta: 'Hora',
                valor: formatoHora(_hora!.horaInicio),
              ),
              FilaDato(
                icono: Icons.badge_outlined,
                etiqueta: 'A nombre de',
                valor: _nombre.text.trim(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TarjetaPublica(
          child: Column(
            children: [
              _FilaMonto('Servicio', formatoMoneda(servicio.precio, _moneda)),
              if (negocio.conApartado) ...[
                _FilaMonto(
                  'Apartado (pagas ahora)',
                  formatoMoneda(negocio.apartadoMonto, _moneda),
                ),
                const Divider(height: 20),
                _FilaMonto(
                  'Pagas en el local',
                  formatoMoneda(
                    (servicio.precio - negocio.apartadoMonto).clamp(
                      0,
                      servicio.precio,
                    ),
                    _moneda,
                  ),
                  fuerte: true,
                ),
              ] else ...[
                const Divider(height: 20),
                _FilaMonto(
                  'Pagas en el local',
                  formatoMoneda(servicio.precio, _moneda),
                  fuerte: true,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (negocio.conApartado) ...[
          Text(
            'Para asegurar tu cita, el negocio pide un apartado de '
            '${formatoMoneda(negocio.apartadoMonto, _moneda)} por '
            'transferencia. Te damos los datos al confirmar. '
            '$avisoVencimientoApartado',
          ),
          if (negocio.apartadoPolitica.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              negocio.apartadoPolitica,
              style: const TextStyle(color: Marca.textoSuave, fontSize: 13),
            ),
          ],
          const SizedBox(height: 8),
        ],
        Text(
          horas == 0
              ? 'Puedes cambiar o cancelar tu cita en línea antes de la hora.'
              : 'Puedes cambiar o cancelar tu cita en línea hasta '
                    '$horas ${horas == 1 ? 'hora' : 'horas'} antes.',
          style: const TextStyle(color: Marca.textoSuave, fontSize: 13),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // ¡Cita reservada!
  // ---------------------------------------------------------------------

  Widget _listo() {
    final cita = _cita!;
    final enlace = _enlaceMiCita(cita.token);
    return MarcoPublico(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        children: [
          const Center(
            child: CircleAvatar(
              radius: 38,
              backgroundColor: Marca.verde,
              child: Icon(Icons.check, color: Colors.white, size: 46),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '¡Cita reservada!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            cita.apartado == null
                ? 'Te esperamos en ${cita.negocio.nombre}.'
                : 'Tu cita se confirma cuando el negocio reciba el apartado.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Marca.textoSuave, fontSize: 15),
          ),
          const SizedBox(height: 20),
          DetalleCita(cita: cita),
          if (cita.apartado != null) ...[
            const SizedBox(height: 12),
            SeccionApartado(
              cita: cita,
              alReportar: (referencia) async {
                final actualizada = await widget.repository.reportarPago(
                  token: cita.token,
                  referencia: referencia,
                );
                if (mounted) setState(() => _cita = actualizada);
              },
            ),
          ],
          const SizedBox(height: 16),
          AccionesCita(cita: cita, enlaceMiCita: enlace),
          const SizedBox(height: 16),
          TarjetaPublica(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tu enlace de "Mi cita"',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Guárdalo: con él puedes ver, cambiar o cancelar tu cita.',
                  style: TextStyle(color: Marca.textoSuave),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  enlace,
                  key: const Key('enlace-mi-cita'),
                  style: const TextStyle(color: Marca.azul),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            copiarTexto(context, enlace, 'Enlace copiado.'),
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copiar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('ver-mi-cita'),
                        onPressed: () => _verMiCita(cita.token),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Ver mi cita'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _nuevaReserva,
            child: const Text('Hacer otra reserva'),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------------
// Piezas de la página
// -------------------------------------------------------------------------

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.negocio});

  final NegocioPublico negocio;

  @override
  Widget build(BuildContext context) {
    final oscuro = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2A2B2E), Marca.negro],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
    return SizedBox(
      height: 260,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImagenRed(url: negocio.imagen, respaldo: oscuro),
          // Velo para que el texto se lea sobre cualquier foto.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0x33000000), Color(0xCC000000)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                LogoNegocio(negocio: negocio, radio: 36),
                const SizedBox(height: 10),
                Text(
                  negocio.nombre,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    if (negocio.direccion.isNotEmpty)
                      _DatoClaro(Icons.place_outlined, negocio.direccion),
                    if (negocio.telefono.isNotEmpty)
                      _DatoClaro(Icons.phone_outlined, negocio.telefono),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DatoClaro extends StatelessWidget {
  const _DatoClaro(this.icono, this.texto);

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, color: Marca.doradoClaro, size: 16),
        const SizedBox(width: 4),
        Flexible(
          child: Text(texto, style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

const _nombresDias = [
  'Domingo',
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
];

class _Horario extends StatelessWidget {
  const _Horario({required this.horarios});

  final List<HorarioDia> horarios;

  @override
  Widget build(BuildContext context) {
    // Lunes primero, domingo al final.
    const orden = [1, 2, 3, 4, 5, 6, 0];
    return Column(
      children: [
        for (final dia in orden)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text(_nombresDias[dia])),
                Text(switch (horarios
                    .where((h) => h.diaSemana == dia)
                    .firstOrNull) {
                  null => 'Cerrado',
                  final h =>
                    '${formatoHora(h.apertura)} – ${formatoHora(h.cierre)}',
                }, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
      ],
    );
  }
}

class _IndicadorPasos extends StatelessWidget {
  const _IndicadorPasos({required this.actual, required this.total});

  final int actual;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Paso $actual de $total',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 1; i <= total; i++) ...[
                  if (i > 1) const SizedBox(width: 6),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 5,
                      decoration: BoxDecoration(
                        color: i <= actual ? Marca.dorado : Marca.borde,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            ExcludeSemantics(
              child: Text(
                'Paso $actual de $total',
                style: const TextStyle(color: Marca.textoSuave, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Opcion extends StatelessWidget {
  const _Opcion({
    super.key,
    required this.titulo,
    required this.onTap,
    this.subtitulo,
    this.icono,
    this.foto = '',
    this.elegida = false,
  });

  final String titulo;
  final String? subtitulo;
  final IconData? icono;
  final String foto;
  final bool elegida;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: 24,
      backgroundColor: Marca.negro,
      child: icono != null
          ? Icon(icono, color: Marca.doradoClaro)
          : Text(
              iniciales(titulo),
              style: const TextStyle(
                color: Marca.doradoClaro,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
    return Material(
      color: elegida ? const Color(0xFFFFFBF2) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: elegida ? Marca.dorado : Marca.borde,
          width: elegida ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: ClipOval(
                  child: ImagenRed(url: foto, respaldo: avatar),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitulo != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitulo!,
                        style: const TextStyle(color: Marca.textoSuave),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Marca.textoSuave),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResumenCorto extends StatelessWidget {
  const _ResumenCorto({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Marca.borde),
      ),
      child: Row(
        children: [
          const Icon(Icons.content_cut, size: 18, color: Marca.dorado),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaMonto extends StatelessWidget {
  const _FilaMonto(this.etiqueta, this.valor, {this.fuerte = false});

  final String etiqueta;
  final String valor;
  final bool fuerte;

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(
      fontWeight: fuerte ? FontWeight.w800 : FontWeight.w500,
      fontSize: fuerte ? 16 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(etiqueta, style: estilo)),
          Text(valor, style: estilo),
        ],
      ),
    );
  }
}
