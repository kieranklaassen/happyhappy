# frozen_string_literal: true

# Live-path latency harness (run it through script/latency/run.sh, which points
# every database at tmp/latency). Fires a burst of fixture payloads through the
# real webhook controllers and the Discord gateway handler while the real Solid
# Queue supervisor (config/queue.yml) works the jobs, and times each stage:
#
#   receipt -> ack -> ingested -> classify start -> classified -> applied
#     -> Action Cable ping received -> dashboard reload (client model)
#     -> Slack escalation posted, outbound webhook delivered
#
# TypeSafe, Slack posts, Slack lookups, and webhook endpoints are stubs with
# sampled latency, so nothing leaves the machine unless --live asks for a
# TypeSafe sample (TYPESAFE_API_KEY must then be in the environment).
unless ENV["LATENCY_HARNESS"] == "1" && Rails.env.production? &&
    ActiveRecord::Base.connection_db_config.database.to_s.include?("tmp/latency")
  abort "script/latency/run.rb only runs through script/latency/run.sh"
end

require "action_dispatch/testing/integration"
require "optparse"
require Rails.root.join("test/support/fake_classifier").to_s

OPTIONS = { burst: 50, backfill: 0, spacing: 40, seed: 22, live: 0, label: "run", timeout: 180 }
OptionParser.new do |parser|
  parser.on("--burst N", Integer, "live messages, spread over the five kinds (50)") { |value| OPTIONS[:burst] = value }
  parser.on("--backfill N", Integer, "backfilled messages queued just before the burst (0)") { |value| OPTIONS[:backfill] = value }
  parser.on("--spacing MS", Integer, "milliseconds between burst messages (40)") { |value| OPTIONS[:spacing] = value }
  parser.on("--seed N", Integer, "stub latency seed (22)") { |value| OPTIONS[:seed] = value }
  parser.on("--live N", Integer, "also time N real TypeSafe calls (0)") { |value| OPTIONS[:live] = value }
  parser.on("--label NAME", "names tmp/latency/NAME.json") { |value| OPTIONS[:label] = value }
end.parse!(ARGV)

DIR = Rails.root.join("tmp/latency")
EVENTS = DIR.join("events.jsonl")
FIXTURES = Rails.root.join("test/fixtures/files")
TYPESAFE_LATENCY = (0.3..0.9)
SLACK_LOOKUP_LATENCY = 0.12
SLACK_POST_LATENCY = 0.15
WEBHOOK_ENDPOINT_LATENCY = 0.08
ANGRY_EVERY = 5

module Latency
  def self.record(stage, **keys)
    line = { s: stage, t: Time.now.to_f, pid: Process.pid, **keys }.to_json
    File.open(EVENTS, "a") { |file| file.puts(line) }
  end

  def self.events
    EVENTS.readlines.map { |line| JSON.parse(line) }
  end
end

# Stands in for TypeSafe: sleeps a latency sampled from TYPESAFE_LATENCY per
# message (seeded, so before and after runs see the same latencies).
class StubClassifier
  def initialize(seed)
    @seed = seed
  end

  def call(message)
    sleep Random.new(@seed + message.id).rand(TYPESAFE_LATENCY)
    Latency.record("classified", m: message.id)
    Thread.current[:latency_classified] = true
    angry = message.body.include?("[angry]")
    FakeClassifier.answers(product: "cora", anger: angry ? 0.95 : 0.2, sentiment: angry ? "complaint" : "question",
      team_author: 0.05)
  end
end

