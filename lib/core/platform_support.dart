import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Capacidades por plataforma para os plugins que NÃO têm implementação
/// desktop (Windows/Linux/macOS). Usado para degradar graciosamente no
/// executável desktop sem quebrar mobile.
class PlatformSupport {
  PlatformSupport._();

  /// Desktop nativo (Windows/Linux/macOS).
  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// `image_cropper` só tem Android/iOS/web. No desktop, pulamos o recorte e
  /// usamos a imagem original.
  static bool get canCropImage =>
      kIsWeb || Platform.isAndroid || Platform.isIOS;

  /// `mobile_scanner` (câmera/QR) só tem Android/iOS/web/macOS(parcial). No
  /// desktop Windows/Linux, oferecemos digitação manual do código.
  static bool get canScanCamera =>
      kIsWeb || Platform.isAndroid || Platform.isIOS;
}
