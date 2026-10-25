import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:qiraat_audio/catalog.dart';

void main() {
  final c = Catalog.parse(File('assets/catalog.json').readAsStringSync());
  test('Twenty canonical riwayat from ten readings, not API categories', () {
    expect(c.riwayat.length, 20);
    expect(c.riwayat.map((r) => r.qiraa).toSet().length, 10);
    expect(c.suwar.length, 114);
  });
  test(
    'No shared or stylistic categories are assigned to individual narrators',
    () {
      for (final m in c.mushafs) {
        final r = c.riwayat.singleWhere((r) => r.id == m.riwaya);
        if (m.source == 'mp3quran')
          expect(r.sourceIds, contains(m.sourceRiwaya));
        else
          expect(m.verifiedExternal, isTrue);
        expect([9, 11, 21, 22], isNot(contains(m.sourceRiwaya)));
      }
    },
  );
  test(
    'Every advertised audio URL comes from its source server and actual list',
    () {
      for (final m in c.mushafs) {
        for (final n in m.surahs) {
          final url = Uri.parse(m.audioUrl(n));
          expect(url.scheme, 'https');
          expect(url.path, endsWith('/${n.toString().padLeft(3, '0')}.mp3'));
        }
        final missing = List.generate(
          114,
          (i) => i + 1,
        ).where((n) => !m.surahs.contains(n));
        if (missing.isNotEmpty)
          expect(() => m.audioUrl(missing.first), throwsArgumentError);
      }
    },
  );
  test(
    'Partial mushafs stay partial and API gaps only use verified external sources',
    () {
      expect(c.mushafs.any((m) => m.surahs.length < 114), isTrue);
      for (final r in c.riwayat.where((r) => r.sourceIds.isEmpty)) {
        expect(c.forRiwaya(r.id).every((m) => m.verifiedExternal), isTrue);
      }
      final short = c.mushafs.firstWhere((m) => m.surahs.length < 114);
      for (var i = 0; i < short.surahs.length - 1; i++) {
        expect(short.surahs[i + 1], greaterThan(short.surahs[i]));
      }
    },
  );
  test(
    'Masarawi is first in every riwaya, and the exact nQuran lists match imported audio',
    () {
      final raw =
          jsonDecode(File('assets/masarawi-nquran.json').readAsStringSync())
              as Map<String, dynamic>;
      expect((raw['records'] as List).length, 20);
      for (final row in raw['records']) {
        final m = c.byId(100000 + (row['category'] as int));
        expect(m.surahs.length, 64);
        expect(m.surahs.first, 51);
        expect(m.surahs.last, 114);
        expect(m.webDownloads, isFalse);
        expect(c.forRiwaya(m.riwaya).first.reciterId, 278);
        for (final n in m.surahs) expect(m.audioUrl(n), row['tracks']['$n']);
      }
    },
  );
  test('Malformed or cross-origin source records are rejected', () {
    expect(
      () => Mushaf.fromJson({
        'id': 1,
        'riwaya': 1,
        'sourceRiwaya': 1,
        'reciterId': 1,
        'reciter': 'x',
        'name': 'x',
        'server': 'https://example.com/',
        'surahs': [1],
      }),
      throwsFormatException,
    );
    expect(
      () => Catalog.parse('{"riwayat": [], "mushafs": []}'),
      throwsFormatException,
    );
  });
}
