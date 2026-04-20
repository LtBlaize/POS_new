import 'business.dart';

class Profile {
  final String id; // matches auth.users id
  final String? businessId;
  final String fullName;
  final UserRole role;
  final String? avatarUrl;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined relations (populated when fetched with select('*, businesses(*)'))
  final Business? business;

  const Profile({
    required this.id,
    this.businessId,
    required this.fullName,
    required this.role,
    this.avatarUrl,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.business,
  });

  factory Profile.fromMap(Map<String, dynamic> map) {
    // 'businesses' is the joined object from Supabase select('*, businesses(*)')
    final businessMap = map['businesses'] as Map<String, dynamic>?;

    return Profile(
      id: map['id'] as String,
      businessId: map['business_id'] as String?,
      fullName: map['full_name'] as String,
      role: UserRole.fromString(map['role'] as String),
      avatarUrl: map['avatar_url'] as String?,
      isActive: map['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      business: businessMap != null ? Business.fromMap(businessMap) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'full_name': fullName,
      'role': role.value,
      'avatar_url': avatarUrl,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Profile copyWith({
    String? id,
    String? businessId,
    String? fullName,
    UserRole? role,
    String? avatarUrl,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    Business? business,
  }) {
    return Profile(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      business: business ?? this.business,
    );
  }

  // Convenience getters
  BusinessType? get businessType => business?.businessType;
  bool get isRestaurant => business?.businessType.isRestaurant ?? false;
  bool get isRetail     => business?.businessType.isRetail ?? false;
  bool get isOwner      => role == UserRole.owner;
  bool get isManager    => role == UserRole.manager;
  bool get canManageInventory =>
      role == UserRole.owner || role == UserRole.manager;

  @override
  String toString() =>
      'Profile(id: $id, name: $fullName, role: $role, business: ${business?.name})';
}

// ── UserRole enum ─────────────────────────────────────────────────────────────

enum UserRole {
  owner('owner'),
  manager('manager'),
  cashier('cashier'),
  kitchenStaff('kitchen_staff'),
  waiter('waiter');

  final String value;
  const UserRole(this.value);

  factory UserRole.fromString(String value) {
    return UserRole.values.firstWhere(
      (e) => e.value == value,
      orElse: () => UserRole.cashier,
    );
  }

  String get displayName {
    return switch (this) {
      UserRole.owner        => 'Owner',
      UserRole.manager      => 'Manager',
      UserRole.cashier      => 'Cashier',
      UserRole.kitchenStaff => 'Kitchen Staff',
      UserRole.waiter       => 'Waiter',
    };
  }
}