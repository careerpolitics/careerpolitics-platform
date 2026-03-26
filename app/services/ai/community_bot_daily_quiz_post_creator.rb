module Ai
  class CommunityBotDailyQuizPostCreator
    VERSION = "1.3"
    PostResult = Struct.new(:title, :body, :tags, keyword_init: true)

    def initialize(ai_context:, additional_instructions: nil, tags: nil, ai_client: nil, affected_user: nil)
      @ai_context = ai_context
      @additional_instructions = additional_instructions
      @tags = normalize_tags(tags)
      @ai_client = ai_client || Ai::Base.new(wrapper: self, affected_user: affected_user)
    end

    def generate
      return if ai_context.blank?

      Rails.logger.info("Ai::CommunityBotDailyQuizPostCreator: generation started (context_length=#{ai_context.length}, fixed_tags=#{tags.presence || 'none'})")

      response = ai_client.call(build_prompt)
      result = parse_response(response)

      Rails.logger.info("Ai::CommunityBotDailyQuizPostCreator: generation completed (title=#{result&.title.inspect}, tags=#{result&.tags || []})")
      result
    rescue StandardError => e
      Rails.logger.error("Community bot daily quiz generation failed: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end

    private

    attr_reader :ai_context, :additional_instructions, :tags, :ai_client

    def build_prompt
      additional_section = additional_instructions.present? ? "\nAdditional instructions:\n#{additional_instructions.strip}\n" : ""
      tags_section = if tags.present?
                       "Use these tags exactly (comma-separated, maximum 4 tags): #{tags.join(', ')}"
                     else
                       "Generate 1-4 relevant tags (comma-separated) for the post"
                     end

      <<~PROMPT
        You are writing a DAILY current-affairs quiz post for a community bot.

        Use this AI context as the primary instruction set. If it specifies structure or formatting, follow it strictly:
        #{ai_context}
        #{additional_section}

        Return your response in this exact format:
        TITLE: <post title>
        TAGS: <comma-separated tags>
        BODY: <markdown body>

        Requirements:
        - Keep the content exam-oriented, concise, informative, and useful for the community.
        - BODY must be valid markdown.
        - #{tags_section}.
        - Do not include any extra wrapper text outside TITLE/TAGS/BODY.
      PROMPT
    end

    def parse_response(response)
      return if response.blank?

      title_match = response.match(/TITLE:\s*(.+?)(?:\n|$)/i)
      tags_match = response.match(/TAGS:\s*(.+?)(?:\n|$)/i)
      body_match = response.match(/BODY:\s*(.+)/im)

      title = title_match ? title_match[1].strip : "Community Update"
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
