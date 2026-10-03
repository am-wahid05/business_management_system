import 'package:flutter/material.dart';

import 'sync_coordinator.dart';
import 'sync_status_repository.dart';

class SyncStatusCard extends StatefulWidget {
  const SyncStatusCard({required this.statusRepository, this.coordinator, super.key});

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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Synchronization is not configured yet. Records remain safely stored offline.')));
      return;
    }
    setState(() => _retrying = true);
    try {
      await coordinator.synchronize();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Synchronization could not start: $error')));
    } finally {
      if (mounted) setState(() { _retrying = false; _reload(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SyncStatusSnapshot>(
      future: _snapshot,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Card(child: LinearProgressIndicator());
        if (snapshot.hasError) return Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Synchronization status unavailable: ${snapshot.error}')));
        final status = snapshot.data!;
        final failed = status.hasFailures;
        final pending = status.hasPending;
        final color = failed ? Theme.of(context).colorScheme.error : pending ? Theme.of(context).colorScheme.tertiary : Theme.of(context).colorScheme.primary;
        final icon = failed ? Icons.warning_amber_outlined : pending ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined;
        final title = failed ? 'Synchronization failed' : pending ? '${status.pendingCount} records waiting to synchronize' : 'All records synchronized';
        return Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, color: color), const SizedBox(width: 10), Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w600))), SizedBox(height: 40, child: IconButton(tooltip: 'Retry synchronization', onPressed: _retrying ? null : _retry, icon: _retrying ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator()) : const Icon(Icons.refresh))) ]),
          const SizedBox(height: 8),
          Text('Pending records: ${status.pendingCount} · Failed records: ${status.failedCount}'),
          Text(status.lastSuccessfulSync == null ? 'Last successful synchronization: Never' : 'Last successful synchronization: ${_formatDateTime(status.lastSuccessfulSync!)}'),
        ])));
      },
    );
  }

  static String _formatDateTime(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
