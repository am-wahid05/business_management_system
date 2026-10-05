import 'package:flutter/material.dart';

import 'sync_coordinator.dart';
import 'sync_models.dart';
import 'sync_status_repository.dart';
import '../../app/app_ui.dart';

/// Shows the synchronization state and lets the user retry.
///
/// The three outcomes a round trip can have are reported differently on
/// purpose. A record that reached the server is never described as a failure
/// just because the follow-up download did not complete, because telling the
/// user their upload failed would be untrue and would push them to resend data
/// the server already has.
class SyncStatusCard extends StatefulWidget {
  const SyncStatusCard({
    required this.statusRepository,
    this.coordinator,
    super.key,
  });

  final SyncStatusRepository statusRepository;
  final SyncCoordinator? coordinator;

  @override
  State<SyncStatusCard> createState() => _SyncStatusCardState();
}

class _SyncStatusCardState extends State<SyncStatusCard> {
  late Future<SyncStatusSnapshot> _snapshot;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _snapshot = widget.statusRepository.load();

  Future<void> _retry() async {
    final coordinator = widget.coordinator;
    if (coordinator == null) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Synchronization is not configured yet. Records remain safely stored offline.',
            ),
          ),
        );
      return;
    }
    setState(() => _retrying = true);
    try {
      final summary = await coordinator.synchronize();
      if (!mounted) return;
      final message = _describe(summary);
      if (message != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Synchronization could not start: $error')),
        );
    } finally {
      if (mounted)
        setState(() {
          _retrying = false;
          _reload();
        });
    }
  }

  /// Turns a completed round trip into the single most useful sentence.
  ///
  /// Returns null when everything succeeded, so a successful sync says nothing
  /// rather than inventing a message.
  static String? _describe(SyncSummary summary) {
    if (summary.failed > 0) {
      final first = summary.failures.first.message;
      return 'Could not upload ${summary.failed} record(s). $first';
    }
    if (summary.warnings.isNotEmpty) {
      return 'Uploaded successfully, but some updates could not be downloaded. '
          '${summary.warnings.first}';
    }
    if (summary.attempted > 0) {
      return 'Synced successfully: ${summary.synced} record(s) uploaded.';
    }
    return 'Everything is already up to date.';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SyncStatusSnapshot>(
      future: _snapshot,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSkeleton(width: 220, height: 18),
                SizedBox(height: 12),
                AppSkeleton(width: 300, height: 14),
                SizedBox(height: 8),
                AppSkeleton(width: 240, height: 14),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          return const AppErrorState(
            title: 'Synchronization status unavailable',
            message: 'Retry when the local status store is available.',
          );
        }
        final status = snapshot.data!;
        final failed = status.hasFailures;
        final pending = status.hasPending;
        final color = failed
            ? Theme.of(context).colorScheme.error
            : pending
            ? Theme.of(context).colorScheme.tertiary
            : Theme.of(context).colorScheme.primary;
        final icon = failed
            ? Icons.warning_amber_outlined
            : pending
            ? Icons.cloud_upload_outlined
            : Icons.cloud_done_outlined;
        final title = failed
            ? 'Synchronization failed'
            : pending
            ? '${status.pendingCount} records waiting to synchronize'
            : 'All records synchronized';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    SizedBox(
                      height: 40,
                      child: IconButton(
                        tooltip: 'Retry synchronization',
                        onPressed: _retrying ? null : _retry,
                        icon: _retrying
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(),
                              )
                            : const Icon(Icons.refresh),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Pending records: ${status.pendingCount} \u00b7 Failed records: ${status.failedCount}',
                ),
                Text(
                  status.lastSuccessfulSync == null
                      ? 'Last successful synchronization: Never'
                      : 'Last successful synchronization: ${_formatDateTime(status.lastSuccessfulSync!)}',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _formatDateTime(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
