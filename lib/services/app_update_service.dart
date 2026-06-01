import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Resultado da checagem de atualização. [storeUrl] só é preenchido no iOS
/// (link da App Store pra abrir); no Android a atualização é conduzida pelo
/// `in_app_update` e não precisa de URL.
class AppUpdateStatus {
  final bool available;
  final String? storeUrl;

  const AppUpdateStatus({required this.available, this.storeUrl});

  static const none = AppUpdateStatus(available: false);
}

/// Detecta se há uma versão mais nova publicada na loja (Google Play / App
/// Store) e conduz a atualização. É um aviso **suave**: nunca bloqueia o app —
/// só alimenta um banner dispensável. A fonte da verdade é a própria loja,
/// então NÃO há versão pra manter manualmente (nada de bump). Qualquer falha
/// (sem rede, build sideloaded/debug, loja indisponível) resulta em "sem
/// atualização" — o banner simplesmente não aparece (fail-safe).
class AppUpdateService {
  /// Checa a loja da plataforma atual. Veja a nota da classe sobre fail-safe.
  static Future<AppUpdateStatus> check() async {
    try {
      if (kIsWeb) return AppUpdateStatus.none;
      if (Platform.isAndroid) {
        final info = await InAppUpdate.checkForUpdate();
        return AppUpdateStatus(
          available:
              info.updateAvailability == UpdateAvailability.updateAvailable,
        );
      }
      if (Platform.isIOS) {
        return await _checkAppStore();
      }
    } catch (_) {
      // fail-safe: qualquer erro = não avisa.
    }
    return AppUpdateStatus.none;
  }

  /// iOS: usa o endpoint oficial de lookup da App Store (sem chave) pra obter a
  /// versão publicada e compara com a instalada.
  static Future<AppUpdateStatus> _checkAppStore() async {
    final pkg = await PackageInfo.fromPlatform();
    final uri = Uri.parse(
      'https://itunes.apple.com/lookup?bundleId=${pkg.packageName}&country=br',
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return AppUpdateStatus.none;

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final results = body['results'] as List?;
    if (results == null || results.isEmpty) return AppUpdateStatus.none;

    final first = results.first as Map<String, dynamic>;
    final storeVersion = (first['version'] ?? '').toString();
    final storeUrl = (first['trackViewUrl'] ?? '').toString();
    if (storeVersion.isEmpty) return AppUpdateStatus.none;

    return AppUpdateStatus(
      available: _isNewer(storeVersion, pkg.version),
      storeUrl: storeUrl.isNotEmpty ? storeUrl : null,
    );
  }

  /// True se [store] for maior que [installed] comparando campo a campo
  /// numérico (ex.: 1.4.0 > 1.3.9; 1.10.0 > 1.9.0).
  static bool _isNewer(String store, String installed) {
    final a = _parts(store);
    final b = _parts(installed);
    final len = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static List<int> _parts(String v) =>
      v.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();

  /// Conduz a atualização ao toque do usuário. Android: fluxo flexível do
  /// `in_app_update` (baixa em background e instala); se indisponível, cai pra
  /// Play Store. iOS/outros: abre a App Store pelo link capturado na checagem.
  static Future<void> startUpdate(AppUpdateStatus status) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await InAppUpdate.startFlexibleUpdate();
        await InAppUpdate.completeFlexibleUpdate();
        return;
      } catch (_) {
        try {
          final pkg = await PackageInfo.fromPlatform();
          await launchUrl(
            Uri.parse(
              'https://play.google.com/store/apps/details?id=${pkg.packageName}',
            ),
            mode: LaunchMode.externalApplication,
          );
        } catch (_) {}
        return;
      }
    }

    final url = status.storeUrl;
    if (url != null && url.isNotEmpty) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }
}
