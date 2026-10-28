import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/cita.dart';
import '../models/reserva.dart';
import '../services/reserva_repository.dart';
import '../theme.dart';
import '../utils/enlace_publico.dart';
import '../utils/formato.dart';
import '../widgets/estado_cita_badge.dart';
import '../widgets/reserva_publica.dart';
import 'reserva_page.dart';

/// "Mi cita" sin cuenta: `#/cita/<token>`.
class MiCitaPage extends StatefulWidget {
  const MiCitaPage({
    super.key,
    required this.token,
    required this.repository,
    this.baseEnlace,
  });

  final String token;
  final ReservaRepository repository;
  final Uri? baseEnlace;

  @override
  State<MiCitaPage> createState() => _MiCitaPageState();
}

class _MiCitaPageState extends State<MiCitaPage> {
  CitaPublica? _cita;
  String? _error;
  bool _cargando = true;
  bool _cancelando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final cita = await widget.repository.consultar(widget.token);
      if (!mounted) return;
      setState(() => _cita = cita);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = errorDeReserva(error).mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String get _enlace => enlaceCita(
    widget.token,
    base: widget.baseEnlace ?? (kIsWeb ? Uri.base : null),
  );

  void _avisar(String mensaje) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensaje)));

  Future<void> _cancelar() async {
    final cita = _cita!;
    final pagado = cita.apartado?.estado == EstadoApartado.pagado;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('¿Cancelar tu cita?'),
        content: Text(
          '${cita.servicioNombre}, ${formatoFechaLarga(cita.fecha).toLowerCase()} '
          'a las ${formatoHora(cita.horaInicio)}.'
          '${pagado ? '\n\nEl apartado pagado no se devuelve automáticamente; '
                    'el negocio decide según su política.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text('No, mantener'),
          ),
          FilledButton(
            key: const Key('confirmar-cancelar'),
            style: FilledButton.styleFrom(backgroundColor: Marca.rojo),
            onPressed: () => Navigator.of(contexto).pop(true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _cancelando = true);
    try {
      final actualizada = await widget.repository.cancelar(widget.token);
      if (!mounted) return;
      setState(() => _cita = actualizada);
      _avisar('Tu cita fue cancelada.');
    } catch (error) {
      if (mounted) _avisar(errorDeReserva(error).mensaje);
    } finally {
      if (mounted) setState(() => _cancelando = false);
    }
  }

  Future<void> _reprogramar() async {
    final actualizada = await Navigator.of(context).push<CitaPublica>(
      MaterialPageRoute(
        builder: (_) =>
            _ReprogramarPage(cita: _cita!, repository: widget.repository),
      ),
    );
    if (actualizada == null || !mounted) return;
    setState(() => _cita = actualizada);
    _avisar('Listo. Tu cita quedó para el nuevo horario.');
  }

  void _reservarOtra() {
    final slug = _cita!.negocio.slug;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/reservar/$slug'),
        builder: (_) => ReservaPage(
          slug: slug,
          repository: widget.repository,
          baseEnlace: widget.baseEnlace,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final puedeVolver = Navigator.of(context).canPop();
    final volver = puedeVolver ? () => Navigator.of(context).maybePop() : null;

    if (_cita == null) {
      return MarcoPublico(
        titulo: 'Mi cita',
        alVolver: volver,
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : ErrorPublico(
                mensaje: _error ?? mensajeSinConexion,
                alReintentar: _cargar,
              ),
      );
    }

    final cita = _cita!;
    return MarcoPublico(
      titulo: 'Mi cita',
      alVolver: volver,
      child: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TarjetaPublica(
              child: Row(
                children: [
                  LogoNegocio(negocio: cita.negocio, radio: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cita.negocio.nombre,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (cita.negocio.telefono.isNotEmpty)
                          Text(
                            cita.negocio.telefono,
                            style: const TextStyle(color: Marca.textoSuave),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                EstadoCitaBadge(estado: cita.estado),
                const Spacer(),
                Text(
                  formatoMoneda(cita.precio, cita.negocio.moneda),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              cita.servicioNombre,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            if (cita.barberoNombre.isNotEmpty)
              Text(
                'Con ${cita.barberoNombre}',
                style: const TextStyle(color: Marca.textoSuave, fontSize: 16),
              ),
            const SizedBox(height: 4),
            _MensajeEstado(cita: cita),
            const SizedBox(height: 12),
            DetalleCita(cita: cita),
            if (cita.apartado != null) ...[
              const SizedBox(height: 12),
              SeccionApartado(
                cita: cita,
                alReportar: (referencia) async {
                  final actualizada = await widget.repository.reportarPago(
                    token: widget.token,
                    referencia: referencia,
                  );
                  if (!mounted) return;
                  setState(() => _cita = actualizada);
                  _avisar('Recibimos tu referencia.');
                },
              ),
            ],
            if (cita.activa) ...[
              const SizedBox(height: 12),
              _Plazo(cita: cita),
            ],
            if (cita.puedeReprogramar || cita.puedeCancelar) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (cita.puedeReprogramar)
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          key: const Key('mi-cita-reprogramar'),
                          onPressed: _cancelando ? null : _reprogramar,
                          icon: const Icon(Icons.edit_calendar_outlined),
                          label: const Text('Reprogramar'),
                        ),
                      ),
                    ),
                  if (cita.puedeReprogramar && cita.puedeCancelar)
                    const SizedBox(width: 10),
                  if (cita.puedeCancelar)
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          key: const Key('mi-cita-cancelar'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Marca.rojo,
                            side: const BorderSide(color: Marca.rojo),
                          ),
                          onPressed: _cancelando ? null : _cancelar,
                          icon: _cancelando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.delete_outline),
                          label: const Text('Cancelar cita'),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            AccionesCita(
              cita: cita,
              enlaceMiCita: _enlace,
              conCalendario: cita.activa,
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () =>
                  copiarTexto(context, _enlace, 'Enlace de tu cita copiado.'),
              icon: const Icon(Icons.link),
              label: const Text('Copiar enlace de esta cita'),
            ),
            if (!cita.activa)
              TextButton(
                onPressed: _reservarOtra,
                child: const Text('Reservar otra cita'),
              ),
          ],
        ),
      ),
    );
  }
}

