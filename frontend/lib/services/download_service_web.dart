import 'dart:convert';
import 'dart:html' as html;

Future<void> downloadJsonFile(String fileName, String jsonContent) async {
  await downloadTextFile(
    fileName,
    jsonContent,
    mimeType: 'application/json;charset=utf-8',
  );
}

Future<void> downloadTextFile(
  String fileName,
  String content, {
  String mimeType = 'text/plain;charset=utf-8',
}) async {
  final bytes = utf8.encode(content);
  final blob = html.Blob(<dynamic>[bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';

  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
