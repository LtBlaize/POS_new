// lib/features/settings/widgets/ip_setup_screen.dart
//
// First-time setup screen for connecting kitchen device to POS device.
//
// POS side (desktop):
//   Shows a QR code of its local IP address.
//   Staff point the kitchen tablet camera at this QR.
//   Also shows the raw IP in case manual entry is needed.
//
// Kitchen side (Android/iOS):
//   QR scanner → extracts IP → probes POS server → saves IP.
//   Manual IP entry as fallback if camera is unavailable.
//
// Add to your router:
//   '/ip-setup': (_) => const IpSetupScreen()

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/services/connectivity_service.dart';
import '../../../main.dart';
import '../../../shared/widgets/app_colors.dart';

class IpSetupScreen extends ConsumerStatefulWidget {
  const IpSetupScreen({super.key});

  @override
  ConsumerState<IpSetupScreen> createState() => _IpSetupScreenState();
}

class _IpSetupScreenState extends ConsumerState<IpSetupScreen> {
  bool _scanning = false;
  bool _probing = false;
  bool _probeSuccess = false;
  String? _resolvedIp;
  final _manualController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _connectToIp(String ip) async {
    setState(() {
      _probing = true;
      _probeSuccess = false;
      _resolvedIp = ip;
      _scanning = false;
    });

    final reachable =
        await ref.read(connectivityServiceProvider).probeLan(ip);

    if (!mounted) return;

    if (reachable) {
      await savePosIp(ip, ref);
      setState(() {
        _probing = false;
        _probeSuccess = true;
      });
    } else {
      setState(() => _probing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Cannot reach POS at $ip\nMake sure both devices are on the same WiFi.'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  void _onQrScanned(BarcodeCapture capture) {
    if (_probing || _probeSuccess) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    final ip = raw.replaceFirst('pos://', '').trim();
    if (_isValidIp(ip)) _connectToIp(ip);
  }

  void _submitManual() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _connectToIp(_manualController.text.trim());
  }

  bool _isValidIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(deviceRoleProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Device Setup',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: role == DeviceRole.pos
          ? const _PosQrDisplay()
          : _KitchenSetupBody(
              scanning: _scanning,
              probing: _probing,
              probeSuccess: _probeSuccess,
              resolvedIp: _resolvedIp,
              manualController: _manualController,
              formKey: _formKey,
              onStartScan: () => setState(() => _scanning = true),
              onStopScan: () => setState(() => _scanning = false),
              onQrScanned: _onQrScanned,
              onManualSubmit: _submitManual,
              onDone: () => Navigator.of(context).pop(),
            ),
    );
  }
}

// ── POS side: display QR ───────────────────────────────────────────────────────

class _PosQrDisplay extends StatelessWidget {
  const _PosQrDisplay();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: readPosLocalIp(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final ip = snap.data;

        if (ip == null || ip.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.wifi_off_outlined,
                      size: 48, color: AppColors.textSecondary),
                  SizedBox(height: 16),
                  Text(
                    'Could not determine local IP address.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 16, color: AppColors.textSecondary),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Connect to WiFi and restart the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }

        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Point the kitchen tablet at this QR code',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Both devices must be on the same WiFi network',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: QrImageView(
                    data: 'pos://$ip',
                    version: QrVersions.auto,
                    size: 220,
                    eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square, color: Colors.black),
                  ),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: ip));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('IP address copied to clipboard'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.copy_outlined,
                            size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 10),
                        Text(
                          ip,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 18,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tap to copy — use if kitchen tablet needs manual entry',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Kitchen side: scan QR ─────────────────────────────────────────────────────

class _KitchenSetupBody extends StatelessWidget {
  final bool scanning;
  final bool probing;
  final bool probeSuccess;
  final String? resolvedIp;
  final TextEditingController manualController;
  final GlobalKey<FormState> formKey;
  final VoidCallback onStartScan;
  final VoidCallback onStopScan;
  final void Function(BarcodeCapture) onQrScanned;
  final VoidCallback onManualSubmit;
  final VoidCallback onDone;

  const _KitchenSetupBody({
    required this.scanning,
    required this.probing,
    required this.probeSuccess,
    required this.resolvedIp,
    required this.manualController,
    required this.formKey,
    required this.onStartScan,
    required this.onStopScan,
    required this.onQrScanned,
    required this.onManualSubmit,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    // Success
    if (probeSuccess) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline,
                    size: 44, color: AppColors.success),
              ),
              const SizedBox(height: 20),
              const Text('Connected to POS!',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Text(resolvedIp ?? '',
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                      letterSpacing: 1,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              const Text(
                'Orders will now flow directly to this screen,\neven without internet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: onDone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Open Kitchen Display',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Probing
    if (probing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text('Connecting to POS at $resolvedIp...',
                style: const TextStyle(
                    fontSize: 15, color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    // Camera scanner
    if (scanning) {
      return Stack(
        children: [
          MobileScanner(onDetect: onQrScanned),
          Positioned(
            top: 16,
            right: 16,
            child: SafeArea(
              child: IconButton.filled(
                icon: const Icon(Icons.close),
                style:
                    IconButton.styleFrom(backgroundColor: Colors.black54),
                onPressed: onStopScan,
              ),
            ),
          ),
          const Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Text(
              'Point at the QR code shown on the POS screen',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
              ),
            ),
          ),
        ],
      );
    }

    // Default: prompt to scan or enter manually
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          const Icon(Icons.qr_code_scanner,
              size: 72, color: AppColors.textSecondary),
          const SizedBox(height: 24),
          const Text(
            'Connect to POS',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          const Text(
            'Scan the QR code shown on the POS cashier screen.\n'
            'Both devices must be on the same WiFi network.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR Code',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              onPressed: onStartScan,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Text('or enter IP manually',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 20),
          Form(
            key: formKey,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: manualController,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                      labelText: 'POS IP address',
                      hintText: '192.168.1.x',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Enter an IP address';
                      }
                      final parts = v.trim().split('.');
                      if (parts.length != 4) return 'Invalid format';
                      final valid = parts.every((p) {
                        final n = int.tryParse(p);
                        return n != null && n >= 0 && n <= 255;
                      });
                      return valid ? null : 'Invalid IP address';
                    },
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: onManualSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Connect',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}