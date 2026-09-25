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

  test "a claimed item keeps its relevance and labels when an off-topic message arrives after the claim" do
    item = new_item
    classify(add_message(item), product: "spiral", category: "bug", sentiment: "complaint", anger: 0.85, relevant: 0.93)
    assert_equal 1, item.escalations.count
    travel 1.hour
    item.update!(status: "claimed", claimed_by_agent: agents(:cursor), claimed_at: Time.current,
      status_changed_at: Time.current)
    travel 1.hour

    assert_no_difference -> { Escalation.count } do
      classify(add_message(item, body: "anyone up for lunch?"), relevant: 0.05, product: "none", category: "other",
        sentiment: "neutral", anger: 0.9)
    end

    item.reload
    assert item.relevant?
    assert_includes Item.relevant, item
    assert_equal products(:spiral), item.product
    assert_equal categories(:bug), item.category
    assert item.complaint?
    assert_in_delta 0.85, item.anger_probability
    assert_in_delta 0.93, item.relevance_probability
    assert item.events.last.classified?
  end

  test "an in-progress item takes the labels of a relevant message that arrives after the claim" do
    item = new_item(status_changed_at: 2.hours.ago)
    classify(add_message(item, at: 90.minutes.ago), product: "cora", sentiment: "complaint", anger: 0.4)
    item.update!(status: "in_progress", status_changed_at: 1.hour.ago)

    classify(add_message(item), product: "spiral", sentiment: "question", anger: 0.3)

    item.reload
    assert_equal products(:spiral), item.product
    assert item.question?
    assert_in_delta 0.3, item.anger_probability
  end

  test "a new item still becomes not relevant when only off-topic messages are open" do
    item = new_item(status_changed_at: 2.hours.ago)
    classify(add_message(item, at: 90.minutes.ago), anger: 0.4)
    item.update!(status: "handled", status_changed_at: 1.hour.ago)
    item.update!(status: "new", status_changed_at: 30.minutes.ago)

    classify(add_message(item, body: "anyone up for lunch?"), relevant: 0.05, product: "none")

    refute item.reload.relevant?
  end

  test "backfilled history does not change the labels or anger of an item live messages reached" do
    item = new_item(status_changed_at: 2.hours.ago)
    classify(add_message(item, at: 1.hour.ago), product: "cora", category: "bug", sentiment: "question", anger: 0.2)
    item.update!(status: "handled", status_changed_at: 30.minutes.ago)

    old = add_message(item, body: "Spiral billing is a scam", at: 40.days.ago)
    old.update!(backfilled: true, created_at: Time.current)
    classify(old, product: "spiral", category: "billing", sentiment: "complaint", anger: 0.97)

    item.reload
    assert_equal products(:cora), item.product
    assert_equal categories(:bug), item.category
    assert item.question?
    assert_in_delta 0.2, item.anger_probability
    assert old.reload.classified?
  end

  test "an item reached only by backfilled history takes its labels from that history" do
    item = new_item(status_changed_at: Time.current)
    old = add_message(item, at: 40.days.ago)
    old.update!(backfilled: true, created_at: Time.current)

    classify(old, product: "spiral", sentiment: "complaint", anger: 0.7)

    item.reload
    assert_equal products(:spiral), item.product
    assert item.complaint?
    assert_in_delta 0.7, item.anger_probability
  end

  test "the item takes the customer's latest message, not the angriest one: angry then happy is happy now" do
    item = new_item
    classify(add_message(item, body: "This charged me twice. Unacceptable!", at: 10.minutes.ago),
      sentiment: "complaint", anger: 0.9)
    classify(add_message(item, body: "Refund came through, thank you so much!"), sentiment: "relieved",
      sentiment_probability: 0.8, anger: 0.02)

    item.reload
    assert item.relieved?
    assert_in_delta 0.02, item.anger_probability
    assert_equal "relieved", item.mood
    assert_equal %w[furious relieved], item.events.classified.map { |event| event.data["mood"] }
  end

  test "a live thank-you after a backfilled complaint is relief, and a live ok keeps the complaint" do
    item = new_item
    complaint = add_message(item, body: "Charged twice and nobody answers.", at: 2.days.ago)
    complaint.update!(backfilled: true)
    classify(complaint, sentiment: "complaint", anger: 0.6)
    classify(add_message(item, body: "Refund arrived, thanks!"), sentiment: "relieved", anger: 0.0)
    assert item.reload.relieved?

    other = new_item
    old = add_message(other, body: "Brief is broken again.", at: 2.days.ago)
    old.update!(backfilled: true)
    classify(old, sentiment: "complaint", anger: 0.6)
    classify(add_message(other, body: "ok"), sentiment: "neutral", anger: 0.0)
    assert other.reload.complaint?
  end

  test "relief without an earlier upset in the thread is praise" do
    item = new_item
    classify(add_message(item, body: "Love the new Brief!"), sentiment: "relieved", sentiment_probability: 0.5, anger: 0.0)

    item.reload
    assert item.praise?
    assert_in_delta 0.625, item.sentiment_probability
  end

  test "a bare acknowledgement keeps the customer's last substantive stance" do
    item = new_item
    classify(add_message(item, body: "Drafts keep disappearing and nobody answers.", at: 5.minutes.ago),
      sentiment: "complaint", anger: 0.5)
    classify(add_message(item, body: "ok"), sentiment: "neutral", anger: 0.0)

    item.reload
    assert item.complaint?
    assert_in_delta 0.5, item.anger_probability
  end

  test "team messages never set labels or anger" do
    item = new_item
    classify(add_message(item, body: "Brief is late again", at: 5.minutes.ago), sentiment: "complaint", anger: 0.3)
    reply = add_message(item, body: "Kieran from Every: we are furious at ourselves, fix is coming", author_role: "team")
    classify(reply, sentiment: "praise", anger: 0.95, category: "praise")

    item.reload
    assert item.complaint?
    assert_in_delta 0.3, item.anger_probability
    assert_equal categories(:bug), item.category
    assert_equal "team", item.events.last.data["author_role"]
  end

  test "an item where only the team has spoken is not relevant" do
    item = new_item
    classify(add_message(item, body: "Monologue 2.0 is out today!", author_role: "team"), relevant: 0.97, sentiment: "praise")

    item.reload
    refute item.relevant?
    assert_nil item.anger_probability
    refute_includes Item.relevant, item
  end

  test "an unknown author takes the classifier's team_author answer" do
    item = new_item
    staff = add_message(item, body: "Thanks all, shipping a fix tonight. — Kieran from Every", author_role: "unknown")
    customer = add_message(item, body: "Brief never arrives", author_role: "unknown")

    classify(staff, team_author: 0.93)
    classify(customer, team_author: 0.04)

    assert staff.reload.author_team?
    assert customer.reload.author_customer?
    assert_equal Classification::VERSION, customer.classifier_version
  end

  test "a known author keeps its role whatever the classifier says" do
    message = add_message(new_item, author_role: "customer")

    classify(message, team_author: 0.99)

    assert message.reload.author_customer?
  end

  test "actionability comes from the customer's current message and is banded" do
    item = new_item
    classify(add_message(item, body: "Charged twice, refund please", at: 5.minutes.ago), actionable: 0.97)
    assert_equal [ 0.97, "act_now" ], item.reload.values_at(:actionability, :actionability_band)

    classify(add_message(item, body: "Refund arrived, thanks!"), sentiment: "relieved", actionable: 0.05)
    assert_equal [ 0.05, "fyi" ], item.reload.values_at(:actionability, :actionability_band)
    assert_equal "fyi", item.events.last.data["actionability_band"]
  end

  test "spam is noise and scores no higher than its relevance" do
    item = new_item
    classify(add_message(item, body: "Boost your SEO today!"), relevant: 0.1, actionable: 0.8)

    item.reload
    assert_equal "noise", item.actionability_band
    assert_in_delta 0.1, item.actionability
  end

  test "an item where only the team has spoken is noise" do
    item = new_item
    classify(add_message(item, body: "New release is out", author_role: "team"), actionable: 0.9)

    assert_equal [ nil, "noise" ], item.reload.values_at(:actionability, :actionability_band)
  end

  test "quiet applies record backfill events and publish nothing" do
    item = new_item
    message = add_message(item)
    published = []
    subscriber = ActiveSupport::Notifications.subscribe(Item::CLASSIFIED_EVENT) { |event| published << event }

    Classification::Apply.call(message: message, answers: FakeClassifier.answers(anger: 0.99), quiet: true)

    assert_empty published
    assert_equal({ "backfill" => true, "reclassified" => true },
      item.events.last.data.slice("backfill", "reclassified"))
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  private

  def new_item(source: sources(:slack_community), status_changed_at: 1.hour.ago, **attributes)
    Item.create!(source: source, thread_key: SecureRandom.hex(6), status_changed_at: status_changed_at,
      last_message_at: Time.current, product: source.default_product, **attributes)
  end

  def add_message(item, body: "Cora lost my drafts again.", at: Time.current, author_role: "customer")
    item.messages.create!(source: item.source, external_id: SecureRandom.hex(6), body: body, occurred_at: at,
      created_at: at, author_role: author_role)
  end

  def classify(message, **answers)
    Classification::Apply.call(message: message, answers: FakeClassifier.answers(**answers))
  end
end
