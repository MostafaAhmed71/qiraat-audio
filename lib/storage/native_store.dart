import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class MediaStore {
  late Directory dir;
  final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  Future<void> init() async {
    dir = Directory('${(await getApplicationSupportDirectory()).path}/audio');
    await dir.create(recursive: true);
  }

  bool get supportsResume => true;
  String path(String key) => '${dir.path}/$key.mp3';
  Future<String?> local(String key) async {
    final file = File(path(key));
    return await file.exists() && await file.length() > 0
        ? file.uri.toString()
        : null;
  }

  Future<int> size(String key) async =>
      await File(path(key)).exists() ? File(path(key)).length() : 0;
  Future<void> delete(String key) async {
    for (final suffix in ['.mp3', '.part', '.part.meta']) {
      final f = File('${dir.path}/$key$suffix');
      if (await f.exists()) await f.delete();
    }
  }

  Future<void> download(
    String key,
    String url,
    CancelToken token,
    void Function(int, int) progress,
  ) async {
    if (await local(key) != null) return;
    final part = File('${dir.path}/$key.part');
    var offset = await part.exists() ? await part.length() : 0;
    final meta = File('${dir.path}/$key.part.meta');
    final validator = await meta.exists() ? await meta.readAsString() : '';
    if (validator.isEmpty) offset = 0;

    final response = await dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: offset > 0
            ? {'Range': 'bytes=$offset-', 'If-Range': validator}
            : null,
      ),
      cancelToken: token,
    );
    final body = response.data!;
    if (!(response.headers.value('content-type') ?? '')
        .toLowerCase()
        .startsWith('audio/')) {
      throw StateError('لم يرجع المصدر ملفًا صوتيًا');
    }
    final newValidator =
        response.headers.value('etag') ??
        response.headers.value('last-modified') ??
        '';
    await meta.writeAsString(newValidator);

    if (response.statusCode != 206) offset = 0;
    if (offset > 0 &&
        !(response.headers.value('content-range') ?? '').startsWith(
          'bytes $offset-',
        )) {
      throw StateError(
        'تعذر التحقق من استئناف التنزيل؛ احذف الملف الجزئي وأعد التنزيل',
      );
    }
    final total =
        (int.tryParse(response.headers.value('content-length') ?? '') ?? -1);
    final sink = part.openWrite(
      mode: offset > 0 ? FileMode.append : FileMode.write,
    );
    var received = offset;
    try {
      await for (final chunk in body.stream) {
        if (token.isCancelled)
          throw DioException(
            requestOptions: response.requestOptions,
            type: DioExceptionType.cancel,
          );
        sink.add(chunk);
        received += chunk.length;
        progress(received, total < 0 ? -1 : offset + total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (token.isCancelled)
      throw DioException(
        requestOptions: response.requestOptions,
        type: DioExceptionType.cancel,
      );
    if (received == 0 || (total >= 0 && received != offset + total))
      throw StateError('التنزيل غير مكتمل');
    await part.rename(path(key));
    if (await meta.exists()) await meta.delete();
  }
}
