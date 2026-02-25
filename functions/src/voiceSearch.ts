import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import {
  GoogleGenerativeAI,
  HarmCategory,
  HarmBlockThreshold,
} from "@google/generative-ai";

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const GEMINI_MODEL = "gemini-1.5-flash";
const LISTINGS_COLLECTION = "listings";
const USERS_COLLECTION = "users";

/**
 * Maximum number of Firestore documents to load for in-memory scoring.
 * For production at scale, replace with Algolia / Typesense full-text search.
 */
const MAX_LISTINGS_TO_SCORE = 200;

/** Maximum results returned to the client. */
const MAX_RESULTS = 20;

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

type ListingCategory = "dress" | "shoes" | "bag" | "accessory";

/** Fields read from the `users/{uid}` document. All optional — profile may be partial. */
interface UserProfile {
  /** User's clothing size (e.g. "S", "M", "L", "36", "8"). Used as a scoring boost. */
  defaultSize?: string;
  /** User's preferred categories. Used as a fallback when the AI couldn't infer one. */
  preferredCategories?: ListingCategory[];
  /** User's self-declared budget ceiling in USD/day. Applied as a hard Firestore filter. */
  maxPricePerDay?: number;
}

/**
 * Resolved overrides merged from AI attributes + user profile.
 * Split into two groups to make their role in the query clear.
 */
interface QueryOverrides {
  // ── Firestore-level (.where() clauses) ──────────────────────────────────────
  /** Final resolved category — AI wins, profile is the fallback. */
  category: ListingCategory | null;
  /**
   * Hard price ceiling from the user's profile.
   * Applied as `.where("pricePerDay", "<=", maxPricePerDay)`.
   * The AI never overrides this; it is always the user's saved preference.
   */
  maxPricePerDay: number | null;

  // ── In-memory scoring only ───────────────────────────────────────────────────
  /**
   * User's default clothing size.
   * Scores +4 when the listing's description mentions this size.
   * Not used as a Firestore filter because size lives in free-text description.
   */
  preferredSize: string | null;
}

/** The structured fashion attributes the LLM extracts from the user's query. */
interface ParsedAttributes {
  category: ListingCategory | null;
  style: string | null;
  color: string | null;
  occasion: string | null;
  specific_features: string[];
}

/** LLM envelope when attributes were successfully extracted. */
interface LLMEnvelopeSuccess {
  needs_clarification: false;
  clarification_question: null;
  /** ISO 639-1 language code auto-detected from the user's input (e.g. "en", "he"). */
  detected_language: string;
  /**
   * A friendly result announcement in the user's language.
   * Contains exactly one "{count}" placeholder for the number of results found.
   * Example (en): "Great choice! I found {count} stunning Hollywood-style dresses for you."
   * Example (he): "בחירה מעולה! מצאתי {count} שמלות מדהימות בסגנון הוליווד בשבילך."
   */
  response_template: string;
  /**
   * A short empathetic message shown when zero results are found.
   * Always in the user's language.
   */
  no_results_response: string;
  attributes: ParsedAttributes;
}

/** LLM envelope when the query is too vague to extract useful attributes. */
interface LLMEnvelopeClarification {
  needs_clarification: true;
  /** A single friendly follow-up question in the user's language. */
  clarification_question: string;
  detected_language: string;
  response_template: null;
  no_results_response: null;
  attributes: null;
}

type LLMEnvelope = LLMEnvelopeSuccess | LLMEnvelopeClarification;

/** A single listing document projected from Firestore. */
interface ListingDoc {
  id: string;
  title: string;
  description: string;
  category: string;
  pricePerDay: number;
  imageUrl: string;
}

/** A single result item returned to the client. */
interface SearchResult {
  id: string;
  title: string;
  category: string;
  pricePerDay: number;
  imageUrl: string;
  score: number;
}

