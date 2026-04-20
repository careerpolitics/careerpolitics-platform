module TrendDiscovery
  class GoogleTrendsClient
    GOOGLE_TRENDS_URL = ENV.fetch("GOOGLE_TRENDS_URL", "https://trends.google.com/trending")
    FALLBACK_TRENDS = ENV.fetch("TRENDING_FALLBACK_TRENDS", "").split(",").map(&:strip).reject(&:blank?).freeze

    def initialize(browser_client:)
      @browser = browser_client
    end

    def discover(geo:, language:, max_trends:)
      url = build_url(geo, language)
      Rails.logger.info("TrendDiscovery::GoogleTrendsClient: Fetching trends from #{url}")

      titles = @browser.fetch_trend_titles(url, max_trends: max_trends)

      if titles.blank?
        Rails.logger.warn("TrendDiscovery::GoogleTrendsClient: Selenium returned no trends, trying HTML parse fallback")
        html = @browser.fetch_page(url)
        titles = parse_trends_from_html(html, max_trends) if html.present?
      end

      if titles.blank? && FALLBACK_TRENDS.any?
        Rails.logger.warn("TrendDiscovery::GoogleTrendsClient: Using fallback trends")
        titles = FALLBACK_TRENDS.first(max_trends)
      end

      titles.map do |title|
        cleaned = TrendRunHistory.clean(title)
        slug = TrendRunHistory.slugify(cleaned)
        { name: cleaned, slug: slug, keywords: [cleaned] }
      end
    end

    private

    def build_url(geo, language)
      params = []
      params << "geo=#{geo}" if geo.present?
      params << "hl=#{language}" if language.present?

      if params.any?
        "#{GOOGLE_TRENDS_URL}?#{params.join('&')}"
      else
        GOOGLE_TRENDS_URL
      end
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
  end
end
