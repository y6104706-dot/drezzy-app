import * as admin from "firebase-admin";
import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import {
  IDMVTON_MODEL_VERSION,
  submitPrediction,
  extractOutputUrl,
  ReplicatePrediction,
} from "./replicateClient";

// ─────────────────────────────────────────────────────────────────────────────
// Firestore collection for tracking try-on jobs
// ─────────────────────────────────────────────────────────────────────────────

const TRYON_JOBS_COLLECTION = "tryOnJobs";

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

interface TryOnRequest {
  /** URL of the user's full-body photo. */
  user_image_url: string;
  /** URL of the flat-lay or model photo of the garment. */
  garment_image_url: string;
  /** Plain-text description of the garment (improves model accuracy). */
  garment_description: string;
  /** The user's FCM device token to receive the push notification. */
  fcm_token: string;
}

interface TryOnResponse {
  /** Firestore document ID of the created try-on job. */
  job_id: string;
  message: string;
}

// Shape written to Firestore
interface TryOnJobDocument {
  userId: string;
  fcmToken: string;
  userImageUrl: string;
  garmentImageUrl: string;
  garmentDescription: string;
  replicatePredictionId: string;
  status: "processing" | "completed" | "failed";
  resultUrl: string | null;
  errorMessage: string | null;
  createdAt: admin.firestore.FieldValue;
  updatedAt: admin.firestore.FieldValue;
}

// ─────────────────────────────────────────────────────────────────────────────
// processVirtualTryOn — HTTPS Callable Function
//
// Flow:
//   1. Verify the caller is authenticated.
//   2. Submit an IDM-VTON prediction to Replicate with a webhook URL
//      pointing at `handleReplicateWebhook` (defined below).
//   3. Save a `tryOnJobs/{jobId}` document with status "processing".
//   4. Return the job ID immediately — the client listens to this doc
//      for status changes and the webhook sends a push notification when done.
// ─────────────────────────────────────────────────────────────────────────────

