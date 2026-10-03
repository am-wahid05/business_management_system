import '../receiving/delivery_repository.dart';
import 'daily_report.dart';

class DailyReportRepository {
  DailyReportRepository(this.deliveryRepository);

  final DeliveryRepository deliveryRepository;

  Future<DailyReport> forDate(DateTime date) async {
    return DailyReport(date: date, deliveries: await deliveryRepository.forDate(date));
  }
}
