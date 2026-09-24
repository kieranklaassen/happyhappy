class ItemLabelsController < InertiaController
  LABEL_NAMES = { "product" => "Product", "category" => "Category", "sentiment" => "Sentiment", "relevant" => "Relevance" }.freeze

  def update
    item = Item.find(params[:item_id])
    Items::CorrectLabel.call(item: item, label: params[:label], value: params[:value], actor: Current.user)
    redirect_to item_path(item), notice: "#{LABEL_NAMES.fetch(params[:label])} set to #{describe(item, params[:label])}."
  rescue Items::CorrectLabel::Invalid => error
    redirect_to item_path(item), alert: error.message
  end

  private

  def describe(item, label)
    case label
    when "product" then item.product&.name || "none"
    when "category" then item.category&.name || "none"
    when "sentiment" then item.sentiment || "none"
    when "relevant" then item.relevant ? "relevant" : "not relevant"
    end
  end
end
