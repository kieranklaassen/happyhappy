require "test_helper"

class DigestDispatchJobTest < ActiveJob::TestCase
  include SlackStubHelper

  setup do
    DailyDigest.delete_all
    OverviewDigest.delete_all
  end

  test "the overview of all products is claimed once a day at the Settings hour in the Settings time zone" do
    Setting.current.update!(slack_channel_id: "C0AGB2RKA6R", digest_time_zone: "America/Los_Angeles", digest_hour: 8)

    travel_to Time.utc(2030, 1, 15, 15, 59) # 07:59 in Los Angeles
    assert_no_enqueued_jobs(only: PostOverviewDigestJob) { DigestDispatchJob.perform_now }
    assert_empty OverviewDigest.all

    travel_to Time.utc(2030, 1, 15, 16, 0) # 08:00 in Los Angeles
    assert_enqueued_jobs(1, only: PostOverviewDigestJob) { DigestDispatchJob.perform_now }
    assert_equal Date.new(2030, 1, 15), OverviewDigest.sole.date

    travel_to Time.utc(2030, 1, 15, 17, 0)
    assert_no_enqueued_jobs(only: PostOverviewDigestJob) { DigestDispatchJob.perform_now }
  end

  test "the overview date follows the Settings time zone, not the server's" do
    Setting.current.update!(slack_channel_id: "C0AGB2RKA6R", digest_time_zone: "America/Los_Angeles", digest_hour: 8)
    travel_to Time.utc(2030, 1, 16, 7, 0) # still Jan 15 at 23:00 in Los Angeles

    DigestDispatchJob.perform_now

    assert_equal Date.new(2030, 1, 15), OverviewDigest.sole.date
  end

  test "without a Settings channel there is no overview" do
    travel_to Time.utc(2030, 1, 15, 20, 0)

    assert_no_enqueued_jobs(only: PostOverviewDigestJob) { DigestDispatchJob.perform_now }
    assert_empty OverviewDigest.all
  end

  test "at its digest hour a product with a Slack channel gets today's digest" do
    travel_to Time.zone.local(2030, 1, 15, 9, 0)

    assert_enqueued_jobs 1, only: PostDigestJob do
      DigestDispatchJob.perform_now
    end

    digest = DailyDigest.sole
    assert_equal products(:cora), digest.product
    assert_equal Date.new(2030, 1, 15), digest.date
  end

  test "nothing is due before a product's digest hour" do
    travel_to Time.zone.local(2030, 1, 15, 8, 59)

    DigestDispatchJob.perform_now

    assert_empty DailyDigest.all
  end

  test "a missed digest hour posts on the next run that day" do
    travel_to Time.zone.local(2030, 1, 15, 18, 0)

    DigestDispatchJob.perform_now

    assert_equal [ products(:cora), products(:spiral) ].sort_by(&:id), DailyDigest.all.map(&:product).sort_by(&:id)
  end

  test "the dispatcher never posts two digests for one product on one day" do
    stub_slack_post_message
    travel_to Time.zone.local(2030, 1, 15, 9, 0)

    perform_enqueued_jobs do
      DigestDispatchJob.perform_now
      DigestDispatchJob.perform_now
      travel 3.hours
      DigestDispatchJob.perform_now
    end

    assert_equal 1, DailyDigest.where(product: products(:cora)).count
    assert_equal 1, slack_posts.count { |post| post["channel"] == "C0CORASUPPORT" }
  end

  test "covers AE8: a quiet day still posts a digest covering the previous calendar day" do
    stub_slack_post_message
    travel_to Time.zone.local(2030, 1, 15, 9, 0)

    perform_enqueued_jobs { DigestDispatchJob.perform_now }

    post = slack_posts.sole
    assert_equal "C0CORASUPPORT", post["channel"]
    assert_equal "Cora digest for January 14, 2030", post["text"]
    assert_includes post["blocks"].to_json, "Quiet day: no new feedback about Cora."

    digest = DailyDigest.sole
    assert digest.posted?
    assert_equal SLACK_OK_TS, digest.slack_message_ts
  end

  test "digest hours and days use the app time zone" do
    Time.use_zone("America/Los_Angeles") do
      travel_to Time.utc(2030, 1, 15, 17, 0)

      DigestDispatchJob.perform_now

      assert_equal Date.new(2030, 1, 15), DailyDigest.find_by!(product: products(:cora)).date
    end
  end

  test "a Slack 5xx keeps the claimed digest, records the error, and retries" do
    stub_slack_post_message(status: 502, body: "bad gateway")
    travel_to Time.zone.local(2030, 1, 15, 9, 0)
    DigestDispatchJob.perform_now
    digest = DailyDigest.sole

    assert_enqueued_with(job: PostDigestJob, args: [ digest ]) { PostDigestJob.perform_now(digest) }

    assert_equal "Slack HTTP 502", digest.reload.last_error
    assert_not digest.posted?
  end

  test "every environment schedules the dispatcher hourly" do
    recurring = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true)

    %w[production development test].each do |env|
      task = recurring.fetch(env).fetch("digest_dispatch")
      assert_equal "DigestDispatchJob", task.fetch("class")
      assert_equal "0 * * * *", task.fetch("schedule")
    end
  end
end
