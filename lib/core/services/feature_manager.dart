// lib/core/services/feature_manager.dart
import '../../core/models/business.dart';

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
  static const String export    = 'export';
  static const String barcode   = 'barcode';
}

// ── Feature sets ──────────────────────────────────────────────────────────────

const _freeFeatures = <String>{
  AppFeature.pos,
  AppFeature.orders,
  AppFeature.inventory,
  AppFeature.credits,
  AppFeature.shifts,
};

const _paidFeatures = <String>{
  AppFeature.pos,
  AppFeature.orders,
  AppFeature.inventory,
  AppFeature.credits,
  AppFeature.shifts,
  AppFeature.reports,
  AppFeature.kitchen,
  AppFeature.tables,
  AppFeature.export,
  AppFeature.barcode,
};

// ── FeatureManager ────────────────────────────────────────────────────────────

class FeatureManager {
  final Business? _business;
  // Config flags from business_configs — these are set per-business
  // during registration and can be toggled in settings independently
  // of the subscription plan.
  final bool configBarcodeEnabled;
  final bool configKitchenEnabled;
  final bool configTablesEnabled;

  const FeatureManager(
    this._business, {
    this.configBarcodeEnabled = false,
    this.configKitchenEnabled = false,
    this.configTablesEnabled  = false,
  });

  bool get hasFullAccess {
    if (_business == null) return false;
    if (_business.subscriptionPlan.isPaid) return true;
    return _business.isOnActiveTrial;
  }

  bool get isOnActiveTrial => _business?.isOnActiveTrial ?? false;
  int  get trialDaysLeft   => _business?.trialDaysLeft   ?? 0;

  SubscriptionPlan get currentPlan =>
      _business?.subscriptionPlan ?? SubscriptionPlan.free;

  bool hasFeature(String feature) {
    if (_business == null) return false;

    // Barcode: plan must allow it AND business config must have it enabled.
    // This keeps feature_manager and business_configs in sync — a retail
    // business on Basic+ has both gates satisfied; a restaurant does not.
    if (feature == AppFeature.barcode) {
      return (hasFullAccess ? _paidFeatures : _freeFeatures).contains(feature)
          && configBarcodeEnabled;
    }

    // Kitchen/tables: plan gate takes priority. Config is a secondary toggle
    // that only matters when the plan already allows it.
    if (feature == AppFeature.kitchen) {
      return hasFullAccess && configKitchenEnabled;
    }
    if (feature == AppFeature.tables) {
      return hasFullAccess && configTablesEnabled;
    }

    return (hasFullAccess ? _paidFeatures : _freeFeatures).contains(feature);
  }

  bool get canAccessReports => hasFeature(AppFeature.reports);
  bool get canAccessKitchen => hasFeature(AppFeature.kitchen);
  bool get canAccessTables  => hasFeature(AppFeature.tables);
  bool get canExport        => hasFeature(AppFeature.export);
}