type VoiceSearchResponse =
  | {
      type: "results";
      listings: SearchResult[];
      attributes: ParsedAttributes;
      /** Natural-language summary of the results, in the user's input language. */
      conversational_response: string;
      /** ISO 639-1 code — lets the client set text direction (RTL for "he", "ar", etc.). */
      detected_language: string;
    }
  | {
      type: "clarification_needed";
      /** Friendly follow-up question in the user's language. */
      question: string;
      detected_language: string;
    }
  | {
      type: "no_results";
      attributes: ParsedAttributes;
      conversational_response: string;
      detected_language: string;
    };

// ─────────────────────────────────────────────────────────────────────────────
// Gemini client factory
// ─────────────────────────────────────────────────────────────────────────────

function getGeminiClient(): GoogleGenerativeAI {
  const key = process.env.GEMINI_API_KEY;
  if (!key) {
    throw new Error(
      "GEMINI_API_KEY environment variable is not set. " +
        "Add it to functions/.env and redeploy."
    );
  }
  return new GoogleGenerativeAI(key);
}

// ─────────────────────────────────────────────────────────────────────────────
// System prompt
// ─────────────────────────────────────────────────────────────────────────────

const SYSTEM_PROMPT = `
You are a fashion expert assistant for Drezzy, a peer-to-peer fashion rental marketplace.

TASK: Analyse the user's natural-language search query and return ONLY a valid JSON object.

RULES:
1. Return ONLY a valid JSON object — no markdown fences, no extra keys, no explanation.
2. Auto-detect the language of the user's input. Set "detected_language" to the ISO 639-1 code (e.g. "en", "he", "fr", "ar", "es").
3. ALL natural-language strings you write (response_template, no_results_response, clarification_question) MUST be in the same language as the user's input.
4. "response_template" must contain exactly one "{count}" placeholder. It should be an enthusiastic, friendly announcement of the search results. Example (en): "Great choice! I found {count} stunning Hollywood-style dresses for you." Example (he): "בחירה מעולה! מצאתי {count} שמלות מדהימות בסגנון הוליווד בשבילך."
5. "no_results_response" is shown when zero matching items exist. It should be empathetic and encourage the user to check back or try a broader search.
6. "needs_clarification" must be true ONLY when the query is so vague that you cannot extract even ONE useful attribute. Vague examples: "something pretty", "nice", "I don't know", "anything". NOT vague: "something red for a party" (has color + occasion).
7. When needs_clarification is true, write a single friendly follow-up question in "clarification_question" targeting the most helpful missing detail.
8. "category" must be exactly one of: "dress", "shoes", "bag", "accessory", or null. Default to "dress" if the user does not specify a type.
9. All attribute string values (style, color, occasion, features) must be lowercase.
10. "specific_features" may be an empty array.

SHAPE A — attributes successfully extracted:
{
  "needs_clarification": false,
  "clarification_question": null,
  "detected_language": "<ISO 639-1 code>",
  "response_template": "<enthusiastic result announcement in user's language with {count} placeholder>",
  "no_results_response": "<empathetic no-results message in user's language>",
  "attributes": {
    "category": "dress" | "shoes" | "bag" | "accessory" | null,
    "style": string | null,
    "color": string | null,
    "occasion": string | null,
    "specific_features": string[]
  }
}

SHAPE B — query is too vague:
{
  "needs_clarification": true,
  "clarification_question": "<friendly follow-up question in user's language>",
  "detected_language": "<ISO 639-1 code>",
  "response_template": null,
  "no_results_response": null,
  "attributes": null
}

EXAMPLES:

User: "I need a red floral midi dress for a beach wedding"
Response: {"needs_clarification":false,"clarification_question":null,"detected_language":"en","response_template":"Great choice! I found {count} stunning red floral dresses perfect for a beach wedding.","no_results_response":"We couldn't find any red floral dresses right now — new items are added daily, so check back soon!","attributes":{"category":"dress","style":"floral","color":"red","occasion":"wedding","specific_features":["midi","beach"]}}

User: "אני רוצה שמלה בסגנון הוליווד"
Response: {"needs_clarification":false,"clarification_question":null,"detected_language":"he","response_template":"בחירה מעולה! מצאתי {count} שמלות מדהימות בסגנון הוליווד בשבילך.","no_results_response":"לא מצאנו שמלות בסגנון הוליווד כרגע — פריטים חדשים מתווספים מדי יום, כדאי לבדוק שוב בקרוב!","attributes":{"category":"dress","style":"hollywood","color":null,"occasion":null,"specific_features":[]}}

User: "something pretty"
Response: {"needs_clarification":true,"clarification_question":"I'd love to help! Could you tell me what occasion you're dressing for — a wedding, party, or night out?","detected_language":"en","response_template":null,"no_results_response":null,"attributes":null}

User: "משהו יפה"
Response: {"needs_clarification":true,"clarification_question":"אשמח לעזור! לאיזה אירוע את/ה מחפש/ת להתלבש — חתונה, מסיבה, יציאה לערב?","detected_language":"he","response_template":null,"no_results_response":null,"attributes":null}

User: "I want heels for a night out"
Response: {"needs_clarification":false,"clarification_question":null,"detected_language":"en","response_template":"You'll turn heads! I found {count} fabulous heels perfect for a night out.","no_results_response":"No heels available right now, but we're growing fast — check back soon!","attributes":{"category":"shoes","style":"heels","color":null,"occasion":"night out","specific_features":[]}}
`.trim();

