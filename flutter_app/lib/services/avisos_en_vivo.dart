import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

enum TipoAviso { nuevaReserva, citaCancelada, pagoReportado }

class AvisoEnVivo {
  const AvisoEnVivo(this.tipo, this.texto);

  final TipoAviso tipo;
  final String texto;
}

/// Avisos en vivo del negocio. Cerrar con [cerrar] al salir.
abstract interface class AvisosEnVivo {
  Stream<AvisoEnVivo> get avisos;

  Future<void> cerrar();
}

class SupabaseAvisosEnVivo implements AvisosEnVivo {
  SupabaseAvisosEnVivo(
    this._client, {
    required this.negocioId,
    required this.esOwner,
  }) {
    final filtro = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'negocio_id',
      value: negocioId,
    );
    var canal = _client.channel('avisos-$negocioId');
    canal = canal.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'citas',
      filter: filtro,
      callback: (p) => _emitir(avisoDeCitaNueva(p.newRecord)),
    );
    canal = canal.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'citas',
      filter: filtro,
      callback: (p) =>
          _emitir(avisoDeCitaActualizada(p.oldRecord, p.newRecord)),
    );
    if (esOwner) {
      canal = canal.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'apartados',
        filter: filtro,
        callback: (p) =>
            _emitir(avisoDeApartadoActualizado(p.oldRecord, p.newRecord)),
      );
    }
    _canal = canal.subscribe();
  }

  final SupabaseClient _client;
  final String negocioId;
  final bool esOwner;
  late final RealtimeChannel _canal;
  final _controlador = StreamController<AvisoEnVivo>.broadcast();

  void _emitir(AvisoEnVivo? aviso) {
    if (aviso != null && !_controlador.isClosed) _controlador.add(aviso);
  }

  @override
  Stream<AvisoEnVivo> get avisos => _controlador.stream;

  @override
  Future<void> cerrar() async {
    await _controlador.close();
    await _client.removeChannel(_canal);
  }
}

/// INSERT en citas. Los payloads traen ids, no nombres.
AvisoEnVivo avisoDeCitaNueva(Map<String, dynamic> nueva) {
  final hora = _hora(nueva['hora_inicio']);
  final base = nueva['origen'] == 'PUBLICA'
      ? 'Nueva reserva en línea'
      : 'Nueva cita';
  return AvisoEnVivo(
    TipoAviso.nuevaReserva,
    hora.isEmpty ? base : '$base: $hora',
  );
}

/// UPDATE en citas: solo cuando pasa a CANCELADA.
AvisoEnVivo? avisoDeCitaActualizada(
  Map<String, dynamic> vieja,
  Map<String, dynamic> nueva,
) {
  if (nueva['estado'] != 'CANCELADA' || vieja['estado'] == 'CANCELADA') {
    return null;
  }
  return const AvisoEnVivo(TipoAviso.citaCancelada, 'Cita cancelada');
}

/// UPDATE en apartados: la referencia pasa de vacía a un valor.
AvisoEnVivo? avisoDeApartadoActualizado(
  Map<String, dynamic> vieja,
  Map<String, dynamic> nueva,
) {
  final antes = (vieja['referencia'] as String?)?.trim() ?? '';
  final despues = (nueva['referencia'] as String?)?.trim() ?? '';
  if (antes.isNotEmpty || despues.isEmpty) return null;
  return const AvisoEnVivo(
    TipoAviso.pagoReportado,
    'Pago de apartado reportado',
  );
}

String _hora(Object? valor) {
  final t = valor?.toString() ?? '';
  return t.length >= 5 ? t.substring(0, 5) : t;
}
