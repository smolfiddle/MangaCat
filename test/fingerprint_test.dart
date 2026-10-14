import 'package:flutter_test/flutter_test.dart';
import 'package:mangacat/data/fingerprint.dart';

void main() {
  test('matches when size and mtime are equal', () {
    expect(const FileFingerprint(10, 100).matches(const FileFingerprint(10, 100)), isTrue);
  });

  test('detects size changes', () {
    expect(const FileFingerprint(10, 100).matches(const FileFingerprint(11, 100)), isFalse);
  });

  test('detects mtime changes', () {
    expect(const FileFingerprint(10, 100).matches(const FileFingerprint(10, 101)), isFalse);
  });

  test('ignores components the provider cannot report', () {
    expect(const FileFingerprint(-1, 100).matches(const FileFingerprint(-1, 100)), isTrue);
    expect(const FileFingerprint(-1, 100).matches(const FileFingerprint(-1, 101)), isFalse);
    expect(const FileFingerprint(10, -1).matches(const FileFingerprint(11, -1)), isFalse);
    expect(const FileFingerprint(-1, -1).matches(const FileFingerprint(10, 100)), isTrue);
  });
}
