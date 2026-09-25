# frozen_string_literal: true

class CategoriesController < InertiaController
  before_action :set_category, only: %i[update retire restore]

  def index
    categories = Category.ordered.to_a
    item_counts = Item.where(category_id: categories.map(&:id)).group(:category_id).count
    rows = categories.map { |category| category_row(category, item_counts.fetch(category.id, 0)) }

    render inertia: "categories/index", props: {
      categories: rows.reject { |row| row[:retired_at] },
      retired_categories: rows.select { |row| row[:retired_at] }
    }
  end

  def create
    attributes = category_params
    category = Category.new(attributes)
    category.position = Category.maximum(:position).to_i + 1 if attributes[:position].blank?
    if category.save
      redirect_to categories_path, notice: "Added #{category.name}."
    else
      redirect_to categories_path, inertia: { errors: bagged_errors(category) }
    end
  end

  def update
    if @category.update(category_params)
      redirect_to categories_path, notice: "Saved #{@category.name}."
    else
      redirect_to categories_path, inertia: { errors: bagged_errors(@category) }
    end
  end

  def retire
    @category.retire!
    redirect_to categories_path, notice: "Retired #{@category.name}. Past items keep the label."
  end

  def restore
    @category.restore!
    redirect_to categories_path, notice: "Restored #{@category.name}."
  end

  private

  def set_category
    @category = Category.find(params[:id])
  end

  # Each category row and the add form post with their own Inertia error bag,
  # so a failed save only marks the form that sent it.
  def bagged_errors(category)
    bag = request.headers["X-Inertia-Error-Bag"].presence
    bag ? { bag => category.errors } : category.errors
  end

  def category_params
    params.expect(category: %i[name description position])
  end

  def category_row(category, item_count)
    category.slice(:id, :name, :description, :position)
      .merge(retired_at: category.retired_at&.iso8601, item_count: item_count)
  end
end
