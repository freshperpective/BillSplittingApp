import 'package:decimal/decimal.dart';

/// Domain models. Plain Dart so the project compiles without codegen.
/// Switch to Freezed once `build_runner` is wired in CI.

class Profile {
  const Profile({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.defaultCurrency = 'INR',
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        displayName: json['display_name'] as String? ?? 'Unknown',
        avatarUrl: json['avatar_url'] as String?,
        defaultCurrency: json['default_currency'] as String? ?? 'INR',
      );

  final String id;
  final String displayName;
  final String? avatarUrl;
  final String defaultCurrency;

  Map<String, dynamic> toJson() => {
        'id': id,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'default_currency': defaultCurrency,
      };
}

class Group {
  const Group({
    required this.id,
    required this.name,
    required this.emoji,
    required this.defaultCurrency,
    required this.createdBy,
    this.archivedAt,
    required this.createdAt,
  });

  factory Group.fromJson(Map<String, dynamic> json) => Group(
        id: json['id'] as String,
        name: json['name'] as String,
        emoji: json['emoji'] as String? ?? '💸',
        defaultCurrency: json['default_currency'] as String? ?? 'INR',
        createdBy: json['created_by'] as String,
        archivedAt: json['archived_at'] == null
            ? null
            : DateTime.parse(json['archived_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String name;
  final String emoji;
  final String defaultCurrency;
  final String createdBy;
  final DateTime? archivedAt;
  final DateTime createdAt;

  bool get isArchived => archivedAt != null;
}

class GroupMember {
  const GroupMember({
    required this.groupId,
    required this.profileId,
    required this.role,
    required this.joinedAt,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) => GroupMember(
        groupId: json['group_id'] as String,
        profileId: json['profile_id'] as String,
        role: json['role'] as String? ?? 'member',
        joinedAt: DateTime.parse(json['joined_at'] as String),
      );

  final String groupId;
  final String profileId;
  final String role; // 'owner' | 'member'
  final DateTime joinedAt;
}

class ExpenseShare {
  const ExpenseShare({
    required this.profileId,
    required this.paidShare,
    required this.owedShare,
  });

  factory ExpenseShare.fromJson(Map<String, dynamic> json) => ExpenseShare(
        profileId: json['profile_id'] as String,
        paidShare: Decimal.parse(json['paid_share'].toString()),
        owedShare: Decimal.parse(json['owed_share'].toString()),
      );

  final String profileId;
  final Decimal paidShare;
  final Decimal owedShare;

  Map<String, dynamic> toJson() => {
        'profile_id': profileId,
        'paid_share': paidShare.toString(),
        'owed_share': owedShare.toString(),
      };
}

class Expense {
  const Expense({
    required this.id,
    required this.groupId,
    required this.description,
    required this.amount,
    required this.currency,
    required this.fxToGroup,
    required this.paidAt,
    required this.category,
    this.note,
    required this.createdBy,
    required this.createdAt,
    this.deletedAt,
    required this.shares,
  });

  factory Expense.fromJson(
    Map<String, dynamic> json, {
    List<ExpenseShare> shares = const [],
  }) =>
      Expense(
        id: json['id'] as String,
        groupId: json['group_id'] as String,
        description: json['description'] as String,
        amount: Decimal.parse(json['amount'].toString()),
        currency: json['currency'] as String,
        fxToGroup: Decimal.parse(json['fx_to_group']?.toString() ?? '1'),
        paidAt: DateTime.parse(json['paid_at'] as String),
        category: json['category'] as String? ?? 'general',
        note: json['note'] as String?,
        createdBy: json['created_by'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        deletedAt: json['deleted_at'] == null
            ? null
            : DateTime.parse(json['deleted_at'] as String),
        shares: shares,
      );

  final String id;
  final String groupId;
  final String description;
  final Decimal amount;
  final String currency;
  final Decimal fxToGroup;
  final DateTime paidAt;
  final String category;
  final String? note;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? deletedAt;
  final List<ExpenseShare> shares;

  bool get isDeleted => deletedAt != null;
}

class Settlement {
  const Settlement({
    required this.id,
    required this.groupId,
    required this.fromProfile,
    required this.toProfile,
    required this.amount,
    required this.currency,
    this.note,
    required this.createdAt,
  });

  factory Settlement.fromJson(Map<String, dynamic> json) => Settlement(
        id: json['id'] as String,
        groupId: json['group_id'] as String,
        fromProfile: json['from_profile'] as String,
        toProfile: json['to_profile'] as String,
        amount: Decimal.parse(json['amount'].toString()),
        currency: json['currency'] as String,
        note: json['note'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String groupId;
  final String fromProfile;
  final String toProfile;
  final Decimal amount;
  final String currency;
  final String? note;
  final DateTime createdAt;
}

enum ActivityKind {
  expenseAdd,
  expenseEdit,
  expenseDelete,
  settle,
  groupCreate,
  groupMemberAdd,
  groupMemberRemove;

  static ActivityKind parse(String s) {
    switch (s) {
      case 'expense.add':
        return ActivityKind.expenseAdd;
      case 'expense.edit':
        return ActivityKind.expenseEdit;
      case 'expense.delete':
        return ActivityKind.expenseDelete;
      case 'settle':
        return ActivityKind.settle;
      case 'group.create':
        return ActivityKind.groupCreate;
      case 'group.member.add':
        return ActivityKind.groupMemberAdd;
      case 'group.member.remove':
        return ActivityKind.groupMemberRemove;
    }
    throw ArgumentError('Unknown activity kind: $s');
  }
}

class ActivityEvent {
  const ActivityEvent({
    required this.id,
    this.groupId,
    required this.actor,
    required this.kind,
    required this.targetId,
    required this.payload,
    required this.createdAt,
  });

  factory ActivityEvent.fromJson(Map<String, dynamic> json) => ActivityEvent(
        id: json['id'] as String,
        groupId: json['group_id'] as String?,
        actor: json['actor'] as String,
        kind: ActivityKind.parse(json['kind'] as String),
        targetId: json['target_id'] as String,
        payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? {},
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String? groupId;
  final String actor;
  final ActivityKind kind;
  final String targetId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
}
