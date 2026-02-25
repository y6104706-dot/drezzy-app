import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import {
  INSIGHTFACE_MODEL_VERSION,
  submitPrediction,
  pollPredictionUntilDone,
  extractOutputUrl,
} from "./replicateClient";

// ─────────────────────────────────────────────────────────────────────────────
// Request / Response shapes
// ─────────────────────────────────────────────────────────────────────────────

interface FaceSwapRequest {
  /** The listing document ID to update after the swap completes. */
  listing_id: string;
  /**
   * URL of the image whose face will be transplanted onto the listing photo.
   * Typically the authenticated user's selfie.
   */
  image_url: string;
}

interface FaceSwapResponse {
  /** The new display image URL stored in the listing. */
  display_image_url: string;
}

// ─────────────────────────────────────────────────────────────────────────────
// generateFaceSwap — HTTPS Callable Function
//
// Flow:
//   1. Verify the caller is authenticated.
//   2. Verify the caller owns the specified listing.
//   3. Submit an InsightFace prediction to Replicate.
//   4. Poll synchronously (max ~80 s) until the prediction completes.
//   5. Write `displayImageUrl` and `isFaceSwapped: true` back to the listing.
//   6. Return the new image URL to the client.
//
// Timeout: set to 120 s to give Replicate ample time to run the model.
// ─────────────────────────────────────────────────────────────────────────────

export const generateFaceSwap = onCall<FaceSwapRequest>(
  {
    timeoutSeconds: 120,
    memory: "256MiB",
    region: "us-central1",
  },
  async (request): Promise<FaceSwapResponse> => {
    // ── 1. Authentication guard ──────────────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to use the face-swap feature."
      );
    }

    const callerUid = request.auth.uid;
    const { listing_id, image_url } = request.data;

    // ── 2. Input validation ──────────────────────────────────────────────────
    if (!listing_id || typeof listing_id !== "string") {
      throw new HttpsError("invalid-argument", "`listing_id` is required.");
    }
    if (!image_url || typeof image_url !== "string") {
      throw new HttpsError("invalid-argument", "`image_url` is required.");
    }

    // ── 3. Ownership check ───────────────────────────────────────────────────
    const db = admin.firestore();
    const listingRef = db.collection("listings").doc(listing_id);
    const listingSnap = await listingRef.get();

    if (!listingSnap.exists) {
      throw new HttpsError("not-found", `Listing '${listing_id}' not found.`);
    }

    const listingData = listingSnap.data()!;
    if (listingData.lenderId !== callerUid) {
      throw new HttpsError(
        "permission-denied",
        "You can only apply face swap to your own listings."
      );
    }

    const listingImageUrl: string = listingData.imageUrl;
    if (!listingImageUrl) {
      throw new HttpsError(
        "failed-precondition",
        "The listing does not have a base image to swap onto."
      );
    }

    // ── 4. Submit InsightFace prediction to Replicate ────────────────────────
    let prediction;
    try {
      prediction = await submitPrediction(INSIGHTFACE_MODEL_VERSION, {
        // source_image: the face donor (caller's selfie)
        source_image: image_url,
        // target_image: the listing photo that receives the swapped face
        target_image: listingImageUrl,
      });
    } catch (err) {
      console.error("[generateFaceSwap] Replicate submission failed:", err);
      throw new HttpsError(
        "internal",
        "Failed to start the face-swap model. Please try again."
      );
    }

    // ── 5. Poll until complete ───────────────────────────────────────────────
    let completed;
    try {
      completed = await pollPredictionUntilDone(prediction.id);
    } catch (err) {
      console.error(
        `[generateFaceSwap] Prediction ${prediction.id} failed or timed out:`,
        err
      );
      throw new HttpsError(
        "deadline-exceeded",
        "Face-swap model did not complete in time. Please try again."
      );
    }

    const displayImageUrl = extractOutputUrl(completed);

    // ── 6. Update the listing document ──────────────────────────────────────
    await listingRef.update({
      displayImageUrl,
      isFaceSwapped: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(
      `[generateFaceSwap] Listing ${listing_id} updated for user ${callerUid}. ` +
        `Prediction: ${prediction.id}`
    );

    return { display_image_url: displayImageUrl };
  }
);
