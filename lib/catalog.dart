import 'dart:convert';
import 'package:flutter/services.dart';

class Riwaya {
  final int id;
  final String qiraa, narrator;
  final List<int> sourceIds;
  const Riwaya(this.id, this.qiraa, this.narrator, this.sourceIds);
  String get label => '$narrator عن $qiraa';
}

class Mushaf {
  final int id, riwaya, reciterId, sourceRiwaya;
  final String reciter, name, server;
  final List<int> surahs;
  const Mushaf({
    required this.id,
    required this.riwaya,
    required this.reciterId,
    required this.sourceRiwaya,
    required this.reciter,
    required this.name,
    required this.server,
    required this.surahs,
  });
  factory Mushaf.fromJson(Map<String, dynamic> j) {
    final ss = (j['surahs'] as List).cast<int>();
    final uri = Uri.parse(j['server'] as String);
    if (ss.isEmpty ||
        ss.toSet().length != ss.length ||
        ss.any((s) => s < 1 || s > 114) ||
        uri.scheme != 'https' ||
        !(uri.host == 'mp3quran.net' || uri.host.endsWith('.mp3quran.net'))) {
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
            (r) => r.id == m.riwaya && r.sourceIds.contains(m.sourceRiwaya),
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
  List<Mushaf> forRiwaya(int id) =>
      mushafs.where((m) => m.riwaya == id).toList();
  Mushaf byId(int id) => mushafs.firstWhere((m) => m.id == id);
}