module LatencyHooks
  module Ingest
    def call
      super.tap do |result|
        Latency.record("ingested", x: @inbound.external_id, m: result.message.id) unless result.duplicate?
      end
    end
  end

  module ClassifyJob
    def perform(message)
      Latency.record("classify_start", m: message.id)
      Thread.current[:latency_message] = message.id
      Thread.current[:latency_classified] = false
      super
    ensure
      Thread.current[:latency_message] = nil
      Thread.current[:latency_classified] = nil
    end
  end

  module Cable
    def refresh(...)
      if (message_id = Thread.current[:latency_message]) && Thread.current[:latency_classified]
        Latency.record("applied", m: message_id)
        Thread.current[:latency_classified] = false
      end
      super
    end
  end

  module SlackLookups
    private

    def lookups(user_id, channel, ts)
      sleep SLACK_LOOKUP_LATENCY
      { author_handle: user_id, author_name: "Harness #{user_id}", author_email: nil,
        permalink: "https://slack.com/archives/#{channel}/p#{ts.delete(".")}" }
    end
  end

  module SlackPost
    def post_message(channel:, text:, blocks:)
      sleep SLACK_POST_LATENCY
      format("%.6f", Time.now.to_f)
    end
  end

  module EscalationJob
    def perform(escalation)
      super
      Latency.record("escalated", m: escalation.message_id) if escalation.reload.posted?
    end
  end

  StubResponse = Struct.new(:code, :body, :message)

  module WebhookPost
    private

    def post(_body, _now)
      sleep WEBHOOK_ENDPOINT_LATENCY
      StubResponse.new("200", "", "OK")
    end
  end

  module WebhookJob
    def perform(delivery)
      super
      if delivery.reload.succeeded? && delivery.event == "item.classified"
        Latency.record("webhook", m: delivery.item_event&.data&.dig("message_id"))
      end
    end
  end
end

Items::Ingest.prepend(LatencyHooks::Ingest)
ClassifyMessageJob.prepend(LatencyHooks::ClassifyJob)
MoodChannel.singleton_class.prepend(LatencyHooks::Cable)
Connectors::Slack.prepend(LatencyHooks::SlackLookups)
Slack::Client.prepend(LatencyHooks::SlackPost)
PostEscalationJob.prepend(LatencyHooks::EscalationJob)
WebhookDelivery.prepend(LatencyHooks::WebhookPost)
WebhookDeliveryJob.prepend(LatencyHooks::WebhookJob)

stub = StubClassifier.new(OPTIONS[:seed])
Classification.classifier = defined?(Classification::RateLimiter) ? Classification::RateLimiter.new(stub) : stub

# Seed: one product with an escalation channel, one active source per kind, and
# an endpoint subscribed to item.classified.
Setting.current
product = Product.find_or_create_by!(slug: "cora") { |record| record.assign_attributes(name: "Cora", digest_hour: 9) }
product.update!(slack_channel_id: "C0CORASUPPORT")
Category.find_or_create_by!(name: "bug")
sources = {
  slack: Source.create!(kind: :slack, name: "Slack", selector: "C0COMMUNITY", default_product: product),
  discord: Source.create!(kind: :discord, name: "Discord", selector: "1100000000000000001", default_product: product),
  intercom: Source.create!(kind: :intercom, name: "Intercom", selector: "7000001", default_product: product),
  email: Source.create!(kind: :email, name: "Email", selector: "help@cora.computer", default_product: product),
  custom: Source.create!(kind: :custom, name: "Custom", default_product: product)
}
WebhookEndpoint.create!(name: "Harness", url: "https://hooks.example.test/happyhappy", events: %w[item.classified])

def fixture(path)
  JSON.parse(FIXTURES.join(path).read)
end

def body_for(index, kind)
  angry = (index % ANGRY_EVERY).zero?
  "#{kind} burst message #{index}: Cora archived my inbox again and support has not answered#{" [angry]" if angry}."
end

# Each builder returns [external_id, callable that delivers the message and returns the HTTP status].
def slack_message(app, index)
  payload = fixture("slack/message_event.json")
  ts = format("%.6f", Time.now.to_f + index / 1_000_000.0)
  payload["event"].merge!("ts" => ts, "event_ts" => ts, "text" => body_for(index, "slack"), "user" => "U0BURST#{index}")
  payload["event_id"] = "Ev0BURST#{index}"
  raw = payload.to_json
  timestamp = Time.now.to_i.to_s
  signature = "v0=#{OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("SLACK_SIGNING_SECRET"), "v0:#{timestamp}:#{raw}")}"
  [ "C0COMMUNITY:#{ts}", -> {
    app.post("/webhooks/slack/events", params: raw, headers: { "Content-Type" => "application/json",
      "X-Slack-Request-Timestamp" => timestamp, "X-Slack-Signature" => signature })
  } ]
