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
      "complaint" => "Unhappy about something: a problem, a failure, a charge, or a letdown. Sarcastic praise " \
        "(\"great, charged twice\") is a complaint. A polite request alone is not.",
      "praise" => "Happy about something: thanks, compliments, or a success story, with no earlier upset in the thread.",
      "question" => "Asking how something works, for help, or for something to be done (a refund, a cancellation, " \
        "a discount, an account change), without clear frustration.",
      "neutral" => "None of the above, such as an observation, an announcement, small talk, or an acknowledgement " \
        "with no ask.",
      "relieved" => "Was upset earlier in this thread and the latest message shows the problem is resolved and " \
        "they are satisfied now."
    }.freeze

    # Where the stored category descriptions leave room for doubt, these say
    # what else belongs and what goes elsewhere. Categories are keyed by name.
    CATEGORY_RULES = {
      "bug" => { not_for: "Slowness or lag (performance), or a missing capability (feature request)." },
      "performance" => { includes: "Delays before capture, lag, unresponsive taps, or timeouts." },
      "how-to" => { includes: "Asking where to find something (a link, a setting, a community, an event) or " \
        "whether a feature exists.", not_for: "Something that is broken (bug)." },
      "feature request" => { includes: "Asking for access to an unreleased product, or support for another " \
        "platform, even when later thanked." },
      "pricing and plans" => { includes: "Discounts for students, educators, nonprofits, or people between jobs." },
      "content feedback" => { includes: "Newsletter delivery and how often emails arrive." },
      "cancellation" => { includes: "Saying they are close to turning it off or reconsidering paying." },
      "other" => { not_for: "Anything a more specific category covers; pick other last." }
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
          instructions: {
            question: "What is the customer's current sentiment, as of this message?",
            focus: "When a message mixes tones, pick the one that drives it: a bug report wrapped in compliments " \
              "is a complaint or a question. A bare \"ok\" or \"any update?\" keeps the stance of the " \
              "customer's last substantive message.",
            context: CONTEXT
          },
          criteria: SENTIMENTS
        s.noul :anger,
          instructions: { question: "Is the customer angry right now, as of this message?", context: CONTEXT },
          criteria: {
            true => "Clearly angry, furious, or fed up: hostile words, threats to dispute a charge or leave in " \
              "anger, \"scam\", \"ridiculous\", or exasperated repeated chasing.",
            false => "Calm, polite, disappointed, mildly annoyed, neutral, or happy. Asking for a refund or to " \
              "cancel is not anger by itself, and anger earlier in the thread does not count once they are satisfied."
          }
        s.noul :actionable,
          instructions: {
            question: "Does this thread need someone at Every to act or reply now?",
            context: "Judge the thread as it stands at `message`, the latest message; `earlier_in_thread` holds what came before."
          },
          criteria: {
            true => "A customer is blocked by a bug, was charged wrongly, wants to cancel or get a refund, is angry, " \
              "or is still waiting on an answer to a real question or request.",
            false => "Nothing for Every to do: spam, pitches, automated mail, small talk, praise, plain thanks, " \
              "an opinion with no ask, or a thread the customer says is resolved."
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
      criteria = @categories.to_h do |category|
        rules = CATEGORY_RULES[category.name]
        [ category.name, rules ? { what: category.description.presence, **rules }.compact : category.description.presence ]
      end
      criteria[OTHER_CATEGORY] ||= "Fits none of the categories above."
      criteria
    end
  end
end
