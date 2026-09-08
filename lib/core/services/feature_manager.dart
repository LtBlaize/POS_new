// lib/core/services/feature_manager.dart
import '../../core/models/business.dart';
import '../config/access_enforcement_flag.dart';

// ── Feature constants ─────────────────────────────────────────────────────────

class AppFeature {
  AppFeature._();

  static const String pos       = 'pos';
  static const String orders    = 'orders';
  static const String inventory = 'inventory';
  static const String credits   = 'credits';
  static const String shifts    = 'shifts';
  static const String reports   = 'reports';
  static const String kitchen   = 'kitchen';
  static const String tables    = 'tables';
  static const String barcode   = 'barcode';
  static const String excelExport   = 'excel_export';
  static const String auditExport   = 'audit_export';
  static const String customRoles   = 'custom_roles';
}

// ── Plan limits ───────────────────────────────────────────────────────────────
// null = unlimited

class PlanLimits {
  final int? maxTerminals;
  final int? maxStaffAccounts;
  final int? maxActivePromos;
  final int? maxTables;
  final int? maxRooms;
  final int? maxKitchenStations;
  final int storageQuotaMb;
  final bool kitchenIncluded;
  final bool tablesIncluded;
  final bool excelExportIncluded;
  final bool auditExportIncluded;
  final bool customRolesIncluded;

  const PlanLimits({
    required this.maxTerminals,
    required this.maxStaffAccounts,
    required this.maxActivePromos,
    required this.maxTables,
    required this.maxRooms,
    required this.maxKitchenStations,
    required this.storageQuotaMb,
    required this.kitchenIncluded,
    required this.tablesIncluded,
    required this.excelExportIncluded,
    required this.auditExportIncluded,
    required this.customRolesIncluded,
  });

  static bool isUnlimited(int? limit) => limit == null;
}

const _starterLimits = PlanLimits(
  maxTerminals: 1,
  maxStaffAccounts: 2,
  maxActivePromos: 5,
  maxTables: 0,
  maxRooms: 0,
  maxKitchenStations: 0,
  storageQuotaMb: 500,
  kitchenIncluded: false,
  tablesIncluded: false,
  excelExportIncluded: false,
  auditExportIncluded: false,
  customRolesIncluded: false,
);

const _growthLimits = PlanLimits(
  maxTerminals: 3,
  maxStaffAccounts: null,
  maxActivePromos: null,
  maxTables: 6,
  maxRooms: 1,
  maxKitchenStations: 1,
  storageQuotaMb: 2048,
  kitchenIncluded: true,
  tablesIncluded: true,
  excelExportIncluded: true,
  auditExportIncluded: true,
  customRolesIncluded: false,
);

const _proLimits = PlanLimits(
  maxTerminals: null,
  maxStaffAccounts: null,
  maxActivePromos: null,
  maxTables: null,
  maxRooms: null,
  maxKitchenStations: null,
  storageQuotaMb: 10240,
  kitchenIncluded: true,
  tablesIncluded: true,
  excelExportIncluded: true,
  auditExportIncluded: true,
  customRolesIncluded: true,
);

PlanLimits limitsFor(SubscriptionPlan plan) => switch (plan) {
      SubscriptionPlan.starter => _starterLimits,
      SubscriptionPlan.growth  => _growthLimits,
      SubscriptionPlan.pro     => _proLimits,
    };

// ── FeatureManager ────────────────────────────────────────────────────────────

class FeatureManager {
  final Business? _business;
  // Config flags from business_configs — set per-business at registration,
  // toggleable in settings independently of the plan. A feature is only
  // actually on when BOTH the plan includes it AND the config enables it.
  final bool configBarcodeEnabled;
  final bool configKitchenEnabled;
  final bool configTablesEnabled;

  const FeatureManager(
    this._business, {
    this.configBarcodeEnabled = false,
    this.configKitchenEnabled = false,
    this.configTablesEnabled  = false,
  });

  bool get isOnActiveTrial => _business?.isOnActiveTrial ?? false;
  int  get trialDaysLeft   => _business?.trialDaysLeft   ?? 0;

  SubscriptionPlan get currentPlan =>
      _business?.subscriptionPlan ?? SubscriptionPlan.starter;

  PlanLimits get limits => limitsFor(currentPlan);

  // Core features (pos/orders/inventory/credits/shifts/barcode) require the
  // business to be active AND either on a live trial or a live paid
  // subscription (Gap A's three-way rule).
  //
  // Gated behind kEnforceCoreAccess: until that flag flips true, this stays
  // permissive (any existing business passes) — same practical effect as
  // the old hardcoded isPaid. This single getter is the only place real
  // enforcement turns on, and it turns on everywhere at once: the POS-shell
  // lockout AND every hasFeature() check below both read this getter, so
  // there's no risk of one enforcing before the other.
  bool get hasCoreAccess {
    if (_business == null) return false;
    if (!kEnforceCoreAccess) return true;
    return _business.isActive &&
        (isOnActiveTrial || _business.isSubscriptionActive);
  }

  bool hasFeature(String feature) {
    if (!hasCoreAccess) return false;

    switch (feature) {
      case AppFeature.barcode:
        return configBarcodeEnabled;
      case AppFeature.kitchen:
        return limits.kitchenIncluded && configKitchenEnabled;
      case AppFeature.tables:
        return limits.tablesIncluded && configTablesEnabled;
      case AppFeature.excelExport:
        return limits.excelExportIncluded;
      case AppFeature.auditExport:
        return limits.auditExportIncluded;
      case AppFeature.customRoles:
        return limits.customRolesIncluded;
      case AppFeature.pos:
      case AppFeature.orders:
      case AppFeature.inventory:
      case AppFeature.credits:
      case AppFeature.shifts:
      case AppFeature.reports:
        return true;
      default:
        return false;
    }
  }

  // ── Convenience getters ─────────────────────────────────────────────────────
  bool get canAccessReports    => hasFeature(AppFeature.reports);
  bool get canAccessKitchen    => hasFeature(AppFeature.kitchen);
  bool get canAccessTables     => hasFeature(AppFeature.tables);
  bool get canExportExcel      => hasFeature(AppFeature.excelExport);
  bool get canExportAuditLog   => hasFeature(AppFeature.auditExport);
  bool get canEditCustomRoles  => hasFeature(AppFeature.customRoles);

  // ── Limit checks (call before insert operations) ────────────────────────────
  bool canAddTerminal(int currentCount) =>
      PlanLimits.isUnlimited(limits.maxTerminals) ||
      currentCount < limits.maxTerminals!;

  bool canAddStaff(int currentCount) =>
      PlanLimits.isUnlimited(limits.maxStaffAccounts) ||
      currentCount < limits.maxStaffAccounts!;

  bool canAddActivePromo(int currentActiveCount) =>
      PlanLimits.isUnlimited(limits.maxActivePromos) ||
      currentActiveCount < limits.maxActivePromos!;

  bool canAddTable(int currentCount) =>
      limits.tablesIncluded &&
      (PlanLimits.isUnlimited(limits.maxTables) ||
          currentCount < limits.maxTables!);

  bool canAddRoom(int currentCount) =>
      limits.tablesIncluded &&
      (PlanLimits.isUnlimited(limits.maxRooms) ||
          currentCount < limits.maxRooms!);

  bool canAddKitchenStation(int currentCount) =>
      limits.kitchenIncluded &&
      (PlanLimits.isUnlimited(limits.maxKitchenStations) ||
          currentCount < limits.maxKitchenStations!);
}