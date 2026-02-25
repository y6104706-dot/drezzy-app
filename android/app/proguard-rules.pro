# Stripe SDK — avoid R8 stripping / missing classes
-dontwarn com.stripe.android.**
-keep class com.stripe.android.** { *; }
