# Job Posts Feature Audit: Critical Gaps and SEO/Engagement Improvements

## Scope Reviewed
- `JobPostsController`, model, routes, views, migration/schema state, and request specs.
- Focus: crawlability, indexability, content quality, internal linking, and conversion/engagement signals.

## Critical Gaps

### 1) Job detail pages are often bypassed by server-side redirect
In `show`, external links are redirected immediately (`redirect_to @job_post.link`) when the link is absolute. This prevents users and crawlers from consuming a rich on-site detail page, reducing page depth, dwell time, internal link opportunities, and long-tail ranking potential.

### 2) Thin content model for ranking intent
The model/migration contains only basic fields (`title`, `description`, `category`, `post_type`, `link`) and the public create/update controller permits only `title`, `post_type`, `link`, and `color`. Missing high-intent attributes (organization, location, eligibility, deadline, salary/grade, application dates, FAQ) make pages too thin for competitive SEO.

### 3) Schema state appears out of sync for this feature
`job_posts` migration exists with timestamp `20251210035211`, but `db/schema.rb` is at version `2026_02_19_204658` and does not define `job_posts`. This indicates the feature may not be represented in canonical schema state in this branch/environment, creating deployment and test confidence risk.

### 4) Non-canonical/scaffold routes and weak tests
Top-level legacy routes (`get 'job_posts/index'`, etc.) coexist with canonical `/jobs` resources, which can create duplicate entry points and unclear canonicalization. Request specs currently test scaffold endpoints only and assert `:success`, not business behavior, SEO metadata, redirects, or crawlable HTML content.

### 5) Structured data is incomplete and client-injected
Index page JSON-LD is injected via client JS and only includes title+url for featured posts. For best crawler reliability and eligibility, structured data should be rendered server-side and include richer properties (validThrough, datePosted, employmentType, hiringOrganization, jobLocation, etc.) where available.

## High-Impact SEO Improvements

1. **Stop auto-redirecting detail pages**
   - Keep `/jobs/:slug` as first-class destination pages.
   - Replace immediate redirect with prominent CTA button to external apply link (`rel="nofollow sponsored noopener"`, `target="_blank"`).
   - Preserve internal content, related jobs, and metadata.

2. **Expand job content schema and editorial surface**
   - Add normalized fields: `organization_name`, `location`, `deadline_at`, `employment_type`, `salary_range`, `qualification`, `vacancies`, `source_name`, `source_url`, `important_dates`.
   - Render this in structured sections (Overview, Eligibility, Dates, How to Apply).

3. **Server-render JSON-LD for each job page**
   - Emit `JobPosting` JSON-LD in `show` response HTML (not appended after page load in JS).
   - Add `BreadcrumbList` JSON-LD for `/jobs` → post type → slug.

4. **Canonical and robots hygiene**
   - Add canonical tags on index/detail pages.
   - Ensure only canonical `/jobs` routes are used; remove legacy scaffold routes.
   - Add paginated rel links where relevant and ensure page-parameter handling is crawl-safe.

5. **Programmatic internal linking strategy**
   - Create crawlable post-type hubs (`/jobs/new_update`, `/jobs/admit_card`, `/jobs/online_form`) with unique intro copy.
   - Add “related by exam/organization/category/deadline” blocks.
   - Add “latest updates” widgets to high-traffic pages.

## High-Impact Engagement & Traffic Improvements

1. **SERP CTR optimization**
   - Generate dynamic titles/meta descriptions by job attributes (org + exam + deadline + location + year).
   - Add freshness indicators (updated date and status badges) in visible snippet text.

2. **Retention loops**
   - Add “follow category/exam” and “deadline reminder” (email/push) CTAs.
   - Track reminder subscriptions and send pre-deadline nudges.

3. **On-site UX for scan behavior**
   - Add sticky “Apply Now” and “Save/Remind me” actions.
   - Add quick facts panel above the fold and expandable detail sections below.

4. **Measurement and experimentation**
   - Define funnel events: listing impression → detail view → apply click.
   - A/B test title templates, CTA placement, and related-job modules.

## Prioritized Implementation Plan

### Phase 1 (Immediate)
- Remove auto-redirect in `show`; keep on-site detail page as canonical landing page.
- Clean up duplicate scaffold routes.
- Add regression request specs for canonical routes and metadata presence.

### Phase 2 (Short-term)
- Add core structured fields and render richer job detail content.
- Implement server-side JSON-LD for `JobPosting` and breadcrumbs.
- Improve internal linking with post-type/category hubs.

### Phase 3 (Growth)
- Build reminder/follow features and track conversion events.
- Add automated SEO checks (presence of canonical, JSON-LD validity, title length guards).

## Suggested KPIs
- Organic sessions to `/jobs/*`
- Indexed job-detail pages
- CTR from search to job-detail pages
- Detail page engagement time
- Apply-link click-through rate
- Return visits from reminder/follow flows
