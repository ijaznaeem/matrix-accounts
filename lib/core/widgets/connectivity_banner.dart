import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connectivity_provider.dart';
import '../providers/sync_providers.dart';

/// App-level wrapper that inserts an animated offline banner above all screens.
class ConnectivityBanner extends ConsumerWidget {
  final Widget child;
  const ConnectivityBanner({required this.child, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);

    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          child: isOnline
              ? const SizedBox.shrink()
              : const _OfflineBannerContent(),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _OfflineBannerContent extends StatelessWidget {
  const _OfflineBannerContent();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.orange.shade800,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: const SafeArea(
        bottom: false,
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'You\'re offline — changes will sync when reconnected',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// AppBar action icon showing connectivity + sync state.
/// Tapping it navigates to the sync screen.
class SyncStatusAppBarIcon extends ConsumerWidget {
  final VoidCallback? onTap;
  const SyncStatusAppBarIcon({this.onTap, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);
    final syncData = ref.watch(syncStateProvider);

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: _buildIcon(isOnline, syncData),
      ),
    );
  }

  Widget _buildIcon(bool isOnline, SyncStateData syncData) {
    if (!isOnline) {
      return const Tooltip(
        message: 'Offline',
        child: Icon(Icons.cloud_off_rounded, color: Colors.white70, size: 22),
      );
    }

    switch (syncData.state) {
      case SyncState.syncing:
        return const Tooltip(
          message: 'Syncing…',
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        );
      case SyncState.success:
        return Tooltip(
          message: syncData.lastSyncTime != null
              ? 'Last sync: ${_formatTime(syncData.lastSyncTime!)}'
              : 'Sync complete',
          child: const Icon(Icons.cloud_done_rounded,
              color: Colors.lightGreenAccent, size: 22),
        );
      case SyncState.error:
        return Tooltip(
          message: syncData.message ?? 'Sync error',
          child: const Icon(Icons.cloud_off_rounded,
              color: Colors.redAccent, size: 22),
        );
      case SyncState.idle:
        return const Tooltip(
          message: 'Tap to sync',
          child:
              Icon(Icons.cloud_sync_rounded, color: Colors.white70, size: 22),
        );
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

/// Small inline chip showing online/offline status — use inside AppBar title area.
class OnlineStatusChip extends ConsumerWidget {
  const OnlineStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: isOnline
          ? const SizedBox.shrink()
          : Container(
              key: const ValueKey('offline_chip'),
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.shade700,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'OFFLINE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
    );
  }
}
