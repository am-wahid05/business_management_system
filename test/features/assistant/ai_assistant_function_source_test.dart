import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the security properties of the `ai-assistant` Edge Function.
///
/// The function's authorization, company isolation and read-only guarantees are
/// enforced in TypeScript, which `flutter test` cannot execute. These checks
/// read the source so the critical invariants cannot be silently removed: if
/// someone later adds a write, trusts a client-supplied company, or executes
/// model output, this suite fails.
void main() {
  final source = File('supabase/functions/ai-assistant/index.ts')
      .readAsStringSync();

  // Block comments are stripped, and line comments are only stripped when the
  // '//' starts the line, so a URL like https://... is never mangled. This stops
  // a rule from being "satisfied" merely by the word appearing in a comment that
  // explains the rule.
  final code = source
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

  /// No model id may be baked into the source: availability and cost depend on
  /// the OpenAI account, so the operator pins it with a secret instead.
  final hardcodedModel = RegExp('model:\\s*.gpt-');

  group('the assistant can never write business data', () {
    test(
      'contains no insert, update, upsert or delete against the database',
      () {
        for (final verb in ['.insert(', '.update(', '.upsert(', '.delete(']) {
          expect(
            code,
            isNot(contains(verb)),
            reason: 'The assistant is read-only, so $verb must never appear.',
          );
        }
      },
    );

    test('has no raw SQL execution path', () {
      // The model can never reach the database directly, because the function
      // never runs SQL at all: it uses the typed query builder only.
      expect(code, isNot(contains('.rpc(')));
      expect(code, isNot(contains('sql` ')));
      expect(code.toLowerCase(), isNot(contains('execute sql')));
    });

    test('does not post the model output anywhere as a command', () {
      // The model's text is returned to the client, never re-entered into any
      // other call.
      expect(code, isNot(contains('spaql')));
      expect(code, isNot(contains('rls')));
    });
  });

  group('authentication and company isolation', () {
    test('requires an Authorization header and resolves the user', () {
      expect(code, contains("request.headers.get('Authorization')"));
      expect(code, contains('auth.getUser()'));
    });

    test(
      'reads the company from company_memberships, not from the request',
      () {
        expect(code, contains("from('company_memberships')"));
        expect(code, contains(".eq('user_id', callerId)"));
      },
    );

    test('rejects a client-supplied company_id outright', () {
      expect(code, contains('COMPANY_ID_NOT_ACCEPTABLE'));
      expect(
        code,
        contains("if (input.company_id != null)"),
        reason: 'A caller-supplied company must be rejected, not ignored.',
      );
    });

    test('scopes every delivery read to the authorized company', () {
      expect(code, contains(".eq('company_id', scope.companyId)"));
    });

    test('requires an admin role, so a secretary is refused', () {
      expect(code, contains('ADMIN_ACCESS_REQUIRED'));
      expect(code, contains("ADMIN_ROLES = ['owner', 'admin']"));
    });
  });

  group('provider configuration is server-side only', () {
    test('reads the OpenAI key from the function environment', () {
      expect(code, contains("Deno.env.get('OPENAI_API_KEY')"));
    });

    test(
      'reads the model id from the environment instead of hardcoding it',
      () {
        expect(code, contains("Deno.env.get('OPENAI_MODEL')"));
        expect(
          hardcodedModel.hasMatch(code),
          isFalse,
          reason: 'The model must come from OPENAI_MODEL, not from the source.',
        );
      },
    );

    test('uses the current Responses API, not legacy Chat Completions', () {
      expect(code, contains('https://api.openai.com/v1/responses'));
      expect(code, contains('max_output_tokens'));
      expect(code, contains('instructions'));
      // The legacy shape must not appear.
      expect(code, isNot(contains('/v1/chat/completions')));
      expect(code, isNot(contains('choices')));
    });

    test('never returns the raw provider error to the client', () {
      // Provider failures are mapped to stable codes plus friendly wording, so
      // no provider body and no key can reach the app.
      expect(code, contains('ProviderError'));
      expect(code, contains('FRIENDLY_ERRORS'));
    });
  });
}
