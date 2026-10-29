import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/app.dart';
import 'package:barberiapro/models/reserva.dart';
import 'package:barberiapro/services/reserva_repository.dart';
import 'package:barberiapro/utils/enlace_publico.dart';
import 'package:barberiapro/utils/enlaces_cita.dart';
import 'package:barberiapro/utils/formato.dart';

// Lunes 26 de octubre de 2026; el negocio cierra los domingos.
final _hoy = DateTime(2026, 10, 26);

Map<String, dynamic> _negocio() => {
  'nombre': 'El Jefe',
  'slug': 'el-jefe',
  'telefono': '809-555-1234',
  'direccion': 'Calle Principal #123, Santo Domingo',
  'moneda': 'DOP',
  'zona_horaria': 'America/Santo_Domingo',
  'apartado_requerido': true,
  'apartado_monto': 100,
  'apartado_politica': 'El apartado se descuenta del total del servicio.',
  'apartado_instrucciones': 'Banco Popular, cuenta 123-456',
  'cancelacion_horas_minimas': 24,
};

Map<String, dynamic> _catalogo() => {
  'negocio': _negocio(),
  'hoy': formatoFechaIso(_hoy),
  'fecha_maxima': formatoFechaIso(DateTime(2026, 10, 26 + 60)),
  'servicios': [
    {'id': 's1', 'nombre': 'Corte', 'precio': 500, 'duracion_minutos': 30},
    {'id': 's2', 'nombre': 'Barba', 'precio': 250, 'duracion_minutos': 15},
  ],
  'empleados': [
    {'id': 'b1', 'nombre': 'Luis', 'servicio_ids': null},
    {
      'id': 'b2',
      'nombre': 'Pedro',
      'servicio_ids': ['s2'],
    },
  ],
  'horarios': [
    for (var d = 1; d <= 6; d++)
      {'dia_semana': d, 'hora_apertura': '09:00', 'hora_cierre': '18:00'},
  ],
};

Map<String, dynamic> _citaMap({
  String estado = 'PENDIENTE',
  String referencia = '',
  bool puede = true,
  String fecha = '2026-10-30',
  String hora = '15:00',
}) => {
  'cita_id': 'c1',
  'token_publico': 'tok-9',
  'estado': estado,
  'fecha': fecha,
  'hora_inicio': hora,
  'hora_fin': '15:30',
  'precio': 500,
  'servicio': {'id': 's1', 'nombre': 'Corte', 'duracion_minutos': 30},
  'barbero': {'id': 'b1', 'nombre': 'Luis', 'foto': null},
  'negocio': _negocio(),
  'apartado': {
    'estado': estado == 'CANCELADA' ? 'CANCELADO' : 'PENDIENTE',
    'monto': 100,
    'metodo_pago': null,
    'referencia': referencia.isEmpty ? null : referencia,
    'instrucciones': 'Banco Popular, cuenta 123-456',
    'politica': 'El apartado se descuenta del total del servicio.',
  },
  'limite_cambios': '2026-10-29T15:00:00',
  'puede_cancelar': puede,
  'puede_reprogramar': puede,
};

class _FakeReservaRepository implements ReservaRepository {
  List<String> horas = ['09:00', '10:00', '10:30'];
  final Set<String> tomadas = {};
  int consultasHoras = 0;
  String? ultimoToken;
  bool? ultimaAcepta;
  String? ultimoEmpleado;
  Map<String, Object?>? reserva;
  bool cancelada = false;
  String referencia = '';
  String? reprogramadaA;

  @override
  Future<CatalogoReserva> catalogo(String slug) async {
    if (slug != 'el-jefe') {
      throw const ReservaError(
        'No encontramos esta barbería. Revisa el enlace.',
      );
    }
    return CatalogoReserva.fromMap(_catalogo());
  }

  @override
  Future<List<HoraDisponible>> horasDisponibles({
    required String slug,
    required String servicioId,
    required DateTime fecha,
    String? empleadoId,
    String? token,
  }) async {
    consultasHoras++;
    ultimoToken = token;
    ultimoEmpleado = empleadoId;
    return [
      for (final h in horas)
        HoraDisponible(horaInicio: h, empleadoId: empleadoId ?? 'b1'),
    ];
  }

