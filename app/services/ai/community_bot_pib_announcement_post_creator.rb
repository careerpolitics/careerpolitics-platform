module Ai
  class CommunityBotPibAnnouncementPostCreator
    VERSION = "1.0"
    FEED_URL = "https://www.pib.gov.in/RssMain.aspx?ModId=6&reg=3&lang=1".freeze
    MAX_FEED_ITEMS = 30
    PostResult = Struct.new(:title, :body, :tags, keyword_init: true)

    def initialize(ai_context:, additional_instructions: nil, tags: nil, ai_client: nil, feed_url: FEED_URL,
                   feed_fetcher: HTTParty, affected_user: nil)
      @ai_context = ai_context
      @additional_instructions = additional_instructions
      @tags = normalize_tags(tags)
      @feed_url = feed_url
      @feed_fetcher = feed_fetcher
      @ai_client = ai_client || Ai::Base.new(wrapper: self, affected_user: affected_user)
    end

    def generate
      return if ai_context.blank?

      feed_items = fetch_feed_items
      return if feed_items.blank?

      Rails.logger.info("Ai::CommunityBotPibAnnouncementPostCreator: generation started (feed_items=#{feed_items.length}, fixed_tags=#{tags.presence || 'none'})")

      response = ai_client.call(build_prompt(feed_items))
      result = parse_response(response)

      Rails.logger.info("Ai::CommunityBotPibAnnouncementPostCreator: generation completed (title=#{result&.title.inspect}, tags=#{result&.tags || []})")
      result
    rescue StandardError => e
      Rails.logger.error("Community bot PIB announcement generation failed: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end

    private

    attr_reader :ai_context, :additional_instructions, :tags, :ai_client, :feed_url, :feed_fetcher

    def fetch_feed_items
      response = feed_fetcher.get(feed_url, timeout: 10)
      parsed_feed = Feedjira.parse(response.body.to_s)
      return [] if parsed_feed.blank? || parsed_feed.entries.blank?

      parsed_feed.entries.first(MAX_FEED_ITEMS).filter_map do |item|
        title = item.title.to_s.strip
        url = item.url.to_s.strip
        next if title.blank? || url.blank?

        { title: title, url: url }
      end
    end

    def build_prompt(feed_items)
      additional_section = additional_instructions.present? ? "\nAdditional instructions:\n#{additional_instructions.strip}\n" : ""
      tags_section = if tags.present?
                       "Use these tags exactly (comma-separated, maximum 4 tags): #{tags.join(', ')}"
                     else
                       "Generate 1-4 relevant tags (comma-separated) for the post"
                     end
      feed_section = feed_items.each_with_index.map do |item, index|
        "#{index + 1}. #{item[:title]} - #{item[:url]}"
      end.join("\n")

      <<~PROMPT
        You are writing a community bot article from the Press Information Bureau (PIB) RSS feed.

        Use this AI context as the primary instruction set. If it specifies structure or formatting, follow it strictly:
        #{ai_context}
        #{additional_section}

        Here are the latest PIB RSS items (title + URL):
        #{feed_section}

        Task:
        - Select only announcements that are truly relevant and important for a broad public audience.
        - Ignore duplicate, low-signal, or highly niche updates.
        - Write a concise markdown article that summarizes the selected announcements.
        - Include source links from the provided URLs in the article body.

        Return your response in this exact format:
        TITLE: <post title>
        TAGS: <comma-separated tags>
        BODY: <markdown body>

        Requirements:
        - BODY must be valid markdown.
        - Keep the summary factual and easy to scan.
        - #{tags_section}.
        - Do not include any extra wrapper text outside TITLE/TAGS/BODY.
      PROMPT
    end

    def parse_response(response)
      return if response.blank?

      title_match = response.match(/TITLE:\s*(.+?)(?:\n|$)/i)
      tags_match = response.match(/TAGS:\s*(.+?)(?:\n|$)/i)
      body_match = response.match(/BODY:\s*(.+)/im)

      title = title_match ? title_match[1].strip : "PIB Announcements Update"
      body = body_match ? body_match[1].strip : response.strip
      return if body.blank?

      parsed_tags = normalize_tags(tags_match&.captures&.first)
      parsed_tags = tags if parsed_tags.blank? && tags.present?
      parsed_tags = fallback_tags_from_context if parsed_tags.blank?

      PostResult.new(title: title, body: body, tags: parsed_tags)
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
