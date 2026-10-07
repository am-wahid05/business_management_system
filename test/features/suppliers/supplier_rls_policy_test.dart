import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final multiCompanySql =
      File('supabase/migrations/202609230002_multi_company.sql')
          .readAsStringSync()
          .replaceAll(RegExp(r'--.*'), '')
          .replaceAll(RegExp(r'\s+'), ' ');

  final companyRolePredicate =
      "public.has_company_role(company_id, array['owner','admin']::public.company_role[])";
  final updateStart = multiCompanySql.indexOf(
    'create policy suppliers_company_update',
  );
  final nextPolicy = multiCompanySql.indexOf(
    'create policy',
    updateStart + 'create policy'.length,
  );
  final updatePolicy = multiCompanySql.substring(
    updateStart,
    nextPolicy == -1 ? multiCompanySql.length : nextPolicy,
  );

  final roleFunctionStart = multiCompanySql.indexOf(
    'create or replace function public.has_company_role',
  );
  final nextFunction = multiCompanySql.indexOf(
    'create or replace function',
    roleFunctionStart + 'create or replace function'.length,
  );
  final roleFunction = multiCompanySql.substring(
    roleFunctionStart,
    nextFunction == -1 ? multiCompanySql.length : nextFunction,
  );

  group('supplier update RLS authorization', () {
    test('Company A admin can update Company A supplier', () {
      expect(updatePolicy, contains('using ($companyRolePredicate)'));
      expect(updatePolicy, contains('with check ($companyRolePredicate)'));
      expect(roleFunction, contains('m.company_id = target_company'));
      expect(roleFunction, contains('m.user_id = auth.uid()'));
      expect(roleFunction, contains('m.is_active'));
      expect(roleFunction, contains('m.role = any(allowed_roles)'));
    });

    test('Company A secretary cannot update Company A supplier', () {
      expect(updatePolicy, contains(companyRolePredicate));
      expect(updatePolicy, isNot(contains('is_company_member')));
      expect(companyRolePredicate, isNot(contains('secretary')));
    });

    test('Company A admin cannot update Company B supplier', () {
      expect(updatePolicy, contains('has_company_role(company_id,'));
      expect(roleFunction, contains('m.company_id = target_company'));
      expect(roleFunction, contains('m.user_id = auth.uid()'));
    });

    test('Company B admin can update Company B supplier', () {
      expect(updatePolicy, contains('using ($companyRolePredicate)'));
      expect(updatePolicy, contains('with check ($companyRolePredicate)'));
    });

    test('supplier insert remains available to active company members', () {
      expect(
        multiCompanySql,
        contains(
          'create policy suppliers_company_insert on public.suppliers for insert to authenticated with check (public.is_company_member(company_id))',
        ),
      );
    });
  });
}
