# DREZZY — Architect Status Report
> Generated: 2026-02-25 · Based on full codebase analysis
> Audience: Lead Architect / Technical Lead

---

## 1. Implemented Features

### Flutter App (`lib/`)

| Layer | File | Status |
|---|---|---|
| **Theme** | `core/theme/app_theme.dart` | ✅ Complete — Material 3, dark/light, Cormorant + DM Sans fonts, Obsidian Plum + Champagne Gold palette |
| **Shimmer Loader** | `core/widgets/shimmer_box.dart` | ✅ Complete — Pure-Flutter sweep animation, `ListingCardSkeleton` pre-built |
| **Listing Model** | `features/listings/domain/listing_model.dart` | ✅ Complete — Firestore `fromMap`/`toMap`, computed `priceLabel` |
| **Discovery Feed** | `features/listings/presentation/screens/discovery_feed_screen.dart` | ✅ Complete — Search bar, category chips, active filter chip row, 2-col grid, skeleton/empty/error states, scroll-shadow header |
| **Listing Card** | `features/listings/presentation/widgets/listing_card.dart` | ✅ Complete — Full-bleed Hero image, gradient overlay, gold price, location chip, animated wishlist heart |
| **Filter Sheet** | `features/listings/presentation/widgets/filter_bottom_sheet.dart` | ✅ Complete — Category, Size (multi-select), Price RangeSlider, Distance Slider, Sort radio — local draft → apply |
| **Listings Provider** | `features/listings/presentation/providers/listings_provider.dart` | ✅ Complete (mock) — `FutureProvider` with 10 mock items, applies category + text + size + price + sort; `activeFilterChipsProvider` |
| **Filter Provider** | `features/listings/presentation/providers/filter_provider.dart` | ✅ Complete — `AdvancedFilterState`, `AdvancedFilterNotifier`, `SortOption`, `FilterChipData`, chip removal |
| **Voice STT** | `features/ai_services/presentation/providers/voice_search_provider.dart` | ✅ Complete — 7-state machine (idle → initialising → listening → processing → done / error / denied), `speech_to_text` wired |
| **Voice Overlay** | `features/ai_services/presentation/widgets/voice_stylist_overlay.dart` | ✅ Complete — `BackdropFilter` blur, 3 pulsing rings, 5-bar waveform, 3 orb states (mic / spinner / error), status + transcript text, auto-dismiss on done |
| **TTS Service** | `features/ai_services/presentation/services/tts_service.dart` | ✅ Complete — `flutter_tts` wrapper, contextual result announcement, `ttsServiceProvider` |

### Feature Folders Scaffolded (Empty)

| Folder | Contents |
|---|---|
| `features/auth/` | Barrel + `data/`, `domain/`, `presentation/` stubs only |
| `features/payments/` | Barrel + `data/`, `domain/`, `presentation/` stubs only |
| `features/ai_services/data/`, `domain/` | `.gitkeep` only |

---

## 2. Firebase / Backend State

### Firestore Collections

| Collection | Schema | Security Rules | Composite Indexes |
|---|---|---|---|
| `listings` | ✅ Designed (`firestore_schema.md`) | ✅ Auth guard, ownership, category/status validation, 20% fee check | ✅ 4 indexes defined (category+status, status+price, category+status+price, ownerId+createdAt) |
| `rentals` | ✅ Designed | ✅ Auth guard, financial-field immutability, status transitions | ✅ 2 indexes (renterId+status, ownerId+status) |
| `users` | ✅ Designed | ✅ Owner-only read/write | ❌ No index needed |
| `tryOnJobs` | ✅ Defined in `virtualTryOn.ts` | ❌ No Firestore rules written | ✅ 2 indexes (predictionId, userId+createdAt) |
| `reviews` | ❌ Not in rules | ❌ Missing entirely | ❌ Missing |
| `bookings` | ❌ Master Plan uses "bookings"; codebase uses "rentals" — **name drift** | ❌ No `bookings` rules | ❌ Missing |

### Cloud Functions (`functions/src/`)

| Function | File | Description | Status |
|---|---|---|---|
| `generateFaceSwap` | `faceSwap.ts` | HTTPS Callable — auth + ownership guard → InsightFace on Replicate → polls → writes `displayImageUrl` + `isFaceSwapped: true` back to listing | ✅ Implemented, **not deployed** |
| `processVirtualTryOn` | `virtualTryOn.ts` | HTTPS Callable — submits IDM-VTON prediction with webhook URL → saves `tryOnJobs` doc → returns `job_id` immediately | ✅ Implemented, **not deployed** |
| `handleReplicateWebhook` | `virtualTryOn.ts` | HTTPS Request — receives Replicate callback → updates job status → sends FCM push notification | ✅ Implemented, **not deployed** |
| `processVoiceSearch` | `voiceSearch.ts` | HTTPS Callable — **Gemini 1.5 Flash** parses NL query (multilingual: EN + HE examples) → Firestore query → relevance scoring → personalised response | ✅ Implemented, **not deployed** |
| `processGarmentUpload` | *(missing)* | Storage trigger — auto face-anonymise on lender photo upload (specified in Master Plan §7) | ❌ **Not implemented** |

