import Replicate from "replicate";

// ─────────────────────────────────────────────────────────────────────────────
// Replicate model identifiers
// ─────────────────────────────────────────────────────────────────────────────

/**
 * InsightFace face-swap model on Replicate.
 * Check https://replicate.com/deepinsight/insightface for the latest version hash.
 */
export const INSIGHTFACE_MODEL_VERSION =
  "563a66acc0b39e5308e8372bed42504731b7fec3f21dcaf8210560059714933e";

/**
 * IDM-VTON virtual try-on model on Replicate.
 * Check https://replicate.com/yisol/idm-vton for the latest version hash.
 */
export const IDMVTON_MODEL_VERSION =
  "906425dbca90663ff5427624839572cc56ea7d380343d13e2a4c4b09d3f0c30f";

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

export interface FaceSwapInput {
  /** The source image whose face will be placed on the target. */
  source_image: string;
  /** The target image that will receive the swapped face. */
  target_image: string;
}

export interface VirtualTryOnInput {
  /** Full-body photo of the person. */
  human_img: string;
  /** Flat-lay or model photo of the garment. */
  garm_img: string;
  /** Text description of the garment (improves accuracy). */
  garment_des: string;
  /** Whether to run at higher quality (slower). Default false. */
  is_checked?: boolean;
}

export interface ReplicatePrediction {
  id: string;
  status: "starting" | "processing" | "succeeded" | "failed" | "canceled";
  output: string | string[] | null;
  error: string | null;
  urls: { get: string; cancel: string };
}

// ─────────────────────────────────────────────────────────────────────────────
// Client factory — reads token from env at call-time (not import-time)
// ─────────────────────────────────────────────────────────────────────────────

export function getReplicateClient(): Replicate {
  const token = process.env.REPLICATE_API_TOKEN;
  if (!token) {
    throw new Error(
      "REPLICATE_API_TOKEN environment variable is not set. " +
        "Add it to functions/.env and redeploy."
    );
  }
  return new Replicate({ auth: token });
}

// ─────────────────────────────────────────────────────────────────────────────
// Submit a prediction (fire-and-forget, with optional webhook)
// ─────────────────────────────────────────────────────────────────────────────

export async function submitPrediction(
  modelVersion: string,
  input: Record<string, unknown>,
  webhookUrl?: string
): Promise<ReplicatePrediction> {
  const replicate = getReplicateClient();

  const prediction = await replicate.predictions.create({
    version: modelVersion,
    input,
    ...(webhookUrl ? { webhook: webhookUrl, webhook_events_filter: ["completed"] } : {}),
  });

  return prediction as ReplicatePrediction;
}

// ─────────────────────────────────────────────────────────────────────────────
// Poll a prediction until it reaches a terminal state or times out.
// ─────────────────────────────────────────────────────────────────────────────

const POLL_INTERVAL_MS = 4_000; // 4 seconds between polls
const MAX_POLLS = 20; // max 80 seconds total

export async function pollPredictionUntilDone(
  predictionId: string
): Promise<ReplicatePrediction> {
  const replicate = getReplicateClient();

  for (let attempt = 0; attempt < MAX_POLLS; attempt++) {
    const prediction = (await replicate.predictions.get(
      predictionId
    )) as ReplicatePrediction;

    if (prediction.status === "succeeded") return prediction;

    if (prediction.status === "failed" || prediction.status === "canceled") {
      throw new Error(
        `Replicate prediction ${predictionId} ended with status: ${prediction.status}. ` +
          `Error: ${prediction.error ?? "unknown"}`
      );
    }

    // Still processing — wait before next poll
    await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
  }

  throw new Error(
    `Replicate prediction ${predictionId} did not complete within the allowed time.`
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Extract the first output URL from a completed prediction
// ─────────────────────────────────────────────────────────────────────────────

export function extractOutputUrl(prediction: ReplicatePrediction): string {
  const output = prediction.output;

  if (typeof output === "string") return output;
  if (Array.isArray(output) && output.length > 0) return output[0];

  throw new Error(
    `Replicate prediction ${prediction.id} succeeded but returned no output URL.`
  );
}
