import 'package:firebase_auth/firebase_auth.dart';

/// Fake mínimo de FirebaseAuth para testes — devolve `currentUser == null`
/// para que o auth interceptor do TatamiClient pule a injeção de token.
///
/// Não usa o pacote `firebase_auth_mocks` para evitar uma dependência extra
/// só para este test bench. Conforme precisarmos testar fluxos autenticados,
/// migrar para um mock formal.
class FakeFirebaseAuth implements FirebaseAuth {
  FakeFirebaseAuth.unauthenticated();

  @override
  User? get currentUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
