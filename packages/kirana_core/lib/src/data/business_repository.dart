import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models.dart';

class InviteError implements Exception {
  const InviteError(this.code);

  /// One of: not_found, used, expired.
  final String code;
  @override
  String toString() => 'InviteError($code)';
}

/// Business-level operations: onboarding, stores and staff. These happen
/// online, with the exception of editing a store's details.
class BusinessRepository {
  BusinessRepository(this.db, {Random? random}) : _random = random ?? Random.secure();

  final FirebaseFirestore db;
  final Random _random;

  static const _inviteAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const inviteLifetime = Duration(days: 7);

  DocumentReference<Json> _business(String id) => db.doc('businesses/$id');

  /// Creates the business, its first store, and the owner's membership.
  Future<String> createBusiness({
    required String uid,
    required String email,
    required String ownerName,
    required String businessName,
    required String storeName,
  }) async {
    final business = db.collection('businesses').doc();
    final store = business.collection('stores').doc();
    final batch = db.batch();
    batch.set(business, {
      'name': businessName.trim(),
      'ownerUid': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(business.collection('members').doc(uid), {
      'name': ownerName.trim(),
      'email': email,
      'role': MemberRole.owner.name,
      'storeIds': <String>[],
      'active': true,
    });
    batch.set(store, Store(id: store.id, name: storeName.trim()).toMap());
    batch.set(db.doc('users/$uid'), {'businessId': business.id});
    await batch.commit();
    return business.id;
  }

  Stream<List<Store>> stores(String businessId) =>
      _business(businessId).collection('stores').snapshots().map(
          (s) => s.docs.map((d) => Store.fromMap(d.id, d.data())).toList()
            ..sort((a, b) => a.name.compareTo(b.name)));

  Stream<List<Member>> members(String businessId) =>
      _business(businessId).collection('members').snapshots().map(
          (s) => s.docs.map((d) => Member.fromMap(d.id, d.data())).toList()
            ..sort((a, b) => a.name.compareTo(b.name)));

  Future<String> addStore(String businessId, Store store) async {
    final ref = _business(businessId).collection('stores').doc();
    await ref.set(store.toMap());
    return ref.id;
  }

  Future<void> updateStore(String businessId, Store store) =>
      _business(businessId).collection('stores').doc(store.id).set(store.toMap());

  Future<void> updateMember(
    String businessId,
    String uid, {
    MemberRole? role,
    List<String>? storeIds,
    bool? active,
  }) =>
      _business(businessId).collection('members').doc(uid).update({
        if (role != null) 'role': role.name,
        'storeIds': ?storeIds,
        'active': ?active,
      });

  Future<Invite> createInvite({
    required Business business,
    required String createdBy,
    required MemberRole role,
    required List<String> storeIds,
    DateTime? now,
  }) async {
    if (role == MemberRole.owner) throw ArgumentError('Owner cannot be invited');
    final code = _newCode();
    final expiresAt = (now ?? DateTime.now()).add(inviteLifetime);
    await db.doc('invites/$code').set({
      'businessId': business.id,
      'businessName': business.name,
      'role': role.name,
      'storeIds': storeIds,
      'createdBy': createdBy,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'usedBy': null,
    });
    return Invite(
      code: code,
      businessId: business.id,
      businessName: business.name,
      role: role,
      storeIds: storeIds,
      expiresAt: expiresAt,
    );
  }

  Stream<List<Invite>> openInvites(String businessId) => db
      .collection('invites')
      .where('businessId', isEqualTo: businessId)
      .where('usedBy', isNull: true)
      .snapshots()
      .map((s) => s.docs.map((d) => Invite.fromMap(d.id, d.data())).toList());

  Future<void> revokeInvite(String code) => db.doc('invites/$code').delete();

  /// Joins a business using an invite. Security rules re-check everything here.
  Future<void> joinWithInvite({
    required String code,
    required String uid,
    required String email,
    required String name,
    DateTime? now,
  }) async {
    final normalized = code.trim().toUpperCase();
    final doc = await db.doc('invites/$normalized').get();
    if (!doc.exists) throw const InviteError('not_found');
    final invite = Invite.fromMap(doc.id, doc.data()!);
    if (invite.usedBy != null) throw const InviteError('used');
    if (invite.expiresAt.isBefore(now ?? DateTime.now())) {
      throw const InviteError('expired');
    }
    final batch = db.batch();
    batch.set(_business(invite.businessId).collection('members').doc(uid), {
      'name': name.trim(),
      'email': email,
      'role': invite.role.name,
      'storeIds': invite.storeIds,
      'active': true,
      'inviteCode': normalized,
    });
    batch.update(db.doc('invites/$normalized'), {
      'usedBy': uid,
      'usedAt': FieldValue.serverTimestamp(),
    });
    batch.set(db.doc('users/$uid'), {'businessId': invite.businessId});
    await batch.commit();
  }

  String _newCode() => List.generate(
          8, (_) => _inviteAlphabet[_random.nextInt(_inviteAlphabet.length)])
      .join();
}
