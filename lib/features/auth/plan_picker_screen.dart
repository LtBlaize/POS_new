// lib/features/auth/plan_picker_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';
import 'register_screen.dart';
import 'widgets/auth_theme.dart';
import 'widgets/auth_components.dart';
import '../../core/config/store_build_flag.dart';

class PlanPickerScreen extends ConsumerStatefulWidget {
  const PlanPickerScreen({super.key});

  @override
  ConsumerState<PlanPickerScreen> createState() => _PlanPickerScreenState();
}

class _PlanPickerScreenState extends ConsumerState<PlanPickerScreen> {
  String _selectedPlan = 'growth';

  // Read once. _submit() clears pendingBusinessTypeProvider, and a
  // ref.watch would flip the wording back to retail mid-navigation.
  late final bool _isRestaurant;

  @override
  void initState() {
    super.initState();
    _isRestaurant = ref.read(pendingBusinessTypeProvider) == 'restaurant';
  }

  // Utang is retail-only (hidden in restaurant mode). Display filter only.
  List<_Feature> _forType(List<_Feature> f) => _isRestaurant
      ? f.where((x) => x.label != 'Credits (utang)').toList()
      : f.where((x) =>
          !x.label.startsWith('Kitchen display') &&
          !x.label.startsWith('Table') &&
          !x.label.startsWith('Tables') &&
          !x.label.startsWith('Multi-station kitchen') &&
          !x.label.startsWith('Unlimited tables')).toList();
  bool   _isLoading    = false;
  String? _error;

  Future<void> _submit() async {
    final userId = ref.read(pendingUserIdProvider);
    if (userId == null) {
      setState(() => _error = 'Session expired. Please register again.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error     = null;
    });

    try {
      ref.read(pendingSelectedPlanProvider.notifier).state = _selectedPlan;

      await ref.read(authServiceProvider).completeRegistration(
            userId:       userId,
            fullName:     ref.read(pendingFullNameProvider) ?? '',
            businessName: ref.read(pendingBusinessNameProvider) ?? '',
            businessType: ref.read(pendingBusinessTypeProvider) ?? 'retail',
            ownerPin:     ref.read(pendingOwnerPinProvider) ??
                (throw Exception('PIN missing')),
            selectedPlan: _selectedPlan,
          );

      ref.read(pendingUserIdProvider.notifier).state       = null;
      ref.read(pendingOwnerPinProvider.notifier).state     = null;
      ref.read(pendingFullNameProvider.notifier).state     = null;
      ref.read(pendingBusinessNameProvider.notifier).state = null;
      ref.read(pendingBusinessTypeProvider.notifier).state = null;
      ref.read(pendingSelectedPlanProvider.notifier).state = 'growth';

      // FIX: MyApp's authStateProvider listener already fired once during
      // OTP verification and bailed out via the "Mid-registration" guard.
      // No new auth event happens when completeRegistration() finishes, so
      // nothing re-triggers navigation. We must push it ourselves here.
      // /pending re-resolves profileProvider and routes to /pos once the
      // freshly-inserted profile/business rows are visible.
      ref.invalidate(profileProvider);
      if (mounted) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/pending', (route) => false);
      }
    } catch (e) {
      debugPrint('[PlanPicker] completeRegistration error: $e');
      if (mounted) {
        setState(() {
          _error     = 'Could not complete setup. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _PlanCard(
        plan: 'starter',
        title: 'Starter',
        price: kStoreBuild ? '7-day free trial' : '₱499 / month',
        description:
            _isRestaurant
                ? '1 terminal, up to 2 staff — the essentials to get started.'
                : '1 terminal, up to 2 staff — everything a growing tindahan needs.',
        features: _forType(const [
          _Feature('POS & orders', true),
          _Feature('Unlimited products', true),
          _Feature('Credits (utang)', true),
          _Feature('Shifts', true),
          _Feature('Up to 5 active promos', true),
          _Feature('Reports & Excel export', false),
          _Feature('Kitchen display', false),
          _Feature('Table management', false),
        ]),
        isSelected: _selectedPlan == 'starter',
        isBestValue: false,
        onTap: () => setState(() => _selectedPlan = 'starter'),
      ),
      _PlanCard(
        plan: 'growth',
        title: 'Growth',
        price: kStoreBuild ? '7-day free trial' : '₱799 / month',
        description:
            kStoreBuild
                ? 'Full access free for 7 days. Up to 3 terminals, unlimited staff.'
                : 'Full access free for 7 days, then ₱799/mo. Up to 3 terminals, unlimited staff.',
        features: _forType(const [
          _Feature('POS & orders', true),
          _Feature('Unlimited products', true),
          _Feature('Credits (utang)', true),
          _Feature('Shifts', true),
          _Feature('Unlimited promos', true),
          _Feature('Reports & Excel export', true),
          _Feature('Kitchen display (1 station)', true),
          _Feature('Tables (up to 6, 1 room)', true),
        ]),
        isSelected: _selectedPlan == 'growth',
        isBestValue: true,
        onTap: () => setState(() => _selectedPlan = 'growth'),
      ),
      _PlanCard(
        plan: 'pro',
        title: 'Pro',
        price: kStoreBuild ? '7-day free trial' : '₱1,299 / month',
        description:
            'Full access free for 7 days, then ₱1,299/mo. Unlimited terminals & tables.',
        features: _forType(const [
          _Feature('Everything in Growth', true),
          _Feature('Unlimited terminals', true),
          _Feature('Unlimited tables & rooms', true),
          _Feature('Multi-station kitchen', true),
          _Feature('Custom role permissions', true),
        ]),
        isSelected: _selectedPlan == 'pro',
        isBestValue: false,
        onTap: () => setState(() => _selectedPlan = 'pro'),
      ),
    ];

    return AuthScaffold(
      maxWidth: 1000,
      onBack: () => Navigator.pop(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthStepper(current: 3, label: 'Plan selection'),
          const SizedBox(height: 24),
          const Text('Choose your plan', style: AuthText.title),
          const SizedBox(height: 6),
          const Text('You can change this anytime.', style: AuthText.subtitle),
          const SizedBox(height: 24),

          // Side-by-side on wide windows, stacked on narrow ones.
          LayoutBuilder(builder: (context, c) {
            if (c.maxWidth >= 720) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(child: cards[i]),
                    ],
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  cards[i],
                ],
              ],
            );
          }),

