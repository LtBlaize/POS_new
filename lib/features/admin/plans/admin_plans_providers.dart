// lib/features/admin/plans/admin_plans_providers.dart
//
// Phase 9. Direct client CRUD against subscription_plans, protected by
// Phase 2's RLS (admin-only read/write) — no Edge Function, since this is
// catalog config with no per-business side effect, unlike Phase 7/8's writes.
// features jsonb is edited as raw JSON text in the form; kept intentionally
// simple rather than building a dynamic feature-flag editor UI.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

class SubscriptionPlan {
  final String id;
  final String name;
  final double price;
  final String billingInterval; // 'monthly' | 'yearly'
  final Map<String, dynamic> features;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.price,
    required this.billingInterval,
    required this.features,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SubscriptionPlan.fromMap(Map<String, dynamic> m) => SubscriptionPlan(
        id: m['id'] as String,
        name: m['name'] as String,
        price: (m['price'] as num?)?.toDouble() ?? 0,
        billingInterval: m['billing_interval'] as String? ?? 'monthly',
        features: (m['features'] as Map<String, dynamic>?) ?? {},
        isActive: m['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        updatedAt: DateTime.parse(m['updated_at'] as String).toLocal(),
      );
}

final subscriptionPlansProvider =
    FutureProvider.autoDispose<List<SubscriptionPlan>>((ref) async {
  try {
    final client = Supabase.instance.client;
    final rows = await client
        .from('subscription_plans')
        .select()
        .order('price', ascending: true);
    return (rows as List)
        .map((r) => SubscriptionPlan.fromMap(r as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
});

class AdminPlansService {
  final _client = Supabase.instance.client;

  /// Throws on failure (unique name violation, invalid JSON, RLS denial) —
  /// callers should catch and surface e.toString() to the admin.
  Future<void> createPlan({
    required String name,
    required double price,
    required String billingInterval,
    required Map<String, dynamic> features,
    bool isActive = true,
  }) async {
    await _client.from('subscription_plans').insert({
      'name': name,
      'price': price,
      'billing_interval': billingInterval,
      'features': features,
      'is_active': isActive,
    });
  }

  Future<void> updatePlan({
    required String id,
    required String name,
    required double price,
    required String billingInterval,
    required Map<String, dynamic> features,
    required bool isActive,
  }) async {
    await _client.from('subscription_plans').update({
      'name': name,
      'price': price,
      'billing_interval': billingInterval,
      'features': features,
      'is_active': isActive,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> setActive(String id, bool isActive) async {
    await _client
        .from('subscription_plans')
        .update({'is_active': isActive, 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
  }
}

final adminPlansServiceProvider = Provider<AdminPlansService>((ref) => AdminPlansService());

/// Parses the features JSON textarea; throws FormatException with a message
/// suitable for direct display if invalid.
Map<String, dynamic> parseFeaturesJson(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return {};
  final decoded = jsonDecode(trimmed);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Features must be a JSON object, e.g. {"kitchen": true}');
  }
  return decoded;
}