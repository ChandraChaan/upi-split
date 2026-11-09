import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../data/session_controller.dart';
import 'strings_common.dart';

/// Translation lookup. Each app registers its own screen strings at startup
/// on top of the shared set; a test asserts both languages have every key.
class Tr {
  const Tr(this.language);
  final String language;

  static final Map<String, String> _en = Map.of(commonEn);
  static final Map<String, String> _te = Map.of(commonTe);

  static void register({required Map<String, String> en, required Map<String, String> te}) {
    _en.addAll(en);
    _te.addAll(te);
  }

  static Map<String, String> get english => Map.unmodifiable(_en);
  static Map<String, String> get telugu => Map.unmodifiable(_te);

  String call(String key, [Map<String, String> args = const {}]) {
    var text = (language == 'te' ? _te[key] : null) ?? _en[key];
    assert(text != null, 'Missing translation key: $key');
    text ??= key;
    args.forEach((k, v) => text = text!.replaceAll('{$k}', v));
    return text!;
  }
}

extension TrContext on BuildContext {
  /// Rebuilds the calling widget when the language changes.
  Tr get tr => Tr(select<SessionController, String>((s) => s.language));
}
