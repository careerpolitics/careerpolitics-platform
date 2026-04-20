module TrendDiscovery
  class HeadlineEnricher
    REQUEST_TIMEOUT = 5
    MAX_CONTENT_LENGTH = 4_000
    USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".freeze

    def enrich(headlines)
      return [] if headlines.blank?

      headlines.map { |headline| enrich_headline(headline) }
    end

    private

    def enrich_headline(headline)
      return headline if headline[:link].blank?

      begin
        response = HTTParty.get(
          headline[:link],
          headers: { "User-Agent" => USER_AGENT },
          timeout: REQUEST_TIMEOUT,
          follow_redirects: true,
          )

        return headline unless response.success?

        doc = Nokogiri::HTML(response.body)
        details = extract_details(doc, headline)

        Rails.logger.info(
          "TrendDiscovery::HeadlineEnricher: Enriched headline for source='#{headline[:source]}' url='#{headline[:link]}' mediaType=#{details[:media_type]}",
          )

        headline.merge(article_details: details)
      rescue StandardError => e
        Rails.logger.warn("TrendDiscovery::HeadlineEnricher: Unable to enrich headline for url='#{headline[:link]}': #{e.message}")
        headline
      end
    end

    def extract_details(doc, headline)
      description = first_non_blank(
        meta_content(doc, "meta[property='og:description']"),
        meta_content(doc, "meta[name='twitter:description']"),
        meta_content(doc, "meta[name='description']"),
        headline[:summary],
        )

      media_urls = collect_media_urls(doc, headline)
      media_type = infer_media_type(media_urls.first, doc)
      content = extract_content(doc)

      {
        description: description,
        content: content,
        media_urls: media_urls,
        media_type: media_type,
      }
    end

    def meta_content(doc, selector)
      el = doc.at_css(selector)
      return nil unless el

      value = el["content"].to_s.strip
      value.present? ? value : nil
    end

    def collect_media_urls(doc, headline)
      candidates = []

      candidates << meta_content(doc, "meta[property='og:image']")
      candidates << meta_content(doc, "meta[name='twitter:image']")
      candidates << meta_content(doc, "meta[itemprop='image']")
      candidates << meta_content(doc, "meta[property='og:video']")
      candidates << meta_content(doc, "meta[property='og:video:url']")
      candidates << iframe_source(doc)

      doc.css("img[src^='http'], source[src^='http'], video[src^='http']").each do |el|
        url = el["src"].to_s.strip
        candidates << url if supported_media_url?(url)
      end

      if headline.dig(:article_details, :media_urls).present?
        candidates.concat(headline[:article_details][:media_urls])
      end

      candidates << headline[:media_url] if headline[:media_url].present?

      sanitize_media_urls(candidates)
    end

    def iframe_source(doc)
      el = doc.at_css("iframe[src*='youtube.com'], iframe[src*='youtu.be'], iframe[src*='player.vimeo.com']")
      return nil unless el

      src = el["src"].to_s.strip
      src.present? ? src : nil
    end

    def extract_content(doc)
      paragraphs = Set.new
      doc.css("article p, main p, body p").each do |p|
        text = p.text.strip
        next if text.length < 40

        paragraphs.add(text)
        break if paragraphs.size >= 8
      end

      joined = paragraphs.to_a.join("\n\n")
      joined.length <= MAX_CONTENT_LENGTH ? joined : "#{joined[0...MAX_CONTENT_LENGTH]}..."
    end

    def infer_media_type(media_url, doc)
      return nil if media_url.blank?

      url = media_url.downcase
      return "youtube" if url.include?("youtube.com") || url.include?("youtu.be")
      return "gif" if url.end_with?(".gif") || url.include?(".gif?")
      return "video" if url.end_with?(".mp4") || url.include?(".mp4?") || doc.at_css("meta[property='og:video'], video[src]")

      "image"
    end

    def supported_media_url?(url)
      return false if url.blank?

      lower = url.downcase
      lower.end_with?(".png", ".jpg", ".jpeg", ".webp", ".gif", ".mp4", ".mp3") ||
        lower.include?("youtube.com") || lower.include?("youtu.be")
    end

    def sanitize_media_urls(candidates)
      seen = Set.new
      candidates.each_with_object([]) do |url, result|
        trimmed = url.to_s.strip
        next if trimmed.blank? || trimmed.start_with?("data:") || seen.include?(trimmed)

        seen.add(trimmed)
        result << trimmed
      end
    end

    def first_non_blank(*values)
      values.find { |v| v.present? }
    end
  end
end
