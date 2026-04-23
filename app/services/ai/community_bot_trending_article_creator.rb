module Ai
  class CommunityBotTrendingArticleCreator
    VERSION = "2.0".freeze
    MAX_TAGS = 4
    DEFAULT_TARGET_WORD_COUNT= 800
    AI_GENERATION_MAX_ATTEMPTS = ENV.fetch("COMMUNITY_BOT_AI_GENERATION_MAX_ATTEMPTS", "3").to_i
    PostResult = Struct.new(:title, :body, :tags,:cover_image, keyword_init: true)

    def initialize(
      ai_context:,
      additional_instructions: nil,
      tags: nil,
      ai_client: nil,
      affected_user: nil,
      target_word_count: DEFAULT_TARGET_WORD_COUNT,
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
      @target_word_count = [[target_word_count.to_i, 400].max, 2000].min
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

      # Step 6: Fetch platform tags for intelligent tagging
      platform_tags = fetch_platform_tags

      # Step 7: Build prompt and call AI
      prompt = build_prompt(best_trend[:name], @language, headlines, platform_tags)
      result = nil
      AI_GENERATION_MAX_ATTEMPTS.times do |attempt|
        response = @ai_client.call(generation_prompt(prompt, attempt), response_mime_type: "application/json")
        result = parse_response(response, platform_tags, headlines)
        break if result

        Rails.logger.warn("Ai::CommunityBotTrendingArticleCreator: Invalid AI JSON payload on attempt #{attempt + 1}/#{AI_GENERATION_MAX_ATTEMPTS}")
      end
      return nil unless result

      # Step 8: Record cooldown
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

      trends_client = TrendDiscovery::GoogleTrendsClient.new(browser_client: browser, ai_client: @ai_client)
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
      tags_hint = platform_tags.any? ? "\nPreferred platform tags: #{platform_tags.first(30).join(', ')}" : ""
      word_range = "#{@target_word_count}–#{(@target_word_count * 1.3).to_i}"
      section_count = @target_word_count <= 600 ? "3–4" : "5–8"

      <<~PROMPT
        You are a senior journalist and SEO strategist writing for CareerPolitics.com — a platform for Indian government job aspirants and competitive exam candidates.

        TREND: #{trend}
        Language: #{language}
        Target length: #{word_range} words
        #{context}#{additional}#{tags_hint}

        QUALITY RULES:
        • #{word_range} words — dense, no filler or repetition
        • Expert depth — specific numbers, dates, official sources; never invent facts
        • Actionable — every section gives the reader something to DO
        • Natural voice — conversational yet authoritative, like a trusted mentor
        • DO NOT mention AI/automation or use filler phrases ("In this article...", "As we all know...")

        ENGAGEMENT (weave throughout):
        • Include 1–2 discussion questions that invite comments
        • Bold critical deadlines/numbers; include a surprising statistic
        • At least 2 tables for structured data (dates, vacancies, salary, exam pattern)
        • At least 1–2 images from source media: `![descriptive alt text](url)`
        • If data is unavailable, write "Official details are awaited" — never invent facts
        • No promotional content, Telegram links, or subscription prompts

        STRUCTURE:
        Open with a hook paragraph (no heading) — lead with the most newsworthy fact.
        Then pick #{section_count} sections that fit from: Key Highlights | Detailed Overview | Important Dates | Vacancy Breakdown | Eligibility | Salary & Perks | Exam Pattern | Preparation Strategy | How to Apply | Expert Analysis | FAQs | Next Steps.
        Close with an actionable prompt that encourages comments.

        FORMATTING:
        • H2 for sections, H3 for subsections; short paragraphs (2–4 lines)
        • Use 2–4 liquid tags: `{% details Summary %} ... {% enddetails %}` for dense reference data, `{% card %} ... {% endcard %}` for the most critical update (once)
        • `{% cta URL %} text {% endcta %}` only if an official URL exists in sources

        SEO:
        • Title: primary keyword + value signal, 50–70 chars
        • Description: 140–160 chars, information-dense, not repeating title
        • Primary keyword in first paragraph and first H2

        TAGS: exactly 4, lowercase hyphenated (e.g. "ssc-cgl"). Strategy: exam-name + category + domain + content-type. Prefer existing platform tags.

        SOURCE DATA:
        #{sources_text}

        Media:
        #{media_text}

        OUTPUT (strict JSON, no code fences, no surrounding text):
        {"title":"...","markdown":"...","description":"...","tags":["..."],"cover_image":"URL or null"}

        The markdown must be the FULL article (#{word_range} words), not a summary. Escape quotes properly. cover_image should be the best source media image URL.
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
      min_words = (@target_word_count * 0.6).to_i
      if word_count < min_words
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
