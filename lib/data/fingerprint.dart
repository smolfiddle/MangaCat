class FileFingerprint {
  const FileFingerprint(this.size, this.mtimeMs);

  final int size;
  final int mtimeMs;

  bool get isUsable => size >= 0 || mtimeMs >= 0;

  bool matches(FileFingerprint other) {
    final sizeKnown = size >= 0 && other.size >= 0;
    final mtimeKnown = mtimeMs >= 0 && other.mtimeMs >= 0;
    if (!sizeKnown && !mtimeKnown) return true;
    if (sizeKnown && size != other.size) return false;
    if (mtimeKnown && mtimeMs != other.mtimeMs) return false;
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is FileFingerprint && other.size == size && other.mtimeMs == mtimeMs;

  @override
  int get hashCode => Object.hash(size, mtimeMs);
}
