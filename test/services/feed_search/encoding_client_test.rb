require "test_helper"

class FeedSearch::EncodingClientTest < ActiveSupport::TestCase
  include TrufflerHelper

  # Answers the way live Jev does: every word a keyword.
  def jev(intents: {}, options: {})
    truffler_fake(intents: intents, options: options)
  end

  def encode(query, inner)
    encoder = Truffler::QueryEncoding::Encoder.new(client: FeedSearch::EncodingClient.new(inner))
    q = Truffler::Search::Query.new(query)
    request = encoder.request(Item, q, tenant_key: nil)
    answers = encoder.client.ask(state: request.state, questions: request.questions, priority: :encode)
    encoder.encoding_for(Item, request, answers, tenant_key: nil)
  end

  test "words that name an applied label become label terms and stopwords filler, so only text words stay required" do
    inner = jev(intents: { "anger" => "filter", "product" => "filter", "category" => "filter" },
      options: { "product" => "cora", "category" => "billing" })

    encoding = encode("angry cora billing for my invoice", inner)

    assert_equal %w[angry cora billing], encoding.label_term_tokens
    assert_equal %w[invoice], encoding.keywords(Truffler::Search::Query.new("angry cora billing for my invoice"))
  end

  test "a word naming a label Jev did not apply stays a keyword" do
    encoding = encode("needs action on cora", jev(intents: { "needs_action" => "filter" }))

    assert_equal %w[needs action], encoding.label_term_tokens
    assert_equal %w[cora], encoding.keywords(Truffler::Search::Query.new("needs action on cora"))
  end

  test "the product name counts, not only its slug" do
    product = products(:cora)
    product.update!(slug: "cora-mail")

    encoding = encode("cora refunds", jev(intents: { "product" => "filter" }, options: { "product" => "cora-mail" }))

    assert_equal %w[cora], encoding.label_term_tokens
  end

  test "labeling and reranking pass through untouched" do
    inner = Truffler::Clients::Fake.new.answer(:churn_risk, 0.8)
    client = FeedSearch::EncodingClient.new(inner)

    answers = client.ask(state: { "record" => "x" }, questions: { "r001__churn_risk" => { "type" => "noul", "instructions" => "?" } })

    assert_in_delta 0.8, answers.noul("r001__churn_risk")
  end
end
