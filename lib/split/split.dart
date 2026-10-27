/// How a bill is divided between people.
enum SplitMode {
  /// Everyone pays the same.
  equal,

  /// Each person pays in proportion to their shares (a couple counts as 2).
  shares,

  /// Each person's amount is typed in.
  amounts,
}

/// Someone sharing the bill. The person who paid is not in this list: their
/// own share is worked out separately and never requested.
class Friend {
  const Friend({
    required this.id,
    required this.name,
    this.shares = 1,
    this.customPaise = 0,
    this.paid = false,
  });

  final String id;
  final String name;

  /// Used by [SplitMode.shares].
  final int shares;

  /// Used by [SplitMode.amounts].
  final int customPaise;

  /// Ticked once they've paid you back.
  final bool paid;

  Friend copyWith({String? name, int? shares, int? customPaise, bool? paid}) =>
      Friend(
        id: id,
        name: name ?? this.name,
        shares: shares ?? this.shares,
        customPaise: customPaise ?? this.customPaise,
        paid: paid ?? this.paid,
      );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'shares': shares,
    'customPaise': customPaise,
    'paid': paid,
  };

  factory Friend.fromJson(Map<String, Object?> json) => Friend(
    id: json['id'] as String,
    name: json['name'] as String,
    shares: (json['shares'] as int?) ?? 1,
    customPaise: (json['customPaise'] as int?) ?? 0,
    paid: (json['paid'] as bool?) ?? false,
  );

  @override
  bool operator ==(Object other) =>
      other is Friend &&
      other.id == id &&
      other.name == name &&
      other.shares == shares &&
      other.customPaise == customPaise &&
      other.paid == paid;

  @override
  int get hashCode => Object.hash(id, name, shares, customPaise, paid);
}

/// One bill: what it was for, the total, and who shares it.
class Bill {
  const Bill({
    this.title = '',
    this.totalPaise = 0,
    this.mode = SplitMode.equal,
    this.includeMe = true,
    this.myShares = 1,
    this.friends = const [],
  });

  final String title;

  /// The whole bill, including tax and tip, in paise.
  final int totalPaise;

  final SplitMode mode;

  /// Whether the person who paid also has a share (usual for dinners), or
  /// paid on behalf of others only.
  final bool includeMe;

  /// The payer's own shares in [SplitMode.shares].
  final int myShares;

  final List<Friend> friends;

  Bill copyWith({
    String? title,
    int? totalPaise,
    SplitMode? mode,
    bool? includeMe,
    int? myShares,
    List<Friend>? friends,
  }) => Bill(
    title: title ?? this.title,
    totalPaise: totalPaise ?? this.totalPaise,
    mode: mode ?? this.mode,
    includeMe: includeMe ?? this.includeMe,
    myShares: myShares ?? this.myShares,
    friends: friends ?? this.friends,
  );

  Map<String, Object> toJson() => {
    'title': title,
    'totalPaise': totalPaise,
    'mode': mode.name,
    'includeMe': includeMe,
    'myShares': myShares,
    'friends': [for (final f in friends) f.toJson()],
  };

  factory Bill.fromJson(Map<String, Object?> json) => Bill(
    title: (json['title'] as String?) ?? '',
    totalPaise: (json['totalPaise'] as int?) ?? 0,
    mode: SplitMode.values.asNameMap()[json['mode']] ?? SplitMode.equal,
    includeMe: (json['includeMe'] as bool?) ?? true,
    myShares: (json['myShares'] as int?) ?? 1,
    friends: [
      for (final f in (json['friends'] as List<Object?>?) ?? const [])
        Friend.fromJson((f as Map).cast<String, Object?>()),
    ],
  );
}

/// The result of splitting a [Bill].
class SplitResult {
  const SplitResult({
    required this.perFriend,
    required this.myPaise,
    required this.unassignedPaise,
  });

  /// What each friend owes, by friend id.
  final Map<String, int> perFriend;

  /// The payer's own share.
  final int myPaise;

  /// In [SplitMode.amounts]: the total minus everything typed in. Positive
  /// means part of the bill is still unassigned (it's treated as the payer's
  /// share), negative means the amounts add up to more than the bill.
  final int unassignedPaise;

  /// What the payer gets back in total.
  int get owedToMePaise => perFriend.values.fold(0, (a, b) => a + b);
}

/// Splits [totalPaise] by [weights] so the parts add up exactly to the total.
///
/// Uses the largest-remainder method: everyone gets their exact share rounded
/// down, then the leftover paise go one by one to the largest remainders
/// (earlier entries win ties). No paisa is ever lost or invented.
List<int> allocate(int totalPaise, List<int> weights) {
  if (totalPaise < 0) throw ArgumentError.value(totalPaise, 'totalPaise');
  if (weights.any((w) => w < 0)) {
    throw ArgumentError.value(weights, 'weights', 'Must not be negative');
  }
  final sum = weights.fold(0, (a, b) => a + b);
  if (sum == 0) return List.filled(weights.length, 0);

  final parts = [for (final w in weights) totalPaise * w ~/ sum];
  final remainders = [
    for (var i = 0; i < weights.length; i++) (totalPaise * weights[i]) % sum,
  ];
  var left = totalPaise - parts.fold(0, (a, b) => a + b);
  final order = List.generate(weights.length, (i) => i)
    ..sort((a, b) {
      final byRemainder = remainders[b].compareTo(remainders[a]);
      return byRemainder != 0 ? byRemainder : a.compareTo(b);
    });
  for (final i in order) {
    if (left == 0) break;
    parts[i]++;
    left--;
  }
  return parts;
}

/// Works out who owes what for [bill].
SplitResult split(Bill bill) {
  final friends = bill.friends;
  switch (bill.mode) {
    case SplitMode.equal:
    case SplitMode.shares:
      final friendWeights = [
        for (final f in friends) bill.mode == SplitMode.equal ? 1 : f.shares,
      ];
      final myWeight = !bill.includeMe
          ? 0
          : bill.mode == SplitMode.equal
          ? 1
          : bill.myShares;
      // The payer goes last: when the total doesn't divide evenly, the odd
      // paise go to friends rather than staying with the payer.
      final parts = allocate(bill.totalPaise, [...friendWeights, myWeight]);
      return SplitResult(
        perFriend: {
          for (var i = 0; i < friends.length; i++) friends[i].id: parts[i],
        },
        myPaise: parts.last,
        unassignedPaise: 0,
      );
    case SplitMode.amounts:
      final assigned = friends.fold(0, (a, f) => a + f.customPaise);
      final rest = bill.totalPaise - assigned;
      return SplitResult(
        perFriend: {for (final f in friends) f.id: f.customPaise},
        myPaise: rest > 0 ? rest : 0,
        unassignedPaise: rest,
      );
  }
}
