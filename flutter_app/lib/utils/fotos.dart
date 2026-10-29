import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Foto elegida por el dueño, ya reducida, lista para subir.
class FotoElegida {
  const FotoElegida(this.bytes, this.tipo);

  final Uint8List bytes;
  final String tipo;
}

typedef ElegirFoto = Future<FotoElegida?> Function();

/// Galería o cámara del dispositivo; la reduce a 800 px para que pese poco.
Future<FotoElegida?> elegirFotoDelDispositivo() async {
  final archivo = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 800,
    maxHeight: 800,
    imageQuality: 80,
  );
  if (archivo == null) return null;
  final tipo = archivo.mimeType ?? 'image/jpeg';
  return FotoElegida(await archivo.readAsBytes(), tipo);
}

/// Sube una foto al bucket público de Storage (013), dentro de la carpeta del
/// negocio, y devuelve su dirección pública. El nombre lleva la hora para que
/// el navegador nunca muestre una versión vieja.
Future<String> subirFotoDelNegocio(
  SupabaseClient client, {
  required String negocioId,
  required String nombre,
  required Uint8List bytes,
  required String tipo,
}) async {
  // Solo los tipos que acepta el bucket; lo demás se sube como JPEG, que es
  // lo que entrega el navegador al reducir la foto.
  final (extension, contentType) = switch (tipo) {
    'image/png' => ('png', 'image/png'),
    'image/webp' => ('webp', 'image/webp'),
    _ => ('jpg', 'image/jpeg'),
  };
  final ruta =
      '$negocioId/$nombre-${DateTime.now().millisecondsSinceEpoch}.$extension';
  final storage = client.storage.from('servicios');
  // Sin upsert: el nombre es único y "upsert" exige además permiso de
  // lectura sobre storage.objects, que no se concede.
  await storage.uploadBinary(
    ruta,
    bytes,
    fileOptions: FileOptions(contentType: contentType),
  );
  return storage.getPublicUrl(ruta);
}
