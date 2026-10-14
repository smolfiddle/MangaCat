import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mangacat/data/csv_codec.dart';
import 'package:mangacat/data/models/entry.dart';

List<int> bytes(String value) => utf8.encode(value);

Entry makeEntry({
  int id = 1,
  String title = 'Title',
  String artist = '',
  EntryStatus status = EntryStatus.none,
  int rating = 0,
  String progress = '',
  String notes = '',
}) {
  final now = DateTime(2026, 1, 1);
  return Entry(
    id: id,
    title: title,
    artist: artist,
    status: status,
    rating: rating,
    progress: progress,
    notes: notes,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('decode', () {
    test('parses a simple CSV', () {
      final report = MangaCatCsv.decode(
        bytes('id,title,artist\r\n1,"Solo Leveling",\r\n2,"Bocchi the Rock!",\r\n'),
      );
      expect(report.advanced, isFalse);
      expect(report.entries.length, 2);
      expect(report.entries.first.title, 'Solo Leveling');
      expect(report.entries.first.artist, '');
      expect(report.entries.last.title, 'Bocchi the Rock!');
    });

    test('parses advanced CSV and detects advanced mode', () {
      final report = MangaCatCsv.decode(
        bytes('id,title,artist,status,rating,progress,notes\r\n'
            '1,Frieren,Kanehito Yamada,completed,5,,\r\n'
            '2,Berserk,Kentaro Miura,reading,4,ch. 143,peak\r\n'),
      );
      expect(report.advanced, isTrue);
      expect(report.entries[0].status, EntryStatus.completed);
      expect(report.entries[0].rating, 5);
      expect(report.entries[1].progress, 'ch. 143');
      expect(report.entries[1].notes, 'peak');
    });

    test('handles quoted commas and escaped quotes', () {
      final report = MangaCatCsv.decode(
        bytes('id,title,artist\r\n1,"Hello, World",Bob "The Builder"\r\n'),
      );
      expect(report.entries.single.title, 'Hello, World');
      expect(report.entries.single.artist, 'Bob "The Builder"');
    });

    test('accepts LF line endings', () {
      final report = MangaCatCsv.decode(bytes('id,title,artist\n1,Alpha,Ann\n'));
      expect(report.entries.single.title, 'Alpha');
      expect(report.entries.single.artist, 'Ann');
    });

    test('semicolons inside quoted fields keep the comma dialect', () {
      final report = MangaCatCsv.decode(
        bytes('id,title,artist,notes\r\n1,Alpha,Ann,"a;b;c;d;e"\r\n'),
      );
      expect(report.entries.single.notes, 'a;b;c;d;e');
    });

    test('rejects semicolon-delimited files', () {
      expect(
        () => MangaCatCsv.decode(bytes('id;title;artist\n1;Alpha;Ann')),
        throwsA(isA<CsvFormatException>()),
      );
    });

    test('rejects tab-delimited files', () {
      expect(
        () => MangaCatCsv.decode(bytes('id\ttitle\tartist\n1\tAlpha\tAnn')),
        throwsA(isA<CsvFormatException>()),
      );
    });

    test('rejects files without id/title header', () {
      expect(
        () => MangaCatCsv.decode(bytes('name,artist\nAlpha,Ann')),
        throwsA(isA<CsvFormatException>()),
      );
    });

    test('rejects non-UTF8 bytes', () {
      expect(
        () => MangaCatCsv.decode(<int>[0xC3, 0x28, 0xFF]),
        throwsA(isA<CsvFormatException>()),
      );
    });

    test('empty file decodes to empty list with warning', () {
      final report = MangaCatCsv.decode(<int>[]);
      expect(report.entries, isEmpty);
      expect(report.warnings, isNotEmpty);
    });

    test('skips malformed lines and reports line numbers', () {
      final report = MangaCatCsv.decode(
        bytes('id,title,artist\r\n'
            '1,Good,Ann\r\n'
            'notanumber,Bad,Bob\r\n'
            ',NoId,,\r\n'
            '2,"",Carl\r\n'),
      );
      expect(report.entries.length, 2);
      expect(report.skippedLines, containsAll(<int>[3, 5]));
      expect(report.warnings.join(' '), contains('Skipped malformed line'));
      expect(report.entries.last.id, 2);
    });

    test('remaps duplicate ids', () {
      final report = MangaCatCsv.decode(
        bytes('id,title,artist\r\n1,Alpha,Ann\r\n1,Beta,Bob\r\n'),
      );
      expect(report.entries.length, 2);
      expect(report.entries[0].id, 1);
      expect(report.entries[1].id, isNot(1));
      expect(report.warnings.join(' '), contains('duplicate id'));
    });

    test('warns about unknown columns but loads known ones', () {
      final report = MangaCatCsv.decode(
        bytes('id,title,artist,genre\r\n1,Alpha,Ann,horror\r\n'),
      );
      expect(report.entries.single.title, 'Alpha');
      expect(report.warnings.join(' '), contains('genre'));
    });

    test('warns about unknown status values', () {
      final report = MangaCatCsv.decode(
        bytes('id,title,artist,status\r\n1,Alpha,,paused\r\n'),
      );
      expect(report.entries.single.status, EntryStatus.none);
      expect(report.warnings.join(' '), contains('paused'));
    });

    test('truncates over-long progress and notes', () {
      final longProgress = 'p' * 60;
      final longNotes = 'n' * 600;
      final report = MangaCatCsv.decode(
        bytes('id,title,artist,progress,notes\r\n1,Alpha,,$longProgress,$longNotes\r\n'),
      );
      expect(report.entries.single.progress.length, 40);
      expect(report.entries.single.notes.length, 500);
      expect(report.warnings.length, greaterThanOrEqualTo(2));
    });

    test('clamps out-of-range ratings', () {
      final report = MangaCatCsv.decode(
        bytes('id,title,artist,rating\r\n1,Alpha,,9\r\n'),
      );
      expect(report.entries.single.rating, 5);
    });
  });

  group('encode', () {
    test('writes sorted rows with CRLF and RFC4180 quoting', () {
      final csv = MangaCatCsv.encode(
        <Entry>[
          makeEntry(id: 2, title: 'Hello, World', artist: 'Bob'),
          makeEntry(id: 1, title: 'Alpha', artist: 'Ann'),
        ],
        advanced: false,
      );
      expect(csv, startsWith('id,title,artist\r\n'));
      expect(csv, endsWith('\r\n'));
      final lines = csv.trim().split('\r\n');
      expect(lines[1], '1,Alpha,Ann');
      expect(lines[2], '2,"Hello, World",Bob');
    });

    test('advanced mode includes all columns', () {
      final csv = MangaCatCsv.encode(
        <Entry>[
          makeEntry(
            id: 1,
            title: 'Alpha',
            artist: 'Ann',
            status: EntryStatus.completed,
            rating: 5,
            progress: 'ch. 10',
            notes: 'note',
          ),
        ],
        advanced: true,
      );
      expect(csv.split('\r\n').first, 'id,title,artist,status,rating,progress,notes');
      expect(csv, contains('1,Alpha,Ann,completed,5,ch. 10,note'));
    });

    test('simple mode omits advanced data', () {
      final csv = MangaCatCsv.encode(
        <Entry>[makeEntry(id: 1, status: EntryStatus.completed, rating: 5)],
        advanced: false,
      );
      expect(csv.split('\r\n').first, 'id,title,artist');
      expect(csv, isNot(contains('completed')));
      expect(csv, isNot(contains(',5')));
    });

    test('encode/decode roundtrip preserves entries', () {
      final original = <Entry>[
        makeEntry(
          id: 7,
          title: 'Quote "Test", comma',
          artist: 'Ann',
          status: EntryStatus.reading,
          rating: 3,
          progress: 'Vol 2',
          notes: 'multi\nline',
        ),
      ];
      final csv = MangaCatCsv.encode(original, advanced: true);
      final report = MangaCatCsv.decode(bytes(csv));
      expect(report.entries.single.title, original.single.title);
      expect(report.entries.single.artist, 'Ann');
      expect(report.entries.single.status, EntryStatus.reading);
      expect(report.entries.single.rating, 3);
      expect(report.entries.single.progress, 'Vol 2');
      expect(report.entries.single.notes, 'multi\nline');
    });
  });
}
