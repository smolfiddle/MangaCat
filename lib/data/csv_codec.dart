import 'dart:convert';

import 'package:csv/csv.dart';

import '../core/constants.dart';
import 'models/entry.dart';

class CsvFormatException implements Exception {
  const CsvFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CsvLoadReport {
  const CsvLoadReport({
    required this.entries,
    required this.skippedLines,
    required this.warnings,
    required this.advanced,
  });

  const CsvLoadReport.empty()
      : entries = const <Entry>[],
        skippedLines = const <int>[],
        warnings = const <String>[],
        advanced = false;

  final List<Entry> entries;
  final List<int> skippedLines;
  final List<String> warnings;
  final bool advanced;
}

abstract final class MangaCatCsv {
  static const List<String> simpleHeader = <String>['id', 'title', 'artist'];
  static const List<String> advancedHeader = <String>[
    'id',
    'title',
    'artist',
    'status',
    'rating',
    'progress',
    'notes',
  ];

  static const Set<String> _knownColumns = <String>{
    'id',
    'title',
    'artist',
    'status',
    'rating',
    'progress',
    'notes',
  };

  static CsvLoadReport decode(List<int> bytes) {
    if (bytes.isEmpty) {
      return const CsvLoadReport(
        entries: <Entry>[],
        skippedLines: <int>[],
        warnings: <String>['File is empty; start by adding a title.'],
        advanced: false,
      );
    }
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const CsvFormatException('Not a valid MangaCat CSV (not UTF-8 text).');
    }
    if (text.startsWith('\uFEFF')) {
      text = text.substring(1);
    }
    if (text.trim().isEmpty) {
      return const CsvLoadReport(
        entries: <Entry>[],
        skippedLines: <int>[],
        warnings: <String>['File is empty; start by adding a title.'],
        advanced: false,
      );
    }

    final headerLine = _firstLine(text);
    if (!headerLine.contains(',') && (headerLine.contains(';') || headerLine.contains('\t'))) {
      throw const CsvFormatException(
        'Not a valid MangaCat CSV (comma delimiter required).',
      );
    }

    final Csv codec = Csv(
      lineDelimiter: '\r\n',
      autoDetect: false,
      skipEmptyLines: false,
      dynamicTyping: false,
    );

    List<List<dynamic>> rows;
    try {
      rows = codec.decode(text);
    } on FormatException {
      throw const CsvFormatException('Not a valid MangaCat CSV (unreadable structure).');
    }
    if (rows.isEmpty) {
      return const CsvLoadReport.empty();
    }

    final List<String> header =
        rows.first.map((dynamic cell) => cell.toString().trim().toLowerCase()).toList();
    final int idIndex = header.indexOf('id');
    final int titleIndex = header.indexOf('title');
    if (idIndex < 0 || titleIndex < 0) {
      throw const CsvFormatException('Not a valid MangaCat CSV (missing id/title header).');
    }

    final warnings = <String>[];
    final unknown = header
        .where((String column) => column.isNotEmpty && !_knownColumns.contains(column))
        .toSet();
    if (unknown.isNotEmpty) {
      warnings.add('Ignored unknown column(s): ${unknown.join(', ')}.');
    }

    final int artistIndex = header.indexOf('artist');
    if (artistIndex < 0) {
      warnings.add('No artist column found; artists will be empty.');
    }
    final int statusIndex = header.indexOf('status');
    final int ratingIndex = header.indexOf('rating');
    final int progressIndex = header.indexOf('progress');
    final int notesIndex = header.indexOf('notes');
    final bool advanced = statusIndex >= 0 ||
        ratingIndex >= 0 ||
        progressIndex >= 0 ||
        notesIndex >= 0;

    final entries = <Entry>[];
    final usedIds = <int>{};
    final skippedLines = <int>[];
    var runningMax = 0;
    final now = DateTime.now();

