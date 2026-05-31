import { useState, useEffect } from 'preact/hooks';
import { translateText } from './translateClient';

/**
 * Resolve a mock-exam question's display text for the requested language.
 *
 * Order of preference for each field:
 *   1. Server-side pre-translated column (text_hi / explanation_hi /
 *      option.text_hi) — zero cost, instant, highest quality.
 *   2. On-demand client-side translation via the free gtx endpoint.
 *   3. The original English text (graceful fallback) + a `failed` flag so the
 *      UI can show a small notice.
 *
 * Results are memoised per-question by translateText's module cache, so toggling
 * back and forth between English and Hindi never re-fetches.
 *
 * @param {object} question Mock exam question (snake_case API shape).
 * @param {string} language 'en' or 'hi'.
 * @param {boolean} includeExplanation Whether to also translate the explanation
 *   (only needed in review mode).
 * @returns {{
 *   questionText: string,
 *   options: Array,
 *   explanation: string,
 *   status: 'idle' | 'loading' | 'ready' | 'failed',
 *   usedFallback: boolean,
 * }}
 */
export function useQuestionTranslation(question, language, includeExplanation) {
  const wantsHindi = language === 'hi';

  // English path, or Hindi fully covered by pre-translated columns: no fetch.
  const hasPreTranslatedText = Boolean(question.text_hi);

  const baseline = {
    questionText: wantsHindi && question.text_hi ? question.text_hi : question.question_text,
    options: (question.options || []).map((opt) => ({
      ...opt,
      displayText: wantsHindi && opt.text_hi ? opt.text_hi : opt.text,
    })),
    explanation:
      wantsHindi && question.explanation_hi ? question.explanation_hi : question.explanation,
    status: 'ready',
    usedFallback: false,
  };

  const [resolved, setResolved] = useState(baseline);

  useEffect(() => {
    if (!wantsHindi) {
      setResolved(baseline);
      return undefined;
    }

    // Figure out which fields still need machine translation. SVG/image-only
    // options have no text to translate.
    const needsQuestion = !question.text_hi && Boolean(question.question_text);
    const needsExplanation =
      includeExplanation && !question.explanation_hi && Boolean(question.explanation);
    const optionFetches = (question.options || []).map((opt) =>
      !opt.text_hi && Boolean(opt.text) ? opt.text : null,
    );

    if (!needsQuestion && !needsExplanation && !optionFetches.some(Boolean)) {
      // Everything is pre-translated.
      setResolved({ ...baseline, status: 'ready' });
      return undefined;
    }

    let cancelled = false;
    setResolved((prev) => ({ ...prev, status: 'loading' }));

    const tasks = [
      needsQuestion
        ? translateText(question.question_text, 'hi')
        : Promise.resolve({ text: baseline.questionText, translated: true }),
      needsExplanation
        ? translateText(question.explanation, 'hi')
        : Promise.resolve({ text: baseline.explanation, translated: true }),
      Promise.all(
        optionFetches.map((text, i) =>
          text
            ? translateText(text, 'hi')
            : Promise.resolve({
                text: baseline.options[i] ? baseline.options[i].displayText : '',
                translated: true,
              }),
        ),
      ),
    ];

    Promise.all(tasks)
      .then(([q, expl, opts]) => {
        if (cancelled) return;
        const anyFailed =
          (needsQuestion && !q.translated) ||
          (needsExplanation && !expl.translated) ||
          opts.some((o, i) => optionFetches[i] && !o.translated);

        setResolved({
          questionText: q.text,
          options: baseline.options.map((opt, i) => ({
            ...opt,
            displayText: opts[i] ? opts[i].text : opt.displayText,
          })),
          explanation: expl.text,
          status: anyFailed ? 'failed' : 'ready',
          usedFallback: anyFailed,
        });
      })
      .catch(() => {
        if (cancelled) return;
        // translateText never rejects, but guard anyway.
        setResolved({ ...baseline, status: 'failed', usedFallback: true });
      });

    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [question.id, language, includeExplanation, hasPreTranslatedText]);

  return resolved;
}
