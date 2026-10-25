import 'audio_signature.dart';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:idb_shim/idb_browser.dart';
import 'package:web/web.dart' as web;

class MediaStore {
  late Database db;
  final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );
  final Map<String, String> urls = {};
  bool get supportsResume => false;
  Future<void> init() async {
    db = await idbFactoryNative.open(
      'qiraat-audio-v1',
      version: 1,
      onUpgradeNeeded: (event) {
        event.database.createObjectStore('audio');
        event.database.createObjectStore('sizes');
      },
    );
  }

  Future<Uint8List?> _bytes(String key) async {
    final t = db.transaction('audio', idbModeReadOnly);
    final value = await t.objectStore('audio').getObject(key);
    await t.completed;
    return value == null
        ? null
        : Uint8List.fromList((value as List).cast<int>());
  }

  Future<String?> local(String key) async {
    if (await size(key) == 0) {
      await _revoke(key);
      return null;
    }
    if (urls.containsKey(key)) return urls[key];
    final bytes = await _bytes(key);
    if (bytes == null) {
      await _revoke(key);
      return null;
    }
    return urls.putIfAbsent(
      key,
      () => web.URL.createObjectURL(
        web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'audio/mpeg')),
      ),
    );
  }

  Future<void> _revoke(String key) async {
    final old = urls.remove(key);
    if (old != null) web.URL.revokeObjectURL(old);
  }

  Future<int> size(String key) async {
    final t = db.transaction('sizes', idbModeReadOnly);
    final result = await t.objectStore('sizes').getObject(key);
    await t.completed;
    return result is num ? result.toInt() : 0;
  }

  Future<void> delete(String key) async {
    final t = db.transactionList(['audio', 'sizes'], idbModeReadWrite);
    await t.objectStore('audio').delete(key);
    await t.objectStore('sizes').delete(key);
    await t.completed;
    await _revoke(key);
  }

  Future<void> download(
    String key,
    String url,
    CancelToken token,
    void Function(int, int) progress,
  ) async {
    if (await size(key) > 0) return;
    final response = await dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
      cancelToken: token,
      onReceiveProgress: progress,
    );
    if (token.isCancelled)
      throw DioException(
        requestOptions: response.requestOptions,
        type: DioExceptionType.cancel,
      );
    if (!allowedAudioType(response.headers.value('content-type'))) {
      throw StateError('لم يرجع المصدر ملفًا صوتيًا');
    }
    final bytes = response.data!;
    if (!isMp3(bytes)) throw StateError('الملف ليس تلاوة MP3 صالحة');
    // Atomic transaction: canceled/failed downloads cannot be marked complete.
    final t = db.transactionList(['audio', 'sizes'], idbModeReadWrite);
    await t.objectStore('audio').put(Uint8List.fromList(bytes), key);
    await t.objectStore('sizes').put(bytes.length, key);
    await t.completed;
  }
}
