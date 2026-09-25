# Feed search (U25, docs/search.md). Item declares its labels in Item::Searchable.
Truffler.configure do |config|
  # Must equal Classification::Classifier::MODEL, so both read customers the same
  # way. Changing it marks the asked label (churn_risk) stale; supplied labels stay.
  config.model = "jev-latest"

  # Classification::RateLimiter already spends the TypeSafe account limit on
  # live classification, so search keeps to half of it.
  config.headroom = 0.5

  # Smart search waits on these jobs, so they stay off the backfill queue, and
  # off realtime, which belongs to live classification (config/queue.yml).
  config.queue_name = :default

  # Every signed-in person is an every.to team member with full access (R3), so
  # anyone may write app-wide or personal lenses.
  config.lenses.creators = :developers
  config.lenses.authorize_lens = ->(user, _scope) { user.is_a?(User) }

  if Rails.env.test?
    config.client = Truffler::Clients::Fake.new
    config.lenses.generator = Truffler::Lenses::FakeGenerator.new
    # The test Rails.cache is a null store, which cannot count budgets or hold Smart runs.
    config.cache_store = ActiveSupport::Cache::MemoryStore.new
  end
end

Rails.application.config.to_prepare do
  Truffler.config.client = FeedSearch::EncodingClient.new unless Rails.env.test?
end
