# DREZZY — Master Plan
> **Single Source of Truth** · Last updated: 2026-02-25
> *Any AI agent or developer reading this document should treat it as the canonical reference for every architectural, product, and business decision made on this project.*

---

## 1. Vision

**Drezzy** is a premium, peer-to-peer (P2P) fashion rental marketplace where anyone can rent or lend high-end clothing and accessories. It is powered by AI to deliver an experience that is personal, safe, and frictionless — making luxury fashion accessible to everyone, without the commitment of ownership.

> "Wear More. Own Less."

---

## 2. Core Features — The Game Changers

These are the features that differentiate Drezzy from any generic rental marketplace. They are non-negotiable for the MVP and define the product's competitive moat.

---

### 2.1 Virtual Try-On (VTON)

| Property | Detail |
|---|---|
| **What it does** | Allows a renter to upload a single full-body photo and see themselves wearing any listed dress before booking. |
| **AI Model** | [IDM-VTON](https://replicate.com/yisol/idm-vton) — state-of-the-art garment transfer model, hosted on Replicate. |
| **Inputs** | `person_image` (renter photo) + `garment_image` (listing photo extracted by lender). |
| **Output** | A photorealistic composite image rendered and displayed in-app. |
| **UX placement** | "Try On" button on every listing detail screen. Result is shown in a full-screen preview overlay. |
| **Privacy** | The renter's body photo is never stored persistently — it is sent directly to the Replicate API and the result URL is cached temporarily (TTL: 1 hour). |

---

### 2.2 Face Swap Privacy (Lender Identity Protection)

| Property | Detail |
|---|---|
| **What it does** | When a lender uploads a photo wearing the garment, the AI automatically detects and replaces their face with a neutral, photorealistic placeholder to protect their identity. |
| **AI Model** | Face detection + inpainting via Replicate (e.g., `lucataco/face-swap` or equivalent). |
| **Trigger** | Applied automatically at upload time — the lender never needs to take action. |
| **Storage** | Only the face-anonymised version of the photo is stored in Firebase Storage. The original is discarded immediately after processing. |
| **Purpose** | Removes a key barrier for lenders (privacy anxiety) and increases listing supply. |

---

### 2.3 Natural Language Search (Semantic Search)

| Property | Detail |
|---|---|
| **What it does** | Users can search for items using natural, descriptive language instead of rigid keyword filters. |
| **Example queries** | `"Modest dress for a winter wedding"`, `"Bold red gown under £80 in London"`, `"Floral midi dress for a beach birthday party"` |
| **Implementation** | Queries and listing descriptions are embedded using a text embedding model (e.g., `text-embedding-3-small` via OpenAI or a Replicate-hosted model). Embeddings are stored in Firestore / a vector-compatible store and retrieved via cosine similarity. |
| **Fallback** | If semantic search returns low-confidence results, falls back to Firestore keyword + tag filtering. |
| **UX placement** | Default search bar on the Browse/Home screen. A "Search by description" chip toggles semantic mode explicitly. |

---

## 3. Technical Stack

### 3.1 Frontend

| Layer | Technology |
|---|---|
| Framework | **Flutter** (Dart) — cross-platform (iOS + Android) |
| State Management | **Riverpod** (`flutter_riverpod ^2.x`) |
| Routing | `go_router` |
| UI Fonts | **Cormorant Garant** (display) · **DM Sans** (body) via `google_fonts` |
| Theme | Material 3, dark-first. Palette: Obsidian Plum + Champagne Gold |

### 3.2 Backend & Infrastructure

| Layer | Technology |
|---|---|
| Authentication | **Firebase Auth** — Email/Password, Google Sign-In, Apple Sign-In |
| Database | **Cloud Firestore** — real-time document store |
| File Storage | **Firebase Storage** — garment photos, try-on results |
| Functions | **Firebase Cloud Functions** (Node.js / TypeScript) — commission logic, webhook handling |
| AI Services | **Replicate API** — VTON, face swap, future model integrations |
| Payments | **Stripe** — rental checkout, lender payouts, deposit management |

### 3.3 Folder Structure (`lib/`)

```
lib/
├── core/
│   ├── theme/          # DrezzyTheme, DrezzyColors, DrezzyTextTheme
│   └── core.dart       # Barrel export
├── features/
│   ├── auth/
│   │   ├── data/       # Firebase Auth datasource, repository impl
│   │   ├── domain/     # AuthRepository interface, User entity, use cases
│   │   └── presentation/ # Login, Register, Forgot Password screens + providers
│   ├── listings/
│   │   ├── data/       # Firestore datasource, Storage upload, repository impl
│   │   ├── domain/     # Listing entity, ListingRepository, use cases
│   │   └── presentation/ # Browse, Detail, Create/Edit Listing screens + providers
│   ├── ai_services/
│   │   ├── data/       # Replicate API client, response models
│   │   ├── domain/     # AIRepository, VTONUseCase, FaceSwapUseCase, SearchUseCase
│   │   └── presentation/ # Try-On overlay, Search bar widget + providers
│   └── payments/
│       ├── data/       # Stripe SDK integration, Cloud Functions client
│       ├── domain/     # PaymentRepository, CheckoutUseCase, PayoutUseCase
│       └── presentation/ # Checkout flow, Transaction History screens + providers
└── main.dart
```

---

## 4. Business Logic

### 4.1 Commission Model

- Drezzy charges a **20% platform commission** on every completed rental.
- The lender receives **80%** of the agreed rental price.
- Commission is deducted automatically at payout via Stripe Connect.

**Example:**
```
Rental price:   £100
Lender payout:  £80  (80%)
Drezzy revenue: £20  (20%)
```

### 4.2 Supported Categories

| Category | Examples |
|---|---|
| Dresses | Evening gowns, cocktail dresses, midi dresses, wedding guest |
| Shoes | Heels, boots, designer sneakers, sandals |
| Bags | Clutches, totes, designer handbags, crossbody |
| Accessories | Jewellery, belts, scarves, hats, sunglasses |

### 4.3 Rental Pricing Rules

- Lenders set their own **daily rental price**.
- A **refundable security deposit** (configurable per item, recommended: 30–50% of item value) is held by Stripe during the rental period and released upon safe return.
- Rentals are priced in **GBP** by default, with multi-currency support planned for v2.

### 4.4 Dispute & Damage Policy

- Drezzy mediates disputes between lenders and renters.
- Evidence (photos at dispatch and return) is uploaded to Firebase Storage and linked to the booking document.
- Disputes must be raised within **48 hours** of item return.

---

## 5. User Flows

### 5.1 Renter Journey

```
1. Onboarding    → Sign up (email / Google / Apple) → Style quiz (3 questions) → Location set
2. Browse        → Home feed (location-based) → Semantic search → Filter by category/price/date
3. Discovery     → Listing detail → Photo gallery → Virtual Try-On → Size guide
4. Booking       → Select rental dates → Checkout (Stripe) → Deposit held → Confirmation
5. Experience    → Lender ships / hands over → Renter wears → Returns item
6. Post-rental   → Deposit released → Leave review → Share look on social
```

### 5.2 Lender Journey

```
1. Onboarding    → Sign up → ID verification (KYC lite) → Stripe Connect setup
2. List Item     → Upload photos (face swap applied automatically) → Set price/deposit/availability
3. Manage        → Accept/decline booking requests → Message renter → Mark as dispatched
4. Completion    → Confirm return → Receive payout (80%) → Review renter
```

---

## 6. Data Models (Firestore Schema Overview)

### `users/{userId}`
```
id, email, displayName, avatarUrl, stripeCustomerId, stripeAccountId,
role: ['renter' | 'lender' | 'both'], location: GeoPoint,
createdAt, stylePreferences: []
```

### `listings/{listingId}`
```
id, lenderId, title, description, category, brand, size,
pricePerDay, depositAmount, availableDates: [],
images: [{ url, isCover }], tags: [], location: GeoPoint,
status: ['active' | 'rented' | 'inactive'], createdAt
```

### `bookings/{bookingId}`
```
id, listingId, renterId, lenderId,
startDate, endDate, totalPrice, depositAmount, commission,
status: ['pending' | 'confirmed' | 'active' | 'returned' | 'disputed' | 'cancelled'],
stripePaymentIntentId, stripeDepositIntentId, createdAt
```

### `reviews/{reviewId}`
```
id, bookingId, authorId, targetId, targetType: ['user' | 'listing'],
rating: 1–5, body, createdAt
```

---

## 7. AI Services Reference

All AI calls are routed through **Replicate API** and orchestrated by **Firebase Cloud Functions** (server-side) to keep API keys out of the client.

| Service | Replicate Model | Triggered By |
|---|---|---|
| Virtual Try-On | `yisol/idm-vton` | Renter taps "Try On" on listing detail |
| Face Swap / Anonymisation | `lucataco/face-swap` or inpainting model | Lender uploads garment photo |
| Semantic Search Embedding | Text embedding model (TBD) | Any search query |
| Style Recommendation | Custom / fine-tuned model (v2) | Post-booking, home feed personalisation |

### Cloud Function: `processGarmentUpload`
```
Trigger: Firebase Storage onCreate (listings/{listingId}/raw/*)
Steps:
  1. Download raw image from Storage
  2. Call Replicate face-swap model
  3. Upload anonymised result to listings/{listingId}/photos/*
  4. Delete raw image
  5. Update Firestore listing document with new photo URL
```

### Cloud Function: `virtualTryOn`
```
Trigger: HTTPS callable
Input:  { listingId, personImageBase64 }
Steps:
  1. Fetch garment image URL from Firestore listing
  2. Call Replicate IDM-VTON with (personImage, garmentImage)
  3. Poll prediction until complete
  4. Return output image URL (not stored)
```

---

## 8. Future Roadmap

### Phase 2 — Scale (Post-MVP)

| Feature | Description |
|---|---|
| **Dry Cleaning Partnerships** | Integrated with local/national dry cleaning services. Lenders can optionally require renters to pay for a post-rental clean, fulfilled through a Drezzy-managed partner network. |
| **Integrated Delivery** | In-app delivery booking via courier API (e.g., Stuart, Gophr). Removes the coordination burden from lenders and renters. Delivery cost added to checkout. |
| **Multi-currency & Localisation** | Expand beyond GBP. Support EUR, USD. Localise search to city-level. |
| **Wardrobe Valuation** | AI estimates the rental market value of items in a user's wardrobe to encourage listing. |
| **Subscription Tier ("Drezzy Pass")** | Monthly fee for renters granting reduced commission rates and priority access to new listings. |
| **Brand Partnerships** | Direct partnerships with designer brands for authenticated, insured, high-value rentals. |

---

## 9. Non-Functional Requirements

| Requirement | Target |
|---|---|
| App launch time (cold start) | < 2 seconds |
| VTON API response time | < 30 seconds (async with progress indicator) |
| Search result latency | < 500ms (semantic) / < 200ms (keyword fallback) |
| Image upload size limit | 10 MB per photo |
| Firestore security rules | All reads/writes validated server-side; no client can write another user's data |
| GDPR / Privacy | Face data never persisted; user data deletable on request; Privacy Policy in-app |
| Platforms | iOS 15+ · Android 8+ (API 26+) |

---

## 10. Agent Instructions

> This section is addressed directly to any AI agent (Claude, GPT, Cursor, etc.) working on this codebase.

1. **Always refer to this document first** before making architectural decisions. If this document does not cover a scenario, ask the user before inventing conventions.
2. **Folder structure is canonical.** New code goes into the appropriate `features/` sub-layer (`data/`, `domain/`, `presentation/`). Do not create top-level files in `lib/` except `main.dart`.
3. **Riverpod is the only state management solution.** Do not introduce `Provider`, `Bloc`, `GetX`, or `setState` outside of truly local UI state.
4. **All AI API calls must be server-side.** Never expose the Replicate API key or Stripe secret key in client-side Dart code. Route through Firebase Cloud Functions.
5. **Theme is defined in `lib/core/theme/app_theme.dart`.** Do not hardcode colors or font sizes anywhere else in the codebase. Use `Theme.of(context).colorScheme` and `Theme.of(context).textTheme`.
6. **Commission rate (20%) is a business constant.** Define it once in `lib/core/constants/` and reference it everywhere.
7. **When in doubt, do less.** Prefer a clean, working slice of a feature over an ambitious but broken implementation.
