import 'package:flutter/widgets.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The store chosen in the top bar: one store, or null for all of them.
class StoreScope extends ChangeNotifier {
  StoreScope(this._prefs) : _storeId = _prefs.getString(_key);

  static const _key = 'admin_store_scope';
  final SharedPreferences _prefs;
  String? _storeId;

  String? get storeId => _storeId;

  void select(String? storeId) {
    if (storeId == _storeId) return;
    _storeId = storeId;
    notifyListeners();
    if (storeId == null) {
      _prefs.remove(_key);
    } else {
      _prefs.setString(_key, storeId);
    }
  }

  /// The stores in view, out of those this person may access.
  List<Store> resolve(List<Store> accessible) {
    final match = accessible.where((s) => s.id == _storeId).toList();
    return match.isNotEmpty ? match : accessible;
  }
}

/// Stores in view for the calling widget, which rebuilds when they change.
List<Store> scopedStores(BuildContext context) {
  final session = context.watch<SessionController>();
  return context.watch<StoreScope>().resolve(session.stores);
}

/// Finds a store from a route parameter; null if this person cannot access it.
Store? accessibleStore(BuildContext context, String storeId) {
  final session = context.watch<SessionController>();
  for (final s in session.stores) {
    if (s.id == storeId) return s;
  }
  return null;
}
