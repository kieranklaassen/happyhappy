require "test_helper"

class Classification::ClassifierTest < ActiveSupport::TestCase
  ENDPOINT = "https://api.typesafe.ai/v1/systemone".freeze

  setup do
    @previous_key = RubyLLM.config.typesafe_api_key
    @previous_retries = RubyLLM.config.max_retries
    RubyLLM.config.typesafe_api_key = "test-typesafe-key"
    RubyLLM.config.max_retries = 0
  end

  teardown do
    RubyLLM.config.typesafe_api_key = @previous_key
    RubyLLM.config.max_retries = @previous_retries
  end

  test "sends the message with the thread before it as structured state and returns the parsed answers" do
    request_body = nil
    stub_request(:post, ENDPOINT)
      .with(headers: { "Authorization" => "Bearer test-typesafe-key" }) { |request| request_body = JSON.parse(request.body) }
      .to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: file_fixture("typesafe/systemone_angry_cora.json").read
    )
    message = messages(:unclassified_slack_reply)

    answers = Classification::Classifier.new.call(message)

    assert_equal "cora", answers.dig("product", "choice")
    assert_in_delta 0.99, answers.dig("anger", "noul")
    assert_equal "jev-latest", request_body["model"]
    assert_equal(
      {
        "source" => { "kind" => "slack", "name" => "Every community Slack", "usually_about" => "Cora" },
        "earlier_in_thread" => [ { "author" => "Ana Customer", "text" => messages(:angry_slack_first).body } ],
        "message" => { "author" => "Ana Customer", "text" => "Still nothing. Anyone from Every here?" }
      },
      request_body["state"]
    )
    assert_equal Classification::SchemaBuilder.call(ask_author_role: true).questions, request_body["questions"]
  end

  test "labels earlier authors by role, keeps the first message, and asks about authorship only when unknown" do
    request_body = nil
    stub_request(:post, ENDPOINT).to_return do |request|
      request_body = JSON.parse(request.body)
      { status: 200, headers: { "Content-Type" => "application/json" },
        body: file_fixture("typesafe/systemone_angry_cora.json").read }
    end
    item = items(:angry_slack)
    item.messages.first.update!(author_role: "customer")
    replies = (1..Classification::Classifier::CONTEXT_MESSAGES + 1).map do |index|
      item.messages.create!(source: item.source, external_id: "reply-#{index}", body: "Reply #{index}",
        occurred_at: (30 - index).minutes.ago, author_role: index.even? ? "team" : "customer")
    end
    latest = item.messages.create!(source: item.source, external_id: "latest", body: "Thanks, fixed!",
      occurred_at: Time.current, author_role: "customer")

    Classification::Classifier.new.call(latest)

    earlier = request_body.dig("state", "earlier_in_thread")
    assert_equal item.messages.first.body, earlier.first["text"]
    assert_equal "customer", earlier.first["role"]
    assert_equal Classification::Classifier::CONTEXT_MESSAGES + 1, earlier.size
    assert_equal replies.last.body, earlier.last["text"]
    assert_includes earlier.map { |entry| entry["role"] }, "Every team"
    refute request_body["questions"].key?("team_author")
  end

  test "a provider failure raises a RubyLLM error for the job to retry" do
    stub_request(:post, ENDPOINT).to_return(
      status: 500,
      headers: { "Content-Type" => "application/json" },
      body: { detail: { message: "internal error" } }.to_json
    )

    assert_raises(RubyLLM::ServerError) { Classification::Classifier.new.call(messages(:unclassified_slack_reply)) }
  end
end