class _MensajeEstado extends StatelessWidget {
  const _MensajeEstado({required this.cita});

  final CitaPublica cita;

  @override
  Widget build(BuildContext context) {
    final texto = switch (cita.estado) {
      EstadoCita.pendiente =>
        cita.apartado != null &&
                cita.apartado!.estado == EstadoApartado.pendiente
            ? 'Tu cita se confirma cuando el negocio reciba el apartado.'
            : 'El negocio confirmará tu cita.',
      EstadoCita.confirmada => '¡Tu cita está confirmada! Te esperamos.',
      EstadoCita.llego => 'Ya estás en el local.',
      EstadoCita.completada => 'Gracias por visitarnos.',
      EstadoCita.noVino => 'Esta cita se marcó como no asistida.',
      EstadoCita.cancelada => 'Esta cita fue cancelada.',
    };
    return Text(texto, style: TextStyle(color: colorEstadoCita(cita.estado)));
  }
}

class _Plazo extends StatelessWidget {
  const _Plazo({required this.cita});

  final CitaPublica cita;

  @override
  Widget build(BuildContext context) {
    final limite = cita.limiteCambios;
    final horas = cita.negocio.cancelacionHorasMinimas;
    final String texto;
    if (cita.puedeCancelar || cita.puedeReprogramar) {
      texto = limite == null
          ? 'Puedes cambiar o cancelar tu cita hasta $horas horas antes.'
          : 'Puedes cambiar o cancelar hasta el '
                '${formatoFechaLarga(limite).toLowerCase()}, '
                '${formatoHora('${limite.hour}:${limite.minute.toString().padLeft(2, '0')}')}.';
    } else {
      texto =
          'Ya pasó el plazo para cambiar o cancelar en línea '
          '($horas ${horas == 1 ? 'hora' : 'horas'} antes). '
          'Escríbenos por WhatsApp si necesitas algo.';
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 18, color: Marca.textoSuave),
        const SizedBox(width: 8),
        Expanded(
          child: Text(texto, style: const TextStyle(color: Marca.textoSuave)),
        ),
      ],
    );
  }
}

/// Elegir nueva fecha y hora (mismo servicio y barbero).
class _ReprogramarPage extends StatefulWidget {
  const _ReprogramarPage({required this.cita, required this.repository});

  final CitaPublica cita;
  final ReservaRepository repository;

  @override
  State<_ReprogramarPage> createState() => _ReprogramarPageState();
}

class _ReprogramarPageState extends State<_ReprogramarPage> {
  CatalogoReserva? _catalogo;
  String? _error;
  DateTime? _fecha;
  HoraDisponible? _hora;
  int _version = 0;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final catalogo = await widget.repository.catalogo(
        widget.cita.negocio.slug,
      );
      if (mounted) setState(() => _catalogo = catalogo);
    } catch (error) {
      if (mounted) setState(() => _error = errorDeReserva(error).mensaje);
    }
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      final actualizada = await widget.repository.reprogramar(
        token: widget.cita.token,
        fecha: _fecha!,
        horaInicio: _hora!.horaInicio,
      );
      if (mounted) Navigator.of(context).pop(actualizada);
    } catch (error) {
      if (!mounted) return;
      final fallo = errorDeReserva(error);
      if (fallo.horaNoDisponible) {
        setState(() {
          _hora = null;
          _version++;
        });
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(fallo.mensaje)));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cita = widget.cita;
    final catalogo = _catalogo;
    final mismaHora =
        _fecha == cita.fecha && _hora?.horaInicio == cita.horaInicio;

    return MarcoPublico(
      titulo: 'Reprogramar',
      alVolver: () => Navigator.of(context).maybePop(),
      pie: catalogo == null
          ? null
          : BotonPrincipal(
              key: const Key('confirmar-reprogramar'),
              texto: 'Cambiar a esta hora',
              cargando: _guardando,
              onPressed: _hora == null || mismaHora ? null : _guardar,
            ),
      child: catalogo == null
          ? (_error == null
                ? const Center(child: CircularProgressIndicator())
                : ErrorPublico(mensaje: _error!, alReintentar: _cargar))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Ahora: ${formatoFechaLarga(cita.fecha)}, '
                  '${formatoHora(cita.horaInicio)}',
                  style: const TextStyle(color: Marca.textoSuave),
                ),
                const SizedBox(height: 4),
                Text(
                  '${cita.servicioNombre}'
                  '${cita.barberoNombre.isEmpty ? '' : ' con ${cita.barberoNombre}'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                SelectorFechaHora(
                  catalogo: catalogo,
                  version: _version,
                  fechaInicial:
                      catalogo.abre(cita.fecha) &&
                          !cita.fecha.isBefore(catalogo.hoy) &&
                          !cita.fecha.isAfter(catalogo.fechaMaxima)
                      ? cita.fecha
                      : null,
                  cargarHoras: (fecha) => widget.repository.horasDisponibles(
                    slug: cita.negocio.slug,
                    servicioId: cita.servicioId,
                    fecha: fecha,
                    empleadoId: cita.barberoId,
                    token: cita.token,
                  ),
                  alCambiar: (fecha, hora) => setState(() {
                    _fecha = fecha;
                    _hora = hora;
                  }),
                ),
              ],
            ),
    );
  }
}
