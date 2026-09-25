module Classification
  # Asks TypeSafe Jev about one message and returns the parsed answers hash
  # described on the Classification module.
  #
  # Jev judges the message in its thread: the state carries the thread's first
  # message and the messages just before this one, so a reply such as "still
  # broken" or "thanks, that fixed it" is read against what it answers.
  class Classifier
    MODEL = "jev-latest"
    CONTEXT_MESSAGES = 8
    CONTEXT_CHARACTERS = 1_200

    def call(message)
      RubyLLM.chat(model: MODEL, provider: :typesafe)
        .with_schema(SchemaBuilder.call(ask_author_role: message.author_unknown?))
        .ask(state_for(message).to_json)
        .parsed
    end

    private

    def state_for(message)
      {
        source: { kind: message.source.kind, name: message.source.name,
                  usually_about: message.source.default_product&.name }.compact,
        earlier_in_thread: earlier(message).map { |earlier| entry(earlier) }.presence,
        message: entry(message, limit: nil)
      }.compact
    end

    def earlier(message)
      thread = message.item.messages.to_a
      before = thread.first(thread.index(message) || 0)
      ([ before.first ] + before.last(CONTEXT_MESSAGES)).compact.uniq
    end

    def entry(message, limit: CONTEXT_CHARACTERS)
      {
        author: message.author_label,
        role: { "team" => "Every team", "customer" => "customer" }[message.author_role],
        text: limit ? message.body.truncate(limit) : message.body
      }.compact
    end
  end
end
