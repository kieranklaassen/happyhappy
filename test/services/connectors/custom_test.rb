require "test_helper"

class Connectors::CustomTest < ActiveSupport::TestCase
  setup { @source = sources(:cora_app_webhook) }

  test "maps the payload to an inbound message and keeps the whole payload" do
    payload = { "id" => "fb-1", "text" => "Great update", "thread_key" => "t-1", "permalink" => "https://x.test/1",
      "author" => { "name" => "Dana", "handle" => "@dana", "email" => "dana@example.com", "role" => "admin" },
      "metadata" => { "plan" => "pro" } }

    result = Connectors::Custom.call(source: @source, raw_body: payload.to_json)

    message = result.message
    assert_equal "fb-1", message.external_id
    assert_equal "Great update", message.body
    assert_equal payload, message.raw_payload
    item = result.item
    assert_equal [ "custom", "source-#{@source.id}:t-1" ], [ item.source_kind, item.thread_key ]
    assert_equal [ "Dana", "@dana", "dana@example.com" ], [ item.author_name, item.author_handle, item.author_email ]
    assert_equal "https://x.test/1", item.permalink
  end

  test "without an id the external id and thread key come from a hash of the raw body" do
    body = { text: "hello" }.to_json

    result = Connectors::Custom.call(source: @source, raw_body: body)

    assert_equal "sha256:#{Digest::SHA256.hexdigest(body)}", result.message.external_id
    assert_equal "source-#{@source.id}:#{result.message.external_id}", result.item.thread_key
  end

  test "messages sharing a thread key land on one item" do
    first = Connectors::Custom.call(source: @source, raw_body: { id: "a", thread_key: "t", text: "one" }.to_json)
    second = Connectors::Custom.call(source: @source, raw_body: { id: "b", thread_key: "t", text: "two" }.to_json)

    assert_equal first.item, second.item
    assert_equal 2, first.item.messages.count
  end

  test "the same thread key from two custom sources makes two items on their own products" do
    spiral = Source.create!(kind: "custom", name: "Spiral app", selector: "", default_product: products(:spiral))

    cora_result = Connectors::Custom.call(source: @source, raw_body: { id: 1, thread_key: "t", text: "one" }.to_json)
    spiral_result = Connectors::Custom.call(source: spiral, raw_body: { id: 1, thread_key: "t", text: "two" }.to_json)

    assert_not_equal cora_result.item, spiral_result.item
    assert_equal products(:spiral), spiral_result.item.product
    assert_equal "source-#{spiral.id}:t", spiral_result.item.thread_key
  end

  test "a sync duplicate returns the stored labels without classifying again" do
    fake = use_fake_classifier(sentiment: "praise")
    body = { id: "fb-2", text: "Love it" }.to_json

    Connectors::Custom.call(source: @source, raw_body: body, sync: true)
    again = Connectors::Custom.call(source: @source, raw_body: body, sync: true)

    assert_equal 1, fake.calls.size
    assert again.duplicate
    assert_equal "classified", again.to_h[:classification]
    assert_equal "praise", again.to_h.dig(:labels, :sentiment, :value)
  end

  test "labels report each answer's chosen value and its probability" do
    labels = Connectors::Custom.labels(FakeClassifier.answers(category: "billing", category_probability: 0.7, anger: 0.4))

    assert_equal "billing", labels[:category][:value]
    assert_in_delta 0.7, labels[:category][:probability]
    assert_in_delta 0.3, labels[:category][:probabilities]["other"]
    assert_in_delta 0.4, labels[:anger][:probability]
  end
end
