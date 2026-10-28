// Piezas compartidas de la reserva pública y "Mi cita" (celular primero).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/reserva.dart';
import '../services/reserva_repository.dart';
import '../theme.dart';
import '../utils/enlaces_cita.dart';
import '../utils/formato.dart';
import '../utils/navegador.dart';

/// Las reservas públicas sin transferencia reportada vencen a las 3 horas
/// (vencer_reservas_sin_pago, 010_seguridad_reservas_y_roles.sql).
const avisoVencimientoApartado =
    'Reporta tu transferencia en las próximas 3 horas o la reserva se '
    'cancela automáticamente.';

/// Ancho máximo del contenido en computadora.
const anchoMaximoPublico = 520.0;

/// Pantalla pública: fondo claro y contenido centrado de máx. 520 px.
class MarcoPublico extends StatelessWidget {
  const MarcoPublico({
    super.key,
    required this.child,
    this.titulo,
    this.alVolver,
    this.pie,
  });

  final Widget child;
  final String? titulo;
  final VoidCallback? alVolver;

  /// Botón fijo abajo (p. ej. "Continuar").
  final Widget? pie;

  @override
  Widget build(BuildContext context) {
    // heightFactor 1: en la barra de abajo no debe ocupar toda la altura.
    Widget centrado(Widget hijo, {double? alto}) => Center(
      heightFactor: alto,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: anchoMaximoPublico),
        child: hijo,
      ),
    );

    return Scaffold(
      appBar: titulo == null && alVolver == null
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              leading: alVolver == null
                  ? null
                  : IconButton(
                      tooltip: 'Atrás',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: alVolver,
                    ),
              centerTitle: true,
              title: titulo == null
                  ? null
                  : Text(
                      titulo!,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
      body: SafeArea(top: false, child: centrado(child)),
      bottomNavigationBar: pie == null
          ? null
          : SafeArea(
              child: centrado(
                alto: 1,
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: pie,
                ),
              ),
            ),
    );
  }
}

/// Botón principal grande y dorado.
class BotonPrincipal extends StatelessWidget {
  const BotonPrincipal({
    super.key,
    required this.texto,
    required this.onPressed,
    this.icono,
    this.cargando = false,
  });

  final String texto;
  final VoidCallback? onPressed;
  final IconData? icono;
  final bool cargando;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Marca.dorado,
          foregroundColor: Marca.negro,
          disabledBackgroundColor: Marca.borde,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        onPressed: cargando ? null : onPressed,
        child: cargando
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icono != null) ...[
                    Icon(icono, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Flexible(child: Text(texto, textAlign: TextAlign.center)),
                ],
              ),
      ),
    );
  }
}

/// Mensaje de error con botón de reintentar.
class ErrorPublico extends StatelessWidget {
  const ErrorPublico({super.key, required this.mensaje, this.alReintentar});

  final String mensaje;
  final VoidCallback? alReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Marca.textoSuave),
            const SizedBox(height: 12),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            if (alReintentar != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: alReintentar,
                icon: const Icon(Icons.refresh),
                label: const Text('Intentar de nuevo'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Imagen de internet que no rompe la pantalla si falla.
class ImagenRed extends StatelessWidget {
  const ImagenRed({
    super.key,
    required this.url,
    required this.respaldo,
    this.ajuste = BoxFit.cover,
  });

  final String url;
  final Widget respaldo;
  final BoxFit ajuste;

  @override
  Widget build(BuildContext context) {
    if (!(url.startsWith('http://') || url.startsWith('https://'))) {
      return respaldo;
    }
    return Image.network(url, fit: ajuste, errorBuilder: (_, _, _) => respaldo);
  }
}

/// Logo del negocio en círculo (o sus iniciales).
class LogoNegocio extends StatelessWidget {
  const LogoNegocio({super.key, required this.negocio, this.radio = 32});

  final NegocioPublico negocio;
  final double radio;

  @override
  Widget build(BuildContext context) {
    final respaldo = Container(
      color: Marca.negro,
      alignment: Alignment.center,
      child: Text(
        iniciales(negocio.nombre),
        style: TextStyle(
          color: Marca.doradoClaro,
          fontWeight: FontWeight.w800,
          fontSize: radio * 0.7,
        ),
      ),
    );
    return Container(
      width: radio * 2,
      height: radio * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Marca.dorado, width: 2),
      ),
      child: ClipOval(
        child: ImagenRed(url: negocio.logo, respaldo: respaldo),
      ),
    );
  }
}

