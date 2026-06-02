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
  const [examStarted, setExamStarted] = useState(false);
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

  // Load exam data
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

  // Keyboard shortcuts: A/B/C/D to select options, ←/→ to navigate
  useEffect(() => {
    if (!examStarted || !examData?.questions?.length) return;
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
  }, [examStarted, examData, currentIndex, handleSelectOption, handleNavigate]);

  if (!examStarted) {
    const template = examData?.template;
    const qCount = examData?.questions?.length || 0;
    const dataReady = !loading && examData?.questions?.length > 0;

    const enterExam = (goFullscreen) => {
      if (goFullscreen) {
        const el = document.documentElement;
        if (el.requestFullscreen && !document.fullscreenElement) {
          el.requestFullscreen().catch(() => {});
        }
      }
      setExamStarted(true);
    };

    return (
      <div>
        {/* Modal overlay — shows immediately, buttons enable when data ready */}
        <div
          style={{
            position: 'fixed', inset: 0, zIndex: 9999,
            background: 'rgba(0,0,0,0.6)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            padding: isMobile ? '12px' : '0',
          }}
        >
          <div
            class="crayons-card"
            style={{
              maxWidth: '560px', width: '100%',
              maxHeight: isMobile ? '95dvh' : '90vh',
              overflowY: 'auto',
              padding: isMobile ? '16px' : '24px',
            }}
          >
            <h2 class={isMobile ? 'fw-bold fs-xl mb-3' : 'crayons-title mb-4'}>
              {template?.title || 'Mock Exam'}
            </h2>

            {/* Exam info grid */}
            <div
              class="grid gap-2 mb-4"
              style={{ gridTemplateColumns: '1fr 1fr' }}
            >
              <div class="p-3 radius-default" style={{ background: 'var(--card-secondary-bg)' }}>
                <div class="fs-xs color-secondary">Questions</div>
                <div class="fw-bold fs-l">{loading ? '...' : qCount}</div>
              </div>
              <div class="p-3 radius-default" style={{ background: 'var(--card-secondary-bg)' }}>
                <div class="fs-xs color-secondary">Duration</div>
                <div class="fw-bold fs-l">{template?.duration_minutes || '...'} min</div>
              </div>
              <div class="p-3 radius-default" style={{ background: 'var(--card-secondary-bg)' }}>
                <div class="fs-xs color-secondary">Marks/Correct</div>
                <div class="fw-bold fs-l">{template ? `+${template.marks_per_correct}` : '...'}</div>
              </div>
              <div class="p-3 radius-default" style={{ background: 'var(--card-secondary-bg)' }}>
                <div class="fs-xs color-secondary">Negative</div>
                <div class="fw-bold fs-l">{template ? `-${template.negative_marks_per_wrong}` : '...'}</div>
              </div>
            </div>

            {/* Instructions */}
            <div class="mb-4 p-3 radius-default" style={{ background: 'var(--card-secondary-bg)' }}>
              <h4 class="fw-bold mb-2">Instructions</h4>
              <ul style={{ paddingLeft: '18px', lineHeight: '1.7', fontSize: isMobile ? '0.85rem' : 'inherit' }}>
                <li>Complete all questions within the time limit.</li>
                <li>Each correct answer earns marks. Wrong answers may deduct marks.</li>
                <li>Navigate between questions using the question palette.</li>
                <li>Mark questions for review and come back later.</li>
                <li>Use <strong>Clear</strong> to unselect an answer.</li>
                <li>Switch between <strong>English</strong> and <strong>Hindi</strong> anytime.</li>
                <li>The exam auto-submits when the timer runs out.</li>
              </ul>
            </div>

            <div class="flex gap-3" style={{ flexDirection: isMobile && !canFullscreen ? 'column' : 'row' }}>
              {canFullscreen && (
                <button
                  class="c-btn c-btn--primary"
                  onClick={() => enterExam(true)}
                  disabled={!dataReady}
                  style={{ flex: 1, padding: '12px 16px', minHeight: '48px' }}
                >
                  {dataReady ? 'Full Screen Mode' : 'Loading...'}
                </button>
              )}
              <button
                class={canFullscreen ? 'c-btn c-btn--secondary' : 'c-btn c-btn--primary'}
                onClick={() => enterExam(false)}
                disabled={!dataReady}
                style={{ flex: 1, padding: '12px 16px', minHeight: '48px' }}
              >
                {!dataReady ? 'Loading...' : canFullscreen ? 'Window Mode' : 'Start Exam'}
              </button>
            </div>

            {canFullscreen && (
              <p class="color-secondary fs-xs mt-3 text-center">
                You can switch between modes anytime during the exam.
              </p>
            )}
          </div>
        </div>
      </div>
    );
  }

  if (!examData || !examData.questions?.length) {
    return (
      <div class="crayons-card p-6">
        <h2 class="crayons-title mb-2">Preparing Your Exam</h2>
        <p class="color-secondary">
          Questions are being generated. Please refresh in a moment...
        </p>
        <button class="c-btn c-btn--secondary mt-4" onClick={() => window.location.reload()}>
          Refresh
        </button>
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
      {/* Top bar — compact, flush to top */}
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
        {/* Row 1: title + timer + progress */}
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

        {/* Row 2: toolbar buttons — both mobile and desktop */}
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

      {/* Progress strip */}
      <div style={{ height: '3px', background: 'var(--card-secondary-bg)', width: '100%', flexShrink: 0 }}>
        <div style={{
          height: '100%',
          background: 'var(--accent-brand)',
          width: `${questions.length > 0 ? Math.round((answeredCount / questions.length) * 100) : 0}%`,
          transition: 'width 0.4s ease',
          borderRadius: '0 2px 2px 0',
        }} />
      </div>

      {/* Main content area */}
      <div style={{ display: 'flex', flex: 1, overflow: 'hidden', position: 'relative' }}>
        {/* Question area — scrollable */}
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

        {/* Desktop Sidebar — hidden on mobile */}
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