end

def intercom_message(app, index)
  payload = fixture("intercom/conversation_user_created.json")
  conversation = payload["data"]["item"]
  conversation["id"] = "9#{index}0000"
  conversation["created_at"] = Time.now.to_i
  conversation["source"].merge!("id" => "part-burst-#{index}", "body" => "<p>#{body_for(index, "intercom")}</p>",
    "created_at" => Time.now.to_i)
  raw = payload.to_json
  signature = "sha1=#{OpenSSL::HMAC.hexdigest("SHA1", ENV.fetch("INTERCOM_CLIENT_SECRET"), raw)}"
  [ "part-burst-#{index}", -> {
    app.post("/webhooks/intercom", params: raw, headers: { "Content-Type" => "application/json", "X-Hub-Signature" => signature })
  } ]
end

def discord_message(bot, index)
  payload = fixture("discord/message_create.json")
  id = (1_300_000_000_000_000_000 + index).to_s
  payload.merge!("id" => id, "content" => body_for(index, "discord"), "timestamp" => Time.now.utc.iso8601(3))
  payload.delete("message_reference")
  [ id, -> {
    bot.handle_message(payload)
    200
  } ]
end

def postmark_message(app, index)
  payload = fixture("postmark/inbound_first.json")
  message_id = "burst-#{index}-#{SecureRandom.hex(4)}"
  headers = payload["Headers"].reject { |header| header["Name"].in?(%w[Message-ID References In-Reply-To]) }
  payload.merge!("MessageID" => message_id, "Date" => Time.now.rfc2822, "StrippedTextReply" => body_for(index, "email"),
    "TextBody" => body_for(index, "email"), "Headers" => headers + [ { "Name" => "Message-ID", "Value" => "<#{message_id}@example.com>" } ])
  auth = ActionController::HttpAuthentication::Basic.encode_credentials(ENV.fetch("POSTMARK_INBOUND_USER"),
    ENV.fetch("POSTMARK_INBOUND_PASSWORD"))
  [ message_id, -> {
    app.post("/webhooks/postmark", params: payload.to_json, headers: { "Content-Type" => "application/json", "Authorization" => auth })
  } ]
end

def custom_message(app, source, index)
  raw = { id: "custom-burst-#{index}", text: body_for(index, "custom"), author: { name: "Burst #{index}" },
    occurred_at: Time.now.utc.iso8601 }.to_json
  signature = Webhooks::Signature.sign(source.signing_secret, raw, time: Time.current)
  [ "custom-burst-#{index}", -> {
    app.post("/webhooks/custom/#{source.public_token}", params: raw,
      headers: { "Content-Type" => "application/json", Webhooks::Signature::HEADER => signature })
  } ]
end

def backfill_discord(count)
  base = fixture("discord/message_create.json")
  count.times do |index|
    payload = base.merge("id" => (1_200_000_000_000_000_000 + index).to_s, "content" => "backfilled message #{index}",
      "timestamp" => (Time.now.utc - 30.days + index).iso8601)
    payload.delete("message_reference")
    Connectors::Discord.ingest(payload, backfill: true)
  end
end

