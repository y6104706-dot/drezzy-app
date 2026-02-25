# Drezzy — Firestore Schema Design

---

## Collection: `listings`

Each document represents a single fashion item available for rent.

**Document ID:** Auto-generated (or use `id` as the document ID)

| Field          | Type        | Description                                                   | Example                         |
|----------------|-------------|---------------------------------------------------------------|---------------------------------|
| `id`           | `string`    | Matches the Firestore document ID                             | `"abc123"`                      |
| `lenderId`     | `string`    | UID of the authenticated user who created the listing         | `"uid_xyz789"`                  |
| `title`        | `string`    | Display name of the item                                      | `"Red Satin Gown"`              |
| `description`  | `string`    | Full description of the item                                  | `"Floor-length, size 8..."`     |
| `category`     | `string`    | Enum: `"dress"` \| `"shoes"` \| `"bag"` \| `"accessory"`    | `"dress"`                       |
| `brand`        | `string?`   | Designer or brand name (optional)                             | `"Zimmermann"`                  |
| `size`         | `string?`   | Item size (optional)                                          | `"M"`, `"36"`, `"8"`           |
| `pricePerDay`  | `number`    | Rental cost in GBP per day (stored as float)                  | `45.00`                         |
| `depositAmount`| `number?`   | Refundable security deposit in GBP (optional)                 | `150.00`                        |
| `imageUrl`     | `string`    | Public URL of the item's primary (face-anonymised) image      | `"https://..."`                 |
| `isFaceSwapped`| `boolean`   | Whether the listing image has been face-anonymised by AI      | `false`                         |
| `tags`         | `string[]?` | Searchable keyword tags (optional)                            | `["midi", "floral", "summer"]`  |
| `location`     | `GeoPoint`  | Firestore GeoPoint of pickup/listing location                 | `GeoPoint(51.5074, -0.1278)`    |
| `status`       | `string`    | Enum: `"available"` \| `"rented"` \| `"unavailable"`         | `"available"`                   |
| `createdAt`    | `timestamp` | Server timestamp set on document creation                     | `Timestamp`                     |
| `updatedAt`    | `timestamp` | Server timestamp updated on every write                       | `Timestamp`                     |

