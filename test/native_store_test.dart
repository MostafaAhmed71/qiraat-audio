import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qiraat_audio/storage/native_store.dart';

void main() {
  late Directory directory;
  late MediaStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qiraat-storage-test-');
    store = MediaStore()..dir = directory;
  });
  tearDown(() async {
    store.dio.close(force: true);
    await directory.delete(recursive: true);
  });
  test(
    'Completed download remains readable after the network server closes',
    () async {
      final bytes = List<int>.generate(8192, (i) => i % 256);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'audio/mpeg',
        );
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
      });
      var lastReceived = 0;
      await store.download(
        '1_1',
        'http://127.0.0.1:${server.port}/audio',
        CancelToken(),
        (received, total) {
          lastReceived = received;
        },
      );
      await server.close(force: true);
      final uri = await store.local('1_1');
      expect(uri, isNotNull);
      expect(await File.fromUri(Uri.parse(uri!)).readAsBytes(), bytes);
      expect(lastReceived, bytes.length);
      await store.delete('1_1');
      expect(await store.local('1_1'), isNull);
    },
  );
  test(
    'Resume validates Range and If-Range before appending partial bytes',
    () async {
      final bytes = List<int>.generate(8192, (i) => i % 251);
      await File(
        '${directory.path}/2_1.part',
      ).writeAsBytes(bytes.take(1024).toList());
      await File(
        '${directory.path}/2_1.part.meta',
      ).writeAsString('"version-1"');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      String? range, validator;
      server.listen((request) async {
        range = request.headers.value(HttpHeaders.rangeHeader);
        validator = request.headers.value('if-range');
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'audio/mpeg',
        );
        request.response.headers.set('etag', '"version-1"');
        request.response.headers.set('content-range', 'bytes 1024-8191/8192');
        request.response.contentLength = bytes.length - 1024;
        request.response.add(bytes.skip(1024).toList());
        await request.response.close();
      });
      try {
        await store.download(
          '2_1',
          'http://127.0.0.1:${server.port}/audio',
          CancelToken(),
          (_, _) {},
        );
        expect(range, 'bytes=1024-');
        expect(validator, '"version-1"');
        expect(await File(store.path('2_1')).readAsBytes(), bytes);
        expect(await File('${directory.path}/2_1.part').exists(), isFalse);
      } finally {
        await server.close(force: true);
      }
    },
  );
  test(
    'An HTML error response cannot become a completed audio download',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write('<html>Unavailable</html>');
        await request.response.close();
      });
      try {
        await expectLater(
          store.download(
            '3_1',
            'http://127.0.0.1:${server.port}/error',
            CancelToken(),
            (_, _) {},
          ),
          throwsStateError,
        );
        expect(await store.local('3_1'), isNull);
      } finally {
        await server.close(force: true);
      }
    },
  );
}
