// lib/features/auth/plan_picker_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';
import 'register_screen.dart';
import '../../shared/widgets/app_colors.dart';
import '../../shared/widgets/app_button.dart';

class PlanPickerScreen extends ConsumerStatefulWidget {
  const PlanPickerScreen({super.key});

  @override
  ConsumerState<PlanPickerScreen> createState() => _PlanPickerScreenState();
}

class _PlanPickerScreenState extends ConsumerState<PlanPickerScreen> {
  String _selectedPlan = 'premium';
  bool   _isLoading    = false;
  String? _error;

  Future<void> _submit() async {
    if (_selectedPlan == 'enterprise') {
      _launchEnterpriseSales();
      return;
    }

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
            ownerPin:     ref.read(pendingOwnerPinProvider) ?? '0000',
            selectedPlan: _selectedPlan,
          );

      ref.read(pendingUserIdProvider.notifier).state       = null;
      ref.read(pendingOwnerPinProvider.notifier).state     = null;
      ref.read(pendingFullNameProvider.notifier).state     = null;
      ref.read(pendingBusinessNameProvider.notifier).state = null;
      ref.read(pendingBusinessTypeProvider.notifier).state = null;
      ref.read(pendingSelectedPlanProvider.notifier).state = 'premium';

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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Step indicator
              Row(
                children: [
                  _StepDot(active: true, done: true),
                  _StepLine(active: true),
                  _StepDot(active: true, done: true),
                  _StepLine(active: true),
                  _StepDot(active: true, done: false),
                ],
              ),
              const SizedBox(height: 28),

              const Text(
                'Choose your plan',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Step 3 of 3 — You can change this anytime.',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 32),

              // ── Plan cards ─────────────────────────────────────────────────
              _PlanCard(
                plan:        'free',
                title:       'Free',
                price:       '₱0 / month',
                description: 'Basic POS for a single location.',
                features: const [
                  _Feature('POS & orders',       true),
                  _Feature('Basic inventory',    true),
                  _Feature('Credits (utang)',    true),
                  _Feature('Shifts',             true),
                  _Feature('Reports & exports',  false),
                  _Feature('Kitchen display',    false),
                  _Feature('Table management',   false),
                ],
                isSelected: _selectedPlan == 'free',
                isBestValue: false,
                onTap: () => setState(() => _selectedPlan = 'free'),
              ),
              const SizedBox(height: 12),

              _PlanCard(
                plan:        'premium',
                title:       'Pro',
                price:       '₱X / month',
                description: 'Full access free for 7 days, then ₱X/mo.',
                features: const [
                  _Feature('POS & orders',       true),
                  _Feature('Basic inventory',    true),
                  _Feature('Credits (utang)',    true),
                  _Feature('Shifts',             true),
                  _Feature('Reports & exports',  true),
                  _Feature('Kitchen display',    true),
                  _Feature('Table management',   true),
                ],
                isSelected:  _selectedPlan == 'premium',
                isBestValue: true,
                onTap: () => setState(() => _selectedPlan = 'premium'),
              ),
              const SizedBox(height: 12),

              _PlanCard(
                plan:        'enterprise',
                title:       'Enterprise',
                price:       'Contact us',
                description: 'Multiple locations, dedicated support & SLA.',
                features: const [
                  _Feature('Everything in Pro',      true),
                  _Feature('Unlimited branches',     true),
                  _Feature('Dedicated support',      true),
                  _Feature('Custom integrations',    true),
                  _Feature('SLA guarantee',          true),
                ],
                isSelected:  _selectedPlan == 'enterprise',
                isBestValue: false,
                onTap: () => setState(() => _selectedPlan = 'enterprise'),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],

              const SizedBox(height: 28),

              AppButton(
                label:     _isLoading ? 'Setting up…' : _ctaLabel,
                onPressed: _isLoading ? null : _submit,
                icon:      Icons.check_rounded,
              ),

              const SizedBox(height: 12),
              Text(
                _selectedPlan == 'premium'
                    ? 'No credit card required. Trial ends in 7 days.'
                    : ' ',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  void _launchEnterpriseSales() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Contact Sales'),
        content: const Text(
          'For Enterprise pricing and onboarding, reach us at:\n\nsales@yourapp.com',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String get _ctaLabel => switch (_selectedPlan) {
        'free'       => 'Start with Free',
        'premium'    => 'Start 7-day trial',
        'enterprise' => 'Contact sales',
        _            => 'Continue',
      };
}

// ── Plan card ─────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final String         plan;
  final String         title;
  final String         price;
  final String         description;
  final List<_Feature> features;
  final bool           isSelected;
  final bool           isBestValue;
  final VoidCallback   onTap;

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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (isBestValue) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Best value',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        price,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            ...features.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(
                        f.included
                            ? Icons.check_circle_outline_rounded
                            : Icons.remove_circle_outline_rounded,
                        size: 16,
                        color: f.included
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        f.label,
                        style: TextStyle(
                          fontSize: 13,
                          color: f.included
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _Feature {
  final String label;
  final bool   included;
  const _Feature(this.label, this.included);
}

// ── Step indicator (matches register_screen.dart) ─────────────────────────────

class _StepDot extends StatelessWidget {
  final bool active;
  final bool done;
  const _StepDot({required this.active, required this.done});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? AppColors.primary : AppColors.border,
      ),
      child: Center(
        child: done
            ? const Icon(Icons.check, color: Colors.white, size: 16)
            : Text(
                '3',
                style: TextStyle(
                  color: active ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  final bool active;
  const _StepLine({required this.active});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 2,
        color: active ? AppColors.primary : AppColors.border,
      ),
    );
  }
}