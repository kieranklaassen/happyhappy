module Backfill
  # What one backfill run did for one source. `fetched` counts provider messages
  # read; the ones neither created nor duplicate were skipped by the connector
  # (bots, system messages, admin replies, empty bodies).
  class Stats
    attr_reader :source
    attr_accessor :fetched, :created, :duplicates, :error

    def initialize(source)
      @source = source
      @fetched = 0
      @created = 0
      @duplicates = 0
    end

    def record(result)
      return if result.nil?

      result.duplicate? ? self.duplicates += 1 : self.created += 1
    end

    def skipped
      fetched - created - duplicates
    end

    def to_s
      line = "source #{source.id} #{source.name}: fetched=#{fetched} created=#{created} " \
        "duplicates=#{duplicates} skipped=#{skipped}"
      error ? "#{line} error=#{error}" : line
    end
  end
end
