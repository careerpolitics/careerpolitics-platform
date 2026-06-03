/**
 * Free, keyless client-side translation for mock-exam question text.
 *
 * Uses the unofficial Google Translate "gtx" endpoint, which requires no API
 * key and incurs no cost to us because the request is made directly from the
 * learner's browser. This is intentionally NOT the paid Google Cloud
 * Translation API.
 *
 * Caveats (the endpoint is unofficial):
 *   - It can be rate-limited or change/break without notice.
 *   - We therefore (a) cache aggressively in-memory, (b) prefer server-side
 *     pre-translated columns (text_hi etc.) whenever present, and (c) fall back
 *     to the original text on any failure so the learner never sees a blank.
 */

const ENDPOINT = 'https://translate.googleapis.com/translate_a/single';

// Module-level cache shared across every QuestionDisplay instance for the life
// of the page. Keyed by `${targetLang}::${sourceText}` so repeated toggles
// between English and Hindi never re-fetch the same string.
const cache = new Map();

const cacheKey = (text, targetLang) => `${targetLang}::${text}`;

/**
 * Parse the gtx response shape into a single string.
 * The endpoint returns: [[["translated","original",...], ...], ...]
 * We concatenate every sentence segment in the first array.
 */
function parseGtxResponse(payload) {
  if (!Array.isArray(payload) || !Array.isArray(payload[0])) {
    return null;
  }
  const segments = payload[0]
    .filter((segment) => Array.isArray(segment) && typeof segment[0] === 'string')
    .map((segment) => segment[0]);

  if (segments.length === 0) {
    return null;
  }
  return segments.join('');
}

/**
 * Translate a single piece of text to `targetLang` (default Hindi).
 *
 * Resolves to the translated string on success, or the original `text` on any
 * failure (network error, rate limit, unexpected shape). Never rejects, so
 * callers can render the result unconditionally.
 *
 * @param {string} text       Source text (assumed English).
 * @param {string} targetLang BCP-47 target code, e.g. 'hi'.
 * @returns {Promise<{ text: string, translated: boolean }>}
 */
export async function translateText(text, targetLang = 'hi') {
  if (!text || typeof text !== 'string' || !text.trim()) {
    return { text, translated: false };
  }

  const key = cacheKey(text, targetLang);
  if (cache.has(key)) {
    return cache.get(key);
  }

  const params = new URLSearchParams({
    client: 'gtx',
    sl: 'en',
    tl: targetLang,
    dt: 't',
    q: text,
  });

  try {
    const response = await fetch(`${ENDPOINT}?${params.toString()}`, {
      method: 'GET',
    });
    if (!response.ok) {
      throw new Error(`Translate endpoint responded ${response.status}`);
    }
    const payload = await response.json();
    const translated = parseGtxResponse(payload);
    if (!translated) {
      throw new Error('Unrecognised translate response shape');
    }
    const result = { text: translated, translated: true };
    cache.set(key, result);
    return result;
  } catch (error) {
    // Graceful fallback: surface the original text and let the caller show a
    // small notice. We do NOT cache failures so a transient error can be
    // retried on the next toggle.
    return { text, translated: false };
  }
}

/** Test-only helper to reset the shared cache between specs. */
export function __clearTranslationCache() {
  cache.clear();
}
