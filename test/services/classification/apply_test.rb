require "test_helper"

class Classification::ApplyTest < ActiveSupport::TestCase
  test "canned answers set product, category, sentiment, anger, and relevance on the item" do
    item = new_item
    message = add_message(item)

    classify(message, product: "spiral", product_probability: 0.91, category: "billing", category_probability: 0.8,
      sentiment: "praise", sentiment_probability: 0.77, anger: 0.3, relevant: 0.96)

    item.reload
    assert_equal products(:spiral), item.product
    assert_equal categories(:billing), item.category
    assert item.praise?
    assert_in_delta 0.91, item.product_probability
    assert_in_delta 0.8, item.category_probability
    assert_in_delta 0.77, item.sentiment_probability
    assert_in_delta 0.3, item.anger_probability
    assert_in_delta 0.96, item.relevance_probability
    assert item.relevant?
    refute item.needs_review?

    message.reload
    assert message.classified?
    assert_nil message.classification_error
    assert_in_delta 0.3, message.anger_probability
    assert_equal "spiral", message.classification_answers.dig("product", "choice")

    event = item.events.last
    assert event.classified?
    assert_equal message.id, event.data["message_id"]
    assert_equal products(:spiral).id, event.data["product_id"]
  end

  test "AE2: a product probability of 0.45 keeps the best guess and flags review" do
    item = new_item(product: nil)

    classify(add_message(item), product: "cora", product_probability: 0.45)

    item.reload
    assert_equal products(:cora), item.product
    assert_in_delta 0.45, item.product_probability
    assert item.needs_review?
  end

  test "AE3: a low relevance answer marks the item not relevant and keeps it out of the relevant feed" do
    item = new_item(source: sources(:intercom_inbox), product: nil)

    classify(add_message(item, body: "anyone up for lunch?"), relevant: 0.08, product: "none",
      product_probability: 0.95, category: "other", sentiment: "neutral", anger: 0.0)

    item.reload
    refute item.relevant?
    assert_nil item.product
    assert_equal categories(:other), item.category
    refute item.needs_review?
    assert_nil item.anger_probability
    refute_includes Item.relevant, item
  end

  test "a none product falls back to the source's default product with its probability" do
    item = new_item(product: nil)
    answers = FakeClassifier.answers(product: "none", product_probability: 0.7)
    answers["product"]["probabilities"]["cora"] = 0.3

    Classification::Apply.call(message: add_message(item), answers: answers)

    item.reload
    assert_equal products(:cora), item.product
    assert_in_delta 0.3, item.product_probability
    assert item.needs_review?
  end

  test "a human-set product is not replaced by a new classification" do
    item = new_item(product: products(:sparkle), product_human_set: true, product_probability: nil)

    classify(add_message(item), product: "spiral", product_probability: 0.3)

    item.reload
    assert_equal products(:sparkle), item.product
    assert_nil item.product_probability
    refute item.needs_review?
  end

  test "a human-set relevance and sentiment survive a new classification" do
    item = new_item(relevant: true, relevant_human_set: true, sentiment: "question", sentiment_human_set: true)

    classify(add_message(item), relevant: 0.1, sentiment: "complaint")

    item.reload
    assert item.relevant?
    assert item.question?
  end

  test "an off-topic reply on an angry product thread keeps the item relevant with the last relevant labels" do
    item = new_item
    classify(add_message(item, at: 10.minutes.ago), product: "cora", category: "bug", sentiment: "complaint", anger: 0.9)

    classify(add_message(item, body: "brb, lunch"), relevant: 0.1, product: "none", category: "other",
      sentiment: "neutral", anger: 0.2)

    item.reload
    assert item.relevant?
    assert_equal products(:cora), item.product
    assert_equal categories(:bug), item.category
    assert item.complaint?
    assert_in_delta 0.9, item.anger_probability
  end

  test "an off-topic reply with anger 0.95 on a calm product thread leaves item anger unchanged and posts no escalation" do
    item = new_item
    classify(add_message(item, at: 10.minutes.ago), sentiment: "praise", category: "praise", anger: 0.1)

    assert_no_difference -> { Escalation.count } do
      classify(add_message(item, body: "this traffic makes me furious"), relevant: 0.1, product: "none", anger: 0.95)
    end

    item.reload
    assert_in_delta 0.1, item.anger_probability
    assert item.praise?
    assert_operator item.anger_probability, :<, products(:cora).effective_escalation_threshold
  end

  test "messages from before the last status change no longer count" do
    item = new_item(status_changed_at: 30.minutes.ago)
    classify(add_message(item, at: 1.hour.ago), anger: 0.9, sentiment: "complaint")

    classify(add_message(item, at: 5.minutes.ago), anger: 0.2, sentiment: "question")

    item.reload
    assert_in_delta 0.2, item.anger_probability
    assert item.question?
  end

  test "a message classified late after a status change still labels an item with no open messages" do
    item = new_item(status: "claimed", status_changed_at: 1.minute.ago)

    classify(add_message(item, at: 1.hour.ago), product: "spiral", anger: 0.6)

    item.reload
    assert item.relevant?
    assert_equal products(:spiral), item.product
    assert_in_delta 0.6, item.anger_probability
  end

  private

  def new_item(source: sources(:slack_community), status_changed_at: 1.hour.ago, **attributes)
    Item.create!(source: source, thread_key: SecureRandom.hex(6), status_changed_at: status_changed_at,
      last_message_at: Time.current, product: source.default_product, **attributes)
  end

  def add_message(item, body: "Cora lost my drafts again.", at: Time.current)
    item.messages.create!(source: item.source, external_id: SecureRandom.hex(6), body: body, occurred_at: at,
      created_at: at)
  end

  def classify(message, **answers)
    Classification::Apply.call(message: message, answers: FakeClassifier.answers(**answers))
  end
end