### Replicate API Integration

| Component | Status |
|---|---|
| `replicateClient.ts` — shared client factory | ✅ Complete — `getReplicateClient()`, `submitPrediction()`, `pollPredictionUntilDone()`, `extractOutputUrl()` |
| InsightFace model ID pinned | ✅ `563a66acc0...` |
| IDM-VTON model ID pinned | ✅ `906425dbca...` |
| Dart client-side calling code | ❌ Not yet — no `CloudFunctions.instance.httpsCallable('processVirtualTryOn')` in Flutter code |
| `.env` file with `REPLICATE_API_TOKEN` | ❌ **Only `.env.example` exists — token not set** |

### Firebase Emulator Suite

| Emulator | Port | Config |
|---|---|---|
| Cloud Functions | 5001 | ✅ Defined in `firebase.json` |
| Firestore | 8080 | ✅ Defined |
| Auth | 9099 | ✅ Defined |
| Emulator UI | 4000 | ✅ Enabled |

> ⚠️ **Firebase project not linked.** No `.firebaserc` file detected. `firebase use <project-id>` has not been run.

---

## 3. Integrations

| Integration | Package Added | Client Code | Backend | Status |
|---|---|---|---|---|
| **Firebase Auth** | ✅ `firebase_auth ^5.4.1` | ❌ No auth screens, `initializeApp()` commented out | ✅ Rules enforce `isAuthenticated()` | 🟡 Package only |
| **Cloud Firestore** | ✅ `cloud_firestore ^5.6.0` | ❌ Providers use mock data, no real reads | ✅ Rules + indexes defined | 🟡 Package only |
| **Firebase Storage** | ❌ Not in `pubspec.yaml` | ❌ No upload client | ❌ No Storage rules | 🔴 Not started |
| **Firebase Messaging (FCM)** | ❌ Not in `pubspec.yaml` | ❌ No push handling | ✅ FCM send in `handleReplicateWebhook` | 🔴 Missing on Flutter side |
| **Replicate API** | N/A (server-side only) | ❌ No Dart callable | ✅ Full TypeScript client | 🔴 Dart bridge missing |
| **Voice STT** | ✅ `speech_to_text ^7.0.0` | ✅ Full provider + overlay | N/A | ✅ Complete |
| **Voice TTS** | ✅ `flutter_tts ^4.2.0` | ✅ `TtsService` + contextual announcements | N/A | ✅ Complete |
| **Stripe Payments** | ❌ Not in `pubspec.yaml` | ❌ No checkout UI | ❌ No Stripe Cloud Function | 🔴 Not started |
| **Google Fonts** | ✅ `google_fonts ^6.2.1` | ✅ Cormorant + DM Sans in theme | N/A | ✅ Complete |

---

## 4. Pending Tasks — Path to MVP

Listed in priority order per `DREZZY_MASTER_PLAN.md`.

### 🔴 P0 — Blockers (nothing works without these)

- [ ] **Run `flutter create . --project-name drezzy_app`** — generates `android/`, `ios/` platform dirs. The project was scaffolded manually; no native code exists.
- [ ] **Create Firebase project** → download `google-services.json` (Android) + `GoogleService-Info.plist` (iOS) → place in platform dirs.
- [ ] **Uncomment `Firebase.initializeApp()`** in `main.dart` + add `firebase_options.dart` (generated by `flutterfire configure`).
- [ ] **Create `functions/.env`** from `.env.example` — fill in `REPLICATE_API_TOKEN`, `GEMINI_API_KEY`, `FUNCTIONS_BASE_URL`.
- [ ] **Add missing Flutter packages** to `pubspec.yaml`:
  ```yaml
  firebase_storage: ^12.x.x
  firebase_messaging: ^15.x.x
  flutter_stripe: ^10.x.x
  go_router: ^14.x.x
  ```

### 🟠 P1 — Auth (required for any user-facing flow)

- [ ] Implement `features/auth/` — login screen, register screen, Google/Apple sign-in.
- [ ] Create `users/{uid}` document on first sign-in with default profile fields.
- [ ] Add `AuthNotifier` Riverpod provider wrapping `FirebaseAuth.instance.authStateChanges()`.
- [ ] Wire auth gate in `main.dart` — unauthenticated → Auth screen, authenticated → `DiscoveryFeedScreen`.

### 🟠 P1 — Real Data (replace mock listings)

- [ ] Swap `listingsProvider` `FutureProvider` → `StreamProvider` reading live Firestore.
- [ ] Deploy Firestore rules: `firebase deploy --only firestore:rules`.
- [ ] Deploy Firestore indexes: `firebase deploy --only firestore:indexes`.
- [ ] Seed Firestore with test listings via the Emulator UI.

### 🟡 P2 — Core Listing Features

