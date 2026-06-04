import { h } from 'preact';

const STATUS_COLORS = {
  not_visited: 'var(--card-secondary-bg)',
  not_answered: 'var(--accent-danger)',
  answered: 'var(--accent-success)',
  review: '#7c3aed',
  answered_review: '#9b59b6',
};

const STATUS_LABELS = {
  answered: 'Answered',
  review: 'For Review',
  not_answered: 'Not Answered',
  not_visited: 'Not Visited',
  answered_review: 'Answered & Marked',
};

function getStatus(question, responses) {
  const resp = responses[question.id];
  if (!resp) return 'not_visited';
  if (resp.marked_for_review && resp.selected_option_key) return 'answered_review';
  if (resp.marked_for_review) return 'review';
  if (resp.selected_option_key) return 'answered';
  return 'not_answered';
}

export function QuestionPalette({ questions, responses, currentIndex, onNavigate, sectionsConfig }) {
  const counts = {};
  questions.forEach((q) => {
    const s = getStatus(q, responses);
    counts[s] = (counts[s] || 0) + 1;
  });

  // Group questions by section
  const sections = [];
  const sectionMap = new Map();

  if (sectionsConfig && sectionsConfig.length > 0) {
    // Build lookup: map both section names and topic names → config section name
    const toSection = new Map();
    sectionsConfig.forEach((sc) => {
      toSection.set(sc.name, sc.name);
      (sc.topics || []).forEach((topic) => toSection.set(topic, sc.name));
    });

    // Initialise sections from config so order is preserved
    sectionsConfig.forEach((sc) => {
      const entry = { name: sc.name, items: [] };
      sectionMap.set(sc.name, entry);
      sections.push(entry);
    });

    // Assign each question to its section
    questions.forEach((q, i) => {
      const resolved = toSection.get(q.section_name) || q.section_name;
      if (!sectionMap.has(resolved)) {
        const entry = { name: resolved, items: [] };
        sectionMap.set(resolved, entry);
        sections.push(entry);
      }
      sectionMap.get(resolved).items.push({ question: q, index: i });
    });
  } else {
    // Fallback: group by section_name
    questions.forEach((q, i) => {
      const name = q.section_name || 'Questions';
      if (!sectionMap.has(name)) {
        const entry = { name, items: [] };
        sectionMap.set(name, entry);
        sections.push(entry);
      }
      sectionMap.get(name).items.push({ question: q, index: i });
    });
  }

  // Filter out empty sections
  const activeSections = sections.filter((s) => s.items.length > 0);

  return (
    <div>
      <h4 class="fw-bold mb-3 fs-s">Question Palette</h4>

      {/* Section-grouped dots */}
      {activeSections.map((sec, secIdx) => {
        const answered = sec.items.filter(
          (it) => getStatus(it.question, responses) === 'answered' || getStatus(it.question, responses) === 'answered_review',
        ).length;

        return (
          <div key={sec.name} style={{ marginBottom: '12px' }}>
            <div class="flex items-center justify-between" style={{ marginBottom: '4px', cursor: 'pointer' }}>
              <span class="fs-xs fw-bold">Section {secIdx + 1}: {sec.name}</span>
              <span class="fs-xs color-secondary">{answered}/{sec.items.length}</span>
            </div>
            <div class="flex flex-wrap" style={{ gap: 0 }}>
              {sec.items.map(({ question: q, index: i }) => {
                const status = getStatus(q, responses);
                const isCurrent = i === currentIndex;
                return (
                  <button
                    key={q.id}
                    onClick={() => onNavigate(i)}
                    style={{
                      width: '32px',
                      height: '32px',
                      borderRadius: '6px',
                      border: isCurrent
                        ? '2px solid var(--accent-brand)'
                        : `1px solid ${status === 'not_visited' ? 'var(--card-border)' : 'transparent'}`,
                      boxShadow: isCurrent ? '0 0 0 2px var(--accent-brand-a10)' : 'none',
                      background: STATUS_COLORS[status],
                      color: status === 'not_visited' ? 'inherit' : 'white',
                      cursor: 'pointer',
                      fontSize: '0.75rem',
                      fontWeight: isCurrent ? 'bold' : '600',
                      display: 'inline-flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      margin: '2px',
                      transition: 'transform 0.1s',
                    }}
                    onMouseEnter={(e) => { e.currentTarget.style.transform = 'scale(1.12)'; }}
                    onMouseLeave={(e) => { e.currentTarget.style.transform = 'scale(1)'; }}
                    title={`Q${i + 1}: ${STATUS_LABELS[status]}`}
                  >
                    {i + 1}
                  </button>
                );
              })}
            </div>
          </div>
        );
      })}

      {/* Legend */}
      <div style={{ borderTop: '1px solid var(--card-border)', paddingTop: '8px', marginTop: '4px' }}>
        <div class="fs-xs color-secondary" style={{ marginBottom: '6px' }}>Legend:</div>
        <div class="flex flex-col gap-1">
          {Object.entries(STATUS_LABELS).map(([key, label]) => (
            <div key={key} class="flex items-center gap-2 fs-xs">
              <div
                style={{
                  width: '14px',
                  height: '14px',
                  borderRadius: '3px',
                  background: STATUS_COLORS[key],
                  border: key === 'not_visited' ? '1px solid var(--card-border)' : 'none',
                  flexShrink: 0,
                }}
              />
              <span>
                {label} ({counts[key] || 0})
              </span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