    for (var i = 1; i < rows.length; i++) {
      final List<dynamic> row = rows[i];
      final int lineNo = i + 1;
      if (row.isEmpty || row.every((dynamic cell) => cell.toString().trim().isEmpty)) {
        continue;
      }
      if (row.length > header.length) {
        warnings.add('Line $lineNo: extra columns ignored.');
      }

      String cell(int index) =>
          index >= 0 && index < row.length ? row[index].toString() : '';

      final String title = cell(titleIndex);
      if (title.trim().isEmpty) {
        skippedLines.add(lineNo);
        continue;
      }

      final String rawId = cell(idIndex).trim();
      int id;
      if (rawId.isEmpty) {
        id = _nextFreeId(usedIds, runningMax);
        warnings.add('Line $lineNo: missing id; assigned $id.');
      } else {
        final int? parsed = int.tryParse(rawId);
        if (parsed == null || parsed <= 0) {
          skippedLines.add(lineNo);
          continue;
        }
        id = parsed;
        if (usedIds.contains(id)) {
          id = _nextFreeId(usedIds, runningMax);
          warnings.add('Line $lineNo: duplicate id remapped to $id.');
        }
      }
      usedIds.add(id);
      if (id > runningMax) runningMax = id;

      final String rawStatus = cell(statusIndex).trim();
      var status = EntryStatus.none;
      if (rawStatus.isNotEmpty) {
        if (EntryStatus.isValidCsv(rawStatus)) {
          status = EntryStatus.fromCsv(rawStatus);
        } else {
          warnings.add("Line $lineNo: unknown status '$rawStatus' treated as none.");
        }
      }

      final String rawRating = cell(ratingIndex).trim();
      var rating = 0;
      if (rawRating.isNotEmpty) {
        final int? parsed = int.tryParse(rawRating);
        if (parsed == null) {
          warnings.add("Line $lineNo: unreadable rating '$rawRating' treated as 0.");
        } else {
          rating = parsed.clamp(0, 5);
          if (rating != parsed) {
            warnings.add('Line $lineNo: rating $parsed clamped to $rating.');
          }
        }
      }

      var progress = cell(progressIndex);
      if (progress.length > kProgressMaxChars) {
        progress = progress.substring(0, kProgressMaxChars);
        warnings.add('Line $lineNo: progress truncated to $kProgressMaxChars characters.');
      }
      var notes = cell(notesIndex);
      if (notes.length > kNotesMaxChars) {
        notes = notes.substring(0, kNotesMaxChars);
        warnings.add('Line $lineNo: notes truncated to $kNotesMaxChars characters.');
      }

      entries.add(
        Entry(
          id: id,
          title: title,
          artist: cell(artistIndex),
          status: status,
          rating: rating,
          progress: progress,
          notes: notes,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    if (skippedLines.isNotEmpty) {
      warnings.add('Skipped malformed line(s): ${skippedLines.join(', ')}.');
    }

    return CsvLoadReport(
      entries: entries,
      skippedLines: skippedLines,
      warnings: warnings,
      advanced: advanced,
    );
  }

  static String encode(List<Entry> entries, {required bool advanced}) {
    final sorted = List<Entry>.of(entries)..sort((Entry a, Entry b) => a.id.compareTo(b.id));
    final rows = <List<dynamic>>[
      if (advanced) advancedHeader else simpleHeader,
    ];
    for (final Entry entry in sorted) {
      if (advanced) {
        rows.add(<String>[
          entry.id.toString(),
          entry.title,
          entry.artist,
          entry.status == EntryStatus.none ? '' : entry.status.value,
          entry.rating <= 0 ? '' : entry.rating.toString(),
          entry.progress,
          entry.notes,
        ]);
      } else {
        rows.add(<String>[entry.id.toString(), entry.title, entry.artist]);
      }
    }
    final String body = Csv(lineDelimiter: '\r\n').encode(rows);
    return body.endsWith('\r\n') ? body : '$body\r\n';
  }

  static int _nextFreeId(Set<int> used, int runningMax) {
    var candidate = runningMax + 1;
    while (used.contains(candidate)) {
      candidate++;
    }
    return candidate;
  }

  static String _firstLine(String text) {
    final int lf = text.indexOf('\n');
    final int cr = text.indexOf('\r');
    var end = text.length;
    if (lf >= 0 && lf < end) end = lf;
    if (cr >= 0 && cr < end) end = cr;
    return text.substring(0, end);
  }
}
