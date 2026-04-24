// lib/shared/widgets/offline_banner.dart
//
// Persistent banner shown when the device is offline.
// Also shows a "syncing…" state when back online and flushing the queue.
// Shows a badge with pending queue count.
//
// Usage — wrap your Scaffold body (or insert into your sidebar / top_bar):
//
//   Column(children: [
//     const OfflineBanner(),
//     Expanded(child: yourContent),
//   ])
//
// Or, for full-screen overlay at the top of every route, add it to your
// AppBar's bottom slot:
//
//   appBar: AppBar(
//     bottom: const PreferredSize(
//       preferredSize: Size.fromHeight(0),
//       child: OfflineBanner(),
//     ),
//   )

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/connectivity_service.dart';
import '../../core/services/sync_queue_service.dart';

class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);
    final isSyncing = ref.watch(isSyncingProvider);
    final pendingCount = ref.watch(pendingQueueCountProvider);

    // Nothing to show when fully online and nothing pending
    if (isOnline && !isSyncing && pendingCount == 0) {
      return const SizedBox.shrink();
    }

    late final Color bgColor;
    late final Color fgColor;
    late final IconData icon;
    late final String message;

    if (!isOnline) {
      bgColor = const Color(0xFFB71C1C); // deep red
      fgColor = Colors.white;
      icon = Icons.wifi_off_rounded;
      message = pendingCount > 0
          ? 'Offline — $pendingCount change${pendingCount == 1 ? '' : 's'} queued'
          : 'Offline — changes will sync when reconnected';
    } else if (isSyncing) {
      bgColor = const Color(0xFFE65100); // deep orange
      fgColor = Colors.white;
      icon = Icons.sync_rounded;
      message = pendingCount > 0
          ? 'Syncing $pendingCount item${pendingCount == 1 ? '' : 's'}…'
          : 'Syncing…';
    } else {
      // Online, not syncing, but there are still items in queue
      // (shouldn't normally happen but handles edge cases)
      bgColor = const Color(0xFFF9A825); // amber
      fgColor = Colors.black87;
      icon = Icons.cloud_upload_outlined;
      message = '$pendingCount item${pendingCount == 1 ? '' : 's'} pending sync';
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: bgColor,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            isSyncing
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(fgColor),
                    ),
                  )
                : Icon(icon, size: 16, color: fgColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: fgColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // Manual sync button — visible when online and queue not empty
            if (isOnline && pendingCount > 0 && !isSyncing)
              GestureDetector(
                onTap: () => ref.read(syncQueueServiceProvider).flushQueue(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: fgColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Sync now',
                    style: TextStyle(
                      color: fgColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Convenience wrapper ───────────────────────────────────────────────────────
// Wraps any widget so the banner auto-appears at top when offline.
//
// Usage:
//   WithOfflineBanner(child: MyScreen())

class WithOfflineBanner extends StatelessWidget {
  final Widget child;
  const WithOfflineBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const OfflineBanner(),
        Expanded(child: child),
      ],
    );
  }
}