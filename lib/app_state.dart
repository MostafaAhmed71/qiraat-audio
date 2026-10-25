import 'dart:async';
import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'catalog.dart';
import 'storage/media_store.dart';

final catalogProvider = FutureProvider<Catalog>((ref) => Catalog.bundled());
final stateProvider = ChangeNotifierProvider<AppState>((ref) {
  final state = AppState();

  return state;
});

class AppState extends ChangeNotifier {
  final player = AudioPlayer();
  final store = MediaStore();
  late SharedPreferences prefs;
  Catalog? catalog;
  bool ready = false, busy = false, downloading = false, repeat = false;
  String? error, downloadError;
  Mushaf? current;
  int? surah;
  String? activeDownload;
  double? progress;
  int bytesReceived = 0;
  Set<String> favorites = {}, downloaded = {};
  final List<String> queue = [];
  CancelToken? cancel;
  int _savedSecond = -1;
  late final StreamSubscription<Duration> _position;
  late final StreamSubscription<ProcessingState> _processing;
  late final StreamSubscription<PlayerException> _errors;
  bool _disposed = false;

  AppState() {
    _errors = player.errorStream.listen((e) {
      error =
          'انقطع الصوت أو تعذر الوصول إلى التلاوة. أعد التشغيل أو نزّل السورة أولًا.';
      busy = false;
      notifyListeners();
    });
    _position = player.positionStream.listen((p) {
      if (!busy && p.inSeconds ~/ 5 != _savedSecond) {
        _savedSecond = p.inSeconds ~/ 5;
        unawaited(savePosition());
      }
    });
    _processing = player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed && !busy) unawaited(next());
    });
  }
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void>? _initialization;
  Future<void> init(Catalog c) {
    if (ready) return Future.value();
    return _initialization ??= _init(c).catchError((Object e) {
      _initialization = null;
      throw e;
    });
  }

  Future<void> _init(Catalog c) async {
    if (ready) return;
    catalog = c;
    prefs = await SharedPreferences.getInstance();
    await store.init();
    favorites = prefs.getStringList('favorites')?.toSet() ?? {};
    downloaded = prefs.getStringList('downloads')?.toSet() ?? {};
    // Reconcile evictions/deletions before presenting downloads as available.
    final stale = <String>[];
    for (final key in downloaded) {
      if (await store.size(key) == 0) stale.add(key);
    }
    downloaded.removeAll(stale);
    await prefs.setStringList('downloads', downloaded.toList());
    ready = true;
    notifyListeners();
  }

  Future<void> favorite(String key) async {
    favorites.contains(key) ? favorites.remove(key) : favorites.add(key);
    await prefs.setStringList('favorites', favorites.toList());
    notifyListeners();
  }

  Future<void> savePosition() async {
    if (!ready || current == null || surah == null || busy) return;
    await prefs.setString(
      'last',
      jsonEncode({
        'm': current!.id,
        's': surah,
        'p': player.position.inMilliseconds,
      }),
    );
  }

  Map<String, dynamic>? get last {
    if (!ready) return null;
    try {
      final s = prefs.getString('last');
      return s == null ? null : jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> resumeLast() async {
    final l = last;
    if (l == null) return;
    try {
      await play(
        catalog!.byId(l['m']),
        l['s'],
        position: Duration(milliseconds: l['p']),
      );
    } catch (_) {
      error = 'تعذر استعادة آخر تلاوة';
      notifyListeners();
    }
  }

  Future<void> play(
    Mushaf m,
    int s, {
    Duration position = Duration.zero,
  }) async {
    if (busy || !m.surahs.contains(s)) return;
    await savePosition();
    busy = true;
    error = null;
    notifyListeners();
    try {
      await player.pause();
      current = m;
      surah = s;
      final local = await store.local(m.key(s));
      if (local == null && downloaded.remove(m.key(s))) {
        await prefs.setStringList('downloads', downloaded.toList());
      }
      final tag = MediaItem(
        id: m.key(s),
        title: 'سورة ${catalog!.suwar[s]}',
        artist: m.reciter,
        album: m.name,
      );
      await player.setAudioSource(
        AudioSource.uri(Uri.parse(local ?? m.audioUrl(s)), tag: tag),
        initialPosition: position,
      );
      await player.setLoopMode(repeat ? LoopMode.one : LoopMode.off);
      busy = false;
      await savePosition();
      unawaited(
        player.play().catchError((Object e) {
          error = 'تعذر تشغيل الصوت. تحقق من الإنترنت أو أعد تنزيل السورة.';
          notifyListeners();
        }),
      );
    } catch (_) {
      error =
          'تعذر تحميل التلاوة. تأكد من الاتصال أو نزّل السورة للاستماع دون إنترنت.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> toggle() async {
    try {
      if (player.playing) {
        await player.pause();
        await savePosition();
      } else if (player.processingState == ProcessingState.completed &&
          current != null &&
          surah != null) {
        await play(current!, surah!);
      } else {
        unawaited(
          player.play().catchError((Object e) {
            error = 'تعذر تشغيل التلاوة';
            notifyListeners();
          }),
        );
      }
    } catch (_) {
      error = 'تعذر التحكم في الصوت';
      notifyListeners();
    }
  }

  Future<void> next({bool previous = false}) async {
    final m = current;
    if (m == null || surah == null) return;
    final i = m.surahs.indexOf(surah!) + (previous ? -1 : 1);
    if (i >= 0 && i < m.surahs.length) await play(m, m.surahs[i]);
  }

  Future<void> seekBy(int seconds) async {
    final duration = player.duration ?? Duration.zero;
    await player.seek(
      Duration(
        milliseconds: (player.position.inMilliseconds + seconds * 1000)
            .clamp(0, duration.inMilliseconds)
            .toInt(),
      ),
    );
    await savePosition();
  }

  Future<void> setRepeat() async {
    repeat = !repeat;
    await player.setLoopMode(repeat ? LoopMode.one : LoopMode.off);
    notifyListeners();
  }

  Future<void> enqueue(Mushaf m, Iterable<int> surahs) async {
    if (kIsWeb && !m.webDownloads) {
      downloadError =
          'مصدر ن للقرآن لا يتيح التنزيل داخل المتصفح بسبب CORS. الاستماع متاح، والتنزيل داخل تطبيق أندرويد متاح.';
      notifyListeners();
      return;
    }
    for (final s in surahs) {
      final key = m.key(s);
      if (!downloaded.contains(key) &&
          !queue.contains(key) &&
          activeDownload != key)
        queue.add(key);
    }
    if (!downloading) unawaited(_run());
    notifyListeners();
  }

  Future<void> _run() async {
    downloading = true;
    downloadError = null;
    while (queue.isNotEmpty) {
      final key = queue.removeAt(0);
      activeDownload = key;
      progress = null;
      bytesReceived = 0;
      cancel = CancelToken();
      notifyListeners();
      try {
        final parts = key.split('_');
        final m = catalog!.byId(int.parse(parts[0]));
        await store.download(key, m.audioUrl(int.parse(parts[1])), cancel!, (
          got,
          total,
        ) {
          bytesReceived = got;
          progress = total > 0 ? (got / total).clamp(0, 1).toDouble() : null;
          notifyListeners();
        });
        downloaded.add(key);
        await prefs.setStringList('downloads', downloaded.toList());
      } catch (e) {
        queue.insert(0, key);
        downloadError = e is DioException && CancelToken.isCancel(e)
            ? (store.supportsResume
                  ? 'التنزيل متوقف. يمكن استئنافه؛ إذا لم يدعم الخادم الاستئناف فسيبدأ من جديد.'
                  : 'التنزيل متوقف. على الويب تبدأ السورة غير المكتملة من جديد.')
            : 'تعذر التنزيل: تحقق من الاتصال والمساحة وصلاحية رابط المصدر. على الويب قد تمنع سياسة CORS التنزيل.';
        break;
      }
    }
    activeDownload = null;
    cancel = null;
    downloading = false;
    notifyListeners();
  }

  void pauseDownload() => cancel?.cancel();
  void resumeDownloads() {
    if (!downloading && queue.isNotEmpty) unawaited(_run());
  }

  void clearQueue() {
    if (!downloading) {
      queue.clear();
      downloadError = null;
      notifyListeners();
    }
  }

  Future<void> deleteDownload(String key) async {
    if (current != null && surah != null && current!.key(surah!) == key)
      await player.stop();
    await store.delete(key);
    downloaded.remove(key);
    await prefs.setStringList('downloads', downloaded.toList());
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel?.cancel();
    unawaited(_position.cancel());
    unawaited(_processing.cancel());
    unawaited(_errors.cancel());
    unawaited(player.dispose());
    super.dispose();
  }
}
