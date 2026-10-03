import '../analytics/analytics_models.dart';
import '../analytics/analytics_repository.dart';

class BusinessAssistantService {
  BusinessAssistantService(this.analyticsRepository);

  final AnalyticsRepository analyticsRepository;

  Future<String> answer(String question) async {
    final normalized = question.trim().toLowerCase();
    if (normalized.isEmpty) return 'Ask me about receiving, suppliers, products, analytics, reports, or Excel.';
    if (_isHelp(normalized)) return _helpAnswer(normalized);

    final range = _rangeFor(normalized);
    final filters = AnalyticsFilters(from: range.from, to: range.to);
    if (_mentionsProduct(normalized)) {
      final products = await analyticsRepository.productBreakdown(filters);
      if (products.isEmpty) return _noData(range);
      final requested = products.where((item) => normalized.contains(item.productName.toLowerCase())).toList();
      final selected = requested.isEmpty ? products : requested;
      return '${_rangeLabel(range)} received ${selected.map((item) => '${item.productName}: ${item.totalWeight.toStringAsFixed(1)} kg, ${item.totalBags} bags, ${item.deliveryCount} deliveries').join('; ')}.';
    }
    if (_mentionsSupplier(normalized)) {
      final suppliers = await analyticsRepository.supplierBreakdown(filters);
      if (suppliers.isEmpty) return _noData(range);
      final top = suppliers.take(5).map((item) => '${item.supplierName} (${item.totalWeight.toStringAsFixed(1)} kg)').join(', ');
      return '${_rangeLabel(range)} supplier activity: $top.';
    }
    if (_mentionsTrend(normalized)) {
      final trend = await analyticsRepository.trend(filters, AnalyticsTrend.monthly);
      if (trend.isEmpty) return _noData(range);
      return '${_rangeLabel(range)} monthly receiving: ${trend.map((item) => '${item.period} ${item.totalWeight.toStringAsFixed(1)} kg').join(', ')}.';
    }

    final summary = await analyticsRepository.summary(filters);
    if (summary.deliveryCount == 0) return _noData(range);
    return '${_rangeLabel(range)} received ${summary.totalWeight.toStringAsFixed(1)} kg across ${summary.totalBags} bags and ${summary.deliveryCount} deliveries from ${summary.uniqueSuppliers} suppliers.';
  }

  bool _isHelp(String question) => question.contains('how do i') || question.contains('where ') || question.contains('how can i') || question.contains('excel') || question.contains('analytics');

  String _helpAnswer(String question) {
    if (question.contains('excel') || question.contains('export')) return 'Open the admin menu, choose Excel, then select the export you need. Excel export uses local SQLite data and works offline.';
    if (question.contains('supplier')) return 'Open Suppliers from the admin menu, select a supplier, then choose the statement or history action.';
    if (question.contains('analytics') || question.contains('report')) return 'Open Analytics or Reports from the admin menu, choose the date range, then apply product, supplier, type, town, or district filters.';
    return 'I can explain Analytics, Reports, Suppliers, Products, Excel export/import, receiving, backups, and synchronization.';
  }

  bool _mentionsProduct(String question) => question.contains('cashew') || question.contains('cocoa') || question.contains('shea') || question.contains('product');
  bool _mentionsSupplier(String question) => question.contains('supplier') || question.contains('farmer') || question.contains('aggregator');
  bool _mentionsTrend(String question) => question.contains('trend') || question.contains('month') || question.contains('year');

  _DateRange _rangeFor(String question) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (question.contains('yesterday')) return _DateRange(today.subtract(const Duration(days: 1)), today.subtract(const Duration(days: 1)));
    if (question.contains('this month')) return _DateRange(DateTime(today.year, today.month), today);
    if (question.contains('this year')) return _DateRange(DateTime(today.year), today);
    return _DateRange(today, today);
  }

  String _noData(_DateRange range) => '${_rangeLabel(range)} has no matching receiving data.';
  String _rangeLabel(_DateRange range) => '${_formatDate(range.from)} to ${_formatDate(range.to)}';
  String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _DateRange {
  const _DateRange(this.from, this.to);

  final DateTime from;
  final DateTime to;
}
