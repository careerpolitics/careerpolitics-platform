module Ai
  class ContextNoteGenerator
    VERSION = "1.0"
    MIN_NOTE_LENGTH = 10
    MAX_NOTE_LENGTH = 200

    def initialize(article, tag)
      @article = article
      @tag = tag
      @ai_client = Ai::Base.new(wrapper: self, affected_content: article)
    end

    def call
      return unless @article && @tag && @tag.context_note_instructions.present?

      prompt = build_prompt
      response = @ai_client.call(prompt) if prompt.present?

      return if response.blank? || response.strip == "INVALID"

      note_text = normalize_note_text(response)
      return if note_text.blank? || note_text.length < MIN_NOTE_LENGTH

      # Create the context note with the response
      context_note = ContextNote.create!(
        body_markdown: note_text,
        article: @article,
        tag: @tag,
      )
    rescue StandardError => e
      Rails.logger.error("Context Note Generation failed: #{e}")
    end

    def build_prompt
      # tag has context_note_instructions
      # We should generate a context note for the instructions based on the output of what we get from the prompt.
      instructions = @tag.context_note_instructions.strip
      return if instructions.blank?

      <<~PROMPT
        You are an AI assistant that generates context notes for articles.
        The article is titled "#{@article.title}" and has the following content:
        #{@article.body_markdown}

        Based on the above article, please generate a context note that follows these instructions:
        #{instructions}
        Keep the note between #{MIN_NOTE_LENGTH} and #{MAX_NOTE_LENGTH} characters.

        If the article does not fit the valid criteria based on the instructions, return only the word "INVALID" and nothing else.
      PROMPT
    end

    private

    def normalize_note_text(response)
      response.to_s.strip.gsub(/\s+/, " ")[0...MAX_NOTE_LENGTH]
    end
  end
end
