import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/models/cita.dart';
import 'package:barberiapro/utils/citas_reglas.dart';
import 'package:barberiapro/utils/whatsapp.dart';

void main() {
  group('enlaceWhatsApp', () {
    test('keeps only digits and adds 1 to 10-digit numbers', () {
      expect(telefonoWhatsApp('809-555-1234'), '18095551234');
      expect(telefonoWhatsApp('(829) 555 1234'), '18295551234');
      expect(telefonoWhatsApp('+1 809 555 1234'), '18095551234');
      expect(telefonoWhatsApp('+34 612 345 678'), '34612345678');
      expect(telefonoWhatsApp(''), '');
    });

    test('builds a wa.me link with the encoded message', () {
      final enlace = enlaceWhatsApp(
        '809-555-1234',
        'Hola Ana, ¿a las 3:00 PM?',
      );
      expect(
        enlace,
        'https://wa.me/18095551234?text='
        'Hola%20Ana%2C%20%C2%BFa%20las%203%3A00%20PM%3F',
      );
      expect(
        Uri.parse(enlace).queryParameters['text'],
        'Hola Ana, ¿a las 3:00 PM?',
      );
      expect(enlaceWhatsApp('', 'Hola'), 'https://wa.me/?text=Hola');
    });

    test('invitation to book names the business and the link', () {
      expect(
        mensajeInvitarReservar(
          negocio: ' Salón Brillo ',
          enlace: 'https://citabox.pages.dev/r/salon-brillo',
        ),
        '¡Ya puedes reservar tu cita en Salón Brillo desde tu celular! '
        'Escoge el servicio, con quién y la hora que te convenga, en menos de '
        'un minuto y sin esperar respuesta: '
        'https://citabox.pages.dev/r/salon-brillo',
      );
    });

    test('reminder message reads naturally', () {
      expect(
        mensajeRecordatorio(
          cliente: 'Ana López',
          negocio: 'Barbería Central',
          fecha: DateTime(2026, 10, 30),
          hora: '15:00:00',
          servicio: 'Corte',
          barbero: 'Luis',
        ),
        'Hola Ana López, te recordamos tu cita en Barbería Central el '
        'viernes 30 de octubre a las 3:00 PM para Corte con Luis. '
        '¡Te esperamos!',
      );
      expect(
        mensajeRecordatorio(
          cliente: 'Ana',
          negocio: 'Barbería Central',
          fecha: DateTime(2026, 10, 26),
          hora: '09:05:00',
          servicio: 'Barba',
        ),
        'Hola Ana, te recordamos tu cita en Barbería Central el lunes 26 de '
        'octubre a las 9:05 AM para Barba. ¡Te esperamos!',
      );
    });
  });

  group('Atender ahora', () {
    test('rounds the current time down to 5 minutes', () {
      expect(redondearACincoMinutos(DateTime(2026, 10, 28, 14, 37)), 875);
      expect(redondearACincoMinutos(DateTime(2026, 10, 28, 9, 0)), 540);
      expect(redondearACincoMinutos(DateTime(2026, 10, 28, 9, 4, 59)), 540);
    });

    test('next free time skips back-to-back appointments', () {
      const ocupados = [(840, 885), (885, 900), (960, 1000)];
      // 14:20 con 45 min choca con 14:00–14:45 y luego 14:45–15:00.
      expect(
        siguienteHoraLibre(ocupados: ocupados, desde: 860, duracionMinutos: 45),
        900,
      );
      // 15:00 con 75 min chocaría con 16:00: pasa a 16:40.
      expect(
        siguienteHoraLibre(ocupados: ocupados, desde: 900, duracionMinutos: 75),
        1000,
      );
      // Libre: se queda donde está.
      expect(
        siguienteHoraLibre(ocupados: ocupados, desde: 700, duracionMinutos: 30),
        700,
      );
      // No cabe antes de medianoche.
      expect(
        siguienteHoraLibre(
          ocupados: const [(1380, 1430)],
          desde: 1390,
          duracionMinutos: 30,
        ),
        isNull,
      );
    });
  });

  test('appointment reads phone, payment method and tip', () {
    final cita = Cita.fromMap({
      'id': 'c1',
      'fecha': '2026-10-28',
      'hora_inicio': '10:00:00',
      'precio': '500.00',
      'estado': 'COMPLETADA',
      'metodo_pago': 'TRANSFERENCIA',
      'propina': '50.00',
      'clientes': {'nombre': 'Ana', 'telefono': '809-555-1111'},
    });
    expect(cita.clienteTelefono, '809-555-1111');
    expect(cita.metodoPago, MetodoPago.transferencia);
    expect(cita.propina, 50);

    final sinCobro = Cita.fromMap({
      'id': 'c2',
      'estado': 'PENDIENTE',
      'metodo_pago': null,
      'clientes': {'nombre': 'Pedro', 'telefono': null},
    });
    expect(sinCobro.clienteTelefono, '');
    expect(sinCobro.metodoPago, isNull);
    expect(sinCobro.propina, 0);
    // copyWith conserva el cobro al cambiar solo el estado.
    expect(
      cita.copyWith(estado: EstadoCita.llego).metodoPago,
      MetodoPago.transferencia,
    );
  });
}
