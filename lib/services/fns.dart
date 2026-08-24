import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// Erro de chamada de Cloud Function no DESKTOP (espelha o formato do
/// FirebaseFunctionsException: [code] + [message]). No mobile o erro continua
/// sendo o FirebaseFunctionsException real do plugin.
class FnsException implements Exception {
  final String code;
  final String message;
  final dynamic details;
  FnsException(this.code, this.message, [this.details]);
  @override
  String toString() => message;
}

/// Camada única de chamada de Cloud Functions **callable** com fallback para
/// DESKTOP (Windows/Linux), onde o plugin `cloud_functions` NÃO tem
/// implementação nativa.
///
/// - MOBILE / iOS / Android / Web: PASSTHROUGH EXATO para
///   `FirebaseFunctions.instance.httpsCallable(name).call(data)` — mesmo
///   comportamento e MESMAS exceções (FirebaseFunctionsException propaga tal
///   qual). Ou seja, os apps de celular não mudam em nada.
/// - DESKTOP: fala HTTP direto com o endpoint do callable
///   (`https://<region>-<project>.cloudfunctions.net/<name>`) usando o protocolo
///   dos callables (`{data}` no corpo, `{result}` na resposta) e o ID token do
///   Firebase Auth. Erros viram [FnsException] com code/message.
///
/// Uso (drop-in de `result.data`):
///   final data = await Fns.call('minhaFn', {'a': 1});  // == result.data
class Fns {
  Fns._();

  static const String region = 'us-central1';

  /// Cliente drop-in com a MESMA interface de `FirebaseFunctions`
  /// (`httpsCallable(name).call(data).data`) — os serviços trocam só a ORIGEM
  /// do `_functions` para este, sem mexer em nenhum call site nem em nenhum
  /// `catch`. No mobile cai no plugin real (mesmas exceções); no desktop, HTTP.
  static const CallableClient functions = CallableClient();

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  static String get _projectId => Firebase.app().options.projectId;

  /// Chama o callable [name] com [data] e retorna o `data` cru da resposta
  /// (mesmo valor que `HttpsCallableResult.data`).
  static Future<dynamic> call(String name, [Map<String, dynamic>? data]) async {
    if (!_isDesktop) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await user.getIdToken();
        }
        final res =
            await FirebaseFunctions.instance.httpsCallable(name).call(data);
        return res.data;
      } on FirebaseFunctionsException catch (e) {
        if (e.code == 'unauthenticated' || e.code == 'unavailable') {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            await user.getIdToken(true);
          }
          try {
            return await _httpCall(name, data);
          } catch (_) {
            rethrow;
          }
        }
        rethrow;
      } catch (_) {
        return _httpCall(name, data);
      }
    }
    return _httpCall(name, data);
  }

  static Future<dynamic> _httpCall(
      String name, Map<String, dynamic>? data) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final uri = Uri.parse(
        'https://$region-$_projectId.cloudfunctions.net/$name');
    http.Response resp;
    try {
      resp = await http
          .post(uri,
              headers: {
                'Content-Type': 'application/json',
                if (token != null) 'Authorization': 'Bearer $token',
              },
              body: jsonEncode({'data': data ?? const {}}))
          .timeout(const Duration(seconds: 70));
    } catch (e) {
      throw FnsException('unavailable', 'Falha de conexão com o servidor.', e);
    }

    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(resp.body);
      body = decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      body = {};
    }

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return body['result'];
    }
    // Protocolo callable de erro: { error: { status, message, details } }.
    final err = body['error'] is Map
        ? Map<String, dynamic>.from(body['error'] as Map)
        : const <String, dynamic>{};
    throw FnsException(
      (err['status'] ?? 'unknown').toString().toLowerCase(),
      (err['message'] ?? 'Erro ao chamar $name (${resp.statusCode}).').toString(),
      err['details'],
    );
  }
}

/// Espelho de `FirebaseFunctions` (só a parte usada: `httpsCallable`), roteando
/// por [Fns]. Permite trocar `FirebaseFunctions.instance` → `Fns.functions` nos
/// serviços sem alterar os call sites.
class CallableClient {
  const CallableClient();
  CallableRef httpsCallable(String name) => CallableRef(name);
}

class CallableRef {
  final String name;
  const CallableRef(this.name);
  // Genérico só para casar com a assinatura do plugin (`call<T>`); o [T] é
  // ignorado — `data` é dynamic (o call site faz o cast como já fazia).
  Future<CallableResult> call<T>([dynamic parameters]) async {
    final data = parameters == null
        ? null
        : Map<String, dynamic>.from(parameters as Map);
    return CallableResult(await Fns.call(name, data));
  }
}

/// Espelho de `HttpsCallableResult`: só expõe `.data` (o valor cru retornado).
class CallableResult {
  final dynamic data;
  const CallableResult(this.data);
}

