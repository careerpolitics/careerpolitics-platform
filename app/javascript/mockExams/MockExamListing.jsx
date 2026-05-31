import { h } from 'preact';
import { useState, useEffect } from 'preact/hooks';
import { request } from '@utilities/http';

export function MockExamListing() {
  const [templates, setTemplates] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    request('/mock_exams.json')
      .then((res) => res.json())
      .then((data) => {
        setTemplates(data);
        setLoading(false);
      })
      .catch(() => setLoading(false));
  }, []);

  if (loading) {
    return (
      <div class="crayons-card p-6 flex justify-center">
        <div class="crayons-loading" aria-label="Loading mock exams..." />
      </div>
    );
  }

  if (templates.length === 0) {
    return (
      <div class="crayons-card p-6 text-center">
        <h2 class="crayons-title mb-2">Mock Exams</h2>
        <p class="color-secondary">No mock exams available yet. Check back soon!</p>
      </div>
    );
  }

  return (
    <div>
      <h1 class="crayons-title mb-4">Mock Exams</h1>
      <div class="grid gap-4" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(320px, 1fr))' }}>
        {templates.map((t) => (
          <TemplateCard key={t.id} template={t} />
        ))}
      </div>
    </div>
  );
}

function TemplateCard({ template }) {
  const t = template;

  return (
    <a
      href={`/mock_exams/${t.slug}`}
      class="crayons-card crayons-card--secondary p-4 block"
      style={{ textDecoration: 'none', color: 'inherit' }}
    >
      <h3 class="crayons-subtitle-1 mb-2">{t.title}</h3>
      {t.description && (
        <p class="color-secondary fs-s mb-3" style={{ lineHeight: '1.4' }}>
          {t.description.length > 120
            ? `${t.description.slice(0, 120)}...`
            : t.description}
        </p>
      )}
      <div class="flex flex-wrap gap-2 mb-3">
        <span class="crayons-tag">{t.exam_category?.replace(/_/g, ' ')}</span>
        <span class="crayons-tag crayons-tag--monochrome">{t.difficulty_level}</span>
      </div>
      <div class="flex justify-between fs-s color-secondary">
        <span>{t.total_questions} questions</span>
        <span>{t.duration_minutes} min</span>
        <span>+{t.marks_per_correct} / -{t.negative_marks_per_wrong}</span>
      </div>
    </a>
  );
}
