import 'dart:convert';

import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/receiving/sms_receipt_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final delivery = Delivery(
    id: 'TXN-00125',
    supplier: Supplier(id: 'ALB-1', name: 'Abdul Wahid', type: SupplierType.farmer, town: 'Tamale', district: 'Tamale Metro', region: 'Northern', phone: '024 123 4567'),
    product: Product(id: 'cashew', name: 'Cashew'),
    recordedAt: DateTime(2026, 9, 23),
    bagWeights: [25, 30, 20],
    recordedByUserId: 'secretary',
  );

  test('normalizes Ghana numbers', () {
    expect(GhanaPhoneNumber.normalize('024 123 4567'), '233241234567');
    expect(GhanaPhoneNumber.normalize('+233 24 123 4567'), '233241234567');
    expect(GhanaPhoneNumber.normalize('12345'), isNull);
  });

  test('sends only after gateway confirmation', () async {
    Map<String, dynamic>? request;
    final client = MockClient((requestValue) async {
      request = jsonDecode(requestValue.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'accepted': true}), 202);
    });
    await SmsReceiptService(client: client, gatewayUrl: 'https://gateway.test/sms').send(delivery);
    expect(request?['to'], '233241234567');
    expect(request?['reference'], 'TXN-00125');
    expect(request?['message'], contains('Total Weight: 75.0 kg'));
  });

  test('rejects missing phone and failed provider response', () async {
    final missingPhone = Delivery(id: delivery.id, supplier: Supplier(id: 'ALB-1', name: 'Abdul Wahid', type: SupplierType.farmer, town: 'Tamale', district: 'Tamale Metro', region: 'Northern'), product: delivery.product, recordedAt: delivery.recordedAt, bagWeights: delivery.bagWeights, recordedByUserId: delivery.recordedByUserId);
    expect(() => SmsReceiptService(gatewayUrl: 'https://gateway.test/sms').send(missingPhone), throwsA(isA<SmsReceiptException>()));
    final client = MockClient((_) async => http.Response(jsonEncode({'accepted': false}), 200));
    expect(() => SmsReceiptService(client: client, gatewayUrl: 'https://gateway.test/sms').send(delivery), throwsA(isA<SmsReceiptException>()));
  });
}