  @override
  Future<Map<String, dynamic>> crear({
    required String slug,
    required String servicioId,
    String? empleadoId,
    required DateTime fecha,
    required String horaInicio,
    required String nombre,
    required String telefono,
    String? email,
    String? notas,
    bool aceptaPrivacidad = false,
  }) async {
    ultimaAcepta = aceptaPrivacidad;
    if (tomadas.contains(horaInicio)) {
      horas.remove(horaInicio);
      throw const ReservaError(
        'Esa hora acaba de ser reservada por otra persona. Elige otra.',
        horaNoDisponible: true,
      );
    }
    reserva = {
      'servicio': servicioId,
      'empleado': empleadoId,
      'fecha': formatoFechaIso(fecha),
      'hora': horaInicio,
      'nombre': nombre,
      'telefono': telefono,
      'email': email,
    };
    return {
      'cita_id': 'c1',
      'token_publico': 'tok-1',
      'estado': 'PENDIENTE',
      'empleado_id': 'b1',
      'fecha': formatoFechaIso(fecha),
      'hora_inicio': horaInicio,
      'hora_fin': '10:30',
      'precio': 500,
      'apartado': {
        'monto': 100,
        'instrucciones': 'Banco Popular, cuenta 123-456',
        'politica': 'El apartado se descuenta del total del servicio.',
      },
    };
  }

  @override
  Future<CitaPublica> consultar(String token) async {
    if (token != 'tok-9' && token != 'tok-1') {
      throw const ReservaError('No encontramos esta cita. Revisa el enlace.');
    }
    return CitaPublica.fromMap(
      _citaMap(
        estado: cancelada ? 'CANCELADA' : 'PENDIENTE',
        referencia: referencia,
        puede: !cancelada,
      ),
    );
  }

  @override
  Future<CitaPublica> cancelar(String token) async {
    cancelada = true;
    return consultar(token);
  }

  @override
  Future<CitaPublica> reprogramar({
    required String token,
    required DateTime fecha,
    required String horaInicio,
  }) async {
    reprogramadaA = '${formatoFechaIso(fecha)} $horaInicio';
    return CitaPublica.fromMap(
      _citaMap(fecha: formatoFechaIso(fecha), hora: horaInicio),
    );
  }

  @override
  Future<CitaPublica> reportarPago({
    required String token,
    required String referencia,
  }) async {
    this.referencia = referencia;
    return CitaPublica.fromMap(_citaMap(referencia: referencia));
  }
}

void _celular(WidgetTester tester) {
  // Celular alto para no depender del desplazamiento en las pruebas.
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _abrir(
  WidgetTester tester,
  String ruta,
  _FakeReservaRepository repo,
) async {
  _celular(tester);
  await tester.pumpWidget(
    BarberiaApp(
      supabaseConfigured: false,
      rutaInicial: ruta,
      reservaRepository: repo,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _hastaResumen(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('reservar-cita')));
  await tester.pumpAndSettle();
  expect(find.text('Paso 1 de 5'), findsOneWidget);
  await tester.tap(find.byKey(const Key('servicio-s1')));
  await tester.pumpAndSettle();

  // Pedro no hace "Corte": solo aparece Luis y "Cualquiera disponible".
  expect(find.byKey(const Key('barbero-b2')), findsNothing);
  await tester.tap(find.byKey(const Key('barbero-cualquiera')));
  await tester.pumpAndSettle();

  // Domingo 1 de noviembre: cerrado.
  await tester.drag(
    find.byKey(const Key('dia-2026-10-28')),
    const Offset(-200, 0),
  );
  await tester.pumpAndSettle();
  final domingo = tester.widget<InkWell>(
    find.descendant(
      of: find.byKey(const Key('dia-2026-11-01')),
      matching: find.byType(InkWell),
    ),
  );
  expect(domingo.onTap, isNull);
  await tester.tap(find.byKey(const Key('hora-10:00')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('continuar-hora')));
  await tester.pumpAndSettle();

  // Validación de datos.
  await tester.tap(find.byKey(const Key('continuar-datos')));
  await tester.pumpAndSettle();
  expect(find.text('Escribe tu nombre.'), findsOneWidget);
  expect(find.text('Escribe un teléfono válido.'), findsOneWidget);

  await tester.enterText(find.byKey(const Key('reserva-nombre')), 'Juan Pérez');
  await tester.enterText(
    find.byKey(const Key('reserva-telefono')),
    '809-555-7777',
  );

  // Sin aceptar la privacidad no se avanza.
  await tester.tap(find.byKey(const Key('continuar-datos')));
  await tester.pumpAndSettle();
  expect(find.text('Debes aceptar la política de privacidad.'), findsOneWidget);
  expect(find.byKey(const Key('confirmar-reserva')), findsNothing);

  final casilla = find.descendant(
    of: find.byKey(const Key('reserva-consentimiento')),
    matching: find.byType(Checkbox),
  );
  await tester.ensureVisible(casilla);
  await tester.tap(casilla);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('continuar-datos')));
  await tester.pumpAndSettle();
}