export const processVirtualTryOn = onCall<TryOnRequest>(
  {
    timeoutSeconds: 30, // Just submits — returns fast
    memory: "256MiB",
    region: "us-central1",
  },
  async (request): Promise<TryOnResponse> => {
    // ── 1. Authentication guard ──────────────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to use the virtual try-on feature."
      );
    }

    const callerUid = request.auth.uid;
    const { user_image_url, garment_image_url, garment_description, fcm_token } =
      request.data;

    // ── 2. Input validation ──────────────────────────────────────────────────
    if (!user_image_url || typeof user_image_url !== "string") {
      throw new HttpsError("invalid-argument", "`user_image_url` is required.");
    }
    if (!garment_image_url || typeof garment_image_url !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "`garment_image_url` is required."
      );
    }
    if (!garment_description || typeof garment_description !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "`garment_description` is required."
      );
    }
    if (!fcm_token || typeof fcm_token !== "string") {
      throw new HttpsError("invalid-argument", "`fcm_token` is required.");
    }

    // ── 3. Build webhook URL ─────────────────────────────────────────────────
    const functionsBaseUrl = process.env.FUNCTIONS_BASE_URL;
    if (!functionsBaseUrl) {
      throw new HttpsError(
        "internal",
        "FUNCTIONS_BASE_URL environment variable is not configured."
      );
    }
    const webhookUrl = `${functionsBaseUrl}/handleReplicateWebhook`;

    // ── 4. Submit IDM-VTON prediction to Replicate ───────────────────────────
    let prediction;
    try {
      prediction = await submitPrediction(
        IDMVTON_MODEL_VERSION,
        {
          human_img: user_image_url,
          garm_img: garment_image_url,
          garment_des: garment_description,
          is_checked: true, // higher-quality output
          is_checked_crop: false,
          denoise_steps: 30,
          seed: 42,
        },
        webhookUrl
      );
    } catch (err) {
      console.error("[processVirtualTryOn] Replicate submission failed:", err);
      throw new HttpsError(
        "internal",
        "Failed to start the virtual try-on model. Please try again."
      );
    }

    // ── 5. Save job to Firestore ─────────────────────────────────────────────
    const db = admin.firestore();
    const jobRef = db.collection(TRYON_JOBS_COLLECTION).doc(); // auto-ID

    const jobDoc: TryOnJobDocument = {
      userId: callerUid,
      fcmToken: fcm_token,
      userImageUrl: user_image_url,
      garmentImageUrl: garment_image_url,
      garmentDescription: garment_description,
      replicatePredictionId: prediction.id,
      status: "processing",
      resultUrl: null,
      errorMessage: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await jobRef.set(jobDoc);

    console.log(
      `[processVirtualTryOn] Job ${jobRef.id} created for user ${callerUid}. ` +
        `Replicate prediction: ${prediction.id}`
    );

    return {
      job_id: jobRef.id,
      message:
        "Your virtual try-on is processing. You will receive a push notification when it's ready.",
    };
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// handleReplicateWebhook — HTTPS Request Function (Replicate → Firebase)
//
// Replicate calls this endpoint when a prediction completes or fails.
// This function:
//   1. Validates the incoming payload (basic structure check).
//   2. Finds the matching tryOnJobs document by replicatePredictionId.
//   3. Updates the job status and resultUrl.
//   4. Sends an FCM push notification to the user's device.
//
// Security note: Replicate signs webhooks — validate the signature in
// production using the `replicate-webhook-signing-key` secret. See:
// https://replicate.com/docs/webhooks#verifying-webhooks
// ─────────────────────────────────────────────────────────────────────────────

export const handleReplicateWebhook = onRequest(
  {
    timeoutSeconds: 30,
    memory: "256MiB",
    region: "us-central1",
  },
  async (req, res) => {
    // Only accept POST
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const payload = req.body as ReplicatePrediction;

    // ── 1. Basic payload validation ──────────────────────────────────────────
    if (!payload?.id || !payload?.status) {
      console.warn("[handleReplicateWebhook] Malformed payload received.");
      res.status(400).send("Bad Request: missing id or status.");
      return;
    }

    // Only process terminal states
    if (payload.status !== "succeeded" && payload.status !== "failed") {
      res.status(200).send("Acknowledged. Non-terminal status ignored.");
      return;
    }

    const db = admin.firestore();

    // ── 2. Find the matching job ─────────────────────────────────────────────
    const jobQuery = await db
      .collection(TRYON_JOBS_COLLECTION)
      .where("replicatePredictionId", "==", payload.id)
      .limit(1)
      .get();

    if (jobQuery.empty) {
      console.warn(
        `[handleReplicateWebhook] No job found for prediction ${payload.id}.`
      );
      // Return 200 so Replicate does not retry
      res.status(200).send("No matching job found.");
      return;
    }

    const jobDoc = jobQuery.docs[0];
    const jobData = jobDoc.data() as TryOnJobDocument;

    // ── 3. Resolve output ────────────────────────────────────────────────────
    let resultUrl: string | null = null;
    let newStatus: "completed" | "failed";
    let errorMessage: string | null = null;
    let notificationBody: string;

    if (payload.status === "succeeded") {
      try {
        resultUrl = extractOutputUrl(payload);
        newStatus = "completed";
        notificationBody = "Your virtual try-on is ready! Tap to see how it looks.";
      } catch (err) {
        // Succeeded but no output — treat as failure
        newStatus = "failed";
        errorMessage = "Model succeeded but returned no output image.";
        notificationBody = "Your virtual try-on could not be completed. Please try again.";
      }
    } else {
      newStatus = "failed";
      errorMessage = payload.error ?? "Replicate model failed with unknown error.";
      notificationBody = "Your virtual try-on encountered an error. Please try again.";
    }

    // ── 4. Update Firestore job document ─────────────────────────────────────
    await jobDoc.ref.update({
      status: newStatus,
      resultUrl,
      errorMessage,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(
      `[handleReplicateWebhook] Job ${jobDoc.id} updated to '${newStatus}'. ` +
        `ResultUrl: ${resultUrl}`
    );

    // ── 5. Send FCM push notification to the user's device ───────────────────
    const { fcmToken, userId } = jobData;

    if (fcmToken) {
      try {
        await admin.messaging().send({
          token: fcmToken,
          notification: {
            title: newStatus === "completed" ? "Try-On Ready!" : "Try-On Failed",
            body: notificationBody,
          },
          data: {
            // Allows the app to deep-link directly to the result
            type: "virtual_try_on",
            job_id: jobDoc.id,
            status: newStatus,
            result_url: resultUrl ?? "",
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
                badge: 1,
              },
            },
          },
          android: {
            priority: "high",
            notification: {
              sound: "default",
              channelId: "try_on_results",
            },
          },
        });

        console.log(
          `[handleReplicateWebhook] FCM notification sent to user ${userId}.`
        );
      } catch (fcmErr) {
        // Log but do not fail the webhook — the Firestore update already
        // happened so the client can still poll for the result.
        console.error(
          `[handleReplicateWebhook] FCM send failed for user ${userId}:`,
          fcmErr
        );
      }
    }

    // Respond 200 so Replicate does not retry
    res.status(200).json({ success: true, job_id: jobDoc.id, status: newStatus });
  }
);
