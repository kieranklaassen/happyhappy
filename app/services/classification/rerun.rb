module Classification
  # Reclassifies stored messages with the current classifier, oldest first per
  # item, so each message is read with the thread that preceded it.
  #
  #   Classification::Rerun.new(items: Item.all).call # => { items:, messages:, reclassified:, skipped:, failed: }
  #
  # - Idempotent: a message already stamped with Classification::VERSION and an
  #   unchanged author role is skipped, so an interrupted run resumes.
  # - Each message's author role is decided again from its metadata (Discord
  #   authors' server roles are looked up once each); unknown authors go to Jev.
  # - Applies quietly: no escalations and no webhook deliveries, and labels a
  #   human set are kept (Classification::Apply).
  # - An item whose author was taken from a team message is re-pointed at its
  #   first customer, and its last activity at its latest customer message.
  class Rerun
    def initialize(items:, classifier: Classification.classifier, discord_members: nil, logger: nil)
      @items = items
      @classifier = classifier
      @discord_members = discord_members
      @logger = logger
      @stats = Hash.new(0)
    end

    def call
      @items.includes(:source).find_each do |item|
        @stats[:items] += 1
        item.messages.each { |message| rerun(message) }
        refresh_author(item.reload)
        log_progress
      end
      @stats.to_h
    end

    private

    def rerun(message)
      @stats[:messages] += 1
      role = author_role_for(message)
      if message.classifier_version == Classification::VERSION && (role == "unknown" || role == message.author_role)
        @stats[:skipped] += 1
        return
      end

      message.update!(author_role: role) if role != message.author_role
      Classification::Apply.call(message: message, answers: @classifier.call(message), quiet: true)
      @stats[:reclassified] += 1
    rescue *ClassifyMessageJob::PROVIDER_ERRORS => error
      @stats[:failed] += 1
      message.update_columns(classification_error: "#{error.class}: #{error.message}")
      @logger&.warn("[rerun] message #{message.id} failed: #{error.class}: #{error.message}")
    end

    def author_role_for(message)
      payload = message.raw_payload
      if message.source.discord? && payload.is_a?(Hash)
        payload = discord_members.with_member(payload, payload["guild_id"])
      end
      Messages::AuthorRole.call(source_kind: message.source.kind, raw_payload: payload, author_email: author_email(message))
    end

    # Only the item's first message names the item's author.
    def author_email(message)
      message.item.author_email if message.item.messages.first == message
    end

    def discord_members
      @discord_members ||= Backfill::DiscordMembers.new
    end

    def refresh_author(item)
      customers = item.messages.reject(&:author_team?)
      return if customers.empty?

      item.last_message_at = customers.map(&:occurred_at).max
      if item.messages.first.author_team?
        first = customers.first
        item.assign_attributes(author_name: first.author_label, author_handle: first.raw_payload.dig("author", "username"),
          author_email: first.raw_payload.dig("part", "author", "email"))
      end
      item.save! if item.changed?
    end

    def log_progress
      @logger&.info("[rerun] #{@stats.to_h}") if (@stats[:items] % 100).zero?
    end
  end
end
