Future<void> downloadJsonFile(String fileName, String jsonContent) async {
  // Non-web fallback: no-op. Export is still available via clipboard.
}

Future<void> downloadTextFile(
  String fileName,
  String content, {
  String mimeType = 'text/plain;charset=utf-8',
}) async {
  // Non-web fallback: no-op.
}
