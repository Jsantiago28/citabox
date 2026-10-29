import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/servicio.dart';
import 'sin_permiso.dart';

abstract interface class ServiciosRepository {
  Future<List<Servicio>> listar(String negocioId);

  /// Crea o actualiza el servicio y devuelve su id.
  Future<String> guardar({
    required String negocioId,
    required Map<String, Object?> datos,
    String? servicioId,
  });

  /// Sube la foto del servicio a Storage y guarda su dirección.
  Future<void> subirFoto({
    required String negocioId,
    required String servicioId,
    required Uint8List bytes,
    required String tipo,
  });

  Future<void> cambiarEstado({
    required String negocioId,
    required String servicioId,
    required bool activo,
  });

  /// Crea de una vez los servicios elegidos del catálogo sugerido.
  Future<void> crearVarios({
    required String negocioId,
    required List<Map<String, Object?>> servicios,
  });
}

class SupabaseServiciosRepository implements ServiciosRepository {
  const SupabaseServiciosRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Servicio>> listar(String negocioId) async {
    final rows = await _client
        .from('servicios')
        .select(
          'id, nombre, descripcion, precio, duracion_minutos, activo, icono, '
          'imagen_url',
        )
        .eq('negocio_id', negocioId)
        .order('nombre');

    return rows.map((row) => Servicio.fromMap(row)).toList(growable: false);
  }

  @override
  Future<String> guardar({
    required String negocioId,
    required Map<String, Object?> datos,
    String? servicioId,
  }) async {
    if (servicioId == null) {
      final creado = await _client
          .from('servicios')
          .insert({...datos, 'negocio_id': negocioId})
          .select('id')
          .single();
      return creado['id'].toString();
    }

    final filas = await _client
        .from('servicios')
        .update(datos)
        .eq('negocio_id', negocioId)
        .eq('id', servicioId)
        .select('id');
    exigirFilas(filas);
    return servicioId;
  }

  @override
  Future<void> subirFoto({
    required String negocioId,
    required String servicioId,
    required Uint8List bytes,
    required String tipo,
  }) async {
    final extension = switch (tipo) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    // Nombre nuevo en cada subida: el navegador nunca muestra la foto vieja.
    final ruta =
        '$negocioId/$servicioId-${DateTime.now().millisecondsSinceEpoch}.$extension';
    final storage = _client.storage.from('servicios');
    await storage.uploadBinary(
      ruta,
      bytes,
      fileOptions: FileOptions(contentType: tipo, upsert: true),
    );

    final filas = await _client
        .from('servicios')
        .update({'imagen_url': storage.getPublicUrl(ruta)})
        .eq('negocio_id', negocioId)
        .eq('id', servicioId)
        .select('id');
    exigirFilas(filas);
  }

  @override
  Future<void> crearVarios({
    required String negocioId,
    required List<Map<String, Object?>> servicios,
  }) async {
    if (servicios.isEmpty) return;
    await _client.from('servicios').insert([
      for (final datos in servicios) {...datos, 'negocio_id': negocioId},
    ]);
  }

  @override
  Future<void> cambiarEstado({
    required String negocioId,
    required String servicioId,
    required bool activo,
  }) async {
    final filas = await _client
        .from('servicios')
        .update({'activo': activo})
        .eq('negocio_id', negocioId)
        .eq('id', servicioId)
        .select('id');
    exigirFilas(filas);
  }
}
