module FeedSearch
  # The Jev client truffler uses outside tests. Labeling and reranking pass
  # straight through; query encoding answers are reconciled first.
  #
  # truffler 0.1.0 asks Jev the role of each query word without showing it
  # the labels, so Jev calls nearly every word a keyword, and a keyword must
  # appear in the item's text on top of the label filters. "needs action now"
  # then filters on needs_action and also requires all three words in the
  # text, which finds nothing. Here a keyword that names a label Jev applied
  # (angry -> anger, cora -> product "cora") becomes a label term, and a
  # stopword becomes filler, so only words meant as text stay required.
  class EncodingClient < Truffler::Clients::Base
    STOPWORDS = %w[
      a about all an and any are at be by for from have i in is it me my now of on or our please so some that the their
      them there they this to up us was we what when where which who why with you your
    ].to_set.freeze
    STEM = 3

    def initialize(inner = Truffler::Clients::RubyLLMTypeSafe.new)
      @inner = inner
    end

    def perform(state:, questions:, model:)
      response = @inner.perform(state: state, questions: questions, model: model).to_h.deep_stringify_keys
      response = { "answers" => response } unless response.key?("answers")
      return response unless questions.keys.any? { |id| id.to_s.start_with?("token__") }

      response.merge("answers" => reconcile(response["answers"], state))
    end

    private

    def reconcile(answers, state)
      terms = applied_terms(answers)
      tokens = Array(state["tokens"] || state[:tokens])
      answers.to_h do |id, answer|
        next [ id, answer ] unless id.start_with?("token__") && answer["choice"] == "keyword"

        word = tokens[id.delete_prefix("token__").to_i].to_s.downcase
        role = if STOPWORDS.include?(word) then "filler"
        elsif terms.any? { |term| names?(word, term) } then "label_term"
        end
        [ id, role ? answer.merge("choice" => role, "probabilities" => { role => 1.0 }, "confidence" => 1.0) : answer ]
      end
    end

    def applied_terms(answers)
      Item.truffler_definition.labels.values.flat_map do |label|
        next [] unless %w[filter boost].include?(answers.dig("intent__#{label.question_key}", "choice"))

        option = answers.dig("option__#{label.question_key}", "choice") if label.type == :choice
        [ label.key.to_s, option.to_s, option_name(label, option) ].flat_map { |text| text.downcase.scan(/\p{Alnum}+/) }
      end.uniq
    end

    # Product options are slugs; people type the product's name.
    def option_name(label, option)
      label.key == :product && option.present? ? Product.find_by(slug: option)&.name.to_s : ""
    end

    # "angry" names "anger", "cora" names "cora": the same word, or two words
    # of four letters or more that share their first letters.
    def names?(word, term)
      word == term || (word.length > STEM && term.length > STEM && word[0, STEM] == term[0, STEM])
    end
  end
end
