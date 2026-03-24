module Ai
  class CommunityBotPostCreator
    VERSION = "1.0"
    PostResult = Struct.new(:title, :body, keyword_init: true)

    def initialize(ai_context:, additional_instructions: nil, ai_client: nil)
      @ai_context = ai_context
      @additional_instructions = additional_instructions
      @ai_client = ai_client || Ai::Base.new(wrapper: self)
    end

    def generate
      return if ai_context.blank?

      response = ai_client.call(build_prompt)
      parse_response(response)
    rescue StandardError => e
      Rails.logger.error("Community bot post generation failed: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end

    private

    attr_reader :ai_context, :additional_instructions, :ai_client

    def build_prompt
      instructions_section = if additional_instructions.present?
                               "\nAdditional instructions:\n#{additional_instructions.strip}\n"
                             else
                               ""
                             end

      <<~PROMPT
        You are writing a post for a community bot.

        Use the following AI context to generate a high-quality community post:
        #{ai_context}
        #{instructions_section}

        Return your response in this exact format:
        TITLE: <post title>
        BODY: <markdown body>

        Requirements:
        - Keep the response concise, informative, and useful for the community.
        - BODY must be valid markdown.
        - Do not include any extra wrapper text outside TITLE/BODY.
      PROMPT
    end

    def parse_response(response)
      return if response.blank?

      title_match = response.match(/TITLE:\s*(.+?)(?:\n|$)/i)
      body_match = response.match(/BODY:\s*(.+)/im)

      title = title_match ? title_match[1].strip : "Community Update"
      body = body_match ? body_match[1].strip : response.strip
      return if body.blank?

      PostResult.new(title: title, body: body)
    end
  end
end
