namespace :backfill do
  report = lambda do |stats|
    stats.each { |entry| puts entry }
    puts "classification queued for #{stats.sum(&:created)} new messages"
  end

  days_ago = ->(args) { Integer(args[:days] || 90).days.ago }

  desc "Import each active Discord source's channel and thread history from the last N days (default 90)"
  task :discord, [ :days ] => :environment do |_task, args|
    report.call(Backfill::Discord.call(since: days_ago.call(args)))
  end

  desc "Import customer messages from Intercom conversations updated in the last N days (default 90)"
  task :intercom, [ :days ] => :environment do |_task, args|
    $stdout.sync = true
    backfill = Backfill::Intercom.new(since: days_ago.call(args),
      progress: ->(count) { puts "conversations scanned so far: #{count}" })
    stats = backfill.call
    puts "conversations scanned: #{backfill.conversations}"
    report.call(stats)
  end

  desc "Classification progress of backfilled messages, per source"
  task status: :environment do
    Message.where(backfilled: true).group(:source_id).count.each do |source_id, total|
      scope = Message.where(backfilled: true, source_id: source_id)
      classified = scope.where.not(classified_at: nil).count
      failed = scope.where(classified_at: nil).where.not(classification_error: nil).count
      puts "source #{source_id} #{Source.find(source_id).name}: backfilled=#{total} classified=#{classified} " \
        "failed=#{failed} pending=#{total - classified - failed}"
    end
    pending_jobs = SolidQueue::Job.where(class_name: "ClassifyMessageJob", finished_at: nil).count
    puts "unfinished ClassifyMessageJob jobs: #{pending_jobs}"
  end
end
