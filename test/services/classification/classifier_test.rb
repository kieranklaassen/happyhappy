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

  test "sends the message with its source and author as structured state and returns the parsed answers" do
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
        "source" => { "kind" => "slack", "name" => "Every community Slack" },
        "author" => { "handle" => "ana_customer", "name" => "Ana Customer" },
        "message" => "Still nothing. Anyone from Every here?"
      },
      request_body["state"]
    )
    assert_equal Classification::SchemaBuilder.call.questions, request_body["questions"]
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
