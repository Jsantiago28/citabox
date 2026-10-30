import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/pages/historial_page.dart';
import 'package:barberiapro/services/historial.dart';
import 'package:barberiapro/services/historial_repository.dart';

RegistroAuditoria _reg(
  String tabla,
  String accion, {
  Map<String, dynamic>? antes,
  Map<String, dynamic>? despues,
  String? quien,
  String id = '1',
}) => RegistroAuditoria(
  id: id,
  tabla: tabla,
  filaId: 'f1',
  accion: accion,
  antes: antes,
  despues: despues,
  usuarioNombre: quien,
  fecha: DateTime(2026, 10, 29, 15),
);

void main() {
  group('describirCambio', () {
    test('cita completada con precio y propina', () {
      final texto = describirCambio(
        _reg(
          'citas',
          'UPDATE',
          quien: 'Luis',
          antes: {
            'estado': 'CONFIRMADA',
            'precio': 500,
            'propina': 0,
            'hora_inicio': '15:00:00',
            'fecha': '2026-10-29',
            'updated_at': 'a',
          },
          despues: {
            'estado': 'COMPLETADA',
            'precio': '450.00',
            'propina': 100,
            'hora_inicio': '15:00:00',
            'fecha': '2026-10-29',
            'updated_at': 'b',
          },
        ),
      );
      expect(
        texto,
        r'Luis completó la cita de las 3:00 PM (precio RD$500 → RD$450, propina RD$100)',
      );
    });

    test('cita cancelada', () {
      final base = {'hora_inicio': '16:00:00', 'fecha': '2026-10-30'};
      expect(
        describirCambio(
          _reg(
            'citas',
            'UPDATE',
            quien: 'María',
            antes: {...base, 'estado': 'PENDIENTE'},
            despues: {...base, 'estado': 'CANCELADA'},
          ),
        ),
        'María canceló la cita del 30/10 4:00 PM',
      );
    });

    test('cambio de precio de un servicio', () {
      expect(
        describirCambio(
          _reg(
            'servicios',
            'UPDATE',
            quien: 'Dueño',
            antes: {'nombre': 'Corte', 'precio': 300},
            despues: {'nombre': 'Corte', 'precio': 350},
          ),
        ),
        r'Dueño cambió el servicio Corte (precio RD$300 → RD$350)',
      );
    });

    test('cliente desactivado', () {
      expect(
        describirCambio(
          _reg(
            'clientes',
            'UPDATE',
            quien: 'Dueño',
            antes: {'nombre': 'Pedro', 'activo': true},
            despues: {'nombre': 'Pedro', 'activo': false},
          ),
        ),
        'Dueño desactivó al cliente Pedro',
      );
    });

    test('reserva pública y apartado validado', () {
      expect(
        describirCambio(
          _reg(
            'citas',
            'INSERT',
            despues: {
              'origen': 'PUBLICA',
              'fecha': '2026-10-31',
              'hora_inicio': '10:00:00',
            },
          ),
        ),
        'Reserva en línea creada para el 31/10 10:00 AM',
      );
      expect(
        describirCambio(
          _reg(
            'apartados',
            'UPDATE',
            antes: {'estado': 'PENDIENTE', 'monto': 100},
            despues: {'estado': 'PAGADO', 'monto': 100},
          ),
        ),
        r'Apartado validado: RD$100',
      );
    });

    test('ignora cambios que solo tocan updated_at', () {
      expect(
        camposCambiados(
          {'updated_at': 'a', 'nombre': 'X'},
          {'updated_at': 'b', 'nombre': 'X'},
        ),
        isEmpty,
      );
    });
  });

  group('HistorialPage', () {
    testWidgets('filtra por tipo y muestra el detalle', (tester) async {
      final repo = _FakeHistorial();
      await tester.pumpWidget(
        MaterialApp(
          home: HistorialPage(negocioId: 'n1', repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dueño desactivó al cliente Pedro'), findsOneWidget);
      expect(find.textContaining('Reserva en línea creada'), findsOneWidget);
      expect(find.textContaining('Sistema / reserva en línea'), findsOneWidget);

      await tester.tap(find.byKey(const Key('historial-filtro-clientes')));
      await tester.pumpAndSettle();
      expect(repo.ultimaTabla, 'clientes');
      expect(find.text('Dueño desactivó al cliente Pedro'), findsOneWidget);
      expect(find.textContaining('Reserva en línea creada'), findsNothing);

      await tester.tap(find.text('Ver detalle'));
      await tester.pumpAndSettle();
      expect(find.text('Antes'), findsOneWidget);
      expect(find.text('Después'), findsOneWidget);
      expect(find.text('activo: true'), findsOneWidget);
      expect(find.text('activo: false'), findsOneWidget);
    });
  });
}

class _FakeHistorial implements HistorialRepository {
  String? ultimaTabla;

  @override
  Future<PaginaHistorial> listar(
    String negocioId, {
    int pagina = 0,
    String? tabla,
    String? accion,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    ultimaTabla = tabla;
    final todos = [
      _reg(
        'clientes',
        'UPDATE',
        quien: 'Dueño',
        antes: {'nombre': 'Pedro', 'activo': true},
        despues: {'nombre': 'Pedro', 'activo': false},
        id: '2',
      ),
      _reg(
        'citas',
        'INSERT',
        despues: {
          'origen': 'PUBLICA',
          'fecha': '2026-10-31',
          'hora_inicio': '10:00:00',
        },
      ),
    ];
    return PaginaHistorial(
      registros: [
        for (final r in todos)
          if (tabla == null || r.tabla == tabla) r,
      ],
      hayMas: false,
    );
  }
}
