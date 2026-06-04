import { h } from 'preact';
import { useState, useEffect, useMemo, useCallback } from 'preact/hooks';
import { request } from '@utilities/http';

export function MockExamListing() {
  const [templates, setTemplates] = useState([]);
  const [followedTags, setFollowedTags] = useState([]);
  const [loading, setLoading] = useState(true);
  const [userSignedIn, setUserSignedIn] = useState(false);

  useEffect(() => {
    request('/mock_exams.json')
      .then((res) => res.json())
      .then((data) => {
        setTemplates(data.templates || []);
        setFollowedTags(data.followed_tags || []);
        setUserSignedIn(data.user_signed_in || false);
        setLoading(false);
      })
      .catch(() => setLoading(false));
  }, []);

  const followedNames = useMemo(
    () => new Set(followedTags.map((t) => t.name)),
    [followedTags],
  );

  const toggleTag = useCallback((tagObj) => {
    if (!userSignedIn) {
      window.location.href = '/enter';
      return;
    }
    setFollowedTags((prev) => {
      const isFollowed = prev.some((t) => t.name === tagObj.name);
      const updated = isFollowed
        ? prev.filter((t) => t.name !== tagObj.name)
        : [...prev, tagObj];

      // Fire-and-forget follow/unfollow via Forem's API
      request('/follows', {
        method: 'POST',
        body: JSON.stringify({ followable_type: 'Tag', followable_id: tagObj.id }),
        headers: { 'Content-Type': 'application/json' },
      }).catch(() => {});

      return updated;
    });
  }, [userSignedIn]);

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
      <div class="flex items-center justify-between mb-4 flex-wrap gap-2">
        <h1 class="crayons-title">Mock Exams</h1>
      </div>

      <div class="grid gap-4" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))' }}>
        {templates.map((t) => (
          <ExamCard key={t.id} template={t} followedNames={followedNames} onToggleTag={toggleTag} />
        ))}
      </div>
    </div>
  );
}

function TagChip({ tag, isFollowed, onToggle }) {
  return (
    <span class="flex items-center gap-1" style={{ display: 'inline-flex' }}>
      <a
        href={`/t/${tag.name}`}
        class="crayons-tag"
        onClick={(e) => e.stopPropagation()}
        style={{ textDecoration: 'none' }}
      >
        <span class="crayons-tag__prefix">#</span>
        {tag.name}
      </a>
      <button
        class={`c-btn c-btn--s ${isFollowed ? 'c-btn--primary' : 'c-btn--secondary'}`}
        style={{
          padding: '1px 6px',
          fontSize: '0.65rem',
          minHeight: '22px',
          borderRadius: '4px',
        }}
        onClick={(e) => { e.preventDefault(); e.stopPropagation(); onToggle(tag); }}
        title={isFollowed ? 'Unfollow this tag' : 'Follow this tag'}
      >
        {isFollowed ? 'Following' : 'Follow'}
      </button>
    </span>
  );
}

function ExamCard({ template: t, followedNames, onToggleTag }) {
  const tags = t.tag_list || [];
  const isFollowed = tags.some((tag) => followedNames.has(tag.name));

  return (
    <a
      href={`/mock_exams/${t.slug}`}
      class="crayons-card p-4 block"
      style={{
        textDecoration: 'none', color: 'inherit',
        transition: 'box-shadow 0.15s ease, transform 0.15s ease',
        border: isFollowed ? '2px solid var(--accent-brand)' : '1px solid var(--card-border)',
      }}
      onMouseEnter={(e) => { e.currentTarget.style.boxShadow = '0 4px 12px rgba(0,0,0,0.1)'; e.currentTarget.style.transform = 'translateY(-2px)'; }}
      onMouseLeave={(e) => { e.currentTarget.style.boxShadow = 'none'; e.currentTarget.style.transform = 'none'; }}
    >
      <div class="flex items-start justify-between mb-2">
        <h3 class="fw-bold fs-l" style={{ lineHeight: '1.3' }}>{t.title}</h3>
        {isFollowed && (
          <span class="crayons-tag crayons-tag--monochrome fs-xs" style={{ flexShrink: 0 }}>Following</span>
        )}
      </div>

      {t.description && (
        <p class="color-secondary fs-s mb-3" style={{ lineHeight: '1.5' }}>
          {t.description.length > 100 ? `${t.description.slice(0, 100)}...` : t.description}
        </p>
      )}

      <div class="flex flex-wrap gap-2 mb-3">
        {tags.map((tag) => (
          <TagChip key={tag.name} tag={tag} isFollowed={followedNames.has(tag.name)} onToggle={onToggleTag} />
        ))}
        {t.published_sets_count > 0 && (
          <span class="crayons-tag crayons-tag--monochrome">
            {t.published_sets_count} sets
          </span>
        )}
      </div>

      <div style={{ borderTop: '1px solid var(--card-border)', paddingTop: '8px' }}>
        <div class="flex justify-between fs-s color-secondary">
          <span title="Questions">{t.total_questions}q</span>
          <span title="Duration">{t.duration_minutes}m</span>
          <span title="Marks">+{t.marks_per_correct} / -{t.negative_marks_per_wrong}</span>
        </div>
      </div>
    </a>
  );
}
