# Runs hourly. Each product with a Slack channel gets one digest row per local
# day (APP_TIME_ZONE), claimed here before posting so a product can never get
# two digests on one day. A product whose digest hour was missed (downtime)
# posts on the next run that day instead of skipping the day.
class DigestDispatchJob < ApplicationJob
  queue_as :default

  def perform(now: Time.current)
    now = now.in_time_zone
    today = now.to_date

    due_products(now).find_each do |product|
      digest = claim(product, today)
      PostDigestJob.perform_later(digest) if digest
    end
  end

  private

  def due_products(now)
    Product.active.where.not(slack_channel_id: [ nil, "" ]).where(digest_hour: ..now.hour)
      .where.not(id: DailyDigest.where(date: now.to_date).select(:product_id))
  end

  def claim(product, date)
    product.daily_digests.create!(date: date)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil
  end
end
