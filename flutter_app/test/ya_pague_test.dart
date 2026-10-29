import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/services/plataforma_repository.dart';
import 'package:barberiapro/utils/fotos.dart';
import 'package:barberiapro/widgets/ya_pague_dialog.dart';

void main() {
  test('el mensaje de pago lleva negocio, plan, referencia y recibo', () {
    final mensaje = mensajePago(
      negocio: 'STIKING',
      plan: 'Barbería',
      precio: 900,
      referencia: ' 123456 ',
      reciboUrl: 'https://x.supabase.co/recibo.jpg',
    );
    expect(mensaje, contains('Negocio: STIKING'));
    expect(mensaje, contains('Plan: Barbería (RD\$900 al mes)'));
    expect(mensaje, contains('Referencia: 123456'));
    expect(mensaje, contains('Recibo: https://x.supabase.co/recibo.jpg'));
  });

  testWidgets('Ya pagué sube el recibo, avisa al panel y abre WhatsApp', (
    tester,
  ) async {
    final soporte = _Soporte();
    Uri? abierto;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => mostrarYaPague(
                context,
                soporte: soporte,
                negocioId: 'n1',
                negocioNombre: 'STIKING',
                subirRecibo: (_) async => 'https://x/recibo.jpg',
                elegirFoto: () async =>
                    FotoElegida(Uint8List(8), 'image/jpeg'),
                abrirEnlace: (enlace) async {
                  abierto = enlace;
                  return true;
                },
                whatsapp: '8095550000',
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('plan-pro')));
    await tester.enterText(find.byKey(const Key('pago-referencia')), '777');
    await tester.tap(find.byKey(const Key('pago-recibo')));
    await tester.pumpAndSettle();
    expect(find.text('Recibo adjunto'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pago-enviar')));
    await tester.pumpAndSettle();

    expect(soporte.mensajes.single, contains('Plan: Pro (RD\$1600 al mes)'));
    expect(soporte.contextos.single['tipo'], 'PAGO');
    expect(abierto.toString(), startsWith('https://wa.me/18095550000?text='));
    expect(Uri.decodeComponent(abierto.toString()), contains('Referencia: 777'));
    expect(find.textContaining('Recibimos tu aviso de pago'), findsOneWidget);
  });
}

class _Soporte implements SoporteRepository {
  final mensajes = <String>[];
  final contextos = <Map<String, Object?>>[];

  @override
  Future<void> enviar({
    required String negocioId,
    required String mensaje,
    required Map<String, Object?> contexto,
  }) async {
    mensajes.add(mensaje);
    contextos.add(contexto);
  }
}