/// Fila "icono · etiqueta · valor" del resumen de la cita.
class FilaDato extends StatelessWidget {
  const FilaDato({
    super.key,
    required this.icono,
    required this.etiqueta,
    required this.valor,
    this.colorValor,
  });

  final IconData icono;
  final String etiqueta;
  final String valor;
  final Color? colorValor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 20, color: Marca.textoSuave),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: Text(
              etiqueta,
              style: const TextStyle(color: Marca.textoSuave),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colorValor ?? Marca.texto,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta blanca con relleno.
class TarjetaPublica extends StatelessWidget {
  const TarjetaPublica({super.key, required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

/// Datos principales de una cita.
class DetalleCita extends StatelessWidget {
  const DetalleCita({super.key, required this.cita});

  final CitaPublica cita;

  @override
  Widget build(BuildContext context) {
    final moneda = cita.negocio.moneda;
    final apartado = cita.apartado;
    return TarjetaPublica(
      child: Column(
        children: [
          FilaDato(
            icono: Icons.content_cut,
            etiqueta: 'Servicio',
            valor: cita.servicioNombre,
          ),
          if (cita.barberoNombre.isNotEmpty)
            FilaDato(
              icono: Icons.person_outline,
              etiqueta: 'Barbero',
              valor: cita.barberoNombre,
            ),
          FilaDato(
            icono: Icons.event_outlined,
            etiqueta: 'Fecha',
            valor: formatoFechaLarga(cita.fecha),
          ),
          FilaDato(
            icono: Icons.schedule,
            etiqueta: 'Hora',
            valor: formatoHora(cita.horaInicio),
          ),
          FilaDato(
            icono: Icons.payments_outlined,
            etiqueta: 'Precio',
            valor: formatoMoneda(cita.precio, moneda),
          ),
          if (apartado != null)
            FilaDato(
              icono: Icons.savings_outlined,
              etiqueta: 'Apartado',
              valor:
                  '${formatoMoneda(apartado.monto, moneda)} '
                  '(${textoEstadoApartado(apartado)})',
              colorValor: colorEstadoApartado(apartado),
            ),
          if (cita.negocio.direccion.isNotEmpty)
            FilaDato(
              icono: Icons.place_outlined,
              etiqueta: 'Dirección',
              valor: cita.negocio.direccion,
            ),
        ],
      ),
    );
  }
}

String textoEstadoApartado(ApartadoPublico apartado) {
  if (apartado.enRevision) return 'en revisión';
  return switch (apartado.estado) {
    EstadoApartado.pendiente => 'pendiente de pago',
    EstadoApartado.pagado => 'pagado',
    EstadoApartado.cancelado => 'cancelado',
  };
}

Color colorEstadoApartado(ApartadoPublico apartado) {
  if (apartado.enRevision) return Marca.azul;
  return switch (apartado.estado) {
    EstadoApartado.pendiente => Marca.naranja,
    EstadoApartado.pagado => Marca.verde,
    EstadoApartado.cancelado => Marca.textoSuave,
  };
}

/// Apartado: monto, instrucciones de transferencia y "Ya transferí".
class SeccionApartado extends StatefulWidget {
  const SeccionApartado({
    super.key,
    required this.cita,
    required this.alReportar,
  });

  final CitaPublica cita;

  /// Envía la referencia; devuelve la cita actualizada.
  final Future<void> Function(String referencia) alReportar;

  @override
  State<SeccionApartado> createState() => _SeccionApartadoState();
}

class _SeccionApartadoState extends State<SeccionApartado> {
  final _referencia = TextEditingController();
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _referencia.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final texto = _referencia.text.trim();
    if (texto.length < 3) {
      setState(() => _error = 'Escribe la referencia de tu transferencia.');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await widget.alReportar(texto);
      if (mounted) _referencia.clear();
    } catch (error) {
      if (mounted) setState(() => _error = errorDeReserva(error).mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final apartado = widget.cita.apartado;
    if (apartado == null) return const SizedBox.shrink();
    final moneda = widget.cita.negocio.moneda;
    final pendiente =
        apartado.estado == EstadoApartado.pendiente && widget.cita.activa;

    return TarjetaPublica(
      color: const Color(0xFFFFFBF2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.savings_outlined, color: Marca.dorado),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Apartado: ${formatoMoneda(apartado.monto, moneda)}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                textoEstadoApartado(apartado),
                style: TextStyle(
                  color: colorEstadoApartado(apartado),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (pendiente && !apartado.enRevision) ...[
            const SizedBox(height: 8),
            const Text(
              'Para asegurar tu cita, transfiere el apartado. '
              'Se descuenta del total del servicio.',
            ),
            const SizedBox(height: 8),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.timer_outlined, size: 18, color: Marca.naranja),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    avisoVencimientoApartado,
                    style: TextStyle(
                      color: Marca.naranja,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (pendiente && apartado.instrucciones.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Marca.borde),
              ),
              child: SelectableText(
                apartado.instrucciones,
                style: const TextStyle(height: 1.4),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => copiarTexto(
                  context,
                  apartado.instrucciones,
                  'Datos de la transferencia copiados.',
                ),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copiar datos'),
              ),
            ),
          ],
          if (apartado.enRevision) ...[
            const SizedBox(height: 8),
            Text(
              'Recibimos tu referencia (${apartado.referencia}). '
              'El negocio confirmará tu pago pronto.',
            ),
          ],
          if (pendiente) ...[
            const SizedBox(height: 12),
            TextField(
              key: const Key('apartado-referencia'),
              controller: _referencia,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _enviar(),
              decoration: InputDecoration(
                labelText: apartado.enRevision
                    ? 'Corregir referencia'
                    : 'Ya transferí: referencia',
                hintText: 'Número de referencia o comprobante',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                key: const Key('apartado-enviar'),
                onPressed: _enviando ? null : _enviar,
                child: _enviando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enviar referencia'),
              ),
            ),
          ],
          if (apartado.politica.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              apartado.politica,
              style: const TextStyle(color: Marca.textoSuave, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

void copiarTexto(BuildContext context, String texto, String aviso) {
  Clipboard.setData(ClipboardData(text: texto));
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(aviso)));
}

/// Abre un enlace en otra pestaña o en la app correspondiente.
Future<void> abrirEnlace(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  var abierto = false;
  try {
    abierto = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
  } catch (_) {
    abierto = false;
  }
  if (!abierto) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No se pudo abrir el enlace.')),
    );
  }
}

/// "Agregar al calendario" y "Escríbenos por WhatsApp".
class AccionesCita extends StatelessWidget {
  const AccionesCita({
    super.key,
    required this.cita,
    required this.enlaceMiCita,
    this.conCalendario = true,
  });

  final CitaPublica cita;
  final String enlaceMiCita;
  final bool conCalendario;

  void _calendario(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (contexto) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.event_available),
              title: const Text('Google Calendar'),
              onTap: () {
                Navigator.of(contexto).pop();
                abrirEnlace(
                  context,
                  enlaceGoogleCalendar(cita, enlaceMiCita: enlaceMiCita),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Apple, Outlook u otro (.ics)'),
              onTap: () {
                Navigator.of(contexto).pop();
                final ok = descargarArchivo(
                  'cita-${cita.negocio.slug}.ics',
                  contenidoIcs(cita, enlaceMiCita: enlaceMiCita),
                  'text/calendar;charset=utf-8',
                );
                if (!ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'La descarga solo funciona en el navegador.',
                      ),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final whatsapp = enlaceWhatsAppNegocio(
      cita.negocio.telefono,
      mensajeWhatsAppCita(cita, enlaceMiCita: enlaceMiCita),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (conCalendario)
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              key: const Key('accion-calendario'),
              onPressed: () {
                // En web hay dos opciones; en el teléfono, Google Calendar.
                if (kIsWeb) {
                  _calendario(context);
                } else {
                  abrirEnlace(
                    context,
                    enlaceGoogleCalendar(cita, enlaceMiCita: enlaceMiCita),
                  );
                }
              },
              icon: const Icon(Icons.calendar_month),
              label: const Text('Agregar al calendario'),
            ),
          ),
        if (whatsapp != null) ...[
          if (conCalendario) const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              key: const Key('accion-whatsapp'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Marca.verde,
                side: const BorderSide(color: Marca.verde, width: 1.5),
              ),
              onPressed: () => abrirEnlace(context, whatsapp),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('Escríbenos por WhatsApp'),
            ),
          ),
        ],
      ],
    );
  }
}

/// Fecha (tira de días) + horas disponibles (chips).
///
/// Cambiar [version] vuelve a pedir las horas del día elegido y borra la
/// hora seleccionada (p. ej. tras un 23P01).
class SelectorFechaHora extends StatefulWidget {
  const SelectorFechaHora({
    super.key,
    required this.catalogo,
    required this.cargarHoras,
    required this.alCambiar,
    this.version = 0,
    this.fechaInicial,
    this.horaInicial,
  });

  final CatalogoReserva catalogo;
  final Future<List<HoraDisponible>> Function(DateTime fecha) cargarHoras;
  final void Function(DateTime? fecha, HoraDisponible? hora) alCambiar;
  final int version;
  final DateTime? fechaInicial;
  final String? horaInicial;

  @override
  State<SelectorFechaHora> createState() => _SelectorFechaHoraState();
}

const _diasCortos = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const _mesesCortos = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

class _SelectorFechaHoraState extends State<SelectorFechaHora> {
  DateTime? _fecha;
  String? _hora;
  List<HoraDisponible>? _horas;
  bool _cargando = false;
  String? _error;
  int _pedido = 0;

  @override
  void initState() {
    super.initState();
    final dias = widget.catalogo.dias;
    _fecha =
        widget.fechaInicial ?? dias.where(widget.catalogo.abre).firstOrNull;
    _hora = widget.horaInicial;
    if (_fecha != null) _cargar(inicial: true);
  }

  @override
  void didUpdateWidget(SelectorFechaHora anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.version != widget.version && _fecha != null) {
      _hora = null;
      _cargar();
    }
  }

  Future<void> _cargar({bool inicial = false}) async {
    final fecha = _fecha!;
    final pedido = ++_pedido;
    void empezar() {
      _cargando = true;
      _error = null;
      _horas = null;
    }

    // En initState todavía no se puede llamar setState.
    inicial ? empezar() : setState(empezar);
    try {
      final horas = await widget.cargarHoras(fecha);
      if (!mounted || pedido != _pedido) return;
      setState(() {
        _horas = horas;
        if (!horas.any((h) => h.horaInicio == _hora)) _hora = null;
      });
      _avisar();
    } catch (error) {
      if (!mounted || pedido != _pedido) return;
      setState(() => _error = errorDeReserva(error).mensaje);
    } finally {
      if (mounted && pedido == _pedido) setState(() => _cargando = false);
    }
  }

  void _avisar() {
    final hora = _horas?.where((h) => h.horaInicio == _hora).firstOrNull;
    widget.alCambiar(_fecha, hora);
  }

  void _elegirFecha(DateTime fecha) {
    if (fecha == _fecha) return;
    setState(() {
      _fecha = fecha;
      _hora = null;
    });
    widget.alCambiar(fecha, null);
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final catalogo = widget.catalogo;
    final dias = catalogo.dias;
    final hayDiasAbiertos = dias.any(catalogo.abre);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _fecha == null ? 'Elige un día' : formatoFechaLarga(_fecha!),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        if (!hayDiasAbiertos)
          const Text('Este negocio no tiene horario de atención publicado.')
        else
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: dias.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final dia = dias[i];
                final abre = catalogo.abre(dia);
                final elegido = dia == _fecha;
                return _ChipDia(
                  key: Key('dia-${formatoFechaIso(dia)}'),
                  dia: dia,
                  hoy: i == 0,
                  habilitado: abre,
                  elegido: elegido,
                  onTap: abre ? () => _elegirFecha(dia) : null,
                );
              },
            ),
          ),
        const SizedBox(height: 18),
        if (_fecha != null) ...[
          const Text(
            'Horas disponibles',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (_cargando)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            ErrorPublico(mensaje: _error!, alReintentar: _cargar)
          else if (_horas != null && _horas!.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No quedan horas libres este día. Prueba con otra fecha.',
                style: TextStyle(color: Marca.textoSuave),
              ),
            )
          else if (_horas != null)
            LayoutBuilder(
              builder: (context, restricciones) {
                // 3 columnas en celular, 4 en pantallas más anchas.
                final columnas = restricciones.maxWidth >= 440 ? 4 : 3;
                final ancho =
                    (restricciones.maxWidth - (columnas - 1) * 8) / columnas;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final hora in _horas!)
                      SizedBox(
                        width: ancho,
                        height: 46,
                        child: _ChipHora(
                          key: Key('hora-${hora.horaInicio}'),
                          texto: formatoHora(hora.horaInicio),
                          elegido: hora.horaInicio == _hora,
                          onTap: () {
                            setState(() => _hora = hora.horaInicio);
                            _avisar();
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ],
    );
  }
}

class _ChipDia extends StatelessWidget {
  const _ChipDia({
    super.key,
    required this.dia,
    required this.hoy,
    required this.habilitado,
    required this.elegido,
    required this.onTap,
  });

  final DateTime dia;
  final bool hoy;
  final bool habilitado;
  final bool elegido;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorTexto = elegido
        ? Colors.white
        : habilitado
        ? Marca.texto
        : Marca.textoSuave.withValues(alpha: 0.5);
    return Semantics(
      button: true,
      enabled: habilitado,
      selected: elegido,
      label: habilitado
          ? formatoFechaLarga(dia)
          : '${formatoFechaLarga(dia)}, cerrado',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 58,
          decoration: BoxDecoration(
            color: elegido
                ? Marca.negro
                : habilitado
                ? Colors.white
                : Marca.fondo,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: elegido ? Marca.negro : Marca.borde),
          ),
          child: ExcludeSemantics(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  hoy ? 'Hoy' : _diasCortos[dia.weekday - 1],
                  style: TextStyle(fontSize: 12, color: colorTexto),
                ),
                Text(
                  '${dia.day}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colorTexto,
                    decoration: habilitado ? null : TextDecoration.lineThrough,
                  ),
                ),
                Text(
                  _mesesCortos[dia.month - 1],
                  style: TextStyle(fontSize: 11, color: colorTexto),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChipHora extends StatelessWidget {
  const _ChipHora({
    super.key,
    required this.texto,
    required this.elegido,
    required this.onTap,
  });

  final String texto;
  final bool elegido;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: elegido ? const Color(0xFFFFF6E0) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: elegido ? Marca.dorado : Marca.borde,
          width: elegido ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Center(
          child: Text(
            texto,
            style: TextStyle(
              fontWeight: elegido ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