void main() {
  group('Reserva pública', () {
    testWidgets('portada del negocio por el enlace público', (tester) async {
      final repo = _FakeReservaRepository();
      await _abrir(tester, '/reservar/el-jefe', repo);

      expect(find.text('El Jefe'), findsOneWidget);
      expect(find.text('Calle Principal #123, Santo Domingo'), findsOneWidget);
      expect(find.text(r'RD$500'), findsOneWidget);
      expect(find.text('Domingo'), findsOneWidget);
      expect(find.text('Cerrado'), findsOneWidget);
    });

    testWidgets('slug inexistente muestra el mensaje del servidor', (
      tester,
    ) async {
      await _abrir(tester, '/reservar/otro', _FakeReservaRepository());
      expect(
        find.text('No encontramos esta barbería. Revisa el enlace.'),
        findsOneWidget,
      );
    });

    testWidgets('flujo completo: reserva, apartado y referencia', (
      tester,
    ) async {
      final repo = _FakeReservaRepository();
      await _abrir(tester, '/reservar/el-jefe', repo);
      await _hastaResumen(tester);

      expect(find.text('Confirma tu cita'), findsOneWidget);
      expect(find.text('Luis'), findsOneWidget); // asignado a esa hora
      expect(find.text('10:00 AM'), findsOneWidget);
      expect(find.text(r'RD$100'), findsOneWidget);
      expect(find.text(r'RD$400'), findsOneWidget); // en el local
      expect(find.textContaining('hasta 24 horas antes'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirmar-reserva')));
      await tester.pumpAndSettle();

      expect(find.text('¡Cita reservada!'), findsOneWidget);
      expect(repo.reserva?['servicio'], 's1');
      expect(repo.reserva?['empleado'], isNull); // cualquiera disponible
      expect(repo.reserva?['hora'], '10:00');
      expect(repo.reserva?['nombre'], 'Juan Pérez');
      expect(repo.reserva?['email'], isNull);
      expect(find.text('Banco Popular, cuenta 123-456'), findsOneWidget);
      expect(find.textContaining('próximas 3 horas'), findsOneWidget);
      expect(find.text('/#/cita/tok-1'), findsOneWidget);
      expect(find.byKey(const Key('accion-calendario')), findsOneWidget);
      expect(find.byKey(const Key('accion-whatsapp')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('apartado-referencia')),
        'REF-2026',
      );
      await tester.tap(find.byKey(const Key('apartado-enviar')));
      await tester.pumpAndSettle();

      expect(repo.referencia, 'REF-2026');
      expect(find.textContaining('Recibimos tu referencia'), findsOneWidget);
      expect(find.text('en revisión'), findsWidgets);
    });

    testWidgets('hora tomada (23P01) vuelve a las horas y las recarga', (
      tester,
    ) async {
      final repo = _FakeReservaRepository()..tomadas.add('10:00');
      await _abrir(tester, '/reservar/el-jefe', repo);
      await _hastaResumen(tester);
      final consultasAntes = repo.consultasHoras;

      await tester.tap(find.byKey(const Key('confirmar-reserva')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Esa hora acaba de ser reservada por otra persona. Elige otra.',
        ),
        findsOneWidget,
      );
      expect(find.text('¿Cuándo?'), findsOneWidget);
      expect(repo.consultasHoras, greaterThan(consultasAntes));
      expect(find.byKey(const Key('hora-10:00')), findsNothing);
      expect(find.byKey(const Key('hora-10:30')), findsOneWidget);
      expect(repo.reserva, isNull);

      // Elige otra hora y reserva.
      await tester.tap(find.byKey(const Key('hora-10:30')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('continuar-hora')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('continuar-datos')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmar-reserva')));
      await tester.pumpAndSettle();

      expect(find.text('¡Cita reservada!'), findsOneWidget);
      expect(repo.reserva?['hora'], '10:30');
    });
  });

  group('Mi cita', () {
    testWidgets('muestra la cita y la cancela con confirmación', (
      tester,
    ) async {
      final repo = _FakeReservaRepository();
      await _abrir(tester, '/cita/tok-9', repo);

      expect(find.text('Mi cita'), findsOneWidget);
      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.text('Viernes 30 de octubre'), findsOneWidget);
      expect(find.text('3:00 PM'), findsOneWidget);
      expect(
        find.textContaining('hasta el jueves 29 de octubre, 3:00 PM'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('mi-cita-cancelar')));
      await tester.pumpAndSettle();
      expect(find.text('¿Cancelar tu cita?'), findsOneWidget);
      await tester.tap(find.text('No, mantener'));
      await tester.pumpAndSettle();
      expect(repo.cancelada, isFalse);

      await tester.tap(find.byKey(const Key('mi-cita-cancelar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmar-cancelar')));
      await tester.pumpAndSettle();

      expect(repo.cancelada, isTrue);
      expect(find.text('Cancelada'), findsOneWidget);
      expect(find.text('Esta cita fue cancelada.'), findsOneWidget);
      expect(find.byKey(const Key('mi-cita-cancelar')), findsNothing);
      expect(find.byKey(const Key('mi-cita-reprogramar')), findsNothing);
      expect(find.byKey(const Key('accion-calendario')), findsNothing);
    });

    testWidgets('reprograma pidiendo horas con el token de la cita', (
      tester,
    ) async {
      final repo = _FakeReservaRepository();
      await _abrir(tester, '/cita/tok-9', repo);

      await tester.tap(find.byKey(const Key('mi-cita-reprogramar')));
      await tester.pumpAndSettle();

      expect(repo.ultimoToken, 'tok-9');
      expect(repo.ultimoEmpleado, 'b1');
      await tester.tap(find.byKey(const Key('hora-10:30')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmar-reprogramar')));
      await tester.pumpAndSettle();

      expect(repo.reprogramadaA, '2026-10-30 10:30');
      expect(find.text('10:30 AM'), findsOneWidget);
    });

    testWidgets('token desconocido muestra el error', (tester) async {
      await _abrir(tester, '/cita/otro', _FakeReservaRepository());
      expect(
        find.text('No encontramos esta cita. Revisa el enlace.'),
        findsOneWidget,
      );
    });
  });

  group('Enlaces', () {
    final cita = CitaPublica.fromMap(_citaMap());

    test('rutas públicas y enlace de "Mi cita"', () {
      expect(rutaCita('abc'), '/#/cita/abc');
      expect(
        enlaceCita(
          'abc',
          base: Uri.parse('https://app.com/barberia/index.html'),
        ),
        'https://app.com/barberia/#/cita/abc',
      );
      expect(enlaceCita('abc'), '/#/cita/abc');

      final reserva = RutaPublica.desde('/reservar/El-Jefe');
      expect(reserva, isA<RutaReserva>());
      expect((reserva as RutaReserva).slug, 'el-jefe');
      final miCita = RutaPublica.desde('#/cita/tok-9?x=1');
      expect((miCita as RutaCita).token, 'tok-9');
      expect(RutaPublica.desde('/'), isNull);
      expect(RutaPublica.desde('/reservar/'), isNull);
      expect(RutaPublica.desde('/agenda/x'), isNull);
      expect(RutaPublica.desde('/cita/%E0%A4%A'), isNull);
    });

    test('Google Calendar con hora del negocio', () {
      final url = Uri.parse(enlaceGoogleCalendar(cita, enlaceMiCita: 'L'));
      expect(url.host, 'calendar.google.com');
      expect(url.path, '/calendar/render');
      expect(url.queryParameters['action'], 'TEMPLATE');
      expect(url.queryParameters['text'], 'Corte en El Jefe');
      expect(url.queryParameters['dates'], '20261030T150000/20261030T153000');
      expect(url.queryParameters['ctz'], 'America/Santo_Domingo');
      expect(url.queryParameters['location'], contains('Calle Principal'));
      expect(url.queryParameters['details'], contains('Luis'));
    });

    test('archivo .ics en UTC para Santo Domingo', () {
      final ics = contenidoIcs(cita, ahora: DateTime.utc(2026, 10, 1));
      expect(ics, contains('DTSTART:20261030T190000Z'));
      expect(ics, contains('DTEND:20261030T193000Z'));
      expect(ics, contains('SUMMARY:Corte en El Jefe'));
      expect(ics, contains(r'LOCATION:Calle Principal #123\, Santo Domingo'));
      expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
    });

    test('WhatsApp: solo dígitos y 1 delante si tiene 10', () {
      expect(enlaceWhatsAppNegocio('', 'hola'), isNull);
      expect(enlaceWhatsAppNegocio('123', 'hola'), isNull);
      expect(
        enlaceWhatsAppNegocio('+1 (829) 555-1234', 'hola'),
        'https://wa.me/18295551234?text=hola',
      );

      final url = enlaceWhatsAppNegocio(
        '809-555-1234',
        mensajeWhatsAppCita(cita, enlaceMiCita: 'https://x.com/#/cita/tok-9'),
      )!;
      expect(url, startsWith('https://wa.me/18095551234?text='));
      final texto = Uri.parse(url).queryParameters['text']!;
      expect(texto, contains('El Jefe'));
      expect(texto, contains('viernes 30 de octubre'));
      expect(texto, contains('3:00 PM'));
      expect(texto, contains('https://x.com/#/cita/tok-9'));
    });
  });
}
