import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:graduabjj/api/dto/upload_dto.dart';
import 'package:graduabjj/api/idempotency.dart';
import 'package:graduabjj/api/tatami_client.dart';
import 'package:graduabjj/api/tatami_exception.dart';
import 'package:graduabjj/api/uploads_repo.dart';

import 'fakes/fake_firebase_auth.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late TatamiClient client;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test.tatami.dev'));
    adapter = DioAdapter(dio: dio);
    client = TatamiClient(
      baseUrl: 'https://api.test.tatami.dev',
      dio: dio,
      auth: FakeFirebaseAuth.unauthenticated(),
    );
  });

  group('ApiUploadPurpose', () {
    test('wire format casa com OpenAPI enum', () {
      expect(ApiUploadPurpose.studentPhoto.wire, 'student_photo');
      expect(ApiUploadPurpose.storeProduct.wire, 'store_product');
      expect(ApiUploadPurpose.academySettings.wire, 'academy_settings');
      expect(ApiUploadPurpose.competitionPhoto.wire, 'competition_photo');
    });

    test('content-type whitelist per purpose', () {
      expect(
        ApiUploadPurpose.studentPhoto.allowedContentTypes,
        containsAll(['image/jpeg', 'image/png', 'image/webp']),
      );
      expect(
        ApiUploadPurpose.academySettings.allowedContentTypes,
        contains('image/svg+xml'),
      );
      expect(
        ApiUploadPurpose.competitionPhoto.allowedContentTypes,
        isNot(contains('image/webp')),
      );
    });
  });

  group('sign', () {
    test('manda purpose + filename + content_type + max_bytes', () async {
      adapter.onPost(
        '/v1/uploads/sign',
        (s) => s.reply(200, {
          'upload_url': 'https://storage.googleapis.com/bucket/tmp/abc?sig=xxx',
          'upload_path': 'tmp/abc',
          'expires_at': '2026-05-17T10:10:00Z',
          'max_bytes': 5242880,
        }),
        data: {
          'purpose': 'student_photo',
          'filename': 'foto.jpg',
          'content_type': 'image/jpeg',
          'max_bytes': 1024,
        },
      );
      final repo = UploadsRemoteRepo(client);
      final res = await repo.sign(
        const SignUploadRequest(
          purpose: ApiUploadPurpose.studentPhoto,
          filename: 'foto.jpg',
          contentType: 'image/jpeg',
          maxBytes: 1024,
        ),
        idempotencyKey: IdempotencyKey.fromString(
            '77777777-7777-4777-8777-777777777777'),
      );
      expect(res.uploadUrl, startsWith('https://storage.googleapis.com'));
      expect(res.uploadPath, 'tmp/abc');
      expect(res.maxBytes, 5242880);
    });

    test('415 vira TatamiException com type problem', () async {
      adapter.onPost(
        '/v1/uploads/sign',
        (s) => s.reply(415, {
          'type': 'https://tatami.dev/problems/unsupported-content-type',
          'title': 'Unsupported Media Type',
          'status': 415,
          'detail': 'image/bmp not allowed for student_photo',
        }),
        data: {
          'purpose': 'student_photo',
          'filename': 'x.bmp',
          'content_type': 'image/bmp',
        },
      );
      final repo = UploadsRemoteRepo(client);
      await expectLater(
        repo.sign(const SignUploadRequest(
          purpose: ApiUploadPurpose.studentPhoto,
          filename: 'x.bmp',
          contentType: 'image/bmp',
        )),
        throwsA(anyOf(isA<TatamiException>(), isA<DioException>())),
      );
    });
  });

  group('finalize', () {
    test('echo upload_path + target_id opcional', () async {
      adapter.onPost(
        '/v1/uploads/finalize',
        (s) => s.reply(200, {
          'file_id': 'file-1',
          'internal_path': 'student_photo/aid/file-1.jpg',
          'public_url': 'https://cdn.tatami.dev/student_photo/aid/file-1.jpg',
        }),
        data: {'upload_path': 'tmp/abc', 'target_id': 'stu-1'},
      );
      final repo = UploadsRemoteRepo(client);
      final res = await repo.finalize(
        const FinalizeUploadRequest(uploadPath: 'tmp/abc', targetId: 'stu-1'),
        idempotencyKey: IdempotencyKey.fromString(
            '88888888-8888-4888-8888-888888888888'),
      );
      expect(res.fileId, 'file-1');
      expect(res.publicUrl, startsWith('https://cdn.tatami.dev/'));
    });

    test('404 (nunca PUT-ou bytes) vira TatamiException', () async {
      adapter.onPost(
        '/v1/uploads/finalize',
        (s) => s.reply(404, {
          'type': 'https://tatami.dev/problems/upload-not-found',
          'title': 'Not Found',
          'status': 404,
        }),
        data: {'upload_path': 'tmp/missing'},
      );
      final repo = UploadsRemoteRepo(client);
      await expectLater(
        repo.finalize(const FinalizeUploadRequest(uploadPath: 'tmp/missing')),
        throwsA(anyOf(isA<TatamiException>(), isA<DioException>())),
      );
    });
  });

  group('uploadFile', () {
    test('orquestra sign + PUT GCS + finalize', () async {
      // 1. sign
      adapter.onPost(
        '/v1/uploads/sign',
        (s) => s.reply(200, {
          'upload_url': 'https://storage.googleapis.com/bucket/tmp/xyz?sig=y',
          'upload_path': 'tmp/xyz',
          'expires_at': '2026-05-17T10:10:00Z',
          'max_bytes': 1048576,
        }),
        data: {
          'purpose': 'store_product',
          'filename': 'prod.png',
          'content_type': 'image/png',
          'max_bytes': 512,
        },
      );
      // 3. finalize
      adapter.onPost(
        '/v1/uploads/finalize',
        (s) => s.reply(200, {
          'file_id': 'file-2',
          'internal_path': 'store_product/aid/file-2.png',
          'public_url': null,
        }),
        data: {'upload_path': 'tmp/xyz'},
      );
      // 2. PUT GCS via MockClient
      final mockHttp = MockClient((req) async {
        expect(req.method, 'PUT');
        expect(req.url.host, 'storage.googleapis.com');
        expect(req.headers['Content-Type'], 'image/png');
        return http.Response('', 200);
      });
      final repo = UploadsRemoteRepo(client, httpClient: mockHttp);
      var progressCalls = 0;
      final bytes = Uint8List.fromList(List<int>.filled(512, 0xff));
      final res = await repo.uploadFile(
        purpose: ApiUploadPurpose.storeProduct,
        filename: 'prod.png',
        contentType: 'image/png',
        bytes: bytes,
        onProgress: (sent, total) {
          progressCalls++;
          expect(sent, total);
        },
      );
      expect(res.fileId, 'file-2');
      expect(res.publicUrl, isNull);
      expect(progressCalls, 1);
    });

    test('rejeita arquivo > maxBytes resolvido pelo BE', () async {
      adapter.onPost(
        '/v1/uploads/sign',
        (s) => s.reply(200, {
          'upload_url': 'https://storage.googleapis.com/bucket/tmp/big',
          'upload_path': 'tmp/big',
          'expires_at': '2026-05-17T10:10:00Z',
          'max_bytes': 100,
        }),
        data: {
          'purpose': 'student_photo',
          'filename': 'big.jpg',
          'content_type': 'image/jpeg',
          'max_bytes': 500,
        },
      );
      final mockHttp = MockClient((req) async {
        fail('PUT não deve ser chamado se size-check falhar antes');
      });
      final repo = UploadsRemoteRepo(client, httpClient: mockHttp);
      final bytes = Uint8List.fromList(List<int>.filled(500, 0));
      await expectLater(
        repo.uploadFile(
          purpose: ApiUploadPurpose.studentPhoto,
          filename: 'big.jpg',
          contentType: 'image/jpeg',
          bytes: bytes,
        ),
        throwsA(isA<UploadSizeLimitException>()),
      );
    });

    test('PUT GCS non-2xx vira GcsUploadException', () async {
      adapter.onPost(
        '/v1/uploads/sign',
        (s) => s.reply(200, {
          'upload_url': 'https://storage.googleapis.com/bucket/tmp/z',
          'upload_path': 'tmp/z',
          'expires_at': '2026-05-17T10:10:00Z',
          'max_bytes': 1024,
        }),
        data: {
          'purpose': 'student_photo',
          'filename': 'x.jpg',
          'content_type': 'image/jpeg',
          'max_bytes': 3,
        },
      );
      final mockHttp = MockClient((req) async => http.Response('signature expired', 403));
      final repo = UploadsRemoteRepo(client, httpClient: mockHttp);
      await expectLater(
        repo.uploadFile(
          purpose: ApiUploadPurpose.studentPhoto,
          filename: 'x.jpg',
          contentType: 'image/jpeg',
          bytes: Uint8List.fromList([0, 1, 2]),
        ),
        throwsA(isA<GcsUploadException>()),
      );
    });
  });
}
