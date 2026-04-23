module Ai
  class CommunityBotTrendingArticleCreator
    VERSION = "2.0".freeze
    MAX_TAGS = 4
    MIN_WORD_COUNT = 1200
    AI_GENERATION_MAX_ATTEMPTS = ENV.fetch("COMMUNITY_BOT_AI_GENERATION_MAX_ATTEMPTS", "3").to_i
    PostResult = Struct.new(:title, :body, :tags,:cover_image, keyword_init: true)

    def initialize(
      ai_context:,
      additional_instructions: nil,
      tags: nil,
      ai_client: nil,
      affected_user: nil,
      geo: "IN",
      language: "en-IN",
      max_trends: 3,
      max_news_per_trend: 5,
      trend_cooldown_hours: 48,
      requested_trends: nil
    )
      @ai_context = ai_context
      @additional_instructions = additional_instructions
      @tags = normalize_tags(tags)
      @ai_client = ai_client || Ai::Base.new(wrapper: self, affected_user: affected_user)
      @geo = geo
      @language = language
      @max_trends = max_trends
      @max_news_per_trend = max_news_per_trend
      @trend_cooldown_hours = trend_cooldown_hours
      @requested_trends = requested_trends
    end

    def generate
      chrome_manager = TrendDiscovery::ChromeManager.new
      trends = []
      all_headlines = {}

      begin
        remote_url = chrome_manager.start!
        browser = TrendDiscovery::SeleniumBrowserClient.new(remote_url: remote_url)

        # Step 1: Discover trends
        trends = discover_trends(browser)
        Rails.logger.info("Ai::CommunityBotTrendingArticleCreator: Discovered #{trends.length} trends")

        # Step 2: Filter by cooldown
        fresh_trends = pick_fresh_trends(trends)
        if fresh_trends.empty?
          Rails.logger.warn("Ai::CommunityBotTrendingArticleCreator: No fresh trends available after cooldown filter")
          return nil
        end

        Rails.logger.info("Ai::CommunityBotTrendingArticleCreator: #{fresh_trends.length} fresh trends after cooldown")

        # Step 3: Collect news headlines for each trend (Selenium)
        news_client = TrendDiscovery::GoogleNewsClient.new(browser_client: browser)
        fresh_trends.each do |trend|
          headlines = news_client.discover(
            trend: trend[:name],
            geo: @geo,
            language: @language,
            max_news: @max_news_per_trend,
            )
          all_headlines[trend[:name]] = headlines
          Rails.logger.info("Ai::CommunityBotTrendingArticleCreator: Found #{headlines.length} headlines for '#{trend[:name]}'")
        end
      ensure
        chrome_manager.stop!
      end

      # Step 4: Enrich headlines (HTTP only, no Selenium)
      enricher = TrendDiscovery::HeadlineEnricher.new
      all_headlines.each do |trend_name, headlines|
        all_headlines[trend_name] = enricher.enrich(headlines)
      end

      # Step 5: Fetch platform tags for intelligent tagging
      platform_tags = fetch_platform_tags

      # Step 6: Generate one article per fresh trend
      results = fresh_trends.filter_map do |trend|
        headlines = all_headlines[trend[:name]] || []
        generate_for_trend(trend, headlines, platform_tags)
      end

      return nil if results.blank?

      results
    end

    private

    def discover_trends(browser)
      if @requested_trends.present?
        return @requested_trends.map do |name|
          cleaned = TrendRunHistory.clean(name)
          { name: cleaned, slug: TrendRunHistory.slugify(cleaned), keywords: [cleaned] }
        end
      end

      trends_client = TrendDiscovery::GoogleTrendsClient.new(browser_client: browser, ai_client: @ai_client)
      trends_client.discover(geo: @geo, language: @language, max_trends: @max_trends)
    end

    def pick_fresh_trends(trends)
      return trends if trends.blank?

      used_slugs = TrendRunHistory.used_since(@trend_cooldown_hours.hours.ago)

      trends.reject { |t| used_slugs.include?(t[:slug]) }
    end

    def normalize_tags(tags)
      return nil if tags.blank?

      tags.is_a?(Array) ? tags : tags.to_s.split(",").map(&:strip).reject(&:blank?)
    end

    def fetch_platform_tags
      supported = Tag.where(supported: true).order(hotness_score: :desc).limit(100).pluck(:name)
      popular = Tag.order(hotness_score: :desc).limit(50).pluck(:name)
      (supported + popular).uniq.first(80)
    rescue StandardError => e
      Rails.logger.warn("Ai::CommunityBotTrendingArticleCreator: Failed to fetch platform tags: #{e.message}")
      []
    end

    def build_prompt(trend, language, headlines, platform_tags = [])
      sources_text = build_sources_text(headlines)
      media_text = build_media_text(headlines)
      additional = @additional_instructions.present? ? "\nAdditional Instructions: #{@additional_instructions}" : ""
      context = @ai_context.present? ? "\nPlatform Context: #{@ai_context}" : ""
      tags_hint = platform_tags.any? ? "\nExisting platform tags (PREFER these): #{platform_tags.first(40).join(', ')}" : ""

      <<~PROMPT
        You are a senior investigative journalist, subject-matter expert, and SEO strategist writing an authoritative, in-depth article for CareerPolitics.com.

        CareerPolitics.com is a content platform for Indian government job aspirants, competitive exam candidates, and career-focused readers. Content must be **high-value, original, and substantive** — the kind that earns reader trust and passes ad network quality reviews.

        TREND: #{trend}
        Language: #{language}
        #{context}#{additional}#{tags_hint}

        ═══════════════════════════════════════
        CONTENT QUALITY REQUIREMENTS (CRITICAL)
        ═══════════════════════════════════════

        This article MUST be:
        • **1200–1800 words** minimum — comprehensive, not thin content
        • **Expert-level depth** — write as a domain specialist, not a news aggregator
        • **Original analysis** — synthesize information, provide insights the reader can't get elsewhere
        • **Actionable** — every section must give the reader something they can DO
        • **Well-researched feel** — reference specific numbers, dates, rules, and official sources
        • **Natural, human voice** — conversational yet authoritative, like a trusted mentor

        ABSOLUTELY DO NOT:
        • Write thin, generic, or surface-level content
        • Repeat the same information across sections
        • Use filler phrases like "In this article we will discuss...", "As we all know...", "It is important to note that..."
        • Mention AI, prompts, generation, or automation
        • Include promotional content, Telegram links, or subscription prompts
        • Invent facts — if data is unavailable, write: "Official details are awaited."
        ═══════════════════════════════════════
        ENGAGEMENT & READER INTERACTION (HIGH PRIORITY)
        ═══════════════════════════════════════

        Articles that earn reactions, comments, and extended reading time rank highest on the platform.
        You MUST weave in engagement triggers throughout the article:

        **Discussion Hooks (MANDATORY — include at least 2):**
        • End the article or a major section with a direct question to the reader
          Examples: "Are you planning to appear for this exam? Share your preparation strategy below."
          "Which post do you think offers the best career growth? Tell us in the comments."
        • Present a debatable opinion or comparison that invites reader responses
        • Ask readers to share their experience, tips, or doubts

        **Reaction-Worthy Moments:**
        • Include a surprising statistic, salary figure, or competition ratio that makes readers react
        • Bold critical deadlines or breaking changes that readers will want to bookmark
        • Provide genuinely useful insider tips that feel exclusive

        **Visual Engagement Anchors:**
        • Use images from source data within the article body (markdown image syntax)
        • Use tables for ANY structured data — readers scan tables far more than paragraphs
        • Use collapsible sections for dense reference material (syllabus, detailed breakdowns)
        • Use card blocks to highlight the single most critical update

        **Time-on-Page Boosters:**
        • Structure content so readers scroll through the entire article
        • Place high-value information (salary, eligibility, dates) in the middle, not just the top
        • End with a strong call-to-action section that encourages comments
        ═══════════════════════════════════════
        ARTICLE STRUCTURE
        ═══════════════════════════════════════

        Choose the best angle and use ONLY sections that add real value. Every section must be information-dense.

        **Opening paragraph** (NO heading — this is the hook):
        • Lead with the most newsworthy fact or number
        • Answer the core question in the first 2 sentences
        • Include the primary keyword naturally
        • Set up why this matters to the reader RIGHT NOW

        Then use relevant sections from this menu (pick 5–8 that fit):

        ## Key Highlights at a Glance
        Quick bullet summary of the most important facts (dates, vacancies, eligibility snapshot). This section helps readers who scan.

        ## Detailed Overview
        In-depth context: what happened, why it matters, historical context if relevant. Go DEEP — explain the background a newcomer wouldn't know.

        ## Important Dates & Timeline
        Chronological table or list. Include application window, exam dates, result dates, counselling dates if applicable.

        ## Vacancy / Recruitment Breakdown
        Category-wise breakdowns, post-wise vacancies, reservation details. Use a TABLE for structured data.

        ## Eligibility Criteria
        Age limits (with relaxation), educational qualifications, experience requirements. Be SPECIFIC — mention exact degrees, percentages, age cutoffs.

        ## Salary, Pay Scale & Perks
        7th CPC pay matrix level, gross salary, allowances (DA, HRA, TA), promotion prospects. Include in-hand salary estimates where possible.

        ## Selection Process & Exam Pattern
        Stages (Prelims → Mains → Interview), marking scheme, negative marking, sectional cutoffs, total marks. Include a pattern TABLE.

        ## Syllabus & Preparation Strategy
        Subject-wise syllabus highlights, recommended books/resources, time allocation strategy, previous year trends.

        ## How to Apply: Step-by-Step
        Numbered steps from registration to final submission. Include fee details, payment modes, documents needed.

        ## Expert Analysis & What This Means
        Your editorial analysis: how does this compare to previous years? What trends do you see? What should aspirants prioritize?

        ## Common Mistakes to Avoid
        Practical pitfalls candidates commonly face — wrong form filling, missed deadlines, preparation gaps.

        ## Frequently Asked Questions
        5–7 FAQs based on real search queries. Each answer must be direct, 2–4 lines, and fact-based.
        Format: **Q: [question]** followed by answer paragraph.

        ## What Should You Do Next?
        Clear, actionable closing: bookmark dates, start preparation, gather documents, etc.

        ═══════════════════════════════════════
        FORMATTING & RICH MEDIA RULES
        ═══════════════════════════════════════

        **Text Formatting:**
        • **Short paragraphs**: 2–4 lines max per paragraph
        • **Bullet points**: for lists of 3+ items
        • **Bold key terms**: dates, salary figures, eligibility criteria, deadlines
        • **Tables**: use for ANY structured data (dates, vacancies, salary, exam pattern) — aim for 2–3 tables per article

        **Images (MANDATORY — include at least 1–2):**
        • Use markdown image syntax: `![descriptive alt text](image_url)`
        • Use relevant images from the source media URLs provided below
        • Place images near relevant sections, not bunched together
        • Every image MUST have descriptive alt text for SEO and accessibility

        **Interactive Liquid Tags (use 3–5 per article):**
        • `{% details Summary text %} ... {% enddetails %}` — collapsible sections for syllabus, detailed breakdowns, long tables (use 2–3 times)
        • `{% card %} ... {% endcard %}` — highlight card for the most critical update, deadline, or breaking news (use ONCE)
        • `{% cta URL %} button text {% endcta %}` — call-to-action button ONLY if an official apply/notification URL exists in source data (use max ONCE)

        **Content Structure for Engagement:**
        • Start with a hook paragraph (no heading)
        • Use H2 (##) for major sections, H3 (###) for subsections
        • Include at least 2 tables with structured data
        • Place a `{% card %}` block around the most time-sensitive information
        • Use `{% details %}` for reference sections readers may want to expand (syllabus, fee structure, etc.)
        • End with a question or discussion prompt that encourages comments


        ═══════════════════════════════════════
        SEO OPTIMIZATION
        ═══════════════════════════════════════

        Title:
        • Include the primary keyword (exam/job name) + a value signal (year, salary, vacancy count, "complete guide")
        • Format examples: "BPSC 69th Prelims 2025: Exam Date, Syllabus & 812 Vacancy Details"
        • 50–70 characters ideal

        Description (meta):
        • 140–160 characters, information-dense
        • Include: what, when, who it's for
        • Must NOT repeat the title verbatim

        Content SEO:
        • Primary keyword in first paragraph, first H2, and naturally throughout
        • Long-tail keywords: "how to apply for [exam]", "[exam] eligibility 2025", "[exam] salary after 7th CPC"
        • FAQ questions should mirror real Google searches
        • First line of each section should be a direct answer (featured snippet optimization)

        ═══════════════════════════════════════
        TAG SELECTION (VERY IMPORTANT)
        ═══════════════════════════════════════

        Choose exactly 4 tags. Tags MUST be:
        • **Lowercase, alphanumeric, hyphens only** (e.g., "government-jobs", "ssc-cgl", "upsc")
        • **Specific to the content** — at least 1 tag should be the exam/job name
        • **From existing platform tags when possible** — reusing existing tags improves discoverability

        Tag strategy:
        1. One tag for the specific exam/recruitment name (e.g., "bpsc", "ssc-cgl", "rrb-ntpc")
        2. One tag for the content category (e.g., "government-jobs", "exam-notification", "results", "admit-card", "syllabus")
        3. One tag for the broader domain (e.g., "currentaffairs", "career", "india")
        4. One tag for the content type or audience (e.g., "preparation", "analysis", "beginners-guide")

        ═══════════════════════════════════════
        SOURCE DATA
        ═══════════════════════════════════════

        News Sources:
        #{sources_text}

        Media:
        #{media_text}

        ═══════════════════════════════════════
        OUTPUT FORMAT (STRICT JSON)
        ═══════════════════════════════════════

        Return ONLY valid JSON:

        {
          "title": "SEO-optimized headline (50-70 chars)",
          "markdown": "Full article in Forem-compatible markdown (1200-1800 words)",
          "description": "Meta description (140-160 chars)",
          "tags": ["specific-exam", "category", "domain", "content-type"]
          "cover_image": "URL of the best image from source media for the article cover (or null if none suitable)"
        }

        CRITICAL:
        • Return ONLY the JSON object — no text before or after
        • No code fences or backticks wrapping the JSON
        • Ensure valid, parseable JSON (escape quotes in markdown properly)
        • The markdown field must contain the FULL article, not a summary
        • The markdown must include inline images, table, liquid tags (details/card), and end with a discussion question
        • cover_image should be a high quality, relevant image URL from the social media- this becomes the articles hero image

      PROMPT
    end

    def build_sources_text(headlines)
      return "- No source details were available." if headlines.blank?

      lines = headlines.map do |h|
        parts = ["- Title: #{h[:title]} | Source: #{h[:source]} | Summary: #{safe(h[:summary])}"]
        if h[:article_details].present?
          parts << "  Description: #{safe(h[:article_details][:description])}"
          parts << "  Content excerpt: #{safe(h[:article_details][:content])}"
        end
        parts.join("\n")
      end

      text = lines.join("\n")
      text.present? ? text : "- No source details were available."
    end

    def generation_prompt(prompt, attempt)
      return prompt if attempt.zero?

      <<~PROMPT
        #{prompt}

        RETRY INSTRUCTION (CRITICAL):
        - Your previous answer was invalid or truncated JSON.
        - Return ONE complete JSON object only (no prose, no code fences).
        - Ensure all JSON string values are escaped correctly.
        - Ensure the JSON object closes properly.
      PROMPT
    end

    def build_media_text(headlines)
      return "- No additional media supplied." if headlines.blank?

      urls = headlines.flat_map do |h|
        (h.dig(:article_details, :media_urls) || []).first(2)
      end.compact.uniq.first(5)

      return "- No additional media supplied." if urls.empty?

      urls.map { |u| "- #{u}" }.join("\n")
    end

    def safe(value)
      value.to_s.gsub(/\s+/, " ").strip
    end

    def generate_for_trend(trend, headlines, platform_tags)
      Rails.logger.info("Ai::CommunityBotTrendingArticleCreator: Generating article for '#{trend[:name]}' with #{headlines.length} headlines")

      prompt = build_prompt(trend[:name], @language, headlines, platform_tags)
      result = nil

      AI_GENERATION_MAX_ATTEMPTS.times do |attempt|
        response = @ai_client.call(generation_prompt(prompt, attempt), response_mime_type: "application/json")
        result = parse_response(response, platform_tags, headlines)
        break if result

        Rails.logger.warn(
          "Ai::CommunityBotTrendingArticleCreator: Invalid AI JSON payload for '#{trend[:name]}' on attempt #{attempt + 1}/#{AI_GENERATION_MAX_ATTEMPTS}",
        )
      end

      unless result
        Rails.logger.warn("Ai::CommunityBotTrendingArticleCreator: Skipping '#{trend[:name]}' because no valid AI response was generated")
        return nil
      end

      trend_slug = TrendRunHistory.slugify(trend[:slug].presence || trend[:name])
      TrendRunHistory.create!(trend: trend[:name], trend_slug: trend_slug, published: true)

      result
    end

    def parse_response(response, platform_tags = [], headlines =[])
      return nil if response.blank?

      json = JSON.parse(extract_json_payload(response))

      title = json["title"].to_s.strip
      markdown = json["markdown"].to_s.strip
      description = json["description"].to_s.strip
      raw_tags = sanitize_tags(json["tags"])
      cover_image = pick_cover_image(json["cover_image"], headlines)

      if title.blank? || markdown.blank?
        Rails.logger.error("Ai::CommunityBotTrendingArticleCreator: AI response missing title or markdown")
        return nil
      end

      word_count = markdown.split(/\s+/).size
      Rails.logger.info("Ai::CommunityBotTrendingArticleCreator: Generated #{word_count} words for '#{title}'")
      if word_count < MIN_WORD_COUNT
        Rails.logger.warn("Ai::CommunityBotTrendingArticleCreator: Article below minimum word count (#{word_count}/#{MIN_WORD_COUNT})")
      end

      log_engagement_signals(markdown)

      body = build_front_matter(description, cover_image) + markdown

      final_tags = if @tags.present?
                     @tags
                   else
                     match_platform_tags(raw_tags, platform_tags)
                   end

      PostResult.new(
        title: title,
        body: body,
        tags: final_tags&.join(", "),
        cover_image: cover_image
        )
    rescue JSON::ParserError => e
      Rails.logger.error("Ai::CommunityBotTrendingArticleCreator: Failed to parse AI JSON response: #{e.message}")
      nil
    end

    def extract_json_payload(content)
      trimmed = content.to_s.strip

      # Strip markdown code fences: ```json ... ``` or ``` ... ```
      if trimmed.match?(/\A```(?:json|JSON)?\s*\n/)
        # Remove opening fence line and closing fence line
        without_open = trimmed.sub(/\A```(?:json|JSON)?\s*\n/, "")
        without_close = without_open.sub(/\n\s*```\s*\z/, "")
        return without_close.strip
      end

      trimmed
    end

    def match_platform_tags(ai_tags, platform_tags)
      return ai_tags if platform_tags.blank? || ai_tags.blank?

      platform_set = platform_tags.map(&:downcase).to_set
      matched = []

      ai_tags.each do |tag|
        if platform_set.include?(tag)
          matched << tag
        else
          resolved = begin
                       Tag.find_preferred_alias_for(tag)
                     rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished => e
                       Rails.logger.warn("Ai::CommunityBotTrendingArticleCreator: Tag alias lookup failed for '#{tag}': #{e.message}")
                       tag
                     end
          if platform_set.include?(resolved)
            matched << resolved
          else
            matched << tag
          end
        end
      end

      Rails.logger.info("Ai::CommunityBotTrendingArticleCreator: Tags: AI=#{ai_tags.inspect} → Final=#{matched.inspect}")
      matched.uniq.first(MAX_TAGS)
    end

    def pick_cover_image(ai_cover_image, headlines)
      url = ai_cover_image.to_s.strip
      return url if url.match?(%r{\Ahttps?://}) && !url.include?("data:")

      headline_media = headlines.flat_map do |h|
        [
          h[:media_url],
          h.dig(:article_details, :media_urls)&.first,
        ]
      end.compact.reject(&:blank?).uniq

      picked = headline_media.find { |u| u.match?(%r{\Ahttps://}) }
      Rails.logger.info("Ai::CommunityBotTrendingArticleCreator: Cover image: #{picked || 'none'}") if picked
      picked
    end

    def build_front_matter(description, cover_image)
      parts = []
      parts << "description: #{description}" if description.present?
      parts << "cover_image: #{cover_image}" if cover_image.present?

      return "" if parts.empty?

      "---\n#{parts.join("\n")}\n---\n\n"
    end

    def log_engagement_signals(markdown)
      has_table = markdown.include?("|---") || markdown.include?("| ---")
      has_image = markdown.match?(/!\[.+?\]\(.+?\)/)
      has_details = markdown.include?("{% details")
      has_card = markdown.include?("{% card")
      has_question = markdown.match?(/\?\s*$/)

      signals = []
      signals << "tables" if has_table
      signals << "images" if has_image
      signals << "details_blocks" if has_details
      signals << "card_blocks" if has_card
      signals << "discussion_questions" if has_question

      Rails.logger.info("Ai::CommunityBotTrendingArticleCreator: Engagement signals present: #{signals.join(', ').presence || 'NONE — article may underperform'}")
    end

    def sanitize_tags(tags_array)
      return [] unless tags_array.is_a?(Array)

      seen = Set.new
      tags_array.filter_map do |tag|
        normalized = tag.to_s.strip.downcase.gsub(/[^[:alnum:]]/, "")
        next if normalized.blank? || seen.include?(normalized)

        seen.add(normalized)
        normalized
      end.first(MAX_TAGS)
    end
  end
end
