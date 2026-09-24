# Domain event subscribers (KTD12). Subscribed in to_prepare so boot does not
# autoload reloadable models; the previous subscriber is dropped on each reload
# so development never escalates twice.
item_classified_subscriber = nil

Rails.application.config.to_prepare do
  ActiveSupport::Notifications.unsubscribe(item_classified_subscriber) if item_classified_subscriber

  item_classified_subscriber = ActiveSupport::Notifications.subscribe(Item::CLASSIFIED_EVENT) do |event|
    item = Item.find_by(id: event.payload[:item_id])
    message = item&.messages&.find_by(id: event.payload[:message_id]) if event.payload[:message_id]
    Escalations::Check.call(item, message) if item
  end
end
