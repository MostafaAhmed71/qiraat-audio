import 'dart:convert';
import 'package:flutter/services.dart';

class Riwaya {
  final int id;
  final String qiraa, narrator;
  final List<int> sourceIds;
  const Riwaya(this.id, this.qiraa, this.narrator, this.sourceIds);
  String get label => '$narrator عن $qiraa';
}

const masarawiCategories = <int, int>{
  690: 1,
  689: 2,
  697: 3,
  706: 4,
  698: 5,
  691: 6,
  704: 7,
  705: 8,
  703: 9,
  688: 10,
  692: 11,
  700: 12,
  693: 13,
  699: 14,
  707: 15,
  696: 16,
  702: 17,
  701: 18,
  695: 19,
  694: 20,
};

class Mushaf {
  final int id, riwaya, reciterId, sourceRiwaya;
  final String reciter, name, server;
  final List<int> surahs;
  final String source;
  final int? sourceCategory;
  final String? sourcePage;
  final bool webDownloads;
  bool get verifiedExternal =>
      source == 'nquran' &&
      reciterId == 278 &&
      id == 100000 + (sourceCategory ?? 0) &&
      masarawiCategories[sourceCategory] == riwaya &&
      sourcePage == 'https://www.nquran.com/ar/categories/$sourceCategory/';
  const Mushaf({
    required this.id,
    required this.riwaya,
    required this.reciterId,
    required this.sourceRiwaya,
    required this.reciter,
    required this.name,
    required this.server,
    required this.surahs,
    this.source = 'mp3quran',
    this.sourceCategory,
    this.sourcePage,
    this.webDownloads = true,
  });
  factory Mushaf.fromJson(Map<String, dynamic> j) {
    final ss = (j['surahs'] as List).cast<int>();
    final uri = Uri.parse(j['server'] as String);
    final source = j['source'] as String? ?? 'mp3quran';
    final trusted = source == 'mp3quran'
        ? (uri.host == 'mp3quran.net' || uri.host.endsWith('.mp3quran.net'))
        : source == 'nquran' &&
              uri.host == 'www.nquran.com' &&
              uri.path.startsWith('/audiof/quran/ahmedmesarawi/');
    if (ss.isEmpty ||
        ss.toSet().length != ss.length ||
        ss.any((s) => s < 1 || s > 114) ||
        uri.scheme != 'https' ||
        !trusted) {
      throw const FormatException('Invalid source catalog');
    }
    return Mushaf(
      id: j['id'],
      riwaya: j['riwaya'],
      reciterId: j['reciterId'],
      sourceRiwaya: j['sourceRiwaya'],
      reciter: j['reciter'],
      name: j['name'],
      server: j['server'],
      surahs: List.unmodifiable(ss),
      source: source,
      sourceCategory: j['sourceCategory'],
      sourcePage: j['sourcePage'],
      webDownloads: j['webDownloads'] as bool? ?? true,
    );
  }
  String audioUrl(int surah) {
    if (!surahs.contains(surah)) throw ArgumentError('Surah not advertised');
    return '${server.replaceFirst(RegExp(r'/$'), '')}/${surah.toString().padLeft(3, '0')}.mp3';
  }

  String key(int surah) => '${id}_$surah';
}

class Catalog {
  final List<Riwaya> riwayat;
  final List<Mushaf> mushafs;
  final Map<int, String> suwar;
  final String checkedAt;
  Catalog(this.riwayat, this.mushafs, this.suwar, this.checkedAt);
  factory Catalog.parse(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    final rr = (j['riwayat'] as List)
        .map(
          (r) => Riwaya(
            r['id'],
            r['qiraa'],
            r['narrator'],
            (r['sourceIds'] as List).cast<int>(),
          ),
        )
        .toList();
    final mm = (j['mushafs'] as List)
        .map((m) => Mushaf.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    if (rr.length != 20 ||
        rr.map((r) => r.id).toSet().length != 20 ||
        mm.any(
          (m) => !rr.any(
            (r) =>
                r.id == m.riwaya &&
                (m.source == 'mp3quran'
                    ? r.sourceIds.contains(m.sourceRiwaya)
                    : m.verifiedExternal),
          ),
        )) {
      throw const FormatException('Unverified riwaya mapping');
    }
    return Catalog(rr, mm, {
      for (final s in j['suwar']) s['id'] as int: s['name'] as String,
    }, j['checkedAt']);
  }
  static Future<Catalog> bundled() async =>
      Catalog.parse(await rootBundle.loadString('assets/catalog.json'));
  List<Mushaf> forRiwaya(int id) {
    final result = mushafs.where((m) => m.riwaya == id).toList();
    result.sort((a, b) {
      final priorityA = a.reciterId == 278 ? 0 : 1;
      final priorityB = b.reciterId == 278 ? 0 : 1;
      if (priorityA != priorityB) return priorityA.compareTo(priorityB);
      if (a.reciterId == b.reciterId)
        return b.surahs.length.compareTo(a.surahs.length);
      return a.reciter.compareTo(b.reciter);
    });
    return result;
  }

  Mushaf byId(int id) => mushafs.firstWhere((m) => m.id == id);
}
