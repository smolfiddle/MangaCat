class FileFingerprint {
  const FileFingerprint(this.size, this.mtimeMs);

  final int size;
  final int mtimeMs;

  bool get isUsable => size >= 0 || mtimeMs >= 0;

  @override
  bool operator ==(Object other) =>
      other is FileFingerprint && other.size == size && other.mtimeMs == mtimeMs;

  @override
  int get hashCode => Object.hash(size, mtimeMs);
}
