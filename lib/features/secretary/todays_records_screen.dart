import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/delivery.dart';
import '../auth/auth_models.dart';
import '../auth/auth_repository.dart';
import '../receiving/delivery_repository.dart';
import 'delivery_detail_screen.dart';
import '../sync/sync_coordinator.dart';
import '../sync/sync_status_card.dart';
import '../sync/sync_status_repository.dart';
import '../auth/active_company_context.dart';
import '../company/company_branding.dart';
import '../credits/sms_credit_service.dart';

class TodaysRecordsScreen extends StatefulWidget {
  const TodaysRecordsScreen({
    required this.repository,
    required this.statusRepository,
    this.coordinator,
    this.brandingService,
    this.activeCompanyContext,
    this.authRepository,
    this.supabaseClient,
    this.creditService,
    super.key,
  });

  final DeliveryRepository repository;
  final SyncStatusRepository statusRepository;
  final SyncCoordinator? coordinator;
  final CompanyBrandingService? brandingService;

  /// Forwarded to the receipt screen so print/SMS show the active company's
  /// name instead of a hardcoded brand.
  final ActiveCompanyContext? activeCompanyContext;
  final AuthRepository? authRepository;

  /// Forwarded to the receipt screen so SMS is sent through the Edge Function.
  final SupabaseClient? supabaseClient;

  /// Forwarded so the receipt screen can show the credit balance.
  final SmsCreditService? creditService;

  @override
  State<TodaysRecordsScreen> createState() => _TodaysRecordsScreenState();
}

class _TodaysRecordsScreenState extends State<TodaysRecordsScreen> {
  late DateTime? _from;
  late DateTime? _to;
  late Future<_RecordsData> _records;

  final _searchController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _recorderUserId;
  bool _searching = false;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _from = DateTime(today.year, today.month, today.day);
    _to = _from!.add(const Duration(days: 1));
    _loadRecords();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// Loads the saved receipts for the current filters.
  ///
  /// This only reads existing delivery rows. Searching, printing, or sending an
  /// SMS never creates a receipt, so no duplicate record can appear.
  void _loadRecords() {
    final generation = ++_searchGeneration;
    _records = () async {
      final deliveries = await widget.repository.search(
        ReceiptSearchFilters(
          query: _searchController.text,
          phone: _phoneController.text,
          from: _from,
          to: _to,
          recorderUserId: _recorderUserId,
        ),
      );
      if (generation != _searchGeneration) {
        return const _RecordsData([], {}, {});
      }
      final names = <String, String>{};
      final user = widget.authRepository?.currentUser;
      if (user != null) {
        if (user.role == UserRole.admin) {
          try {
            for (final member in await widget.authRepository!.allUsers()) {
              names[member.id] = member.displayName;
            }
          } catch (_) {
            // Keep records visible if profile-name lookup is temporarily offline.
          }
        } else {
          names[user.id] = user.displayName;
        }
      }
      final sms = await widget.repository.receiptSmsFor(
        deliveries.map((delivery) => delivery.id).toList(),
      );
      if (generation != _searchGeneration) {
        return const _RecordsData([], {}, {});
      }
      return _RecordsData(deliveries, names, sms);
    }();
  }

