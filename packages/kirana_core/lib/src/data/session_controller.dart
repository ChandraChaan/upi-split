import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import '../domain/money.dart';
import 'business_repository.dart';
import 'store_repository.dart';
import 'sync_monitor.dart';

enum SessionStage { loading, signedOut, needsOnboarding, deactivated, ready }

/// Who is signed in, which business and store they are working in, and the
/// chosen language. Works from Firestore's cache on an offline cold start.
class SessionController extends ChangeNotifier {
  SessionController({
    required this.auth,
    required this.db,
    required this.prefs,
    this.sync,
  }) : businesses = BusinessRepository(db) {
    _language = prefs.getString(_languageKey) ?? 'te';
    _storeId = prefs.getString(_storeKey);
    _authSub = auth.authStateChanges().listen(_onAuth);
  }

  static const _languageKey = 'language';
  static const _storeKey = 'selected_store';
  static const _deviceKey = 'device_tag';

  final FirebaseAuth auth;
  final FirebaseFirestore db;
  final SharedPreferences prefs;
  final SyncMonitor? sync;
  final BusinessRepository businesses;

  StreamSubscription<User?>? _authSub;
  final List<StreamSubscription<dynamic>> _subs = [];

  SessionStage stage = SessionStage.loading;
  User? user;
  Business? business;
  Member? member;
  List<Store> allStores = const [];
  String? _storeId;
  late String _language;
  StoreRepository? _repository;
  String? _repositoryKey;

  String get language => _language;

  List<Store> get stores {
    final m = member;
    if (m == null) return const [];
    return allStores.where((s) => m.canAccess(s.id)).toList();
  }

  Store? get store {
    final list = stores;
    if (list.isEmpty) return null;
    return list.firstWhere((s) => s.id == _storeId, orElse: () => list.first);
  }

  Actor? get actor {
    final m = member;
    return m == null ? null : Actor(uid: m.uid, name: m.name, role: m.role);
  }

  /// The repository for the selected store.
  StoreRepository get repository {
    final repo = _repository;
    if (repo == null) throw StateError('No store selected');
    return repo;
  }

  StoreRepository repositoryFor(String storeId) => StoreRepository(
        db,
        businessId: business!.id,
        storeId: storeId,
        actor: actor!,
        sync: sync,
      );

  Future<void> setLanguage(String language) async {
    _language = language;
    notifyListeners();
    await prefs.setString(_languageKey, language);
  }

  Future<void> selectStore(String storeId) async {
    _storeId = storeId;
    _rebuildRepository();
    notifyListeners();
    await prefs.setString(_storeKey, storeId);
  }

  Future<void> signOut() => auth.signOut();

  /// Bill number unique across offline devices: day, device tag, sequence.
  /// Example: 261109-K7-14.
  Future<String> nextBillNumber([DateTime? now]) async {
    var tag = prefs.getString(_deviceKey);
    if (tag == null) {
      const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      final random = Random.secure();
      tag = List.generate(3, (_) => alphabet[random.nextInt(alphabet.length)]).join();
      await prefs.setString(_deviceKey, tag);
    }
    final key = dayKey(now ?? DateTime.now());
    final counterKey = 'bill_seq_$key';
    final next = (prefs.getInt(counterKey) ?? 0) + 1;
    await prefs.setInt(counterKey, next);
    final compact = key.substring(2).replaceAll('-', '');
    return '$compact-$tag-$next';
  }

  void _onAuth(User? next) {
    _cancelData();
    user = next;
    business = null;
    member = null;
    allStores = const [];
    _rebuildRepository();
    if (next == null) {
      stage = SessionStage.signedOut;
      notifyListeners();
      return;
    }
    stage = SessionStage.loading;
    notifyListeners();
    _subs.add(db.doc('users/${next.uid}').snapshots(includeMetadataChanges: true).listen((doc) {
      // Onboarding's batch shows up locally before the server has the matching
      // member record. Listening now would be denied, and a denied listener
      // never recovers, so wait for the acknowledgement.
      if (doc.metadata.hasPendingWrites) return;
      final businessId = doc.data()?['businessId'] as String?;
      if (businessId == null) {
        // An empty cache proves nothing while offline; wait for the server.
        if (!doc.metadata.isFromCache) {
          stage = SessionStage.needsOnboarding;
          notifyListeners();
        }
        return;
      }
      if (business?.id != businessId) _listenToBusiness(next.uid, businessId);
    }, onError: _onDataError));
  }

  void _listenToBusiness(String uid, String businessId) {
    while (_subs.length > 1) {
      _subs.removeLast().cancel();
    }
    final root = db.doc('businesses/$businessId');
    _subs.add(root.snapshots().listen((doc) {
      if (doc.exists) business = Business.fromMap(doc.id, doc.data()!);
      _refresh();
    }, onError: _onDataError));
    _subs.add(root.collection('members').doc(uid).snapshots().listen((doc) {
      member = doc.exists ? Member.fromMap(doc.id, doc.data()!) : null;
      _refresh();
    }, onError: _onDataError));
    _subs.add(businesses.stores(businessId).listen((list) {
      allStores = list;
      _refresh();
    }, onError: _onDataError));
  }

  void _refresh() {
    final m = member;
    if (business == null || m == null) return;
    stage = m.active ? SessionStage.ready : SessionStage.deactivated;
    _rebuildRepository();
    notifyListeners();
  }

  void _rebuildRepository() {
    final s = store;
    final a = actor;
    final b = business;
    if (s == null || a == null || b == null) {
      _repository = null;
      _repositoryKey = null;
      return;
    }
    final key = '${b.id}/${s.id}/${a.uid}/${a.role.name}/${a.name}';
    if (key == _repositoryKey) return;
    _repositoryKey = key;
    _repository = StoreRepository(db, businessId: b.id, storeId: s.id, actor: a, sync: sync);
  }

  void _onDataError(Object error) {
    // Losing access (for example, removal by the owner) lands here.
    debugPrint('Session data error: $error');
    if (member == null) {
      stage = SessionStage.deactivated;
      notifyListeners();
    }
  }

  void _cancelData() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _cancelData();
    super.dispose();
  }
}
