import { h } from 'preact';
import { useState, useEffect, useMemo, useCallback } from 'preact/hooks';
import { request } from '@utilities/http';

export function MockExamListing() {
  const [templates, setTemplates] = useState([]);
  const [followedTags, setFollowedTags] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    request('/mock_exams.json')
      .then((res) => res.json())
      .then((data) => {
        setTemplates(data.templates || []);
        setFollowedTags(data.followed_tags || []);
        setLoading(false);
      })
      .catch(() => setLoading(false));
  }, []);

  const followedNames = useMemo(
    () => followedTags.map((t) => t.name),
    [followedTags],
  );

  const toggleTag = useCallback((tagObj) => {
    setFollowedTags((prev) => {
      const isFollowed = prev.some((t) => t.name === tagObj.name);
      const updated = isFollowed
        ? prev.filter((t) => t.name !== tagObj.name)
        : [...prev, tagObj];

      // Fire-and-forget follow/unfollow via Forem's API
      request(`/follows`, {
        method: 'POST',
        body: JSON.stringify({
          followable_type: 'Tag',
          followable_id: tagObj.id,
          verb: isFollowed ? 'unfollow' : 'follow',
        }),
        headers: { 'Content-Type': 'application/json' },
      }).catch(() => {});

      return updated;
    });
  }, []);

  const { following, others } = useMemo(() => {
    const f = [];
    const o = [];
    templates.forEach((t) => {
      const tags = t.tag_list || [];
      const isFollowed = tags.some((tag) => followedNames.includes(tag.name));
      if (isFollowed) {
        f.push(t);
      } else {
        o.push(t);
      }
    });
    return { following: f, others: o };
  }, [templates, followedNames]);

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

      {/* Following — large featured cards */}
      {following.length > 0 && (
        <div class="mb-6">
          <h2 class="fw-bold mb-3" style={{ fontSize: '1.1rem' }}>Following</h2>
          <div class="grid gap-4" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))' }}>
            {following.map((t) => (
              <FeaturedCard key={t.id} template={t} followedNames={followedNames} onToggleTag={toggleTag} />
            ))}
          </div>
        </div>
      )}

      {/* All Exams — compact rows */}
      {others.length > 0 && (
        <div>
          <h2 class="fw-bold mb-3" style={{ fontSize: '1.1rem' }}>All Exams</h2>
          <div class="flex flex-col gap-2">
            {others.map((t) => (
              <CompactRow key={t.id} template={t} followedNames={followedNames} onToggleTag={toggleTag} />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

function TagChip({ tag, isFollowed, onToggle }) {
  return (
    <span
      class="fs-xs fw-bold"
      style={{
        padding: '2px 8px',
        borderRadius: '4px',
        cursor: 'pointer',
        background: isFollowed ? 'var(--accent-brand-a10)' : 'var(--card-secondary-bg)',
        color: isFollowed ? 'var(--accent-brand)' : 'var(--body-color)',
        textTransform: 'capitalize',
        whiteSpace: 'nowrap',
      }}
      onClick={(e) => { e.preventDefault(); e.stopPropagation(); onToggle(tag); }}
      title={isFollowed ? 'Click to unfollow' : 'Click to follow'}
    >
      {isFollowed ? '★' : '☆'} {tag.name.replace(/_/g, ' ')}
    </span>
  );
}

function FeaturedCard({ template: t, followedNames, onToggleTag }) {
  return (
    <a
      href={`/mock_exams/${t.slug}`}
      class="crayons-card p-4 block"
      style={{
        textDecoration: 'none', color: 'inherit',
        transition: 'box-shadow 0.15s ease, transform 0.15s ease',
        border: '1px solid var(--card-border)',
      }}
      onMouseEnter={(e) => { e.currentTarget.style.boxShadow = '0 4px 12px rgba(0,0,0,0.1)'; e.currentTarget.style.transform = 'translateY(-2px)'; }}
      onMouseLeave={(e) => { e.currentTarget.style.boxShadow = 'none'; e.currentTarget.style.transform = 'none'; }}
    >
      <div class="flex items-start justify-between mb-2">
        <h3 class="fw-bold fs-l" style={{ lineHeight: '1.3' }}>{t.title}</h3>
      </div>

      {t.description && (
        <p class="color-secondary fs-s mb-3" style={{ lineHeight: '1.5' }}>
          {t.description.length > 100 ? `${t.description.slice(0, 100)}...` : t.description}
        </p>
      )}

      <div class="flex flex-wrap gap-2 mb-3">
        {(t.tag_list || []).map((tag) => (
          <TagChip key={tag.name} tag={tag} isFollowed={followedNames.includes(tag.name)} onToggle={onToggleTag} />
        ))}
        {t.published_sets_count > 0 && (
          <span class="crayons-tag crayons-tag--monochrome">
            {t.published_sets_count} sets
          </span>
        )}
      </div>

      <div style={{ borderTop: '1px solid var(--card-border)', paddingTop: '8px' }}>
        <div class="flex justify-between fs-s color-secondary">
          <span title="Questions">📋 {t.total_questions}q</span>
          <span title="Duration">⏱ {t.duration_minutes}m</span>
          <span title="Marks">+{t.marks_per_correct} / −{t.negative_marks_per_wrong}</span>
        </div>
      </div>
    </a>
  );
}

function CompactRow({ template: t, followedNames, onToggleTag }) {
  return (
    <div
      class="flex items-center justify-between flex-wrap"
      style={{
        padding: '10px 16px',
        border: '1px solid var(--card-border)',
        borderRadius: '8px',
        background: 'var(--card-bg)',
        gap: '12px',
      }}
    >
      <div style={{ flex: '1 1 auto', minWidth: 0 }}>
        <a href={`/mock_exams/${t.slug}`} class="fw-bold fs-s"
           style={{ textDecoration: 'none', color: 'inherit' }}>
          {t.title}
        </a>
        <div class="flex items-center gap-2 mt-1">
          {(t.tag_list || []).map((tag) => (
            <TagChip key={tag.name} tag={tag} isFollowed={followedNames.includes(tag.name)} onToggle={onToggleTag} />
          ))}
          <span class="fs-xs color-secondary">📋 {t.total_questions}q</span>
          <span class="fs-xs color-secondary">⏱ {t.duration_minutes}m</span>
          {t.published_sets_count > 0 && (
            <span class="fs-xs color-secondary">{t.published_sets_count} sets</span>
          )}
        </div>
      </div>
    </div>
  );
}
