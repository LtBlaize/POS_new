import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';
import 'register_screen.dart';
import 'widgets/auth_text_field.dart';
import 'widgets/business_type_card.dart';
import '../../shared/widgets/app_colors.dart';
import '../../shared/widgets/app_button.dart';

class BusinessTypeScreen extends ConsumerStatefulWidget {
  const BusinessTypeScreen({super.key});

  @override
  ConsumerState<BusinessTypeScreen> createState() => _BusinessTypeScreenState();
}

class _BusinessTypeScreenState extends ConsumerState<BusinessTypeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _businessNameCtrl = TextEditingController();

  String? _selectedType;
  bool _isLoading = false;
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

  String _friendlyError(String raw) {
    if (raw.contains('network')) return 'Network error. Check your connection.';
    if (raw.contains('permission')) return 'Permission denied. Please try again.';
    return 'Could not save your business. Please try again.';
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

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ref.read(authServiceProvider).completeRegistration(
            userId: userId,
            fullName: _fullNameCtrl.text.trim(),
            businessName: _businessNameCtrl.text.trim(),
            businessType: _selectedType!,
          );

      // Clear the pending ID — registration is complete
      ref.read(pendingUserIdProvider.notifier).state = null;

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/pos', (_) => false);
      }
    } catch (e) {
      setState(() => _error = _friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                Text(
                  'Step 2 of 2 — Business details',
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

                Text(
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
                        type: opt.type,
                        label: opt.label,
                        description: opt.description,
                        icon: opt.icon,
                        isSelected: _selectedType == opt.type,
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

                // Error banner
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.08),
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
                  label: 'Create Business',
                  onPressed: _isLoading ? null : _submit,
                  icon: Icons.check_rounded,
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

class _BusinessOption {
  final String type;
  final String label;
  final String description;
  final IconData icon;

  const _BusinessOption({
    required this.type,
    required this.label,
    required this.description,
    required this.icon,
  });
}

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