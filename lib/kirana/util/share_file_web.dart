import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Browsers share from memory; there is no file system to write to.
Future<XFile> shareableFile(
  Uint8List bytes, {
  required String name,
  required String mimeType,
}) async => XFile.fromData(bytes, name: name, mimeType: mimeType);
