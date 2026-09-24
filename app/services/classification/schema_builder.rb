module Classification
  # Builds the one TypeSafe request that classifies a message (KTD7): a Noul for
  # relevance, a Choice for product with a none option, a Choice for category
  # with an other option, a Choice for sentiment, and a Noul for anger.
  # Products are keyed by slug and categories by name; retired ones are left out.
  class SchemaBuilder
    NO_PRODUCT = "none"
    OTHER_CATEGORY = "other"

    SENTIMENTS = {
      "complaint" => "Unhappy about something: a problem, a failure, a charge, or a letdown.",
      "praise" => "Happy about something: thanks, compliments, or a success story.",
      "question" => "Asking how something works or for help, without clear frustration.",
      "neutral" => "None of the above, such as an observation, an announcement, or small talk."
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(products: Product.active.ordered, categories: Category.active.ordered)
      @products = products.to_a
      @categories = categories.to_a
    end

    def call
      RubyLLM::Providers::TypeSafe::Schema.new do |s|
        s.noul :relevant,
          instructions: {
            question: "Is this message about one of these products?",
            products: @products.map { |product| product_description(product) }
          },
          criteria: {
            true => "Feedback, a problem, a question, or praise about one of the products.",
            false => "Off topic, such as small talk, or about something else entirely."
          }
        s.choice :product,
          instructions: "Which product is this message about?",
          criteria: product_criteria
        s.choice :category,
          instructions: {
            question: "Which category fits the customer's main point best?",
            focus: "Classify the primary request, not every topic mentioned."
          },
          criteria: category_criteria
        s.choice :sentiment,
          instructions: "What is the customer's sentiment in this message?",
          criteria: SENTIMENTS
        s.noul :anger,
          instructions: "Is the customer angry?",
          criteria: {
            true => "Clearly angry, furious, or fed up.",
            false => "Calm, mildly annoyed, neutral, or happy."
          }
      end
    end

    private

    def product_criteria
      @products.to_h { |product| [ product.slug, product_description(product) ] }
        .merge(NO_PRODUCT => "Not about any of the products above.")
    end

    def product_description(product)
      { name: product.name, what: product.description.presence, also_called: product.hint_words.presence }.compact
    end

    def category_criteria
      criteria = @categories.to_h { |category| [ category.name, category.description.presence ] }
      criteria[OTHER_CATEGORY] ||= "Fits none of the categories above."
      criteria
    end
  end
end