### Notes
- `status` defaults to `"available"` on creation.
- `category` accepts four values: `dress`, `shoes`, `bag`, `accessory`.
- `location` enables Firestore geo-queries using the [GeoFirestore](https://github.com/MichaelSolati/geofirestore-js) pattern or manual bounding-box queries.
- `imageUrl` always stores the face-anonymised version. The original photo is discarded after `generateFaceSwap` completes.

---

## Collection: `bookings`

Each document represents a single rental transaction between a renter and a lender.

**Document ID:** Auto-generated

| Field                    | Type        | Description                                                                          | Example                     |
|--------------------------|-------------|--------------------------------------------------------------------------------------|-----------------------------|
| `listingId`              | `string`    | Reference to the `listings` document ID                                              | `"abc123"`                  |
| `renterId`               | `string`    | UID of the authenticated user renting the item                                       | `"uid_renter42"`            |
| `lenderId`               | `string`    | Denormalized UID of the lender (for Security Rules & queries)                        | `"uid_xyz789"`              |
| `startDate`              | `timestamp` | Start of the rental period                                                           | `Timestamp`                 |
| `endDate`                | `timestamp` | End of the rental period                                                             | `Timestamp`                 |
| `status`                 | `string`    | Enum — see booking status lifecycle below                                            | `"pending"`                 |
| `totalPrice`             | `number`    | `pricePerDay × numberOfDays` — computed before write and stored                      | `135.00`                    |
| `depositAmount`          | `number?`   | Refundable deposit held by Stripe during rental (optional)                           | `150.00`                    |
| `drezzyFee`              | `number`    | Platform fee = **20% of `totalPrice`** — computed before write and stored            | `27.00`                     |
| `stripePaymentIntentId`  | `string?`   | Stripe PaymentIntent ID for the rental charge (set after Stripe processing)          | `"pi_3N..."`                |
| `stripeDepositIntentId`  | `string?`   | Stripe PaymentIntent ID for the deposit hold (set after Stripe processing)           | `"pi_3N..."`                |
| `createdAt`              | `timestamp` | Server timestamp set on document creation                                            | `Timestamp`                 |
| `updatedAt`              | `timestamp` | Server timestamp updated on every write                                              | `Timestamp`                 |

### Booking Status Lifecycle

```
pending ──► confirmed ──► active ──► returned
   │                        │
   ▼                        ▼
cancelled               disputed
```

| Status      | Meaning                                                            | Who sets it       |
|-------------|--------------------------------------------------------------------|-------------------|
| `pending`   | Renter has requested the booking; awaiting lender confirmation     | System (onCreate) |
| `confirmed` | Lender has accepted; Stripe payment captured                       | Lender            |
| `active`    | Item has been dispatched / handed over to the renter               | Lender            |
| `returned`  | Item has been returned to the lender; deposit release initiated    | Lender or Renter  |
| `disputed`  | Either party has raised a damage or non-return dispute             | Lender or Renter  |
| `cancelled` | Booking was cancelled before it became active                      | Renter            |

### `drezzyFee` Calculation

```
drezzyFee = totalPrice × 0.20
totalPrice = pricePerDay × numberOfDays
numberOfDays = (endDate − startDate) in whole days
```

**Example:**
- `pricePerDay` = £45.00
- Rental period = 3 days
- `totalPrice` = £45.00 × 3 = **£135.00**
- `drezzyFee` = £135.00 × 0.20 = **£27.00**
- Lender payout = £135.00 × 0.80 = **£108.00**

> Both `totalPrice` and `drezzyFee` are calculated **client-side or in a Cloud Function** before being written to Firestore. Security Rules validate that `drezzyFee` equals exactly 20% of `totalPrice` on creation.

---

## Collection: `users`

Each document stores a user's profile, preferences, and payment identifiers. Document ID equals the Firebase Auth UID.

**Document ID:** Firebase Auth UID

| Field                 | Type        | Description                                                                         | Example                          |
|-----------------------|-------------|-------------------------------------------------------------------------------------|----------------------------------|
| `email`               | `string`    | User's email address (mirrors Firebase Auth)                                        | `"maya@example.com"`             |
| `displayName`         | `string`    | User's display name (mirrors Firebase Auth)                                         | `"Maya Cohen"`                   |
| `avatarUrl`           | `string?`   | URL of the user's profile photo (optional)                                          | `"https://..."`                  |
| `role`                | `string[]`  | One or more of: `"renter"`, `"lender"`, `"both"`                                   | `["renter"]`                     |
| `stripeCustomerId`    | `string?`   | Stripe Customer ID for renter payment methods (set on first checkout)               | `"cus_Nfj..."`                   |
| `stripeAccountId`     | `string?`   | Stripe Connect Account ID for lender payouts (set during lender onboarding)         | `"acct_1N..."`                   |
| `stylePreferences`    | `string[]?` | Style tags from the onboarding quiz (e.g. `["bohemian", "elegant", "minimalist"]`) | `["elegant", "minimalist"]`      |
| `defaultSize`         | `string?`   | User's clothing/shoe size — scoring boost in voice search                           | `"M"`, `"36"`, `"8"`            |
| `preferredCategories` | `string[]?` | Preferred item categories — fallback in voice search when AI can't infer one        | `["dress", "shoes"]`             |
| `maxPricePerDay`      | `number?`   | Self-declared budget ceiling in GBP/day — hard Firestore filter in voice search     | `75.00`                          |
| `fcmTokens`           | `string[]?` | Active FCM device tokens for push notifications (multiple devices supported)        | `["token1", "token2"]`           |
| `location`            | `GeoPoint?` | User's approximate location for proximity-based feed sorting (optional)             | `GeoPoint(51.5074, -0.1278)`     |
| `createdAt`           | `timestamp` | Server timestamp set on document creation                                           | `Timestamp`                      |
| `updatedAt`           | `timestamp` | Server timestamp updated on every write                                             | `Timestamp`                      |

### Notes
- `stripeCustomerId` is created lazily on the user's first rental checkout via Stripe.
- `stripeAccountId` is created during Stripe Connect onboarding, which is required before a user can receive lender payouts.
- `stylePreferences` is populated during the 3-question onboarding style quiz.
- `maxPricePerDay` is a **hard budget ceiling**: applied as a `pricePerDay <= N` Firestore filter in voice search.
- `defaultSize` is an **in-memory scoring boost** (not a filter) because size lives in free-text `description`.
- `preferredCategories` is a **fallback** used only when the AI could not infer a category from a voice search query.

---

## Collection: `reviews`

Each document represents a rating and written review left by one user about another user or a listing.

**Document ID:** Auto-generated

| Field        | Type        | Description                                                                   | Example                  |
|--------------|-------------|-------------------------------------------------------------------------------|--------------------------|
| `bookingId`  | `string`    | Reference to the `bookings` document this review is associated with           | `"bkg_abc123"`           |
| `authorId`   | `string`    | UID of the authenticated user writing the review                              | `"uid_renter42"`         |
| `targetId`   | `string`    | UID of the user, or document ID of the listing, being reviewed                | `"uid_xyz789"`           |
| `targetType` | `string`    | Enum: `"user"` \| `"listing"`                                                 | `"listing"`              |
| `rating`     | `number`    | Integer rating from **1 to 5** (inclusive)                                    | `5`                      |
| `body`       | `string`    | Written review text                                                           | `"Gorgeous dress!..."`   |
| `createdAt`  | `timestamp` | Server timestamp set on document creation                                     | `Timestamp`              |

### Notes
- Reviews are **immutable** once created. Neither the author nor any other user can edit or delete them — this preserves the integrity of the trust signal.
- A renter reviewing a lender's listing sets `targetType: "listing"` and `targetId` to the `listingId`.
- A lender reviewing a renter sets `targetType: "user"` and `targetId` to the renter's UID.
- Application-layer logic (Cloud Function or client) should enforce one review per `(authorId, bookingId, targetType)` combination to prevent duplicate reviews.

---

## Subcollection Strategy (Optional — for scale)

If a listing accumulates many bookings, consider:

```
listings/{listingId}/bookings/{bookingId}
```

This keeps booking history co-located with the listing and reduces cross-collection joins. The top-level `bookings` collection is preferred for dashboard-style queries (e.g., "all bookings for a renter").

---

## Index Recommendations

| Collection | Fields to Index                                       | Use Case                                          |
|------------|-------------------------------------------------------|---------------------------------------------------|
| `listings` | `category ASC`, `status ASC`                          | Filter by category + availability                 |
| `listings` | `status ASC`, `pricePerDay ASC`                       | Voice search price ceiling (no category filter)   |
| `listings` | `category ASC`, `status ASC`, `pricePerDay ASC`       | Voice search price ceiling + category filter      |
| `listings` | `lenderId ASC`, `createdAt DESC`                      | Lender's listings dashboard                       |
| `bookings` | `renterId ASC`, `status ASC`                          | Renter's active/past bookings                     |
| `bookings` | `lenderId ASC`, `status ASC`                          | Lender's incoming booking requests                |
| `bookings` | `listingId ASC`, `status ASC`                         | All bookings for a specific listing               |
| `reviews`  | `targetId ASC`, `targetType ASC`                      | All reviews for a listing or user profile         |
| `reviews`  | `authorId ASC`, `createdAt DESC`                      | All reviews written by a specific user            |
