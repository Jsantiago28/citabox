# Barbería PRO Flutter

Cliente multiplataforma para Android, iOS y web. Reutiliza el proyecto Supabase y su esquema/RLS existentes. Nunca se debe incluir una clave `secret` o `service_role` en la aplicación.

## Configuración local

Crea `dart_defines.local.json` a partir de `dart_defines.example.json` y completa `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY` con los valores públicos del proyecto. El archivo local está excluido de Git.

```powershell
flutter pub get
flutter run -d edge --dart-define-from-file=dart_defines.local.json
```

## Validación y build web

```powershell
flutter analyze
flutter test
flutter build web --dart-define-from-file=dart_defines.local.json
```

Para desarrollo Android se requiere Android Studio y Android SDK. La compilación y firma de iOS requieren macOS, Xcode y una cuenta de Apple Developer.