# Mirrors useMoodStream: a ping schedules one reload at the later of the
# coalesce delay and the minimum gap since the last reload; a ping whose reload
# would land sooner than the pending one replaces it. Constants come from the
# hook so the model follows the client.
def client_constants
  source = Rails.root.join("app/frontend/components/mood/use-mood-stream.ts").read
  value = ->(name) { source[/const #{name} = ([\d_]+)/, 1]&.delete("_")&.to_i }
  coalesce = value.("COALESCE_MS")
  gap = value.("MIN_RELOAD_GAP_MS")
  { coalesce: coalesce, gap: gap, live_coalesce: value.("LIVE_COALESCE_MS") || coalesce,
    live_gap: value.("LIVE_RELOAD_GAP_MS") || gap }
end

def reload_times(pings, constants)
  reloads = []
  last = -Float::INFINITY
  pending = nil
  pings.sort_by { |ping| ping[:t] }.each do |ping|
    if pending && pending <= ping[:t]
      reloads << pending
      last = pending
      pending = nil
    end
    coalesce, gap = ping[:backfill] ? constants.values_at(:coalesce, :gap) : constants.values_at(:live_coalesce, :live_gap)
    at = [ ping[:t] + coalesce / 1000.0, last + gap / 1000.0 ].max
    pending = at if pending.nil? || at < pending
  end
  reloads << pending if pending
  reloads
end

def percentile(values, fraction)
  return if values.empty?

  sorted = values.sort
  sorted[[ (fraction * sorted.size).ceil - 1, 0 ].max]
end

# Runs --live real TypeSafe calls on stored burst messages, one at a time.
def live_sample(count)
  return [] if count.zero?

  unless ENV["TYPESAFE_API_KEY"].present?
    warn "--live needs TYPESAFE_API_KEY; skipping the live sample"
    return []
  end
  classifier = Classification::Classifier.new
  Message.where(backfilled: false).order(:id).limit(count).filter_map do |message|
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    classifier.call(message)
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
  rescue StandardError => error
    warn "live TypeSafe call failed: #{error.class}"
    nil
  end
end

# --- run ---

pings = []
ActionCable.server.pubsub.subscribe(MoodChannel::STREAM,
  ->(data) { pings << { t: Time.now.to_f, backfill: JSON.parse(data)["backfill"] == true } })

ActiveRecord::Base.connection_handler.clear_all_connections!
supervisor = fork { SolidQueue::Supervisor.start }
at_exit do
  Process.kill("TERM", supervisor)
  Process.wait(supervisor)
rescue Errno::ESRCH, Errno::ECHILD
  nil
end

expected_workers = SolidQueue::Configuration.new(mode: :fork).configured_processes.count { |process| process.kind == :worker }
deadline = 30.seconds.from_now
sleep 0.2 until SolidQueue::Process.where(kind: "Worker").count >= expected_workers || Time.current > deadline
abort "Solid Queue workers did not start" if SolidQueue::Process.where(kind: "Worker").count < expected_workers

if OPTIONS[:backfill].positive?
  backfill_discord(OPTIONS[:backfill])
  sleep 1
end

app = ActionDispatch::Integration::Session.new(Rails.application)
app.https!
app.host = "happyhappy.test"
bot = Connectors::DiscordBot.new(token: "latency-harness")

kinds = %i[slack intercom discord email custom]
burst = Array.new(OPTIONS[:burst]) do |index|
  kind = kinds[index % kinds.size]
  external_id, deliver =
    case kind
    when :slack then slack_message(app, index)
    when :intercom then intercom_message(app, index)
    when :discord then discord_message(bot, index)
    when :email then postmark_message(app, index)
    when :custom then custom_message(app, sources[:custom], index)
    end
  { kind: kind, external_id: external_id, deliver: deliver, angry: (index % ANGRY_EVERY).zero? }
end

started = Time.now
burst.each do |message|
  Latency.record("receipt", x: message[:external_id])
  status = message[:deliver].call
  Latency.record("ack", x: message[:external_id], status: status)
  sleep OPTIONS[:spacing] / 1000.0
end

expected = { applied: burst.size, escalated: burst.count { |message| message[:angry] }, webhook: burst.size }
deadline = OPTIONS[:timeout].seconds.from_now
loop do
  counts = Latency.events.each_with_object(Hash.new(0)) { |event, found| found[event["s"]] += 1 }
  ids = Message.where(backfilled: false).pluck(:id).to_set
  done = Latency.events.select { |event| ids.include?(event["m"]) }.group_by { |event| event["s"] }
  break if expected.all? { |stage, count| done.fetch(stage.to_s, []).map { |event| event["m"] }.uniq.size >= count }
  abort "timed out: #{counts}" if Time.current > deadline

  sleep 0.5
end
sleep 1 # let the last pings arrive
wall = Time.now - started

# --- report ---

events = Latency.events
by_external = events.select { |event| event["x"] }.group_by { |event| event["x"] }
message_ids = events.select { |event| event["s"] == "ingested" }.to_h { |event| [ event["x"], event["m"] ] }
by_message = events.select { |event| event["m"] }.group_by { |event| event["m"] }
constants = client_constants
reloads = reload_times(pings, constants)
first_at = ->(list, stage) { list&.select { |event| event["s"] == stage }&.map { |event| event["t"] }&.min }

rows = burst.map do |message|
  external = by_external[message[:external_id]]
  id = message_ids[message[:external_id]]
  stages = by_message[id]
  times = {
    receipt: first_at.(external, "receipt"), ack: first_at.(external, "ack"), ingested: first_at.(external, "ingested"),
    classify_start: first_at.(stages, "classify_start"), classified: first_at.(stages, "classified"),
    applied: first_at.(stages, "applied"), escalated: first_at.(stages, "escalated"), webhook: first_at.(stages, "webhook")
  }
  times[:cable] = pings.map { |ping| ping[:t] }.select { |time| times[:applied] && time >= times[:applied] }.min
  times[:dashboard] = reloads.select { |time| times[:cable] && time >= times[:cable] }.min
  { kind: message[:kind], times: times }
end

STAGES = [
  [ "webhook ack (receipt to response)", :receipt, :ack ],
  [ "ingest (receipt to stored)", :receipt, :ingested ],
  [ "queue wait (stored to classify start)", :ingested, :classify_start ],
  [ "classify (TypeSafe stub + limiter)", :classify_start, :classified ],
  [ "apply (answers to committed)", :classified, :applied ],
  [ "cable (committed to ping received)", :applied, :cable ],
  [ "dashboard (ping to reload, client model)", :cable, :dashboard ],
  [ "escalation (committed to Slack post)", :applied, :escalated ],
  [ "outbound webhook (committed to delivered)", :applied, :webhook ],
  [ "end to end: dashboard", :receipt, :dashboard ],
  [ "end to end: Slack escalation", :receipt, :escalated ],
  [ "end to end: outbound webhook", :receipt, :webhook ]
].freeze

def span(rows, from, to)
  rows.filter_map { |row| (row[:times][to] - row[:times][from]) * 1000 if row[:times][from] && row[:times][to] }
end

summary = STAGES.to_h do |label, from, to|
  values = span(rows, from, to)
  [ label, { n: values.size, p50: percentile(values, 0.5)&.round, p95: percentile(values, 0.95)&.round } ]
end
per_kind = kinds.to_h do |kind|
  kind_rows = rows.select { |row| row[:kind] == kind }
  [ kind, %i[ack ingested].to_h { |to| [ to, percentile(span(kind_rows, :receipt, to), 0.95)&.round ] } ]
end
live = live_sample(OPTIONS[:live])
workers = SolidQueue::Configuration.new(mode: :fork).configured_processes.select { |process| process.kind == :worker }
  .map { |process| process.attributes.slice(:queues, :threads, :polling_interval) }

puts "## Latency: #{OPTIONS[:label]}"
puts
puts "#{burst.size} live messages #{OPTIONS[:spacing]} ms apart, #{OPTIONS[:backfill]} backfilled messages queued first; " \
  "burst drained in #{wall.round(1)} s. Workers: #{workers.to_json}. Client: #{constants.to_json}."
puts
puts "| Stage | n | p50 ms | p95 ms |"
puts "|---|---|---|---|"
summary.each { |label, stats| puts "| #{label} | #{stats[:n]} | #{stats[:p50]} | #{stats[:p95]} |" }
puts
puts "p95 ms per kind: #{per_kind.map { |kind, stats| "#{kind} ack #{stats[:ack]} / stored #{stats[:ingested]}" }.join(", ")}"
if live.any?
  puts "Live TypeSafe sample (#{live.size} calls): p50 #{percentile(live, 0.5).round} ms, p95 #{percentile(live, 0.95).round} ms"
end

DIR.join("#{OPTIONS[:label]}.json").write(JSON.pretty_generate(options: OPTIONS, wall_s: wall.round(2), workers: workers,
  client: constants, summary: summary, per_kind: per_kind, live_typesafe_ms: live.map(&:round)))
