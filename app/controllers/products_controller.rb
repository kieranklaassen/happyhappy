# frozen_string_literal: true

class ProductsController < InertiaController
  before_action :set_product, only: %i[edit update retire restore]

  def index
    products = Product.ordered.to_a
    render inertia: "products/index", props: {
      products: products.reject(&:retired?).map { |product| product_row(product) },
      retired_products: products.select(&:retired?).map { |product| product_row(product) },
      default_escalation_threshold: Setting.current.escalation_threshold
    }
  end

  def new
    render_form Product.new
  end

  def create
    product = Product.new(product_params)
    if product.save
      redirect_to products_path, notice: "#{product.name} created."
    else
      redirect_to new_product_path, inertia: { errors: product.errors }
    end
  end

  def edit
    render_form @product
  end

  def update
    if @product.update(product_params)
      redirect_to products_path, notice: "#{@product.name} saved."
    else
      redirect_to edit_product_path(@product), inertia: { errors: @product.errors }
    end
  end

  def retire
    @product.retire!
    redirect_to products_path, notice: "#{@product.name} retired. Its past items keep the label."
  end

  def restore
    @product.restore!
    redirect_to products_path, notice: "#{@product.name} restored."
  end

  private

  def set_product
    @product = Product.find(params[:id])
  end

  def product_params
    permitted = params.expect(product: %i[name slug description hint_words search_blurb slack_channel_id escalation_threshold digest_hour])
    permitted[:hint_words] = permitted[:hint_words].split(/[,\n]/) if permitted.key?(:hint_words)
    permitted
  end

  def render_form(product)
    render inertia: "products/form", props: {
      product: product.slice(:id, :name, :slug, :description, :hint_words, :search_blurb, :slack_channel_id,
        :escalation_threshold, :digest_hour),
      default_escalation_threshold: Setting.current.escalation_threshold
    }
  end

  def product_row(product)
    product.slice(:id, :name, :slug, :description, :hint_words, :search_blurb, :slack_channel_id, :escalation_threshold,
      :digest_hour).merge(retired_at: product.retired_at&.iso8601)
  end
end
