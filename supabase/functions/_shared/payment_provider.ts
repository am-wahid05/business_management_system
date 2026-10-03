/**
 * Payment provider seam for SMS credit top-ups.
 *
 * The credit system is provider-agnostic: nothing about balances, the ledger or
 * the SMS credit gate depends on which payment provider is used. A provider is
 * plugged in here and nothing else has to change.
 *
 * IMPORTANT: no payment provider is currently integrated. Hubtel's official
 * server-to-server payment API could not be verified, so no endpoint, request
 * shape, credential name or webhook format has been guessed or implemented here.
 * Until a provider is configured, `unconfiguredProvider` is returned and no
 * purchase can ever be completed, so no company can gain credits without a
 * verified payment.
 */

/** A purchase the customer has asked for, already priced by the server. */
export type CreditPurchaseRequest = {
  /** Company the credits belong to. Derived server-side, never from the client. */
  companyId: string;
  /** Authenticated user who started the purchase. */
  userId: string;
  /** Whole credits requested. Integer, positive. */
  credits: number;
  /**
   * Expected amount in integer minor units (pesewas). Computed by the server
   * from the fixed price, never accepted from the client.
   */
  amountMinor: number;
  /** ISO currency code. Ghana uses GHS. */
  currency: string;
  /**
   * Unique internal reference linking payment -> company -> credits -> status.
   * Must be unguessable; it is the idempotency anchor for crediting.
   */
  reference: string;
  /** Customer mobile money number, when known. */
  customerPhone?: string;
  /** Where the customer returns after paying. */
  returnUrl: string;
  /** Where the provider reports a payment outcome. */
  callbackUrl: string;
};

/** What the caller must do next once a purchase has been created. */
export type CreditPurchaseSession = {
  reference: string;
  /** Where to send the customer to pay. */
  checkoutUrl: string;
};

/** Current state of a purchase, as reported by the provider. */
export type CreditPurchaseStatus = {
  reference: string;
  /** Only 'successful' may ever add credits. */
  status: 'pending' | 'successful' | 'failed' | 'cancelled';
  /** Amount the provider says was actually paid, in minor units. */
  amountMinor?: number;
  /** Provider's own transaction id, for reconciliation. */
  providerTransactionId?: string;
};

export interface PaymentProvider {
  readonly name: string;
  /** False when the provider has no credentials or is not implemented. */
  isConfigured(): boolean;
  /**
   * Starts a purchase and returns where to send the customer.
   *
   * The implementation MUST use server-side credentials only, and MUST record
   * `reference` against the company before returning.
   */
  createPurchase(
    request: CreditPurchaseRequest,
  ): Promise<CreditPurchaseSession>;
  /**
   * Independently re-reads a purchase from the provider and reports its real
   * status and amount.
   *
   * This is the only trustworthy source of payment truth. A client saying
   * "payment successful" must never be used to award credits; the caller must
   * verify through this method and additionally confirm that the returned
   * reference and amount match what was expected.
   */
  verifyPurchase(reference: string): Promise<CreditPurchaseStatus>;
}

export class PaymentNotConfiguredError extends Error {
  constructor(provider: string) {
    super(
      `Payment provider "${provider}" is not configured, so no purchase can be started.`,
    );
    this.name = 'PaymentNotConfiguredError';
  }
}

/**
 * The provider used while none is integrated.
 *
 * It refuses every operation, which guarantees credits can only ever arrive
 * through the verified-payment path once a real provider replaces it.
 */
export function unconfiguredProvider(name: string): PaymentProvider {
  return {
    name,
    isConfigured: () => false,
    createPurchase: () => {
      throw new PaymentNotConfiguredError(name);
    },
    verifyPurchase: () => {
      throw new PaymentNotConfiguredError(name);
    },
  };
}

/**
 * Reads the active payment provider.
 *
 * To add Hubtel later: implement `PaymentProvider` in its own module, read its
 * credentials from `Deno.env` (never from Flutter), and return it here. No
 * other file in the credit system needs to change.
 */
export function resolvePaymentProvider(): PaymentProvider {
  return unconfiguredProvider('none');
}

// ---------------------------------------------------------------------------
// Subscription payments
//
// The seam above was written for SMS credit top-ups. Subscriptions need the
// same three operations but a different vocabulary, because a subscription is
// not a credit purchase: it has purposes (setup fee, monthly, secretary bundle,
// AI premium, SMS credits) and it can only ever be granted by the server after a
// verified payment.
//
// REUSING THE SAME SHAPE is deliberate. Hubtel, when implemented, is one adapter
// for BOTH systems, so a single provider implementation covers SMS credits and
// every subscription purpose. `purpose` and `quantity` ride along in the request
// rather than being baked into the provider: the provider moves money, the
// server decides what the money was for.
// ---------------------------------------------------------------------------

/** What a payment is for. Kept separate so credits and subscriptions never mix. */
export type PaymentPurpose =
  | 'SETUP_FEE'
  | 'SOFTWARE_SUBSCRIPTION'
  | 'SECRETARY_BUNDLE'
  | 'AI_SUBSCRIPTION'
  | 'SMS_CREDITS';

