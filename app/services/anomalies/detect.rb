module Anomalies
  # Finds spikes in every series (Anomalies::Series) for one granularity and keeps one DetectedAnomaly
  # row per spike:
  #
  # - Each scanned window with enough data trains the anomaly gem's Gaussian detector on the baseline
  #   windows before it. Epsilon is the detector's probability at mean + sensitivity * std, so the
  #   setting reads as a z-score, and a spike also needs MIN_LIFT above the mean so a flat baseline
  #   cannot turn a one-message wobble into an alert. Only upward spikes count.
  # - A spike opens a row, or extends the series' active row; the next normal window ends it. Rows
  #   already recorded for an overlapping window are reused, so rescans never duplicate.
  # - A spike whose window ended before the active window (default 7 days, typically backfilled
  #   history) is recorded as ended history and never alerts.
  # - A row that is new and still active after the scan sends the anomaly.detected webhook.
  #
  #   Anomalies::Detect.call(granularity: "hour")  # every 15 minutes, trailing hour windows
  #   Anomalies::Detect.call(granularity: "day")   # daily, calendar days
  class Detect
    CONFIG = {
      "hour" => { scan: 48, baseline: 7 * 24, stale_after: 3.hours },
      "day" => { scan: 90, baseline: 28, stale_after: 2.days }
    }.freeze
    MIN_LIFT = { count: 3.0, ratio: 0.15 }.freeze
    MAX_Z = 99.0
    HOUR_ANCHOR = 15.minutes.to_i

    def self.call(...)
      new(...).call
    end

    def initialize(granularity:, now: Time.current, setting: Setting.current)
      @granularity = granularity
      @config = CONFIG.fetch(granularity)
      @now = now
      @setting = setting
      @created = []
    end

    def call
      windows = self.class.windows(@granularity, now: @now)
      @scan_from = windows.size - @config[:scan]
      rows = existing_rows(windows[@scan_from].first)
      Series.new(windows: windows, granularity: @granularity).lines.each do |line|
        process(line, rows.fetch([ line.product_id, line.source_id, line.metric, line.dimension ], []))
      end
      end_stale
      # A spike found and ended within one scan (say, on the first run) is history by the time we alert.
      @created.select(&:active?).each do |anomaly|
        Rails.error.handle(context: { anomaly_id: anomaly.id }) { Webhooks::FanOut.anomaly(anomaly) }
      end
      @created
    end

    # Consecutive [start, end) windows, oldest first, covering the baseline and the scanned range.
    def self.windows(granularity, now: Time.current)
      config = CONFIG.fetch(granularity)
      total = config[:scan] + config[:baseline]
      if granularity == "hour"
        anchor = Time.zone.at((now.to_i / HOUR_ANCHOR) * HOUR_ANCHOR)
        (1..total).reverse_each.map { |back| [ anchor - back.hours, anchor - (back - 1).hours ] }
      else
        today = now.in_time_zone.to_date
        (1..total).reverse_each.map { |back| [ (today - back).beginning_of_day, (today - back + 1).beginning_of_day ] }
      end
    end

    private

    def existing_rows(scan_start)
      DetectedAnomaly.where(granularity: @granularity)
        .where(window_end: scan_start..).or(DetectedAnomaly.active.where(granularity: @granularity))
        .order(:window_start, :id)
        .group_by { |row| [ row.product_id, row.source_id, row.metric, row.dimension ] }
    end

    def process(line, rows)
      open_row = rows.select(&:active?).max_by(&:window_end)

      (@scan_from...line.points.size).each do |index|
        point = line.points[index]
        verdict = judge(line, index)
        next if verdict.nil?

        if verdict
          overlapping = rows.find { |row| row.window_start < point.window_end && row.window_end > point.window_start }
          target = overlapping || open_row
          if target && (target == open_row || target.active?)
            extend_row(target, line, point, verdict)
            open_row = target
          elsif overlapping.nil?
            open_row = create_row(line, point, verdict)
            rows << open_row
          end
        elsif open_row && point.window_end > open_row.window_end
          open_row.end!(at: @now)
          open_row = nil
        end
      end
    end

    # nil when the window has too little data or baseline, false when normal, else the detection.
    def judge(line, index)
      point = line.points[index]
      return false if line.count_metric? && point.value < @setting.anomaly_min_count
      return nil unless enough?(line, point)

      baseline = baseline_values(line, index)
      return nil if baseline.size < @setting.anomaly_min_baseline_windows

      detector = ::Anomaly::Detector.new(baseline.map { |value| [ value, 0 ] }, eps: 1.0)
      mean = detector.mean.first
      std = detector.std.first
      threshold = detector.probability([ mean + @setting.anomaly_sensitivity * std ])
      lift = point.value - mean
      return false unless lift >= MIN_LIFT[line.count_metric? ? :count : :ratio] && detector.anomaly?([ point.value ], threshold)

      z = [ lift / std, MAX_Z ].min
      { expected: mean, actual: point.value.to_f, z_score: z, level: level(z) }
    end

    def enough?(line, point)
      line.count_metric? || (point.count >= @setting.anomaly_min_count && !point.value.nil?)
    end

    def baseline_values(line, index)
      from = [ index - @config[:baseline], line.first_index ].max
      return [] if from >= index

      line.points[from...index].filter_map { |point| point.value.to_f if enough?(line, point) }
    end

    # 0 to 2 at 1, 1.5, and 2 times the sensitivity; DetectedAnomaly.grade turns it into a severity or highlight.
    def level(z)
      sensitivity = @setting.anomaly_sensitivity
      if z >= sensitivity * 2 then 2
      elsif z >= sensitivity * 1.5 then 1
      else 0
      end
    end

    def graded(line, verdict, item_ids)
      level = verdict[:level]
      verdict.except(:level).merge(DetectedAnomaly.grade(metric: line.metric, dimension: line.dimension, item_ids: item_ids, level: level))
    end

    def create_row(line, point, verdict)
      historical = historical?(point)
      item_ids = point.item_ids.first(DetectedAnomaly::ITEM_LIMIT)
      anomaly = DetectedAnomaly.create!(
        product_id: line.product_id, source_id: line.source_id, metric: line.metric, dimension: line.dimension,
        granularity: @granularity, window_start: point.window_start, window_end: point.window_end,
        item_ids: item_ids,
        status: historical ? :ended : :active, historical: historical, ended_at: (@now if historical),
        first_seen_at: @now, last_seen_at: @now, **graded(line, verdict, item_ids)
      )
      @created << anomaly unless historical
      anomaly
    end

    def extend_row(row, line, point, verdict)
      attributes = { last_seen_at: @now }
      if point.window_end >= row.window_end
        item_ids = (point.item_ids + row.item_ids).uniq.first(DetectedAnomaly::ITEM_LIMIT)
        attributes.merge!(graded(line, verdict, item_ids), window_end: point.window_end, item_ids: item_ids)
        # A spike that runs from old history into the active window is live after all.
        if row.historical? && !historical?(point)
          attributes.merge!(status: :active, historical: false, ended_at: nil)
          @created << row
        end
      end
      row.update!(attributes)
    end

    def historical?(point)
      point.window_end < @now - @setting.anomaly_active_days.days
    end

    def end_stale
      # Rows created by this scan are ended through their in-memory copy so the webhook filter sees it.
      created = @created.index_by(&:id)
      DetectedAnomaly.active.where(granularity: @granularity)
        .where(window_end: ...(@now - @config[:stale_after]))
        .find_each { |row| (created[row.id] || row).end!(at: @now) }
    end
  end
end
