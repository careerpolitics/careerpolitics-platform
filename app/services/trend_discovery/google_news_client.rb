module TrendDiscovery
  class GoogleNewsClient
    GOOGLE_SEARCH_URL = ENV.fetch("GOOGLE_SEARCH_URL", "https://www.google.com/search")

    def initialize(browser_client:)
      @browser = browser_client
    end

    def discover(trend:, geo:, language:, max_news:)
      url = build_url(trend, geo, language)
      Rails.logger.info("TrendDiscovery::GoogleNewsClient: Fetching news for '#{trend}' from #{url}")

      html = @browser.fetch_page(url, news_mode: true)
      return [] if html.blank?

      parse_headlines(html, trend, max_news)
    end

    private

    def build_url(trend, geo, language)
      query = CGI.escape(trend)
      params = ["q=#{query}", "tbm=nws", "udm=14"]
      params << "gl=#{geo}" if geo.present?
      params << "hl=#{language}" if language.present?

      "#{GOOGLE_SEARCH_URL}?#{params.join('&')}"
    end

    def parse_headlines(html, trend, max_news)
      doc = Nokogiri::HTML(html)
      headlines = []

      selectors = ["div.SoaBEf", "div.dbsr", "div.MjjYud g-card", "div.MjjYud"]
      cards = []

      selectors.each do |selector|
        found = doc.css(selector)
        if found.any?
          cards = found
          break
        end
      end

      cards.each do |card|
        headline = extract_headline(card, trend)
        next unless headline

        headlines << headline
        break if headlines.length >= max_news
      end

      if headlines.empty?
        Rails.logger.warn("TrendDiscovery::GoogleNewsClient: No headlines found via card selectors, trying link fallback")
        headlines = extract_headlines_from_links(doc, trend, max_news)
      end

      headlines
    end

    def extract_headline(card, trend)
      title_el = card.at_css("div.n0jPhd, div.mCBkyc, h3, a[role='heading']")
      title = title_el&.text&.strip
      return nil if title.blank?

      link_el = card.at_css("a[href]")
      raw_link = link_el&.[]("href").to_s
      link = resolve_google_redirect(raw_link)

      source_el = card.at_css("div.CEMjEf span, div.NUnG9d span, span.WF4CUc, div.CEMjEf, cite")
      source = source_el&.text&.strip || "Unknown"

      time_el = card.at_css("span.WG9SHc span, div.OSrXXb span, time, span.r0bn4c")
      published_at = time_el&.text&.strip

      summary_el = card.at_css("div.GI74Re, div.Y3v8qd, div.s3v9rd")
      summary = summary_el&.text&.strip

      media_el = card.at_css("img[src^='http'], g-img img[src^='http']")
      media_url = media_el&.[]("src")

      {
        trend: trend,
        title: title,
        link: link,
        source: source,
        published_at: published_at,
        summary: summary,
        media_url: media_url,
        article_details: nil,
      }
    end

    def extract_headlines_from_links(doc, trend, max_news)
      headlines = []
      seen_titles = Set.new

      doc.css("a[href]").each do |link_el|
        heading = link_el.at_css("h3, div[role='heading']")
        next unless heading

        title = heading.text.strip
        next if title.blank? || title.length < 10 || seen_titles.include?(title.downcase)

        seen_titles.add(title.downcase)
        link = resolve_google_redirect(link_el["href"].to_s)

        headlines << {
          trend: trend,
          title: title,
          link: link,
          source: "Unknown",
          published_at: nil,
          summary: nil,
          media_url: nil,
          article_details: nil,
        }

        break if headlines.length >= max_news
      end

      headlines
    end

    def resolve_google_redirect(raw_url)
      return raw_url if raw_url.blank?

      if raw_url.start_with?("/url?")
        parsed = CGI.parse(raw_url.sub("/url?", ""))
        return parsed["q"]&.first || raw_url
      end

      if raw_url.include?("/url?")
        uri = URI.parse(raw_url)
        params = CGI.parse(uri.query.to_s)
        return params["q"]&.first || raw_url
      end

      raw_url
    rescue StandardError
      raw_url
    end
  end
end
