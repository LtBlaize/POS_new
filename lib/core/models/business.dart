// lib/core/models/business.dart

// ── BusinessType enum ─────────────────────────────────────────────────────────

enum BusinessType {
  restaurant('restaurant'),
  retail('retail'),
  cafe('cafe'),
  bakery('bakery');

  final String value;
  const BusinessType(this.value);

  factory BusinessType.fromString(String v) => BusinessType.values.firstWhere(
        (e) => e.value == v,
        orElse: () => BusinessType.retail,
      );

  String get displayName => switch (this) {
        BusinessType.restaurant => 'Restaurant',
        BusinessType.retail     => 'Retail Store',
        BusinessType.cafe       => 'Café',
        BusinessType.bakery     => 'Bakery',
      };

  bool get isRestaurant =>
      this == BusinessType.restaurant ||
      this == BusinessType.cafe ||
      this == BusinessType.bakery;

  bool get isRetail => this == BusinessType.retail;
}

// ── SubscriptionPlan enum ─────────────────────────────────────────────────────

enum SubscriptionPlan {
  free('free'),
  basic('basic'),
  premium('premium');

  final String value;
  const SubscriptionPlan(this.value);

  factory SubscriptionPlan.fromString(String v) =>
      SubscriptionPlan.values.firstWhere(
        (e) => e.value == v,
        orElse: () => SubscriptionPlan.free,
      );

  String get displayName => switch (this) {
        SubscriptionPlan.free    => 'Free',
        SubscriptionPlan.basic   => 'Basic',
        SubscriptionPlan.premium => 'Premium',
      };
}

// ── Business model ────────────────────────────────────────────────────────────

class Business {
  final String id;
  final String name;
  final BusinessType businessType;
  final SubscriptionPlan subscriptionPlan;
  final String? logoUrl;
  final String? address;
  final String? phone;
  final String? email;
  final String currency;
  final String timezone;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Business({
    required this.id,
    required this.name,
    required this.businessType,
    this.subscriptionPlan = SubscriptionPlan.free,
    this.logoUrl,
    this.address,
    this.phone,
    this.email,
    this.currency = 'PHP',
    this.timezone = 'Asia/Manila',
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Business.fromMap(Map<String, dynamic> map) => Business(
        id: map['id'] as String,
        name: map['name'] as String,
        businessType:
            BusinessType.fromString(map['business_type'] as String),
        subscriptionPlan: SubscriptionPlan.fromString(
            map['subscription_plan'] as String? ?? 'free'),
        logoUrl: map['logo_url'] as String?,
        address: map['address'] as String?,
        phone: map['phone'] as String?,
        email: map['email'] as String?,
        currency: map['currency'] as String? ?? 'PHP',
        timezone: map['timezone'] as String? ?? 'Asia/Manila',
        isActive: map['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'business_type': businessType.value,
        'subscription_plan': subscriptionPlan.value,
        'logo_url': logoUrl,
        'address': address,
        'phone': phone,
        'email': email,
        'currency': currency,
        'timezone': timezone,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  Business copyWith({
    String? id,
    String? name,
    BusinessType? businessType,
    SubscriptionPlan? subscriptionPlan,
    String? logoUrl,
    String? address,
    String? phone,
    String? email,
    String? currency,
    String? timezone,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Business(
        id: id ?? this.id,
        name: name ?? this.name,
        businessType: businessType ?? this.businessType,
        subscriptionPlan: subscriptionPlan ?? this.subscriptionPlan,
        logoUrl: logoUrl ?? this.logoUrl,
        address: address ?? this.address,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        currency: currency ?? this.currency,
        timezone: timezone ?? this.timezone,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  String toString() =>
      'Business(id: $id, name: $name, type: ${businessType.value}, '
      'plan: ${subscriptionPlan.value})';
}