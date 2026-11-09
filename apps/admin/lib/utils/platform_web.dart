import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

class PickedTextFile {
  const PickedTextFile(this.name, this.text);
  final String name;
  final String text;
}

void downloadTextFile(String filename, String content, {String mime = 'text/csv'}) {
  final blob = web.Blob(
    <JSAny>[content.toJS].toJS,
    web.BlobPropertyBag(type: '$mime;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}

Future<PickedTextFile?> pickTextFile({String accept = '.csv'}) {
  final completer = Completer<PickedTextFile?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = accept;
  input.addEventListener(
    'change',
    (web.Event _) {
      final file = input.files?.item(0);
      if (file == null) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      file.text().toDart.then((text) {
        if (!completer.isCompleted) {
          completer.complete(PickedTextFile(file.name, text.toDart));
        }
      }, onError: (Object error) {
        if (!completer.isCompleted) completer.completeError(error);
      });
    }.toJS,
  );
  input.addEventListener(
    'cancel',
    (web.Event _) {
      if (!completer.isCompleted) completer.complete(null);
    }.toJS,
  );
  input.click();
  return completer.future;
}

/// Prints [html] from a hidden frame, so the browser lays out real text rather
/// than a picture of the app's canvas.
void printHtml(String html) {
  final frame = web.HTMLIFrameElement();
  frame.style
    ..position = 'fixed'
    ..right = '0'
    ..bottom = '0'
    ..width = '0'
    ..height = '0'
    ..border = '0';
  frame.addEventListener(
    'load',
    (web.Event _) {
      frame.contentWindow?.focus();
      frame.contentWindow?.print();
      Timer(const Duration(minutes: 1), () => frame.remove());
    }.toJS,
  );
  frame.srcdoc = html.toJS;
  web.document.body?.append(frame);
}
