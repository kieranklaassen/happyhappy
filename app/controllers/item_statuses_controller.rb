class ItemStatusesController < InertiaController
  def update
    item = Item.find(params[:item_id])
    Items::ChangeStatus.call(item: item, status: params[:status], actor: Current.user)
    redirect_to item_path(item), notice: "Marked #{item.status.humanize(capitalize: false)}."
  rescue Items::ChangeStatus::Invalid => error
    redirect_to item_path(item), alert: error.message
  end
end
