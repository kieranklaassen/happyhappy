namespace :classifications do
  desc "Reclassify stored messages with the current classifier and set author roles, quietly and resumably " \
    "(ITEM_IDS=1,2 limits the run)"
  task rerun: :environment do
    items = Item.order(:id)
    items = items.where(id: ENV["ITEM_IDS"].split(",")) if ENV["ITEM_IDS"].present?
    logger = ActiveSupport::Logger.new($stdout)
    stats = Current.set(backfill: true) { Classification::Rerun.new(items: items, logger: logger).call }
    puts "rerun finished: #{stats}"
  end
end
