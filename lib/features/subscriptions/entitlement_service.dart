import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'entitlements.dart';
import 'subscription_models.dart';

/// The single place the application asks what a company may do.
///
/// Subscription checks are deliberately NOT scattered through the UI. Screens
/// read this service, so the rules live in one place and the same answer is
/// given everywhere.
///
/// This service is a CACHE, not an authority. The database decides, via the
/// `subscription-status` Edge Function. Two rules follow from that:
///
///  * A cached value may be stale while offline, so it is never used to lock a
///    user out or to grant access. [Entitlements.unknown] is the safe starting
///    state, which lets normal work continue.
///  * Nothing here can grant an entitlement. Only a verified server-side
///    payment can, so no client state can invent a subscription.
class EntitlementService extends ChangeNotifier {
  EntitlementService(this._client);

  final SupabaseClient? _client;

  Entitlements _entitlements = Entitlements.unknown;

  /// The last known entitlements. Never null: an unknown company still has the
  /// free trial, so there is always a safe answer.
  Entitlements get entitlements => _entitlements;

  /// True when the last load failed, so the UI can say it is showing a cached
  /// state rather than pretending it is current.
  bool _offline = true;
  bool get isOffline => _offline;

  int _secretariesInUse = 0;
  int get secretariesInUse => _secretariesInUse;

  /// True when the company has more secretaries than it currently pays for.
  ///
  /// This is reported, never acted on automatically: reducing a subscription
  /// must not delete or deactivate anyone's account.
  bool get isOverSecretaryAllowance =>
      _secretariesInUse > _entitlements.maxSecretaries;

  bool _loading = false;
  bool get isLoading => _loading;

  /// Re-reads the authoritative state from the server.
  ///
  /// Returns true when the server answered. On failure the previous value is
  /// kept, so an offline device keeps working with its last known state rather
  /// than inventing one.
  Future<bool> refresh() async {
    final supabase = _client;
    if (supabase == null) {
      _offline = true;
      notifyListeners();
      return false;
    }
    _loading = true;
    notifyListeners();
    try {
      final response = await supabase.functions.invoke('subscription-status');
      final data = response.data;
      if (data is! Map) {
        _offline = true;
        return false;
      }
      final raw = data['entitlements'];
      if (raw is! Map) {
        _offline = true;
        return false;
      }
      _entitlements = Entitlements.fromJson(Map<String, dynamic>.from(raw));
      _secretariesInUse = (data['secretariesInUse'] as num?)?.toInt() ?? 0;
      _offline = false;
      return true;
    } catch (_) {
      // Never invent a state. The last known value stands.
      _offline = true;
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // The access questions, in one place.
  //
  // Role and subscription are checked TOGETHER, never one in place of the other.
  // A subscription never grants a role, and a role never grants a feature the
  // subscription has not paid for.
  // ---------------------------------------------------------------------------

  /// Whether the admin/owner management side is open.
  ///
  /// Requires the admin role (enforced by the route) AND a subscription that
  /// permits admin access.
  bool get canAccessAdmin => _entitlements.canAccessAdmin;

  /// Whether a secretary may keep recording deliveries and syncing.
  ///
  /// Deliberately independent of [canAccessAdmin]: a company whose admin side
  /// has locked can still record what its secretaries brought in.
  bool get canRecordAsSecretary => _entitlements.canRecordAsSecretary;

  /// Whether the AI assistant is available for this company.
  ///
  /// The admin/owner role check is NOT repeated here because the AI Edge
  /// Function already enforces it. This flag is the company's AI entitlement,
  /// which is what stops an OpenAI call being made for a company that has not
  /// paid for or trialled the AI.
  bool get canUseAI => _entitlements.canUseAI;

  bool get isInTrial => _entitlements.isInTrial;
  bool get isInGracePeriod => _entitlements.isInGracePeriod;
  bool get isPaused => _entitlements.isPaused;
  SubscriptionStatus get status => _entitlements.status;
  AiEntitlementStatus get aiStatus => _entitlements.aiStatus;
  int get maxSecretaries => _entitlements.maxSecretaries;
  int get secretaryBundles => _entitlements.secretaryBundles;
  SubscriptionConfig get config => _entitlements.config;

  /// Whether another secretary may be added right now.
  bool get canAddSecretary => _secretariesInUse < _entitlements.maxSecretaries;

  /// Pauses the subscription. Everything the company owns is preserved.
  Future<bool> pause({String? reason}) => _manage('PAUSE', reason: reason);

  /// Reactivates a paused subscription without issuing a new trial.
  Future<bool> resume() => _manage('RESUME');

  Future<bool> _manage(String action, {String? reason}) async {
    final supabase = _client;
    if (supabase == null) return false;
    try {
      await supabase.functions.invoke(
        'subscription-manage',
        body: <String, dynamic>{'action': action, 'reason': ?reason},
      );
      return await refresh();
    } catch (_) {
      // Pausing or resuming while offline is refused rather than queued: it
      // changes billing state, so it must be deliberate and server-confirmed.
      return false;
    }
  }
}
