module TrendDiscovery
  class GoogleTrendsClient
    GOOGLE_TRENDS_URL = ENV.fetch("GOOGLE_TRENDS_URL", "https://trends.google.com/trending")
    FALLBACK_TRENDS = ENV.fetch("TRENDING_FALLBACK_TRENDS", "").split(",").map(&:strip).reject(&:blank?).freeze

    def initialize(browser_client:, ai_client: nil)
      @browser = browser_client
      @ai_client = ai_client
    end

    def discover(geo:, language:, max_trends:)
      url = build_url(geo, language)
      Rails.logger.info("TrendDiscovery::GoogleTrendsClient: Fetching trends from #{url}")

      html = @browser.fetch_page(url)

      if html.present?
        titles = parse_trends_from_html(html, max_trends)

        if titles.blank? && @ai_client
          Rails.logger.info("TrendDiscovery::GoogleTrendsClient: HTML parse returned no trends, trying AI table extraction")
          ai_topics = extract_trends_via_ai(html, max_trends)
          return ai_topics if ai_topics.any?
        end
      end

      titles = [] if titles.nil?

      if titles.blank? && FALLBACK_TRENDS.any?
        Rails.logger.warn("TrendDiscovery::GoogleTrendsClient: Using fallback trends")
        titles = FALLBACK_TRENDS.first(max_trends)
      end

      return [] if titles.blank?

      titles.map do |title|
        cleaned = TrendRunHistory.clean(title)
        slug = TrendRunHistory.slugify(cleaned)
        { name: cleaned, slug: slug, keywords: [cleaned] }
      end
    end

    private

    def build_url(geo, language)
      uri = URI.parse(GOOGLE_TRENDS_URL)
      existing_params = URI.decode_www_form(uri.query.to_s).to_h

      existing_params["geo"] = geo if geo.present? && !existing_params.key?("geo")
      existing_params["hl"] = language if language.present? && !existing_params.key?("hl")

      uri.query = URI.encode_www_form(existing_params) if existing_params.any?
      uri.to_s
    end

    def parse_trends_from_html(html, max_trends)
      return [] if html.blank?

      doc = Nokogiri::HTML(html)
      titles = []

      doc.css("[data-term]").each do |el|
        term = el["data-term"].to_s.strip
        next if term.blank? || term.length < 3

        titles << term
        break if titles.length >= max_trends
      end

      if titles.empty?
        doc.css(".mZ3RIc, .QNIh4d, a[title]").each do |el|
          text = (el["title"] || el.text).to_s.strip
          next if text.blank? || text.length < 3 || text.length > 120

          titles << text unless titles.include?(text)
          break if titles.length >= max_trends
        end
      end

      titles
    end

    def extract_trends_via_ai(html, max_trends)
      doc = Nokogiri::HTML(html)
      table_html = doc.css("table").select { |t| trend_table?(t) }.map(&:to_html).join("\n")
      return [] if table_html.blank?

      prompt = <<~PROMPT
        Read the Google Trends HTML table below and return structured trend topics.

        Requirements:
        - Parse the table rows and their related breakdown keywords.
        - Merge related keywords under one common topic.
        - Remove UI noise, timestamps, search counts, and duplicate rows.
        - Keep topic names short, clear, and human-readable.

        Return valid JSON only in this format:
        {
          "topics": [
            {
              "name": "Common Topic",
              "keywords": ["keyword one", "keyword two"]
            }
          ]
        }

        Constraints:
        - Return at most #{max_trends} topics.
        - Each keyword should belong to only one best topic.
        - Do not include explanations or markdown fences.

        HTML table:
        #{table_html}
      PROMPT

      response = @ai_client.call(prompt, response_mime_type: "application/json")
      parse_ai_topics(response, max_trends)
    rescue StandardError => e
      Rails.logger.warn("TrendDiscovery::GoogleTrendsClient: AI table extraction failed: #{e.message}")
      []
    end

    def trend_table?(table)
      table.css("tbody tr").any? &&
        (table.css("[data-term], .mZ3RIc, .QNIh4d, a[title]").any? || table.text.downcase.include?("searches"))
    end

    def parse_ai_topics(response, max_trends)
      return [] if response.blank?

      payload = response.to_s.strip
      payload = payload.sub(/\A```(?:json)?\s*\n/, "").sub(/\n\s*```\s*\z/, "").strip
      json = JSON.parse(payload)
      topics = json["topics"]
      return [] unless topics.is_a?(Array)

      seen = Set.new
      topics.first(max_trends).filter_map do |topic|
        name = TrendRunHistory.clean(topic["name"].to_s)
        slug = TrendRunHistory.slugify(name)
        next if name.blank? || slug.blank? || seen.include?(slug)

        seen.add(slug)
        keywords = [name]
        if topic["keywords"].is_a?(Array)
          keywords += topic["keywords"].filter_map { |k| TrendRunHistory.clean(k.to_s).presence }
        end
        { name: name, slug: slug, keywords: keywords.uniq }
      end
    rescue JSON::ParserError => e
      Rails.logger.warn("TrendDiscovery::GoogleTrendsClient: Failed to parse AI topics JSON: #{e.message}")
      []
    end
  end
end
