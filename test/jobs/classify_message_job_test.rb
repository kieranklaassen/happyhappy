require "test_helper"

class ClassifyMessageJobTest < ActiveJob::TestCase
  setup do
    @message = messages(:unclassified_slack_reply)
    @item = @message.item
  end

  test "classifies the message with the configured classifier and updates the item" do
    fake = use_fake_classifier(product: "cora", category: "bug", sentiment: "complaint", anger: 0.93)

    ClassifyMessageJob.perform_now(@message)

    assert_equal [ @message ], fake.calls
    assert @message.reload.classified?
    assert_in_delta 0.93, @item.reload.anger_probability
    assert @item.events.last.classified?
  end

  test "publishes item.classified with the item id" do
    use_fake_classifier
    payloads = []
    callback = ->(*, payload) { payloads << payload }

    ActiveSupport::Notifications.subscribed(callback, Item::CLASSIFIED_EVENT) do
      ClassifyMessageJob.perform_now(@message)
    end

    assert_equal [ { item_id: @item.id, message_id: @message.id } ], payloads
  end

  test "an already classified message is not sent to the classifier again" do
    fake = use_fake_classifier

    ClassifyMessageJob.perform_now(messages(:angry_slack_first))

    assert_empty fake.calls
  end

  test "a provider error retries with backoff" do
    use_fake_classifier.fail_with(RubyLLM::ServiceUnavailableError.new("upstream down"))

    assert_enqueued_with(job: ClassifyMessageJob, args: [ @message ]) do
      ClassifyMessageJob.perform_now(@message)
    end
    assert_nil @message.reload.classification_error
  end

  test "after the final attempt the message shows the error and the item stays in the feed" do
    fake = use_fake_classifier.fail_with(RubyLLM::ServerError.new("boom"))

    perform_enqueued_jobs { ClassifyMessageJob.perform_later(@message) }

    assert_equal ClassifyMessageJob::ATTEMPTS, fake.calls.size
    @message.reload
    refute @message.classified?
    assert_equal "RubyLLM::ServerError: boom", @message.classification_error

    event = @item.events.last
    assert event.classification_failed?
    assert_equal @message.id, event.data["message_id"]
    assert_equal ClassifyMessageJob::ATTEMPTS, event.data["attempts"]

    @item.reload
    assert @item.relevant?
    assert @item.status_new?
    assert_includes Item.relevant.unresolved, @item
  end
end
