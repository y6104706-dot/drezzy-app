import * as admin from "firebase-admin";

// Initialize Firebase Admin SDK once for the entire functions package.
// When running in Cloud Functions, credentials are picked up automatically
// from the service account attached to the function.
admin.initializeApp();

// ── Export all Cloud Functions ────────────────────────────────────────────────

export { generateFaceSwap } from "./faceSwap";
export { processVirtualTryOn, handleReplicateWebhook } from "./virtualTryOn";
export { processVoiceSearch } from "./voiceSearch";
