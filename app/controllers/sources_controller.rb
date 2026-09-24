# frozen_string_literal: true

class SourcesController < InertiaController
  before_action :set_source, only: %i[edit update]

  def index
    sources = Source.includes(:default_product).ordered
    render inertia: "sources/index", props: { sources: sources.map { |source| source_row(source) } }
  end

  def new
    render_form Source.new
  end

  def create
    source = Source.new(source_params(params.expect(source: %i[kind name selector default_product_id monthly_limit])))
    if source.save
      redirect_to sources_path, notice: "#{source.name} connected."
    else
      redirect_to new_source_path, inertia: { errors: source.errors }
    end
  end

  def edit
    render_form @source
  end

  def update
    @source.assign_attributes(source_params(params.expect(source: %i[name selector default_product_id monthly_limit])))
    if @source.save
      redirect_to sources_path, notice: "#{@source.name} saved."
    else
      redirect_to edit_source_path(@source), inertia: { errors: @source.errors }
    end
  end

  private

  def set_source
    @source = Source.find(params[:id])
  end

  def source_params(permitted)
    kind = permitted.fetch(:kind, @source&.kind)
    permitted[:monthly_limit] = nil unless kind == "x"
    permitted
  end

  def render_form(source)
    products = Product.active.or(Product.where(id: source.default_product_id)).ordered
    render inertia: "sources/form", props: {
      source: source.slice(:id, :kind, :name, :selector, :default_product_id)
        .merge(monthly_limit: source.monthly_limit&.to_f),
      kinds: Source.kinds.keys,
      products: products.map { |product| product.slice(:id, :name) }
    }
  end

  def source_row(source)
    source.slice(:id, :kind, :name, :selector, :status, :last_error).merge(
      default_product_name: source.default_product&.name,
      last_message_at: source.last_message_at&.iso8601,
      last_error_at: source.last_error_at&.iso8601,
      monthly_limit: source.monthly_limit&.to_f,
      month_spend: current_month_spend(source)
    )
  end

  def current_month_spend(source)
    return unless source.x?

    source.month_key == Time.current.strftime("%Y-%m") ? source.month_spend.to_f : 0.0
  end
end