  /// Selects a date range. This replaces the previous single-day picker so past
  /// receipts remain reachable.
  Future<void> _chooseRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _rangeOrToday,
    );
    if (range == null) return;
    setState(() {
      _from = DateTime(range.start.year, range.start.month, range.start.day);
      _to = DateTime(range.end.year, range.end.month, range.end.day)
          .add(const Duration(days: 1));
      _loadRecords();
    });
  }

  DateTimeRange get _rangeOrToday {
    final start = _from ?? DateTime.now();
    final endExclusive = _to ?? start.add(const Duration(days: 1));
    final end = endExclusive.subtract(const Duration(days: 1));
    return DateTimeRange(
      start: start,
      end: end.isBefore(start) ? start : end,
    );
  }

  Future<void> _pickRecorder() async {
    final members = <AppUser>[];
    try {
      members.addAll(await widget.authRepository!.allUsers());
    } catch (_) {
      // Filtering by secretary is unavailable while the list cannot load.
    }
    if (!mounted) return;
    final selected = await showModalBottomSheet<String?>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Recorded by')),
            ListTile(
              title: const Text('Anyone'),
              selected: _recorderUserId == null,
              onTap: () => Navigator.pop(context, ''),
            ),
            ...members.map(
              (member) => ListTile(
                title: Text(member.displayName),
                selected: _recorderUserId == member.id,
                onTap: () => Navigator.pop(context, member.id),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    setState(() {
      _recorderUserId = selected.isEmpty ? null : selected;
      _loadRecords();
    });
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _phoneController.clear();
      _recorderUserId = null;
      final today = DateTime.now();
      _from = DateTime(today.year, today.month, today.day);
      _to = _from!.add(const Duration(days: 1));
      _loadRecords();
    });
  }

  void _onFilterChanged(String _) {
    setState(() {
      _searching = true;
      _loadRecords();
    });
    _debounce();
  }

  /// Waits briefly after the last keystroke before querying, so typing does not
  /// run a query per character.
  void _debounce() {
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _loadRecords();
      });
    });
  }

  Future<void> _open(
    Delivery delivery,
    Map<String, String> recorderNames,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeliveryDetailScreen(
          repository: widget.repository,
          delivery: delivery,
          brandingService: widget.brandingService,
          activeCompanyContext: widget.activeCompanyContext,
          recorderNames: recorderNames,
          supabaseClient: widget.supabaseClient,
          creditService: widget.creditService,
        ),
      ),
    );
    if (mounted) setState(_loadRecords);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipts'),
        actions: [
          IconButton(
            tooltip: 'Date range',
            onPressed: _chooseRange,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
        ],
      ),
      body: FutureBuilder<_RecordsData>(
        future: _records,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load records: ${snapshot.error}'),
            );
          }
          final data = snapshot.data!;
          final records = data.deliveries;
          final suppliers = records
              .map((delivery) => delivery.supplier.id)
              .toSet()
              .length;
          final bags = records.fold(
            0,
            (total, delivery) => total + delivery.numberOfBags,
          );
          final weight = records.fold<double>(
            0,
            (total, delivery) => total + delivery.totalWeight,
          );
          return RefreshIndicator(
            onRefresh: () async => setState(_loadRecords),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Receipt history',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  "Search saved receipts by receipt number, supplier name or "
                  "phone number. Only your own company's receipts are shown.",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Receipt number or supplier name',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'Clear',
                      onPressed: () {
                        _searchController.clear();
                        _onFilterChanged('');
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ),
                  onChanged: _onFilterChanged,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  onChanged: _onFilterChanged,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.date_range, size: 18),
                      label: Text(_rangeLabel),
                      onPressed: _chooseRange,
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.person_outline, size: 18),
                      label: Text(
                        _recorderUserId == null
                            ? 'Anyone'
                            : (data.recorderNames[_recorderUserId] ??
                                  'Selected secretary'),
                      ),
                      onPressed: _pickRecorder,
                    ),
                    if (_searching)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    TextButton(
                      onPressed: _clearFilters,
                      child: const Text('Clear filters'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SyncStatusCard(
                  statusRepository: widget.statusRepository,
                  coordinator: widget.coordinator,
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _SummaryCard(label: 'Suppliers', value: '$suppliers'),
                    _SummaryCard(
                      label: 'Deliveries',
                      value: '${records.length}',
                    ),
                    _SummaryCard(label: 'Bags', value: '$bags'),
                    _SummaryCard(
                      label: 'Weight',
                      value: '${weight.toStringAsFixed(1)} kg',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (records.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'No receipts match these filters. Adjust the search or '
                        'date range to find an earlier receipt.',
                      ),
                    ),
                  ),
                ...records.map(
                  (delivery) => _ReceiptCard(
                    delivery: delivery,
                    sms: data.smsByDelivery[delivery.id],
                    recorderName: recorderDisplayName(
                      delivery.recordedByUserId,
                      data.recorderNames,
                    ),
                    onTap: () => _open(delivery, data.recorderNames),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String get _rangeLabel {
    final start = _from;
    final end = _to;
    if (start == null || end == null) return 'Any date';
    final last = end.subtract(const Duration(days: 1));
    if (_formatDate(start) == _formatDate(last)) return _formatDate(start);
    return '${_formatDate(start)} - ${_formatDate(last)}';
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  static String _formatTime(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class _RecordsData {
  const _RecordsData(
    this.deliveries,
    this.recorderNames,
    this.smsByDelivery,
  );

  final List<Delivery> deliveries;
  final Map<String, String> recorderNames;

  /// Latest SMS attempt per delivery, used to show Sent/Failed/Not sent.
  final Map<String, ReceiptSmsRecord> smsByDelivery;
}

/// One historical receipt in the search results.
///
/// The receipt identifier is the existing delivery id, so no second identifier
/// is invented. Opening it shows the saved bag weights, totals, date, supplier,
/// recorder and company exactly as recorded.
class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({
    required this.delivery,
    required this.recorderName,
    required this.onTap,
    this.sms,
  });

  final Delivery delivery;
  final String recorderName;
  final VoidCallback onTap;
  final ReceiptSmsRecord? sms;

  @override
  Widget build(BuildContext context) {
    final record = sms;
    final smsLabel = record?.label ?? 'Not sent';
    final smsColor = record == null
        ? Theme.of(context).colorScheme.outline
        : record.isFailed
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Receipt #: ${delivery.id}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    record == null
                        ? Icons.sms_outlined
                        : record.isFailed
                        ? Icons.sms_failed_outlined
                        : Icons.sms,
                    size: 18,
                    color: smsColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'SMS: $smsLabel',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: smsColor),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                delivery.supplier.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${delivery.product.name} · ${delivery.numberOfBags} bags · '
                '${delivery.totalWeight.toStringAsFixed(1)} kg',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              Text(
                'Recorded by $recorderName · '
                '${_TodaysRecordsScreenState._formatDate(delivery.recordedAt)} '
                '${_TodaysRecordsScreenState._formatTime(delivery.recordedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    ),
  );
}
