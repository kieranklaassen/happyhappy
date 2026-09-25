module Classification
  # Builds the one TypeSafe request that classifies a message (KTD7): a Noul for
  # relevance, a Choice for product with a none option, a Choice for category
  # with an other option, a Choice for sentiment, and a Noul for anger. When the
  # author is unknown it also asks a Noul for whether Every's team wrote it.
  # Products are keyed by slug and categories by name; retired ones are left out.
  class SchemaBuilder
    NO_PRODUCT = "none"
    OTHER_CATEGORY = "other"

    CONTEXT = "Answer about `message`, the latest message. `earlier_in_thread` is only context for reading it."

    SENTIMENTS = {
      "complaint" => "Unhappy about something: a problem, a failure, a charge, or a letdown.",
      "praise" => "Happy about something: thanks, compliments, or a success story.",
      "question" => "Asking how something works or for help, without clear frustration.",
      "neutral" => "None of the above, such as an observation, an announcement, or small talk.",
      "relieved" => "Was upset earlier in this thread and the latest message shows the problem is resolved and they are satisfied now."
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(products: Product.active.ordered, categories: Category.active.ordered, ask_author_role: false)
      @products = products.to_a
      @categories = categories.to_a
      @ask_author_role = ask_author_role
    end

    def call
      RubyLLM::Providers::TypeSafe::Schema.new do |s|
        s.noul :relevant,
          instructions: {
            question: "Is this a customer writing about one of these products or their Every account?",
            context: CONTEXT,
            products: @products.map { |product| product_description(product) }
          },
          criteria: {
            true => "Feedback, a problem, a question, a request (billing, refunds, discounts, cancelling, " \
              "or account changes), or praise about one of the products or the customer's Every subscription.",
            false => "Not a customer talking about the products: spam; sales, partnership, press, sponsorship, " \
              "or job pitches; automated notifications or newsletters (Notion, Google Docs, calendar invites, " \
              "auto-replies); or general AI and community chat that is not about one of the products."
          }
        s.choice :product,
          instructions: { question: "Which product is this message about?", context: CONTEXT },
          criteria: product_criteria
        s.choice :category,
          instructions: {
            question: "Which category fits the customer's main point in this thread best?",
            focus: "Classify the primary request, not every topic mentioned. A thank-you, a follow-up, or " \
              "\"any update?\" takes the category of the request it follows up on; praise is only for a " \
              "thread with no problem or request. A question about how to do something is how-to, not other.",
            context: "`message` is the latest message and `earlier_in_thread` holds the thread before it; " \
              "together they are the thread."
          },
          criteria: category_criteria
        s.choice :sentiment,
          instructions: { question: "What is the customer's sentiment in this message?", context: CONTEXT },
          criteria: SENTIMENTS
        s.noul :anger,
          instructions: { question: "Is the customer angry?", context: CONTEXT },
          criteria: {
            true => "Clearly angry, furious, or fed up.",
            false => "Calm, mildly annoyed, neutral, or happy."
          }
        author_role_question(s) if @ask_author_role
      end
    end

    private

    def author_role_question(schema)
      schema.noul :team_author,
        instructions: "Is this message written by the company's own staff or support team rather than a customer?",
        criteria: {
          true => "Speaks for Every: announces or explains its products as the maker, answers customers, or signs off as staff (for example, \"— Kieran from Every\").",
          false => "A customer, reader, or community member writing to or about Every."
        }
    end

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