/** A subscription payment the customer asked for, already priced server-side. */
export type SubscriptionPaymentRequest = {
  /** Company the purchase belongs to. Derived server-side, never from the client. */
  companyId: string;
  /** Authenticated owner/admin who started the purchase. */
  userId: string;
  purpose: PaymentPurpose;
  /**
   * Expected amount in integer minor units (pesewas), computed by the server
   * from subscription_config. Never accepted from the client, so a caller cannot
   * pay 1 pesewa for a year of software.
   */
  amountMinor: number;
  currency: string;
  /** Internal id of the PENDING payment_transactions row. The idempotency anchor. */
  reference: string;
  /** Extra context, e.g. how many secretary bundles this buys. */
  quantity?: number;
  /** Customer mobile money number, when known. */
  customerPhone?: string;
  /** Where the customer returns after paying. */
  returnUrl: string;
  /** Where the provider reports a payment outcome. */
  callbackUrl: string;
};

export interface SubscriptionPaymentProvider {
  readonly name: string;
  isConfigured(): boolean;
  /**
   * Starts the payment and returns where to send the customer.
   *
   * IMPORTANT: creating a payment MUST NOT grant any entitlement. It records
   * intent only. The entitlement is granted by apply_verified_payment(), and
   * only after verifyPayment() confirms the money actually moved.
   */
  createPayment(request: SubscriptionPaymentRequest): Promise<CreditPurchaseSession>;
  /**
   * Re-reads the payment from the provider and reports its true status.
   *
   * This is the only trustworthy source of payment truth. It must be safe to
   * call repeatedly: a real implementation has to be idempotent, because a
   * provider may deliver the same callback more than once.
   */
  verifyPayment(reference: string): Promise<CreditPurchaseStatus>;
  /**
   * Handles a provider callback. It must return the SAME result for a repeated
   * callback carrying the same provider transaction id.
   */
  handleCallback(request: Request): Promise<CreditPurchaseStatus>;
}

/**
 * FUTURE HUBTEL INTEGRATION POINT -- DELIBERATELY NOT IMPLEMENTED.
 *
 * The company's Hubtel account has not been verified and no official API
 * details are available, so this adapter contains NO endpoint, authorization
 * header, request body, status value or webhook field name. Those must come from
 * the current official Hubtel documentation; guessing them would be worse than
 * having none, because a fabricated integration looks like a working one.
 *
 * To implement it later:
 *   1. Implement SubscriptionPaymentProvider on this class.
 *   2. Read credentials from Deno.env using whatever names Hubtel documents.
 *      Never from Flutter, and never commit them.
 *   3. Map Hubtel's real status values onto
 *      'pending' | 'successful' | 'failed' | 'cancelled'.
 *   4. Return it from resolveSubscriptionPaymentProvider().
 *
 * Nothing else in the subscription system needs to change.
 */
export class HubtelPaymentProvider implements SubscriptionPaymentProvider {
  readonly name = 'hubtel';

  isConfigured(): boolean {
    return false;
  }

  createPayment(_request: SubscriptionPaymentRequest): Promise<CreditPurchaseSession> {
    throw new PaymentNotConfiguredError('hubtel');
  }

  verifyPayment(_reference: string): Promise<CreditPurchaseStatus> {
    throw new PaymentNotConfiguredError('hubtel');
  }

  handleCallback(_request: Request): Promise<CreditPurchaseStatus> {
    throw new PaymentNotConfiguredError('hubtel');
  }
}

/**
 * A provider that exists ONLY for automated tests.
 *
 * It is never a production payment confirmation. Production reaches it only if
 * an operator explicitly selects it, and even then the entitlement is still
 * granted by the server from the payment row after the same idempotency check,
 * so a mock cannot bypass the billing rules: it can only tell the server what
 * outcome to record. The real money still never moves.
 */
export class MockPaymentProvider implements SubscriptionPaymentProvider {
  readonly name = 'mock';

  /** How the next verification answers. A test sets this explicitly. */
  outcome: 'pending' | 'successful' | 'failed' | 'cancelled' = 'pending';
  /** Amount the provider claims was paid, for the mismatch check. */
  paidAmountMinor?: number;

  isConfigured(): boolean {
    return true;
  }

  async createPayment(
    request: SubscriptionPaymentRequest,
  ): Promise<CreditPurchaseSession> {
    return {
      reference: request.reference,
      // An obviously-fake local scheme. It cannot reach a real provider.
      checkoutUrl: `mock://payment/${request.reference}`,
    };
  }

  async verifyPayment(reference: string): Promise<CreditPurchaseStatus> {
    return {
      reference,
      status: this.outcome,
      amountMinor: this.paidAmountMinor,
      providerTransactionId: `mock-tx-${reference}`,
    };
  }

  async handleCallback(request: Request): Promise<CreditPurchaseStatus> {
    const body = (await request.json().catch(() => ({}))) as {
      reference?: string;
    };
    return this.verifyPayment(body.reference ?? 'unknown');
  }
}

/**
 * Reads the subscription payment provider.
 *
 * Returns the real Hubtel adapter once it is implemented and configured, and
 * otherwise a provider that refuses every operation, which guarantees no
 * company can gain an entitlement without a verified payment.
 */
export function resolveSubscriptionPaymentProvider(): SubscriptionPaymentProvider {
  return new HubtelPaymentProvider();
}

/** Used by tests only. Production never calls this. */
export function mockSubscriptionPaymentProvider(): SubscriptionPaymentProvider {
  return new MockPaymentProvider();
}


