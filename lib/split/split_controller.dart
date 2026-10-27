import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upi_kit/upi_kit.dart';

import 'pay_request.dart';
import 'split.dart';

/// Overridden in `main` with the loaded instance.
final preferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override preferencesProvider in main'),
);

/// Everything on the split screen.
class SplitState {
  const SplitState({
    this.myName = '',
    this.myVpa = '',
    this.bill = const Bill(),
  });

  final String myName;
  final String myVpa;
  final Bill bill;

  bool get hasValidVpa => Vpa.isValid(myVpa);

  SplitResult get result => split(bill);

  /// One request per friend who owes something.
  List<(Friend, PayRequest)> get requests {
    final perFriend = result.perFriend;
    return [
      for (final friend in bill.friends)
        if ((perFriend[friend.id] ?? 0) > 0)
          (
            friend,
            PayRequest(
              payeeVpa: myVpa.trim(),
              payeeName: myName.trim(),
              amountPaise: perFriend[friend.id]!,
              note: bill.title.trim(),
              friendName: friend.name,
            ),
          ),
    ];
  }

  SplitState copyWith({String? myName, String? myVpa, Bill? bill}) =>
      SplitState(
        myName: myName ?? this.myName,
        myVpa: myVpa ?? this.myVpa,
        bill: bill ?? this.bill,
      );
}

class SplitController extends Notifier<SplitState> {
  static const _myNameKey = 'my_name';
  static const _myVpaKey = 'my_vpa';
  static const _billKey = 'bill';

  SharedPreferences get _prefs => ref.read(preferencesProvider);

  @override
  SplitState build() {
    final prefs = ref.watch(preferencesProvider);
    var bill = const Bill();
    final saved = prefs.getString(_billKey);
    if (saved != null) {
      try {
        bill = Bill.fromJson(
          (jsonDecode(saved) as Map).cast<String, Object?>(),
        );
      } on Object {
        // A corrupt or old-format draft: start fresh rather than crash.
      }
    }
    return SplitState(
      myName: prefs.getString(_myNameKey) ?? '',
      myVpa: prefs.getString(_myVpaKey) ?? '',
      bill: bill,
    );
  }

  void setMyName(String name) {
    state = state.copyWith(myName: name);
    _prefs.setString(_myNameKey, name);
  }

  void setMyVpa(String vpa) {
    state = state.copyWith(myVpa: vpa.trim());
    _prefs.setString(_myVpaKey, vpa.trim());
  }

  void _setBill(Bill bill) {
    state = state.copyWith(bill: bill);
    _prefs.setString(_billKey, jsonEncode(bill.toJson()));
  }

  void setTitle(String title) => _setBill(state.bill.copyWith(title: title));

  void setTotalPaise(int paise) =>
      _setBill(state.bill.copyWith(totalPaise: paise));

  void setMode(SplitMode mode) => _setBill(state.bill.copyWith(mode: mode));

  void setIncludeMe(bool include) =>
      _setBill(state.bill.copyWith(includeMe: include));

  void setMyShares(int shares) =>
      _setBill(state.bill.copyWith(myShares: shares.clamp(1, 99)));

  void addFriend(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _setBill(
      state.bill.copyWith(
        friends: [
          ...state.bill.friends,
          Friend(id: id, name: trimmed),
        ],
      ),
    );
  }

  void removeFriend(String id) => _setBill(
    state.bill.copyWith(
      friends: [
        for (final f in state.bill.friends)
          if (f.id != id) f,
      ],
    ),
  );

  void updateFriend(String id, Friend Function(Friend) change) => _setBill(
    state.bill.copyWith(
      friends: [for (final f in state.bill.friends) f.id == id ? change(f) : f],
    ),
  );

  /// Clears the bill but keeps your name, UPI ID and friends' names, so the
  /// same group can split the next one quickly.
  void newBill({bool keepFriends = true}) => _setBill(
    Bill(
      includeMe: state.bill.includeMe,
      friends: keepFriends
          ? [for (final f in state.bill.friends) Friend(id: f.id, name: f.name)]
          : const [],
    ),
  );
}

final splitControllerProvider = NotifierProvider<SplitController, SplitState>(
  SplitController.new,
);
