module Classification
  # Asks TypeSafe Jev about one message and returns the parsed answers hash
  # described on the Classification module.
  class Classifier
    MODEL = "jev-latest"

    def call(message)
      RubyLLM.chat(model: MODEL, provider: :typesafe)
        .with_schema(SchemaBuilder.call)
        .ask(state_for(message).to_json)
        .parsed
    end

    private

    def state_for(message)
      item = message.item
      {
        source: { kind: message.source.kind, name: message.source.name },
        author: { handle: item.author_handle, name: item.author_name }.compact,
        message: message.body
      }
    end
  end
end
