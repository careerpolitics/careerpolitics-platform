import { h } from 'preact';
import { KatexText, KatexHtml, hasMath } from './KatexRenderer';
import { useQuestionTranslation } from '../useQuestionTranslation';

export function QuestionDisplay({
                                  question,
                                  selectedOption,
                                  onSelectOption,
                                  isReview,
                                  language,
                                  questionNumber,
                                  totalQuestions,
                                }) {
  const q = question;
  const wantsHindi = language === 'hi';
  // Resolves Hindi text from pre-translated columns, then machine translation,
  // then the original English (with usedFallback set so we can show a notice).
  const {
    questionText,
    options,
    explanation,
    usedFallback,
  } = useQuestionTranslation(q, language, isReview);

  // Raw HTML is only safe for the English source; translated text comes back as
  // plain strings, so render it through KatexText instead.
  const showQuestionHtml = !wantsHindi && q.question_html && !hasMath(q.question_text);
  const showExplanationHtml = !wantsHindi && q.explanation_html && !hasMath(explanation);

  return (
    <div class="crayons-card p-6">
      {/* Question header */}
      <div class="flex items-center justify-between mb-3">
        <div class="flex items-center gap-2">
          <span class="fw-bold" style={{
            background: 'var(--accent-brand)', color: '#fff',
            padding: '3px 12px', borderRadius: '6px',
            fontSize: '0.8rem', letterSpacing: '0.02em',
          }}>
            Q. {questionNumber || q.position}
          </span>
          <span class="crayons-tag crayons-tag--monochrome fs-xs">
            {q.section_name}
          </span>
        </div>
        {totalQuestions > 0 && (
          <span class="fs-xs color-secondary" style={{
            background: 'var(--card-secondary-bg)',
            padding: '2px 8px', borderRadius: '4px',
          }}>
            {questionNumber || q.position} of {totalQuestions}
          </span>
        )}
      </div>

      {/* Question text */}
      <div class="mb-4 fs-l" style={{ lineHeight: '1.6' }}>
        {showQuestionHtml ? (
          <div dangerouslySetInnerHTML={{ __html: q.question_html }} />
        ) : (
          <KatexText text={questionText} />
        )}
      </div>

      {/* Translation fallback notice — shown when on-demand translation failed
          and we are displaying the original English instead of a blank. */}
      {usedFallback && (
        <p class="fs-xs color-secondary mb-3" role="status">
          Translation unavailable — showing the original English.
        </p>
      )}

      {/* Question SVG (visual reasoning) */}
      {q.question_svg && (
        <div
          class="mb-4 flex justify-center"
          dangerouslySetInnerHTML={{ __html: q.question_svg }}
          style={{ maxWidth: '300px', margin: '0 auto' }}
        />
      )}

      {/* Options */}
      <div class="flex flex-col gap-2">
        {(options || []).map((opt) => {
          const optText = opt.displayText;
          const isSelected = selectedOption === opt.key;
          const isCorrect = isReview && opt.key === q.correct_option_key;
          const isWrong = isReview && isSelected && !isCorrect;

          let borderColor = 'var(--card-border)';
          let bgColor = 'transparent';
          if (isReview) {
            if (isCorrect) {
              borderColor = 'var(--accent-success)';
              bgColor = 'rgba(0,128,0,0.05)';
            } else if (isWrong) {
              borderColor = 'var(--accent-danger)';
              bgColor = 'rgba(255,0,0,0.05)';
            }
          } else if (isSelected) {
            borderColor = 'var(--accent-brand)';
            bgColor = 'var(--accent-brand-a10)';
          }

          return (
            <button
              key={opt.key}
              class="p-3 radius-default flex items-start gap-3 text-left"
              style={{
                border: `2px solid ${borderColor}`,
                background: bgColor,
                cursor: isReview ? 'default' : 'pointer',
                width: '100%',
                minHeight: '48px',
                transition: 'all 0.15s ease',
                position: 'relative',
              }}
              onMouseEnter={(e) => { if (!isReview) e.currentTarget.style.transform = 'translateX(2px)'; }}
              onMouseLeave={(e) => { e.currentTarget.style.transform = 'none'; }}
              onClick={() => !isReview && onSelectOption(opt.key)}
              disabled={isReview}
            >
              <span
                class="fw-bold flex-shrink-0"
                style={{
                  width: '28px',
                  height: '28px',
                  borderRadius: '50%',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  background: isSelected ? 'var(--accent-brand)' : 'var(--card-secondary-bg)',
                  color: isSelected ? 'white' : 'inherit',
                  fontSize: '0.85rem',
                }}
              >
                {opt.key}
              </span>
              <div style={{ flex: 1 }}>
                {opt.svg ? (
                  <div class="flex items-center gap-3">
                    <div
                      dangerouslySetInnerHTML={{ __html: opt.svg }}
                      style={{ maxWidth: '100px', maxHeight: '100px' }}
                    />
                    {optText && <KatexText text={optText} />}
                  </div>
                ) : hasMath(optText) ? (
                  <KatexText text={optText} />
                ) : (
                  <span>{optText}</span>
                )}
              </div>
              {isReview && isCorrect && (
                <span style={{ color: 'var(--accent-success)', fontSize: '1.2rem' }}>✓</span>
              )}
              {isReview && isWrong && (
                <span style={{ color: 'var(--accent-danger)', fontSize: '1.2rem' }}>✗</span>
              )}
            </button>
          );
        })}
      </div>

      {/* Explanation (review mode) */}
      {isReview && explanation && (
        <div
          class="mt-4 p-4 radius-default"
          style={{ background: 'var(--card-secondary-bg)' }}
        >
          <h4 class="fw-bold mb-2">Explanation</h4>
          {showExplanationHtml ? (
            <div dangerouslySetInnerHTML={{ __html: q.explanation_html }} />
          ) : (
            <KatexText text={explanation} />
          )}
        </div>
      )}

      {/* Solution steps (review mode, maths) */}
      {isReview && q.solution_steps && (
        <div
          class="mt-3 p-4 radius-default"
          style={{ background: 'var(--card-secondary-bg)' }}
        >
          <h4 class="fw-bold mb-2">Solution Steps</h4>
          {q.solution_steps_html && !hasMath(q.solution_steps) ? (
            <div dangerouslySetInnerHTML={{ __html: q.solution_steps_html }} />
          ) : (
            <KatexText text={q.solution_steps} />
          )}
        </div>
      )}
    </div>
  );
}
