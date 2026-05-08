require "cgi"
require "uri"

module Ai
  class CommunityBotPibAnnouncementPostCreator
    VERSION = "2.0"
    FEED_URL = "https://www.pib.gov.in/RssMain.aspx?ModId=6&reg=3&lang=1".freeze
    MAX_FEED_ITEMS = 30
    MAX_SELECTED_ITEMS = 8
    MAX_ARTICLE_CHARS = 3500
    ARTICLE_CONTENT_SELECTORS = [
      "#printPreview",
      "#articlebody",
      ".innner-page-main-about-us-content-right-part",
      ".content-area",
      "article"
    ].freeze
    PostResult = Struct.new(:title, :body, :tags, keyword_init: true)

    def initialize(ai_context:, additional_instructions: nil, tags: nil, ai_client: nil, feed_url: FEED_URL,
                   feed_fetcher: HTTParty, affected_user: nil, max_feed_items: MAX_FEED_ITEMS,
                   max_selected_items: MAX_SELECTED_ITEMS)
      @ai_context = ai_context
      @additional_instructions = additional_instructions
      @tags = normalize_tags(tags)
      @feed_url = feed_url
      @feed_fetcher = feed_fetcher
      @max_feed_items = max_feed_items.to_i
      @max_selected_items = max_selected_items.to_i
      @ai_client = ai_client || Ai::Base.new(wrapper: self, affected_user: affected_user)
    end

    def generate
      return if ai_context.blank?

      feed_items = fetch_feed_items
      return if feed_items.blank?

      selected_items = filter_relevant_feed_items(feed_items)
      return if selected_items.blank?

      articles_context = fetch_article_contexts(selected_items)
      return if articles_context.blank?

      Rails.logger.info(
        "Ai::CommunityBotPibAnnouncementPostCreator: generation started " \
          "(feed_items=#{feed_items.length}, selected_items=#{selected_items.length}, " \
          "fixed_tags=#{tags.presence || 'none'})",
        )

      response = ai_client.call(build_summary_prompt(articles_context))
      result = parse_response(response, articles_context: articles_context)

      Rails.logger.info(
        "Ai::CommunityBotPibAnnouncementPostCreator: generation completed " \
          "(title=#{result&.title.inspect}, tags=#{result&.tags || []})",
        )
      result
    rescue StandardError => e
      Rails.logger.error("Community bot PIB announcement generation failed: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end

    private

    attr_reader :ai_context, :additional_instructions, :tags, :ai_client, :feed_url, :feed_fetcher, :max_feed_items, :max_selected_items

    def fetch_feed_items
      response = feed_fetcher.get(feed_url, timeout: 10)
      rss_doc = Nokogiri::XML(response.body.to_s)

      rss_doc.css("channel > item").first(max_feed_items).filter_map do |item_node|
        title = item_node.at_css("title")&.text.to_s.strip
        url = item_node.at_css("link")&.text.to_s.strip
        next if title.blank? || url.blank?

        { title: title, url: url }
      end
    end

    def filter_relevant_feed_items(feed_items)
      response = ai_client.call(build_filter_prompt(feed_items))
      selected_indexes = parse_selected_indexes(response)
      return [] if selected_indexes.blank?

      selected_indexes.filter_map do |index|
        feed_items[index - 1] if index.between?(1, feed_items.length)
      end.first(max_selected_items)
    end

    def build_filter_prompt(feed_items)
      feed_section = feed_items.each_with_index.map do |item, index|
        "#{index + 1}. #{item[:title]} - #{item[:url]}"
      end.join("\n")

      <<~PROMPT
        You are deciding whether PIB RSS items should be included on this platform.

        Platform context:
        #{ai_context}

        RSS items:
        #{feed_section}

        Select only the item numbers that are relevant for this platform's audience.
        Ignore irrelevant, low-value, or duplicate announcements.

        Return ONLY one line in this exact format:
        INCLUDE: <comma-separated item numbers>

        If none are relevant, return:
        INCLUDE: NONE
      PROMPT
    end

    def parse_selected_indexes(response)
      return [] if response.blank?

      include_match = response.match(/INCLUDE:\s*(.+?)\s*$/im)
      return [] unless include_match

      included_value = include_match[1].strip
      return [] if included_value.casecmp("none").zero?

      included_value.split(",").map { |value| value.to_i }.select(&:positive?).uniq
    end

    def fetch_article_contexts(selected_items)
      selected_items.filter_map do |item|
        article_response = feed_fetcher.get(item[:url], timeout: 10)
        article_details = extract_article_details(article_response.body.to_s)
        next if article_details[:body].blank?

        {
          title: article_details[:title].presence || item[:title],
          url: item[:url],
          ministry: article_details[:ministry],
          subtitle: article_details[:subtitle],
          posted_on: article_details[:posted_on],
          release_id: article_details[:release_id],
          content: article_details[:body].truncate(MAX_ARTICLE_CHARS),
          images: article_details[:images],
          social_links: article_details[:social_links]
        }
      rescue StandardError => e
        Rails.logger.error("Failed to fetch PIB article #{item[:url]}: #{e.class} - #{e.message}")
        nil
      end
    end

    def extract_article_details(html)
      doc = Nokogiri::HTML(html)
      root = doc.at_css(".innner-page-main-about-us-content-right-part") || doc

      paragraphs = root.css("p").map { |node| node.text.to_s.squish }.reject(&:blank?)
      body = paragraphs.reject { |text| text == "***" || text.match?(/\A[A-Z]{2,6}\/[A-Z]{2,6}\z/) }.join("\n\n")
      body = fallback_article_text(root) if body.blank?

      {
        ministry: root.at_css("#MinistryName")&.text.to_s.squish,
        title: root.at_css("#Titleh2")&.text.to_s.squish,
        subtitle: root.at_css("#Subtitleh3")&.text.to_s.squish,
        posted_on: root.at_css("#PrDateTime")&.text.to_s.squish,
        release_id: root.at_css("#ReleaseId")&.text.to_s.squish,
        body: body,
        images: extract_image_links(root),
        social_links: extract_twitter_links(root)
      }
    end

    def fallback_article_text(root)
      ARTICLE_CONTENT_SELECTORS.each do |selector|
        text = root.css(selector).text.to_s.squish
        return text if text.length >= 200
      end

      body_text = root.at_css("body")&.text.to_s.squish
      return body_text if body_text.length >= 200

      ""
    end

    def extract_image_links(root)
      root.css("p img").map { |img| img["src"].to_s.strip }
          .select { |src| src.present? && src.match?(%r{https?://}) }
          .reject { |src| src.include?("specificdocs/photo") || src.include?("indian-emblem") }
          .uniq.first(6)
    end

    def extract_twitter_links(root)
      root.css("iframe[src*='platform.twitter.com/embed/Tweet']").filter_map do |iframe|
        tweet_id = iframe["data-tweet-id"].presence || extract_tweet_id_from_embed(iframe["src"].to_s)
        next if tweet_id.blank?

        "https://x.com/i/web/status/#{tweet_id}"
      end.uniq.first(6)
    end

    def extract_tweet_id_from_embed(src)
      uri = URI.parse(src)
      CGI.parse(uri.query.to_s)["id"]&.first
    rescue URI::InvalidURIError
      nil
    end

    def build_summary_prompt(articles_context)
      additional_section = if additional_instructions.present?
                             "\nAdditional instructions:\n#{additional_instructions.strip}\n"
                           else
                             ""
                           end
      tags_section = if tags.present?
                       "Use these tags exactly (comma-separated, maximum 4 tags): #{tags.join(', ')}"
                     else
                       "Generate 1-4 relevant tags (comma-separated) for the post"
                     end
      articles_section = articles_context.map.with_index do |article, index|
        <<~ARTICLE
          [#{index + 1}] #{article[:title]}
          URL: #{article[:url]}
          MINISTRY: #{article[:ministry].presence || 'N/A'}
          SUBTITLE: #{article[:subtitle].presence || 'N/A'}
          POSTED_ON: #{article[:posted_on].presence || 'N/A'}
          RELEASE_ID: #{article[:release_id].presence || 'N/A'}
          IMAGE_URLS: #{article[:images].presence&.join(', ') || 'N/A'}
          SOCIAL_LINKS: #{article[:social_links].presence&.join(', ') || 'N/A'}
          CONTENT:
          #{article[:content]}
        ARTICLE
      end.join("\n")

      <<~PROMPT
        You are writing a community bot article from filtered PIB announcements.

        Use this AI context as the primary instruction set. If it specifies structure or formatting, follow it strictly:
        #{ai_context}
        #{additional_section}

        Use the following parsed PIB article content as source material:
        #{articles_section}

        Return your response in this exact format:
        TITLE: <post title>
        TAGS: <comma-separated tags>
        BODY: <markdown body>

        Requirements:
        - BODY must be valid markdown.
        - Format each topic in a card block using this syntax:
          {% card %}
          ### <topic heading>
          <topic summary>
          {% endcard %}
        - Include source links to original PIB URLs inside the relevant card(s).
        - If IMAGE_URLS are available, include markdown images in the relevant card(s).
        - If SOCIAL_LINKS are available, include the links in the relevant card(s).
        - Keep the summary factual and easy to scan.
        - #{tags_section}.
        - Do not include any extra wrapper text outside TITLE/TAGS/BODY.
      PROMPT
    end

    def parse_response(response, articles_context:)
      return if response.blank?

      title_match = response.match(/TITLE:\s*(.+?)(?:\n|$)/i)
      tags_match = response.match(/TAGS:\s*(.+?)(?:\n|$)/i)
      body_match = response.match(/BODY:\s*(.+)/im)

      title = title_match ? title_match[1].strip : "PIB Announcements Update"
      body = body_match ? body_match[1].strip : response.strip
      return if body.blank?

      body = ensure_card_markup(body, articles_context)

      parsed_tags = normalize_tags(tags_match&.captures&.first)
      parsed_tags = tags if parsed_tags.blank? && tags.present?
      parsed_tags = fallback_tags_from_context if parsed_tags.blank?

      PostResult.new(title: title, body: body, tags: parsed_tags)
    end

    def ensure_card_markup(body, articles_context)
      body_with_cards = if body.include?("{% card %}")
                          body
                        else
                          <<~MARKDOWN.strip
                            {% card %}
                            ### PIB Announcement Highlights
                            #{body}
                            {% endcard %}
                          MARKDOWN
                        end

      media_sections = articles_context.filter_map do |article|
        media_lines = []
        media_lines << "![#{article[:title]}](#{article[:images].first})" if article[:images].present?
        media_lines.concat(article[:social_links].map { |link| "- X/Twitter: #{link}" }) if article[:social_links].present?
        next if media_lines.blank?

        <<~CARD.strip
          {% card %}
          ### Media: #{article[:title]}
          #{media_lines.join("\n")}
          {% endcard %}
        CARD
      end

      return body_with_cards if media_sections.blank?

      ([body_with_cards] + media_sections).join("\n\n")
    end

    def fallback_tags_from_context
      context_tags = ai_context.to_s.downcase.scan(/\b[a-z0-9][a-z0-9-]{1,19}\b/)
      stopwords = %w[about after among and are for from has have into not that the their them then they this was with your]
      (context_tags - stopwords).uniq.first(4).presence || ["news"]
    end

    def normalize_tags(raw_tags)
      return [] if raw_tags.blank?

      raw_tags
        .to_s
        .split(",")
        .map { |tag| tag.strip.delete_prefix("#").downcase }
        .reject(&:blank?)
        .uniq
        .first(4)
    end
  end
end
