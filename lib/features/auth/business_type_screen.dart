// lib/features/auth/business_type_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'register_screen.dart';
import 'plan_picker_screen.dart';
import 'widgets/auth_text_field.dart';
import 'widgets/business_type_card.dart';
import '../../shared/widgets/app_colors.dart';
import '../../shared/widgets/app_button.dart';// for DeviceRole + deviceRoleProvider

class BusinessTypeScreen extends ConsumerStatefulWidget {
  const BusinessTypeScreen({super.key});

  @override
  ConsumerState<BusinessTypeScreen> createState() => _BusinessTypeScreenState();
}

class _BusinessTypeScreenState extends ConsumerState<BusinessTypeScreen> {
  final _formKey          = GlobalKey<FormState>();
  final _fullNameCtrl     = TextEditingController();
  final _businessNameCtrl = TextEditingController();

  String? _selectedType;
  String? _error;

  static const _options = [
    _BusinessOption(
      type: 'restaurant',
      label: 'Restaurant / Food Service',
      description: 'Table management, kitchen display, dine-in & takeout orders.',
      icon: Icons.restaurant_rounded,
    ),
    _BusinessOption(
      type: 'retail',
      label: 'Retail Store',
      description: 'Barcode scanning, inventory tracking, walk-in sales.',
      icon: Icons.storefront_rounded,
    ),
  ];

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _businessNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a business type.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final userId = ref.read(pendingUserIdProvider);
    if (userId == null) {
      setState(() => _error = 'Session expired. Please register again.');
      return;
    }

    // Store everything the plan picker will need.
    ref.read(pendingFullNameProvider.notifier).state     = _fullNameCtrl.text.trim();
    ref.read(pendingBusinessNameProvider.notifier).state = _businessNameCtrl.text.trim();
    ref.read(pendingBusinessTypeProvider.notifier).state = _selectedType;

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlanPickerScreen()),
    );
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
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Step indicator
                Row(
                  children: [
                    _StepDot(active: true, done: true),
                    _StepLine(active: true),
                    _StepDot(active: true, done: false),
                    _StepLine(active: false),
                    _StepDot(active: false, done: false),
                  ],
                ),
                const SizedBox(height: 28),

                const Text(
                  'Set up your business',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Step 2 of 3 — Business details',
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 32),

                AuthTextField(
                  label: 'YOUR FULL NAME',
                  hint: 'Juan dela Cruz',
                  controller: _fullNameCtrl,
                  prefixIcon: Icons.person_outline_rounded,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter your name' : null,
                ),
                const SizedBox(height: 20),

                AuthTextField(
                  label: 'BUSINESS NAME',
                  hint: "Juan's Eatery",
                  controller: _businessNameCtrl,
                  prefixIcon: Icons.business_outlined,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter business name' : null,
                ),
                const SizedBox(height: 28),

                const Text(
                  'BUSINESS TYPE',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),

                ..._options.map((opt) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: BusinessTypeCard(
                        type:        opt.type,
                        label:       opt.label,
                        description: opt.description,
                        icon:        opt.icon,
                        isSelected:  _selectedType == opt.type,
                        onTap: () => setState(() => _selectedType = opt.type),
                      ),
                    )),

                // Coming soon pill
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_circle_outline_rounded,
                        color: AppColors.textSecondary,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'More business types coming soon',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha:0.08),
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
                  label: 'Continue',
                  onPressed: _submit,
                  icon: Icons.arrow_forward_rounded,
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Data class ────────────────────────────────────────────────────────────────

class _BusinessOption {
  final String   type;
  final String   label;
  final String   description;
  final IconData icon;

  const _BusinessOption({
    required this.type,
    required this.label,
    required this.description,
    required this.icon,
  });
}

// ── Step indicator widgets ────────────────────────────────────────────────────

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
                '2',
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