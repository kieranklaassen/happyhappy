# Items::Ingest enqueues ClassifyMessageJob by name so the classification unit
# can supply the job. Until app/jobs/classify_message_job.rb exists, tests get
# this no-op stand-in so enqueue assertions have a class to match. Delete this
# file when the real job lands (the autoloaded class then wins either way).
unless Object.const_defined?(:ClassifyMessageJob)
  class ClassifyMessageJob < ApplicationJob
    def perform(message); end
  end
end
