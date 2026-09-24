require "test_helper"

class WebhookDeliveryJobTest < ActiveJob::TestCase
  include WebhookEndpointHelper

  setup do
    @endpoint = create_webhook_endpoint(events: %w[item.classified])
    @delivery = @endpoint.deliveries.create!(item_event: item_events(:angry_slack_classified), event: "item.classified",
      payload: Webhooks::Payload.for_event(item_events(:angry_slack_classified), "item.classified"))
  end

  test "posts the payload signed with the endpoint secret and records success" do
    stub_request(:post, WEBHOOK_TEST_URL).to_return(status: 204)

    freeze_time do
      WebhookDeliveryJob.perform_now(@delivery)

      assert_requested(:post, WEBHOOK_TEST_URL) do |request|
        assert_equal @delivery.payload, JSON.parse(request.body)
        assert_equal "item.classified", request.headers["X-Happyhappy-Event"]
        assert_equal @delivery.id.to_s, request.headers["X-Happyhappy-Delivery"]
        assert_equal "application/json; charset=utf-8", request.headers["Content-Type"]
        header = request.headers["X-Happyhappy-Signature"]
        assert_match(/\At=#{Time.current.to_i},v1=\h{64}\z/, header)
        assert Webhooks::Signature.verify(@endpoint.secret, request.body, header)
        assert_not Webhooks::Signature.verify("whsec_wrong", request.body, header)
        assert_not Webhooks::Signature.verify(@endpoint.secret, "#{request.body} ", header)
      end
    end

    @delivery.reload
    assert @delivery.succeeded?
    assert_equal 1, @delivery.attempts
    assert_equal 204, @delivery.response_code
    assert_nil @delivery.last_error
    assert_no_enqueued_jobs
  end

  test "a signature older than five minutes no longer verifies" do
    header = Webhooks::Signature.sign(@endpoint.secret, "{}", time: 6.minutes.ago)

    assert_not Webhooks::Signature.verify(@endpoint.secret, "{}", header)
    assert Webhooks::Signature.verify(@endpoint.secret, "{}", Webhooks::Signature.sign(@endpoint.secret, "{}", time: 4.minutes.ago))
  end

  test "a 500 response retries with backoff and records the last error" do
    stub_request(:post, WEBHOOK_TEST_URL).to_return(status: 500, body: "upstream exploded")

    freeze_time do
      assert_enqueued_with(job: WebhookDeliveryJob, args: [ @delivery ], at: 1.minute.from_now) do
        WebhookDeliveryJob.perform_now(@delivery)
      end
    end

    @delivery.reload
    assert @delivery.pending?
    assert_equal 1, @delivery.attempts
    assert_equal 500, @delivery.response_code
    assert_equal "HTTP 500: upstream exploded", @delivery.last_error
  end

  test "backoff doubles between attempts" do
    assert_equal [ 1, 2, 4, 8, 16, 32, 64 ].map(&:minutes), (1..7).map { |attempts| WebhookDeliveryJob.backoff(attempts) }
  end

  test "after 8 failed attempts the delivery is marked failed and stops retrying" do
    stub_request(:post, WEBHOOK_TEST_URL).to_return(status: 500)

    7.times { WebhookDeliveryJob.perform_now(@delivery.reload) }
    assert @delivery.reload.pending?
    assert_enqueued_jobs 7

    clear_enqueued_jobs
    WebhookDeliveryJob.perform_now(@delivery.reload)

    @delivery.reload
    assert @delivery.failed?
    assert_equal 8, @delivery.attempts
    assert_no_enqueued_jobs
    assert_requested(:post, WEBHOOK_TEST_URL, times: 8)
  end

  test "a timeout is recorded as the last error and retried" do
    stub_request(:post, WEBHOOK_TEST_URL).to_timeout

    assert_enqueued_jobs(1, only: WebhookDeliveryJob) { WebhookDeliveryJob.perform_now(@delivery) }

    @delivery.reload
    assert_nil @delivery.response_code
    assert_match(/Timeout|timed out|execution expired/i, @delivery.last_error)
  end

  test "any failure to get a response counts as an attempt and retries" do
    stub_request(:post, WEBHOOK_TEST_URL).to_raise(Net::HTTPBadResponse.new("wrong status line"))

    assert_enqueued_jobs(1, only: WebhookDeliveryJob) { WebhookDeliveryJob.perform_now(@delivery) }

    @delivery.reload
    assert @delivery.pending?
    assert_equal 1, @delivery.attempts
    assert_equal "Net::HTTPBadResponse: wrong status line", @delivery.last_error
  end

  test "a deactivated endpoint fails the delivery without posting" do
    @endpoint.update!(active: false)

    WebhookDeliveryJob.perform_now(@delivery)

    assert @delivery.reload.failed?
    assert_not_requested(:post, WEBHOOK_TEST_URL)
  end

  test "a delivery that already finished is not sent again" do
    @delivery.update!(status: :succeeded)

    WebhookDeliveryJob.perform_now(@delivery)

    assert_not_requested(:post, WEBHOOK_TEST_URL)
  end
end
