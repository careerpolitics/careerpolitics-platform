module MockExams
  class TranslatePoolService
    BATCH_SIZE = 10

    def initialize(template, ai_client: nil)
      @template = template
      @ai_client = ai_client || Ai::Base.new(
        model: Ai::Base::DEFAULT_LITE_MODEL,
        )
    end

    def call
      untranslated = @template.pool_questions.where(text_hi: nil)
      total = untranslated.count
      translated = 0

      untranslated.find_in_batches(batch_size: BATCH_SIZE) do |batch|
        translate_batch(batch)
        translated += batch.size
        Rails.logger.info(
          "MockExams::TranslatePoolService: #{translated}/#{total} translated for template #{@template.id}",
          )
      end

      translated
    end

    private

    def translate_batch(questions)
      texts_to_translate = questions.map do |q|
        {
          id: q.id,
          question_text: q.question_text,
          explanation: q.explanation,
          options: q.options.map { |opt| {key: opt["key"], text: opt["text"]}},

        }
      end

      prompt = build_translation_prompt(texts_to_translate)

      begin
        response = @ai_client.call(prompt, response_mime_type: "application/json")
        parsed = JSON.parse(response)

        parsed.each do |translation|
          question = questions.find { |q| q.id == translation["id"] }
          next unless question

          translated_options = question.options.map do |opt|
            hi_opt = (translation["options_hi"] || []).find{ |o| o["key"] == opt["key"]}
            hi_opt ? opt.merge("text_hi" => hi_opt["text_hi"]) : opt
          end

          question.update_columns( # rubocop:disable Rails/SkipsModelValidations
            text_hi: translation["question_text_hi"],
            explanation_hi: translation["explanation_hi"],
            options: translated_options
            )
        end
      rescue StandardError => e
        Rails.logger.error("MockExams::TranslatePoolService: Translation batch failed — #{e.message}")
      end
    end

    def build_translation_prompt(texts)
      <<~PROMPT
        Translate the following exam questions and explanations from English to Hindi.
        Maintain all technical terms, mathematical notation ($...$), and formatting.
        Do NOT translate proper nouns, abbreviations, or LaTeX math.

        Input JSON:
        #{texts.to_json}

        Return a JSON array with the same structure, adding:
        - question_text_hi (Hindi translation of question_text)
        - explanation_hi (Hindi translation of explanation)
        - options_hi (array of {"key": "A", "text_hi": "Hindi translation"} for each option)
        Keep the original "id" field for mapping.
      PROMPT
    end
  end
end