          AuthErrorSlot(_error),
          const SizedBox(height: 24),

          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AuthButton(
                label: _isLoading ? 'Setting up…' : _ctaLabel,
                icon: Icons.check_rounded,
                loading: _isLoading,
                onPressed: _submit,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'No credit card required. Trial ends in 7 days.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AuthColors.textMuted),
          ),
        ],
      ),
    );
  }

  String get _ctaLabel => switch (_selectedPlan) {
        'starter' => 'Start 7-day trial',
        'growth' => 'Start 7-day trial',
        'pro' => 'Start 7-day trial',
        _ => 'Continue',
      };
}

// ── Plan card ─────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final String plan;
  final String title;
  final String price;
  final String description;
  final List<_Feature> features;
  final bool isSelected;
  final bool isBestValue;
  final VoidCallback onTap;

  const _PlanCard({
    required this.plan,
    required this.title,
    required this.price,
    required this.description,
    required this.features,
    required this.isSelected,
    required this.isBestValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isSelected
                ? AuthColors.accent.withValues(alpha: 0.10)
                : AuthColors.field,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? AuthColors.accentLight : AuthColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AuthColors.textPrimary)),
                        if (isBestValue)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AuthColors.accent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Best value',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? AuthColors.accent
                          : Colors.transparent,
                      border: Border.all(
                        color: isSelected
                            ? AuthColors.accentLight
                            : AuthColors.textMuted,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(price,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AuthColors.textPrimary)),
              const SizedBox(height: 8),
              Text(description,
                  style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AuthColors.textSecondary)),
              const SizedBox(height: 14),
              Container(height: 1, color: AuthColors.border),
              const SizedBox(height: 12),
              ...features.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          f.included
                              ? Icons.check_circle_rounded
                              : Icons.remove_circle_outline_rounded,
                          size: 16,
                          color: f.included
                              ? AuthColors.accentLight
                              : AuthColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            f.label,
                            style: TextStyle(
                              fontSize: 13,
                              color: f.included
                                  ? AuthColors.textPrimary
                                  : AuthColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _Feature {
  final String label;
  final bool included;
  const _Feature(this.label, this.included);
}