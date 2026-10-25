// Validate common MP3 prefixes before marking any download complete.
// This is a file-type guard, not a replacement for decoder validation.
bool isMp3(List<int> bytes) =>
    bytes.length >= 3 &&
    ((bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) ||
        (bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0));
bool allowedAudioType(String? contentType) {
  final type = (contentType ?? '').toLowerCase().split(';').first.trim();
  return type.startsWith('audio/') || type == 'application/octet-stream';
}
