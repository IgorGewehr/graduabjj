import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:graduabjj/api/identity_repo.dart';
import 'package:graduabjj/api/tatami_client.dart';
import 'package:graduabjj/models/user.dart';
import 'package:graduabjj/providers/auth_provider.dart';

import 'fakes/fake_firebase_auth.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late IdentityRemoteRepo repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test.tatami.dev'));
    adapter = DioAdapter(dio: dio);
    final client = TatamiClient(
      baseUrl: 'https://api.test.tatami.dev',
      dio: dio,
      auth: FakeFirebaseAuth.unauthenticated(),
    );
    repo = IdentityRemoteRepo(client);
  });

  group('loadCurrentUserFromTatami', () {
    test('retorna AppUser linked com primary academy', () async {
      adapter.onGet(
        '/v1/me',
        (s) => s.reply(200, {
          'user': {
            'uid': 'u-1',
            'email': 'u@x.com',
            'display_name': 'Igor',
            'account_type': 'linked',
          },
          'memberships': [
            {
              'uid': 'u-1',
              'academy_id': 'a-1',
              'role': 'student',
              'status': 'active',
              'student_id': 's-1',
            },
            {
              'uid': 'u-1',
              'academy_id': 'a-2',
              'role': 'admin',
              'status': 'active',
            },
          ],
          'primary_academy_id': 'a-2',
        }),
      );

      final app = await loadCurrentUserFromTatami(repo: repo);
      expect(app.id, 'u-1');
      expect(app.academyId, 'a-2');
      expect(app.role, UserRole.admin);
      expect(app.accountType, AccountType.linked);
    });

    test('selectedAcademyId override sobrescreve primary', () async {
      adapter.onGet(
        '/v1/me',
        (s) => s.reply(200, {
          'user': {
            'uid': 'u-1',
            'email': 'u@x.com',
            'account_type': 'linked',
          },
          'memberships': [
            {
              'uid': 'u-1',
              'academy_id': 'a-1',
              'role': 'instructor',
              'status': 'active',
            },
            {
              'uid': 'u-1',
              'academy_id': 'a-2',
              'role': 'admin',
              'status': 'active',
            },
          ],
          'primary_academy_id': 'a-2',
        }),
      );

      final app = await loadCurrentUserFromTatami(
        repo: repo,
        selectedAcademyId: 'a-1',
      );
      expect(app.academyId, 'a-1');
      expect(app.role, UserRole.instructor);
    });

    test('sem memberships → AppUser free (não null)', () async {
      adapter.onGet(
        '/v1/me',
        (s) => s.reply(200, {
          'user': {
            'uid': 'u-free',
            'email': 'free@x.com',
            'display_name': 'Visitante',
            'account_type': 'free',
          },
          'memberships': [],
        }),
      );

      final app = await loadCurrentUserFromTatami(repo: repo);
      expect(app.id, 'u-free');
      expect(app.accountType, AccountType.free);
      expect(app.academyId, isNull);
      expect(app.role, UserRole.student);
    });

    test('memberships todas removed → AppUser free', () async {
      adapter.onGet(
        '/v1/me',
        (s) => s.reply(200, {
          'user': {
            'uid': 'u-2',
            'email': 'u@x.com',
            'account_type': 'linked',
          },
          'memberships': [
            {
              'uid': 'u-2',
              'academy_id': 'a-1',
              'role': 'student',
              'status': 'removed',
            },
          ],
        }),
      );

      final app = await loadCurrentUserFromTatami(repo: repo);
      expect(app.academyId, isNull);
      expect(app.accountType, AccountType.free);
    });

    test('propaga jiu-jitsu fields do GlobalUser', () async {
      adapter.onGet(
        '/v1/me',
        (s) => s.reply(200, {
          'user': {
            'uid': 'u-1',
            'email': 'u@x.com',
            'account_type': 'linked',
            'highest_belt': 'black',
            'highest_stripes': 2,
            'jiujitsu_start_date': '2010-05-01',
            'is_profile_public': true,
          },
          'memberships': [
            {
              'uid': 'u-1',
              'academy_id': 'a-1',
              'role': 'student',
              'status': 'active',
            },
          ],
        }),
      );

      final app = await loadCurrentUserFromTatami(repo: repo);
      expect(app.highestBelt, 'black');
      expect(app.highestStripes, 2);
      expect(app.jiujitsuStartDate, DateTime(2010, 5, 1));
      expect(app.isProfilePublic, isTrue);
    });

    test('401 propaga TatamiException (provider faz fallback no try/catch)',
        () async {
      adapter.onGet(
        '/v1/me',
        (s) => s.reply(401, {
          'type': 'https://tatami.dev/errors/unauthorized',
          'title': 'Unauthorized',
          'status': 401,
        }),
      );

      expect(
        () => loadCurrentUserFromTatami(repo: repo),
        throwsA(isA<DioException>()),
      );
    });
  });
}