// ─────────────────────────────────────────────────────────────────────────────
// LLM extraction — parses and validates the Gemini JSON response
// ─────────────────────────────────────────────────────────────────────────────

async function extractAttributesWithGemini(
  transcribedText: string
): Promise<LLMEnvelope> {
  const genAI = getGeminiClient();
  const model = genAI.getGenerativeModel({
    model: GEMINI_MODEL,
    systemInstruction: SYSTEM_PROMPT,
    safetySettings: [
      {
        category: HarmCategory.HARM_CATEGORY_HARASSMENT,
        threshold: HarmBlockThreshold.BLOCK_ONLY_HIGH,
      },
      {
        category: HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
        threshold: HarmBlockThreshold.BLOCK_ONLY_HIGH,
      },
    ],
    generationConfig: {
      temperature: 0.1,    // Deterministic for structured output
      maxOutputTokens: 512, // Increased — now includes two template strings
    },
  });

  const result = await model.generateContent(transcribedText);
  const rawText = result.response.text().trim();

  // Strip accidental markdown fences
  const cleaned = rawText
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/, "")
    .trim();

  let parsed: unknown;
  try {
    parsed = JSON.parse(cleaned);
  } catch {
    throw new Error(
      `Gemini returned non-JSON output. Raw: "${rawText.slice(0, 200)}"`
    );
  }

  if (typeof parsed !== "object" || parsed === null) {
    throw new Error("Gemini response was not an object.");
  }

  const obj = parsed as Record<string, unknown>;
  const detectedLanguage =
    typeof obj.detected_language === "string" ? obj.detected_language : "en";

  // ── Clarification branch ────────────────────────────────────────────────────
  if (obj.needs_clarification === true) {
    if (typeof obj.clarification_question !== "string") {
      throw new Error(
        "Gemini returned needs_clarification:true with no clarification_question."
      );
    }
    return {
      needs_clarification: true,
      clarification_question: obj.clarification_question,
      detected_language: detectedLanguage,
      response_template: null,
      no_results_response: null,
      attributes: null,
    };
  }

  // ── Validate template strings ────────────────────────────────────────────────
  if (typeof obj.response_template !== "string" || !obj.response_template.includes("{count}")) {
    throw new Error(
      'Gemini response_template is missing or does not contain "{count}" placeholder.'
    );
  }
  if (typeof obj.no_results_response !== "string") {
    throw new Error("Gemini no_results_response is missing or not a string.");
  }

  // ── Validate attributes ──────────────────────────────────────────────────────
  const attrs = obj.attributes as Record<string, unknown> | undefined;
  if (typeof attrs !== "object" || attrs === null) {
    throw new Error("Gemini response missing 'attributes' object.");
  }

  const validCategories: ListingCategory[] = ["dress", "shoes", "bag", "accessory"];
  const rawCategory = attrs.category;
  const category: ListingCategory | null =
    typeof rawCategory === "string" &&
    validCategories.includes(rawCategory as ListingCategory)
      ? (rawCategory as ListingCategory)
      : null;

  const features = Array.isArray(attrs.specific_features)
    ? (attrs.specific_features as unknown[]).filter(
        (f): f is string => typeof f === "string"
      )
    : [];

  return {
    needs_clarification: false,
    clarification_question: null,
    detected_language: detectedLanguage,
    response_template: obj.response_template,
    no_results_response: obj.no_results_response,
    attributes: {
      category,
      style: typeof attrs.style === "string" ? attrs.style : null,
      color: typeof attrs.color === "string" ? attrs.color : null,
      occasion: typeof attrs.occasion === "string" ? attrs.occasion : null,
      specific_features: features,
    },
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// User profile — fetched from users/{uid}
// ─────────────────────────────────────────────────────────────────────────────

async function fetchUserProfile(uid: string): Promise<UserProfile | null> {
  try {
    const snap = await admin
      .firestore()
      .collection(USERS_COLLECTION)
      .doc(uid)
      .get();
    if (!snap.exists) return null;
    const d = snap.data() as Record<string, unknown>;
    return {
      defaultSize:
        typeof d.defaultSize === "string" ? d.defaultSize : undefined,
      preferredCategories: Array.isArray(d.preferredCategories)
        ? (d.preferredCategories as unknown[]).filter(
            (c): c is ListingCategory =>
              c === "dress" || c === "shoes" || c === "bag" || c === "accessory"
          )
        : undefined,
      maxPricePerDay:
        typeof d.maxPricePerDay === "number" && d.maxPricePerDay > 0
          ? d.maxPricePerDay
          : undefined,
    };
  } catch (err) {
    // Profile fetch failure is non-fatal — degrade gracefully without overrides.
    console.warn(`[processVoiceSearch] Could not fetch profile for ${uid}:`, err);
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Override merging
//
// Precedence rules:
//   category      → AI wins (explicit user intent) > profile preference > null
//   maxPricePerDay → ALWAYS from profile (budget ceiling, never overridden by AI)
//   preferredSize  → ALWAYS from profile (scoring boost only)
// ─────────────────────────────────────────────────────────────────────────────

function buildQueryOverrides(
  aiAttrs: ParsedAttributes,
  profile: UserProfile | null
): QueryOverrides {
  return {
    // AI-detected category wins; fall back to first preferred category from profile.
    category:
      aiAttrs.category ??
      (profile?.preferredCategories?.[0] ?? null),

    // Budget ceiling is always the user's saved preference. The AI never touches it.
    maxPricePerDay: profile?.maxPricePerDay ?? null,

    // Size boost is always from profile — the AI extracts clothing style, not size.
    preferredSize: profile?.defaultSize ?? null,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Firestore query
//
// Applies Firestore-level filters from both AI attributes and profile overrides.
// In-memory text scoring handles the rest (style, color, occasion, size).
// ─────────────────────────────────────────────────────────────────────────────

async function queryListings(
  overrides: QueryOverrides
): Promise<ListingDoc[]> {
  const db = admin.firestore();

  // Base query — always restrict to available listings.
  let query: FirebaseFirestore.Query = db
    .collection(LISTINGS_COLLECTION)
    .where("status", "==", "available");

  // Category filter (equality) — narrows the pool by ~⅔ when set.
  if (overrides.category !== null) {
    query = query.where("category", "==", overrides.category);
  }

  // Price ceiling (range filter) — from user's profile budget preference.
  // Requires composite index: (status ASC, pricePerDay ASC) and
  // (category ASC, status ASC, pricePerDay ASC) — see firestore.indexes.json.
  if (overrides.maxPricePerDay !== null) {
    query = query.where("pricePerDay", "<=", overrides.maxPricePerDay);
  }

  const snapshot = await query.limit(MAX_LISTINGS_TO_SCORE).get();

  return snapshot.docs.map((doc) => {
    const d = doc.data();
    return {
      id: doc.id,
      title: typeof d.title === "string" ? d.title : "",
      description: typeof d.description === "string" ? d.description : "",
      category: typeof d.category === "string" ? d.category : "",
      pricePerDay: typeof d.pricePerDay === "number" ? d.pricePerDay : 0,
      imageUrl: typeof d.imageUrl === "string" ? d.imageUrl : "",
    };
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Relevance scoring
//
// Point weights (tunable):
//   occasion match         → 6 pts  (most specific, rarest signal)
//   style match            → 5 pts
//   color match            → 5 pts
//   per specific feature   → 3 pts  (additive)
//   profile size match     → 4 pts  (personalisation boost)
// ─────────────────────────────────────────────────────────────────────────────

function scoreListing(
  listing: ListingDoc,
  attrs: ParsedAttributes,
  overrides: QueryOverrides
): number {
  const haystack = `${listing.title} ${listing.description}`.toLowerCase();
  let score = 0;

  if (attrs.occasion && haystack.includes(attrs.occasion.toLowerCase()))
    score += 6;
  if (attrs.style && haystack.includes(attrs.style.toLowerCase())) score += 5;
  if (attrs.color && haystack.includes(attrs.color.toLowerCase())) score += 5;

  for (const feature of attrs.specific_features) {
    if (feature && haystack.includes(feature.toLowerCase())) score += 3;
  }

  // Personalisation boost — reward listings that mention the user's saved size.
  if (
    overrides.preferredSize &&
    haystack.includes(overrides.preferredSize.toLowerCase())
  ) {
    score += 4;
  }

  return score;
}

// ─────────────────────────────────────────────────────────────────────────────
// processVoiceSearch — HTTPS Callable Function
//
// Flow:
//   1.  Authenticate the caller.
//   2.  Validate input.
//   3.  Run Gemini extraction + user profile fetch IN PARALLEL.
//   4a. Gemini flagged vague query → return clarification_needed immediately.
//   4b. Merge AI attributes with profile overrides.
//   5.  Query Firestore (with category + price filters).
//   6.  Score, rank, and return results with a conversational response
//       written in the user's detected language.
// ─────────────────────────────────────────────────────────────────────────────

export const processVoiceSearch = onCall<{ transcribed_text: string }>(
  {
    timeoutSeconds: 30,
    memory: "256MiB",
    region: "us-central1",
  },
  async (request): Promise<VoiceSearchResponse> => {
    // ── 1. Authentication guard ──────────────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to use voice search."
      );
    }

    const callerUid = request.auth.uid;

    // ── 2. Input validation ──────────────────────────────────────────────────
    const { transcribed_text } = request.data;

    if (
      typeof transcribed_text !== "string" ||
      transcribed_text.trim().length === 0
    ) {
      throw new HttpsError(
        "invalid-argument",
        "`transcribed_text` must be a non-empty string."
      );
    }
    if (transcribed_text.trim().length > 500) {
      throw new HttpsError(
        "invalid-argument",
        "`transcribed_text` must be 500 characters or fewer."
      );
    }

    const trimmedText = transcribed_text.trim();

    // ── 3. Parallel: Gemini extraction + user profile fetch ──────────────────
    // Both are independent I/O operations — running them concurrently saves
    // ~200-400 ms compared to sequential awaits.
    let envelope: LLMEnvelope;
    let userProfile: UserProfile | null;

    try {
      [envelope, userProfile] = await Promise.all([
        extractAttributesWithGemini(trimmedText),
        fetchUserProfile(callerUid),
      ]);
    } catch (err) {
      // Only Gemini errors are fatal here; fetchUserProfile handles its own
      // errors and returns null gracefully.
      console.error(
        `[processVoiceSearch] Gemini extraction failed for user ${callerUid}:`,
        err
      );
      throw new HttpsError(
        "internal",
        "Could not analyse your search request. Please try again."
      );
    }

    // ── 4a. Vague query — return clarification question in user's language ───
    if (envelope.needs_clarification) {
      console.log(
        `[processVoiceSearch] Vague query (lang: ${envelope.detected_language}) ` +
          `from user ${callerUid}: "${trimmedText}"`
      );
      return {
        type: "clarification_needed",
        question: envelope.clarification_question,
        detected_language: envelope.detected_language,
      };
    }

    const {
      attributes,
      detected_language,
      response_template,
      no_results_response,
    } = envelope;

    console.log(
      `[processVoiceSearch] lang=${detected_language}, attrs=`,
      JSON.stringify(attributes),
      `, profile=`,
      JSON.stringify(userProfile)
    );

    // ── 4b. Merge AI attributes with profile overrides ───────────────────────
    const overrides = buildQueryOverrides(attributes, userProfile);

    console.log(
      `[processVoiceSearch] Resolved overrides for user ${callerUid}:`,
      JSON.stringify(overrides)
    );

    // ── 5. Firestore query ───────────────────────────────────────────────────
    let listings: ListingDoc[];
    try {
      listings = await queryListings(overrides);
    } catch (err) {
      console.error(
        `[processVoiceSearch] Firestore query failed for user ${callerUid}:`,
        err
      );
      throw new HttpsError(
        "internal",
        "Failed to search listings. Please try again."
      );
    }

    // ── 5a. Truly empty — no listings match even the Firestore filters ───────
    if (listings.length === 0) {
      return {
        type: "no_results",
        attributes,
        conversational_response: no_results_response,
        detected_language,
      };
    }

    // ── 6. Score and rank ────────────────────────────────────────────────────
    const hasAnyTextAttributes =
      attributes.style !== null ||
      attributes.color !== null ||
      attributes.occasion !== null ||
      attributes.specific_features.length > 0;

    const scored = listings.map((l) => ({
      id: l.id,
      title: l.title,
      category: l.category,
      pricePerDay: l.pricePerDay,
      imageUrl: l.imageUrl,
      score: hasAnyTextAttributes ? scoreListing(l, attributes, overrides) : 1,
    }));

    const anyMatched = scored.some((r) => r.score > 0);

    // ── 6a. Nothing scored > 0 → return a honest fallback (up to 10 items) ───
    // The response uses no_results_response instead of response_template to
    // be transparent: "No exact match, but here are some available items."
    if (hasAnyTextAttributes && !anyMatched) {
      const fallback = scored.slice(0, 10);
      console.log(
        `[processVoiceSearch] No attribute matches for user ${callerUid}. ` +
          `Returning ${fallback.length} unscored fallback listings.`
      );
      return {
        type: "results",
        listings: fallback,
        attributes,
        conversational_response: no_results_response,
        detected_language,
      };
    }

    // ── 6b. Sort: score desc, tie-break by pricePerDay asc ──────────────────
    scored.sort((a, b) => b.score - a.score || a.pricePerDay - b.pricePerDay);
    const topResults = scored.slice(0, MAX_RESULTS);

    const conversational_response = response_template.replace(
      "{count}",
      String(topResults.length)
    );

    console.log(
      `[processVoiceSearch] Returning ${topResults.length} results ` +
        `(top score: ${topResults[0]?.score ?? 0}) for user ${callerUid}. ` +
        `Response: "${conversational_response}"`
    );

    return {
      type: "results",
      listings: topResults,
      attributes,
      conversational_response,
      detected_language,
    };
  }
);
