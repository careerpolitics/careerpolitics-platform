import { h } from 'preact';
import { useState, useEffect, useCallback, useRef } from 'preact/hooks';
import { request } from '@utilities/http';
import { ExamTimer } from './components/ExamTimer';
import { QuestionDisplay } from './components/QuestionDisplay';
import { QuestionPalette } from './components/QuestionPalette';
import { ExamCalculator } from './components/ExamCalculator';
import { ExamScratchpad } from './components/ExamScratchpad';

const STORAGE_KEY_PREFIX = 'mock_exam_responses_';

export function MockExamInterface({ slug, attemptId }) {
  const [examData, setExamData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [responses, setResponses] = useState({});
  const [submitting, setSubmitting] = useState(false);
  const [showCalculator, setShowCalculator] = useState(false);
  const [showScratchpad, setShowScratchpad] = useState(false);
  const [language, setLanguage] = useState('en');
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [showPalette, setShowPalette] = useState(false);
  const [isMobile, setIsMobile] = useState(false);
  const timePerQuestion = useRef({});
  const questionStartTime = useRef(Date.now());

  // Detect mobile viewport
  useEffect(() => {
    const mq = window.matchMedia('(max-width: 768px)');
    setIsMobile(mq.matches);
    const handler = (e) => setIsMobile(e.matches);
    mq.addEventListener('change', handler);
    return () => mq.removeEventListener('change', handler);
  }, []);

  // Load exam data + auto-fullscreen from URL param
  useEffect(() => {
    request(`/mock_exams/${slug}/attempts/${attemptId}.json`)
      .then((res) => res.json())
      .then((data) => {
        setExamData(data);
        const serverResponses = data.responses || {};
        const storedStr = localStorage.getItem(`${STORAGE_KEY_PREFIX}${attemptId}`);
        const storedResponses = storedStr ? JSON.parse(storedStr) : {};
        const merged = { ...storedResponses };
        Object.entries(serverResponses).forEach(([qId, resp]) => {
          merged[qId] = { ...merged[qId], ...resp };
        });
        setResponses(merged);
        setLoading(false);

        // Auto-enter fullscreen if requested from detail page
        const params = new URLSearchParams(window.location.search);
        if (params.get('mode') === 'fullscreen') {
          const el = document.documentElement;
          if (el.requestFullscreen && !document.fullscreenElement) {
            el.requestFullscreen().catch(() => {});
          }
        }
      })
      .catch(() => setLoading(false));
  }, [slug, attemptId]);

  // Persist responses to localStorage
  useEffect(() => {
    if (Object.keys(responses).length > 0) {
      try {
        localStorage.setItem(`${STORAGE_KEY_PREFIX}${attemptId}`, JSON.stringify(responses));
      } catch {
        // quota exceeded
      }
    }
  }, [responses, attemptId]);

  // Track time on current question
  useEffect(() => {
    questionStartTime.current = Date.now();
  }, [currentIndex]);

  // Track fullscreen state changes
  useEffect(() => {
    const handleFsChange = () => setIsFullscreen(!!document.fullscreenElement);
    document.addEventListener('fullscreenchange', handleFsChange);
    return () => {
      document.removeEventListener('fullscreenchange', handleFsChange);
      if (document.fullscreenElement) {
        document.exitFullscreen().catch(() => {});
      }
    };
  }, []);

  const canFullscreen = typeof document.documentElement.requestFullscreen === 'function';

  const toggleFullscreen = useCallback(() => {
    if (document.fullscreenElement) {
      document.exitFullscreen().catch(() => {});
    } else {
      document.documentElement.requestFullscreen().catch(() => {});
    }
  }, []);

  const recordTimeOnQuestion = useCallback(() => {
    if (!examData) return;
    const q = examData.questions[currentIndex];
    if (!q) return;
    const elapsed = Math.round((Date.now() - questionStartTime.current) / 1000);
    const prev = timePerQuestion.current[q.id] || 0;
    timePerQuestion.current[q.id] = prev + elapsed;
    questionStartTime.current = Date.now();
  }, [currentIndex, examData]);

  const saveResponse = useCallback(
    async (questionId, data) => {
      const resp = responses[questionId];
      const payload = {
        mock_exam_response: {
          selected_option_key: data.selected_option_key,
          marked_for_review: data.marked_for_review || false,
          time_spent_seconds: timePerQuestion.current[questionId] || 0,
        },
      };

      try {
        if (resp?.id) {
          await request(`/mock_exam_responses/${resp.id}`, {
            method: 'PATCH',
            body: JSON.stringify(payload),
            headers: { 'Content-Type': 'application/json' },
          });
        } else {
          const res = await request('/mock_exam_responses', {
            method: 'POST',
            body: JSON.stringify({
              mock_exam_attempt_id: attemptId,
              mock_exam_question_id: questionId,
              ...payload,
            }),
            headers: { 'Content-Type': 'application/json' },
          });
          const saved = await res.json();
          setResponses((prev) => ({
            ...prev,
            [questionId]: { ...prev[questionId], id: saved.id },
          }));
        }
      } catch {
        // will retry on next interaction
      }
    },
    [responses, attemptId],
  );

  const handleSelectOption = useCallback(
    (questionId, optionKey) => {
      recordTimeOnQuestion();
      setResponses((prev) => {
        const updated = {
          ...prev,
          [questionId]: {
            ...prev[questionId],
            selected_option_key: optionKey,
          },
        };
        saveResponse(questionId, updated[questionId]);
        return updated;
      });
    },
    [recordTimeOnQuestion, saveResponse],
  );

  const handleMarkForReview = useCallback(
    (questionId) => {
      setResponses((prev) => {
        const current = prev[questionId] || {};
        const updated = {
          ...prev,
          [questionId]: {
            ...current,
            marked_for_review: !current.marked_for_review,
          },
        };
        saveResponse(questionId, updated[questionId]);
        return updated;
      });
    },
    [saveResponse],
  );

  const handleClearResponse = useCallback(
    (questionId) => {
      setResponses((prev) => {
        const updated = {
          ...prev,
          [questionId]: {
            ...prev[questionId],
            selected_option_key: null,
          },
        };
        saveResponse(questionId, updated[questionId]);
        return updated;
      });
    },
    [saveResponse],
  );

  const handleSubmit = useCallback(async () => {
    if (submitting) return;

    const confirmed = window.confirm(
      'Are you sure you want to submit? You cannot change answers after submission.',
    );
    if (!confirmed) return;

    setSubmitting(true);
    recordTimeOnQuestion();

    try {
      const res = await request(`/mock_exams/${slug}/attempts/${attemptId}/submit`, {
        method: 'PATCH',
        body: JSON.stringify({ time_per_question: timePerQuestion.current }),
        headers: { 'Content-Type': 'application/json' },
      });
      const data = await res.json();
      localStorage.removeItem(`${STORAGE_KEY_PREFIX}${attemptId}`);
      localStorage.removeItem(`mock_exam_scratchpad_${attemptId}`);
      window.location.href = data.redirect_to;
    } catch {
      setSubmitting(false);
      alert('Failed to submit. Please try again.');
    }
  }, [slug, attemptId, submitting, recordTimeOnQuestion]);

  const handleTimeUp = useCallback(() => {
    handleSubmit();
  }, [handleSubmit]);

  const handleNavigate = useCallback(
    (index) => {
      recordTimeOnQuestion();
      setCurrentIndex(index);
    },
    [recordTimeOnQuestion],
  );

  // Keyboard shortcuts: A/B/C/D to select options, arrow keys to navigate
  useEffect(() => {
    if (!examData?.questions?.length) return;
    const handler = (e) => {
      if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
      const key = e.key.toUpperCase();
      const q = examData.questions[currentIndex];
      if (!q) return;
      const optionKeys = (q.options || []).map((o) => o.key);
      if (optionKeys.includes(key)) {
        e.preventDefault();
        handleSelectOption(q.id, key);
      } else if (e.key === 'ArrowLeft' && currentIndex > 0) {
        e.preventDefault();
        handleNavigate(currentIndex - 1);
      } else if (e.key === 'ArrowRight' && currentIndex < examData.questions.length - 1) {
        e.preventDefault();
        handleNavigate(currentIndex + 1);
      }
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [examData, currentIndex, handleSelectOption, handleNavigate]);

  if (loading || !examData || !examData.questions?.length) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '100vh', gap: '16px' }}>
        <div class="crayons-loading" style={{ width: '48px', height: '48px' }} aria-label="Loading exam..." />
        <p class="color-secondary fs-l">Loading your exam...</p>
      </div>
    );
  }

  const questions = examData.questions;
  const currentQuestion = questions[currentIndex];
  const currentResponse = responses[currentQuestion.id] || {};
  const template = examData.template;

  const answeredCount = questions.filter(
    (q) => responses[q.id]?.selected_option_key,
  ).length;

  const viewHeight = isMobile ? '100dvh' : '100vh';

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: viewHeight, overflow: 'hidden', margin: 0, padding: 0 }}>
      {/* Top bar */}
      <div
        style={{
          display: 'flex', flexWrap: 'wrap', alignItems: 'center',
          justifyContent: 'space-between', gap: '2px',
          padding: isMobile ? '4px 8px' : '4px 16px',
          background: 'var(--card-bg)',
          borderBottom: '1px solid var(--card-border)',
          flexShrink: 0,
          margin: 0,
        }}
      >
        <div class="fw-bold" style={{
          fontSize: isMobile ? '0.75rem' : '0.85rem',
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          maxWidth: isMobile ? '45%' : '280px',
        }}>
          {template.title}
        </div>
        <div class="flex items-center gap-3">
          <div class="flex items-center gap-1" style={{
            background: 'var(--card-secondary-bg)',
            padding: '2px 10px', borderRadius: '12px',
          }}>
            <span style={{ fontSize: '0.75rem' }}>⏱</span>
            <ExamTimer
              timeRemainingSeconds={examData.time_remaining_seconds}
              onTimeUp={handleTimeUp}
            />
          </div>
          <div class="flex items-center gap-1" style={{
            background: 'var(--card-secondary-bg)',
            padding: '2px 10px', borderRadius: '12px',
          }}>
            <span class="fs-xs color-secondary">Progress</span>
            <span class="fw-bold fs-s">
              {answeredCount}<span class="color-secondary fw-normal">/{questions.length}</span>
            </span>
          </div>
        </div>

        {/* Toolbar buttons */}
        <div class="flex items-center gap-1" style={{ width: isMobile ? '100%' : 'auto', justifyContent: 'flex-end' }}>
          {template.has_calculator && (
            <button
              class={`c-btn c-btn--s ${showCalculator ? 'c-btn--primary' : 'c-btn--secondary'}`}
              onClick={() => setShowCalculator(!showCalculator)}
              title="Calculator"
              style={{ padding: '3px 7px', minHeight: '30px', fontSize: '0.8rem' }}
            >
              🖩
            </button>
          )}
          {template.has_scratchpad && (
            <button
              class={`c-btn c-btn--s ${showScratchpad ? 'c-btn--primary' : 'c-btn--secondary'}`}
              onClick={() => setShowScratchpad(!showScratchpad)}
              title="Scratchpad"
              style={{ padding: '3px 7px', minHeight: '30px', fontSize: '0.8rem' }}
            >
              📝
            </button>
          )}
          <button
            class="c-btn c-btn--s c-btn--secondary"
            onClick={() => setLanguage(language === 'en' ? 'hi' : 'en')}
            style={{ padding: '3px 7px', minHeight: '30px', fontSize: '0.8rem' }}
          >
            {language === 'en' ? 'हि' : 'EN'}
          </button>
          {canFullscreen && (
            <button
              class="c-btn c-btn--s c-btn--secondary"
              onClick={toggleFullscreen}
              title={isFullscreen ? 'Exit fullscreen' : 'Enter fullscreen'}
              style={{ padding: '3px 7px', minHeight: '30px', fontSize: '0.8rem' }}
            >
              {isFullscreen ? '⊡' : '⊞'}
            </button>
          )}
          {isMobile && (
            <button
              class={`c-btn c-btn--s ${showPalette ? 'c-btn--primary' : 'c-btn--secondary'}`}
              onClick={() => setShowPalette(!showPalette)}
              style={{ padding: '3px 7px', minHeight: '30px', fontSize: '0.8rem' }}
            >
              ≡ Q
            </button>
          )}
          <button
            class="c-btn c-btn--s c-btn--destructive"
            onClick={handleSubmit}
            disabled={submitting}
            style={{ padding: '3px 10px', minHeight: '30px', fontSize: '0.8rem', marginLeft: '4px' }}
          >
            {submitting ? '...' : 'Submit'}
          </button>
        </div>
      </div>

      {/* Main content area */}
      <div style={{ display: 'flex', flex: 1, overflow: 'hidden', position: 'relative' }}>
        {/* Question area */}
        <div style={{
          flex: 1, overflowY: 'auto',
          padding: isMobile ? '10px' : '16px',
          WebkitOverflowScrolling: 'touch',
        }}>
          <QuestionDisplay
            question={currentQuestion}
            selectedOption={currentResponse.selected_option_key}
            onSelectOption={(key) => handleSelectOption(currentQuestion.id, key)}
            isReview={false}
            language={language}
            questionNumber={currentIndex + 1}
            totalQuestions={questions.length}
          />

          {/* Question navigation */}
          <div
            class="flex items-center justify-between mt-3"
            style={{ gap: '8px', paddingTop: '12px', borderTop: '1px solid var(--card-border)' }}
          >
            <div class="flex gap-2">
              <button
                class="c-btn c-btn--secondary"
                onClick={() => handleNavigate(Math.max(0, currentIndex - 1))}
                disabled={currentIndex === 0}
                style={{ minHeight: '40px' }}
              >
                ← Prev
              </button>
              <button
                class="c-btn c-btn--secondary"
                onClick={() =>
                  handleNavigate(Math.min(questions.length - 1, currentIndex + 1))
                }
                disabled={currentIndex >= questions.length - 1}
                style={{ minHeight: '40px' }}
              >
                Next →
              </button>
            </div>

            <div class="flex gap-2">
              <button
                class="c-btn c-btn--secondary c-btn--s"
                onClick={() => handleClearResponse(currentQuestion.id)}
                style={{ minHeight: '40px' }}
              >
                Clear
              </button>
              <button
                class={`c-btn c-btn--s ${
                  currentResponse.marked_for_review
                    ? 'c-btn--primary'
                    : 'c-btn--secondary'
                }`}
                onClick={() => handleMarkForReview(currentQuestion.id)}
                style={{ minHeight: '40px' }}
              >
                {currentResponse.marked_for_review ? '★ Marked' : '☆ Review'}
              </button>
            </div>
          </div>

        </div>

        {/* Desktop Sidebar */}
        {!isMobile && (
          <div
            style={{
              width: '240px',
              flexShrink: 0,
              borderLeft: '1px solid var(--card-border)',
              overflowY: 'auto',
              padding: '12px',
              background: 'var(--card-bg)',
            }}
          >
            <QuestionPalette
              questions={questions}
              responses={responses}
              currentIndex={currentIndex}
              onNavigate={handleNavigate}
            />
          </div>
        )}

        {/* Mobile bottom-sheet palette */}
        {isMobile && showPalette && (
          <div
            style={{
              position: 'absolute', bottom: 0, left: 0, right: 0,
              maxHeight: '60dvh',
              background: 'var(--card-bg)',
              borderTop: '2px solid var(--card-border)',
              borderRadius: '16px 16px 0 0',
              overflowY: 'auto',
              padding: '16px',
              zIndex: 100,
              boxShadow: '0 -4px 20px rgba(0,0,0,0.15)',
              WebkitOverflowScrolling: 'touch',
            }}
          >
            <div class="flex items-center justify-between mb-3">
              <h4 class="fw-bold fs-s">Question Palette</h4>
              <button
                class="c-btn c-btn--s c-btn--secondary"
                onClick={() => setShowPalette(false)}
                style={{ minHeight: '36px' }}
              >
                Close
              </button>
            </div>
            <QuestionPalette
              questions={questions}
              responses={responses}
              currentIndex={currentIndex}
              onNavigate={(i) => { handleNavigate(i); setShowPalette(false); }}
            />
          </div>
        )}

        {/* Overlay behind bottom-sheet */}
        {isMobile && showPalette && (
          <div
            onClick={() => setShowPalette(false)}
            style={{
              position: 'absolute', inset: 0,
              background: 'rgba(0,0,0,0.3)',
              zIndex: 99,
            }}
          />
        )}
      </div>

      {/* Floating tools */}
      {template.has_calculator && (
        <ExamCalculator visible={showCalculator} onClose={() => setShowCalculator(false)} />
      )}
      {template.has_scratchpad && (
        <ExamScratchpad
          visible={showScratchpad}
          onClose={() => setShowScratchpad(false)}
          attemptId={attemptId}
        />
      )}
    </div>
  );
}
