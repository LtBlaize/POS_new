// lib/core/models/staff.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';

enum StaffRole { owner, manager, cashier, kitchen }

extension StaffRolePermissions on StaffRole {
  String get key => switch (this) {
        StaffRole.owner => 'owner',
        StaffRole.manager => 'manager',
        StaffRole.cashier => 'cashier',
        StaffRole.kitchen => 'kitchen',
      };
}

extension StaffRoleX on StaffRole {
  String get label => switch (this) {
        StaffRole.owner => 'Owner',
        StaffRole.manager => 'Manager',
        StaffRole.cashier => 'Cashier',
        StaffRole.kitchen => 'Kitchen',
      };

  String get value => name;

  bool get canAccessPOS =>
      this == StaffRole.owner ||
      this == StaffRole.manager ||
      this == StaffRole.cashier;

  bool get canAccessOrders =>
      this == StaffRole.owner ||
      this == StaffRole.manager ||
      this == StaffRole.cashier;

  bool get canAccessKitchen =>
      this == StaffRole.owner ||
      this == StaffRole.manager ||
      this == StaffRole.kitchen;

  bool get canAccessInventory =>
      this == StaffRole.owner || this == StaffRole.manager;

  bool get canAccessReports => this == StaffRole.owner;

  bool get canAccessSettings => this == StaffRole.owner;
}

/// Returns the assignable (non-owner) roles available for a given business type.
/// Retail: cashier only.
/// Restaurant: manager, cashier, kitchen.
extension StaffRoleAvailability on StaffRole {
  static List<StaffRole> forBusinessType(bool isRestaurant) {
    if (isRestaurant) {
      return [StaffRole.manager, StaffRole.cashier, StaffRole.kitchen];
    }
    return [StaffRole.cashier];
  }
}

class StaffMember {
  final String id;
  final String businessId;
  final String name;
  final StaffRole role;
  final String pinHash;
  final bool isActive;

  const StaffMember({
    required this.id,
    required this.businessId,
    required this.name,
    required this.role,
    required this.pinHash,
    required this.isActive,
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
        id: json['id'] as String,
        businessId: json['business_id'] as String,
        name: json['name'] as String,
        role: StaffRole.values.firstWhere(
          (r) => r.value == json['role'],
          orElse: () => StaffRole.cashier,
        ),
        pinHash: json['pin_hash'] as String,
        isActive: json['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'business_id': businessId,
        'name': name,
        'role': role.value,
        'pin_hash': pinHash,
        'is_active': isActive,
      };

  static String hashPin(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

  bool checkPin(String pin) => hashPin(pin) == pinHash;
} 