- [ ] **Listing Detail Screen** — full-screen Hero transition, garment gallery, size/price, lender info, "Book Now" + **"Try On" button** calling `processVirtualTryOn`.
- [ ] **Create Listing Screen** — photo upload to Firebase Storage, triggers `generateFaceSwap` automatically, writes to `listings/`.
- [ ] Implement missing `processGarmentUpload` Storage trigger Cloud Function (auto face-swap on upload).

### 🟡 P2 — VTON Result Flow

- [ ] Add FCM (`firebase_messaging`) to Flutter — register device token, handle push on try-on completion.
- [ ] Build `VtonResultScreen` — displays `resultUrl` from `tryOnJobs` doc via Firestore `StreamBuilder`.
- [ ] Add Dart callable: `FirebaseFunctions.instance.httpsCallable('processVirtualTryOn')`.

### 🟡 P2 — Payments

- [ ] Add `flutter_stripe` to Flutter.
- [ ] Create Stripe Cloud Function: `createPaymentIntent(listingId, startDate, endDate)` → calculates `totalPrice`, `drezzyFee` (20%), creates Stripe PaymentIntent, writes to `rentals/`.
- [ ] Create `createLenderPayout` Cloud Function — Stripe Connect transfer on rental completion.
- [ ] Build **Checkout Screen** with date picker, deposit summary, `CardField`, confirm button.

### 🟡 P2 — Wire Voice Search to Backend

- [ ] The current `VoiceSearchNotifier` uses only on-device STT and local keyword filtering.
- [ ] After STT captures transcript → call `processVoiceSearch` Cloud Function → use returned `listings[]` + `conversational_response` to update the feed and TTS response.

### 🟢 P3 — Polish & Reviews

- [ ] Add `reviews` Firestore collection + rules.
- [ ] Add Firebase Storage security rules.
- [ ] Add booking calendar / availability logic.
- [ ] Add profile screen with `defaultSize`, `maxPricePerDay`, `preferredCategories`.

---

## 5. Critical Blockers Summary

| # | Blocker | Impact | Fix |
|---|---|---|---|
| 1 | **No `android/` or `ios/` platform directories** | App cannot be built or run on any device | Run `flutter create . --project-name drezzy_app` |
| 2 | **`Firebase.initializeApp()` commented out** | All Firebase SDKs throw on first use | Run `flutterfire configure` + uncomment call |
| 3 | **`functions/.env` missing** | All 4 Cloud Functions crash at runtime (`REPLICATE_API_TOKEN` + `GEMINI_API_KEY` undefined) | Copy `.env.example` → `.env`, fill keys |
| 4 | **Cloud Functions never deployed** | No AI features work in production | `cd functions && npm install && npm run build && firebase deploy --only functions` |
| 5 | **`firebase_storage` + `firebase_messaging` not in `pubspec.yaml`** | VTON webhook push notification dead on arrival; image upload impossible | Add both packages |
| 6 | **Stripe not integrated** | No monetisation; 20% commission logic is rules-only | Add `flutter_stripe`, create Stripe Cloud Functions |
| 7 | **Schema name drift: "bookings" vs "rentals"** | Master Plan §6 uses `bookings`; `firestore_schema.md` + rules use `rentals`; `listing_model.dart` uses `lenderId` but rules use `ownerId` | Pick one naming convention and enforce across all layers |
| 8 | **`processGarmentUpload` Storage trigger absent** | Face-swap privacy (a core differentiator) is not automatic; lenders must manually trigger it | Implement the Storage `onCreate` function in `functions/src/` |
| 9 | **`flutter pub get` not verified** | `pubspec.lock` absent; packages may not resolve (especially `speech_to_text ^7.0.0` and `flutter_tts ^4.2.0`) | Run `flutter pub get` and commit the resulting `pubspec.lock` |
| 10 | **No Firebase `.firebaserc`** | `firebase deploy` has no project to target | Run `firebase use --add` and select the project |

---

## 6. Quick-Reference: Architecture Compliance vs. Master Plan

| Master Plan Feature | Spec Status | Implementation Status |
|---|---|---|
| Virtual Try-On (IDM-VTON) | ✅ Fully specced | 🟡 Backend CF written, Dart client missing |
| Face Swap Privacy | ✅ Fully specced | 🟡 `generateFaceSwap` CF written, Storage trigger missing |
| NL Voice Search (Gemini) | ✅ Fully specced | 🟡 `processVoiceSearch` CF written (best feature in the codebase), not wired to Flutter |
| On-device STT + TTS | ✅ Specced | ✅ Fully implemented in Flutter |
| P2P Discovery Feed | ✅ Specced | ✅ UI complete, mock data |
| Stripe 20% Commission | ✅ Specced + in rules | 🔴 No Dart or CF implementation |
| User Auth (Firebase) | ✅ Specced | 🔴 No UI or provider |
| Dry Cleaning / Delivery (Phase 2) | ✅ Roadmapped | 🔴 Not started (expected) |
