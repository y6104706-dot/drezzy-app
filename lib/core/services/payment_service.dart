import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PaymentService
//
// Wraps flutter_stripe so the rest of the app has a single, typed entry point
// for all payment interactions. Stripe is initialised once at app start by
// calling [PaymentService.initialize] inside main() before runApp().
//
// SECURITY NOTE: The publishable key is safe to embed in the client — it can
// only be used to tokenise card data, never to move money.  The SECRET key
// must NEVER leave the Firebase Cloud Functions environment.
// ─────────────────────────────────────────────────────────────────────────────

class PaymentService {
  // ── Stripe publishable key ─────────────────────────────────────────────────
  // Paste your FULL key here (Dashboard → Developers → API keys).
  // For production, swap the pk_test_ prefix for pk_live_.
  static const String _publishableKey =
      'pk_test_51T4eTdBVUy20pV8PgZQ4KnkuYcuo4EwFx'
      'PASTE_REMAINING_KEY_HERE'; // ← complete the key

  // ── One-time boot initialisation ──────────────────────────────────────────

  /// Must be called in [main] after [WidgetsFlutterBinding.ensureInitialized]
  /// and before [runApp].
  static void initialize() {
    Stripe.publishableKey = _publishableKey;

    // Uncomment when adding Apple Pay support:
    // Stripe.merchantIdentifier = 'merchant.com.drezzy';

    // Uncomment when adding 3-D Secure / bank-redirect support:
    // Stripe.urlScheme = 'drezzy';
  }

  // ── Payment Sheet ─────────────────────────────────────────────────────────

  /// Initialises and presents the Stripe hosted Payment Sheet.
  ///
  /// [clientSecret] — PaymentIntent / SetupIntent client secret returned by
  ///   the `createPaymentIntent` Cloud Function.
  /// [customerEmail] — pre-fills the billing email field.
  ///
  /// Throws [StripeException] if the user cancels or the payment fails.
  Future<void> presentPaymentSheet({
    required String clientSecret,
    required String customerEmail,
  }) async {
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: 'Drezzy',
        billingDetails: BillingDetails(email: customerEmail),
        style: ThemeMode.dark,
        appearance: const PaymentSheetAppearance(
          colors: PaymentSheetAppearanceColors(
            primary: Color(0xFFD4AF6A), // DrezzyColors.champagneGold
            background: Color(0xFF1A1A2E),
          ),
        ),
      ),
    );

    await Stripe.instance.presentPaymentSheet();
  }

  // ── Confirm payment by ID ────────────────────────────────────────────────

  /// Confirms an existing [paymentIntentClientSecret] without re-presenting
  /// the sheet — useful for re-authorising a held deposit.
  Future<void> confirmPayment(String paymentIntentClientSecret) async {
    await Stripe.instance.confirmPayment(
      paymentIntentClientSecret: paymentIntentClientSecret,
      data: const PaymentMethodParams.card(
        paymentMethodData: PaymentMethodData(),
      ),
    );
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final paymentServiceProvider = Provider<PaymentService>(
  (_) => PaymentService(),
);
