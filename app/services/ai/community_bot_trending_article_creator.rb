module Ai
  class CommunityBotTrendingArticleCreator
    VERSION = "1.0".freeze
    MAX_TAGS = 4
    PostResult = Struct.new(:title, :body, :tags, keyword_init: true)

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

      # Step 5: Pick the best trend (most headlines with content)
      best_trend = pick_best_trend(fresh_trends, all_headlines)
      return nil unless best_trend

      headlines = all_headlines[best_trend[:name]] || []
      Rails.logger.info("Ai::CommunityBotTrendingArticleCreator: Generating article for '#{best_trend[:name]}' with #{headlines.length} headlines")

      # Step 6: Build prompt and call AI
      prompt = build_prompt(best_trend[:name], @language, headlines)
      response = @ai_client.call(prompt, response_mime_type: "application/json")
      result = parse_response(response)
      return nil unless result

      # Step 7: Record cooldown
      TrendRunHistory.create!(
        trend: best_trend[:name],
        trend_slug: best_trend[:slug],
        published: true,
        )

      result
    end

    private

    def discover_trends(browser)
      if @requested_trends.present?
        return @requested_trends.map do |name|
          cleaned = TrendRunHistory.clean(name)
          { name: cleaned, slug: TrendRunHistory.slugify(cleaned), keywords: [cleaned] }
        end
      end

      trends_client = TrendDiscovery::GoogleTrendsClient.new(browser_client: browser)
      trends_client.discover(geo: @geo, language: @language, max_trends: @max_trends)
    end

    def pick_fresh_trends(trends)
      return trends if trends.blank?

      used_slugs = TrendRunHistory.used_since(@trend_cooldown_hours.hours.ago)

      trends.reject { |t| used_slugs.include?(t[:slug]) }
    end

    def pick_best_trend(trends, all_headlines)
      trends.max_by do |trend|
        headlines = all_headlines[trend[:name]] || []
        enriched_count = headlines.count { |h| h.dig(:article_details, :content).present? }
        headlines.length + enriched_count
      end
    end

    def normalize_tags(tags)
      return nil if tags.blank?

      tags.is_a?(Array) ? tags : tags.to_s.split(",").map(&:strip).reject(&:blank?)
    end

    def build_prompt(trend, language, headlines)
      sources_text = build_sources_text(headlines)
      media_text = build_media_text(headlines)
      additional = @additional_instructions.present? ? "\nAdditional Instructions: #{@additional_instructions}" : ""
      context = @ai_context.present? ? "\nContext: #{@ai_context}" : ""

      <<~PROMPT
        You are a senior investigative journalist and SEO strategist writing for CareerPolitics.com — a platform focused on government jobs, exams, and policy updates.

        OBJECTIVE:
        TREND: #{trend}
        Language: #{language}
        #{context}#{additional}

        Write a high-quality, human-like article that:
        • Solves real search intent (jobs, exams, results, dates)
        • Provides actionable insights for aspirants
        • Is clear, factual, and non-repetitive
        • Feels natural and not AI-generated

        Additional hard requirements:
        • Use only the provided source data
        • Do not invent facts
        • Do not mention AI, prompts, generation steps, or code
        • Do not include promotional lines, Telegram mentions, subscription prompts, or marketing copy
        • Do not include any extra fields beyond title, markdown, description, and tags
        • If something is unclear, write exactly: "As of now, no official confirmation is available."

        ---

        STEP 1 — CHOOSE A CLEAR ANGLE
        Pick ONE and stay consistent:
        • Recruitment / exam notification
        • Policy impact
        • Timeline change
        • Controversy
        • Opportunity for aspirants

        ---

        STEP 2 — WRITING RULES (STRICT)
        • No fluff or generic phrases
        • No repetition
        • No source-by-source narration
        • Use smooth, natural transitions
        • Write like a professional journalist

        ---

        STEP 3 — STRUCTURE (USE ONLY WHAT FITS)

        Use relevant sections logically. Each section must add new information (no repetition).

        ## Overview
        ## Important Dates
        ## Vacancy Details
        ## Eligibility Criteria
        ## Salary / Pay Scale
        ## Selection Process
        ## Exam Pattern / Syllabus
        ## Timeline of Events
        ## Impact on Aspirants
        ## What Should Aspirants Do Now
        ## FAQ

        Additional rules:
        • Prioritize sections that match search intent (jobs, dates, eligibility, salary)
        • Do NOT include empty or weak sections
        • Ensure each section is actionable and information-dense

        ---

        STEP 4 — FORMATTING (STRICT)

        • Use short paragraphs (2–3 lines max)
        • Use bullet points for clarity
        • Keep content highly scannable

        Structured formatting rules (VERY IMPORTANT):

        1. TABLE USAGE (MANDATORY LOGIC)
        • If the content includes structured data (dates, vacancies, salary, categories), use EXACTLY ONE table
        • Table must be simple (2–4 columns max)
        • Do NOT create multiple tables

        2. DETAILS BLOCK (CONTROLLED USAGE)
        • Use at most TWO details blocks
        • Use ONLY for:
          - Long syllabus
          - Detailed eligibility breakdown
          - Extended FAQs (if needed)
        • Do NOT hide critical information inside details
        • Syntax: `{% details Summary %} ... {% enddetails %}`

        3. HIGHLIGHT BLOCK (IMPORTANT)
        • Use at most ONE highlight/card block
        • Use ONLY for critical updates such as:
          - Last date
          - Major change
          - Important warning
        • Syntax: `{% card %} ... {% endcard %}`

        4. CALL TO ACTION (OPTIONAL)
        • If the source data includes an official URL (apply link, notification PDF), you may add ONE CTA at the end.
        • Use this format: `{% cta URL %} Click here to ... {% endcta %}`
        • Do NOT use CTAs for social media or promotional content.

        5. CONTENT DENSITY
        • Every paragraph must add new information
        • Avoid filler, repetition, or generic statements

        6. READABILITY
        • Maintain clear section separation
        • Avoid large text blocks
        • Ensure mobile-friendly formatting

        ---

        STEP 5 — ACCURACY (VERY IMPORTANT)
        • Use ONLY the provided source data
        • Do NOT invent facts
        • If something is unclear, write:
          "As of now, no official confirmation is available."

        ---

        STEP 6 — SEO OPTIMIZATION (HIGH PRIORITY)

        • Identify primary search intent (e.g., "apply online", "last date", "eligibility", "salary")
        • Ensure the article directly answers these queries

        Featured snippet optimization:
        • Provide clear, direct answers in the first 1–2 lines of relevant sections
        • Use bullet points for list-type queries
        • Use table for structured queries

        Keyword usage:
        • Naturally include high-intent keywords:
          apply online, last date, eligibility, syllabus, salary, notification
        • Avoid keyword stuffing

        Search behavior optimization:
        • Assume reader wants quick, actionable answers
        • Reduce scrolling effort by structuring content logically

        ---

        STEP 7 — FAQ GENERATION (MANDATORY)

        • Include 3 to 5 FAQs within the FAQ section
        • Questions must reflect real search queries:
          - What is the last date?
          - Who is eligible?
          - What is the salary?
          - How to apply?
        • Answers must be:
          - Direct
          - Fact-based
          - 1–3 lines max
        • Do NOT repeat content unnecessarily
        • If data is missing, write:
          "As of now, no official confirmation is available."
        • Formatting options (choose one that fits the article):
          - Simple Q&A list: **Q:** ... **A:** ...
          - Collapsible sections: `{% details Question %} Answer {% enddetails %}`

        ---

        STEP 8 — TITLE

        • Make it clear, specific, and SEO-friendly
        • Use numbers, salary, or dates when useful
        • Avoid vague or clickbait titles

        ---

        STEP 9 — DESCRIPTION

        • Write one concise, high-information summary
        • Include key elements such as role, dates, or opportunity
        • Keep it optimized for search preview (meta description)
        • Do NOT repeat the title

        ---

        STEP 10 — TAGS

        • Choose 4 tags
        • Tags must reflect:
          - Exam or job name
          - Category (government-jobs, results, admit-card, etc.)
        • Keep them concise and SEO-relevant
        • Avoid generic or duplicate tags

        ---

        PROVIDED DATA:

        News Sources:
        #{sources_text}

        Media:
        #{media_text}

        ---

        OUTPUT FORMAT (STRICT)

        Return ONLY valid JSON in this exact structure:

        {
          "title": "Clear and SEO-optimized headline",
          "markdown": "Full article in valid Forem markdown",
          "description": "Short plain-text summary",
          "tags": ["tag-one", "tag-two"]
        }

        IMPORTANT:
        • Do not include any text outside JSON
        • Do not include code blocks
        • Ensure the JSON is valid and parseable
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

    def parse_response(response)
      return nil if response.blank?

      json = JSON.parse(extract_json_payload(response))

      title = json["title"].to_s.strip
      markdown = json["markdown"].to_s.strip
      description = json["description"].to_s.strip
      tags = sanitize_tags(json["tags"])

      if title.blank? || markdown.blank?
        Rails.logger.error("Ai::CommunityBotTrendingArticleCreator: AI response missing title or markdown")
        return nil
      end

      body = markdown
      body = "---\ndescription: #{description}\n---\n\n#{body}" if description.present?

      final_tags = @tags.present? ? @tags : tags

      PostResult.new(
        title: title,
        body: body,
        tags: final_tags&.join(", "),
        )
    rescue JSON::ParserError => e
      Rails.logger.error("Ai::CommunityBotTrendingArticleCreator: Failed to parse AI JSON response: #{e.message}")
      nil
    end

    def extract_json_payload(content)
      trimmed = content.to_s.strip
      if trimmed.start_with?("```

")
        first_newline = trimmed.index("\n")
        last_fence = trimmed.rindex("

```")
        if first_newline && last_fence && last_fence > first_newline
          return trimmed[(first_newline + 1)...last_fence].strip
        end
      end
      trimmed
    end

    def sanitize_tags(tags_array)
      return [] unless tags_array.is_a?(Array)

      seen = Set.new
      tags_array.filter_map do |tag|
        normalized = tag.to_s.strip.downcase.gsub(/[^a-z0-9-]/, "")
        next if normalized.blank? || seen.include?(normalized)

        seen.add(normalized)
        normalized
      end.first(MAX_TAGS)
    end
  end
end
