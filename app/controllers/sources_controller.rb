# frozen_string_literal: true

class SourcesController < InertiaController
  before_action :set_source, only: %i[edit update rotate_secret]

  def index
    sources = Source.includes(:default_product).ordered
    render inertia: "sources/index", props: { sources: sources.map { |source| source_row(source) } }
  end

  def new
    render_form Source.new
  end

  def create
    source = Source.new(params.expect(source: %i[kind name selector default_product_id monthly_limit]))
    source.monthly_limit = nil unless source.x?
    if source.save
      redirect_to source.custom? ? edit_source_path(source) : sources_path, notice: "#{source.name} connected."
    else
      redirect_to new_source_path, inertia: { errors: source.errors }
    end
  end

  def edit
    render_form @source
  end

  def update
    @source.assign_attributes(params.expect(source: %i[name selector default_product_id monthly_limit]))
    @source.monthly_limit = nil unless @source.x?
    @source.status = :active if limit_raised_above_spend?(@source)
    if @source.save
      redirect_to sources_path, notice: "#{@source.name} saved."
    else
      redirect_to edit_source_path(@source), inertia: { errors: @source.errors }
    end
  end

  def rotate_secret
    return head :not_found unless @source.custom?

    @source.rotate_signing_secret!
    redirect_to edit_source_path(@source), notice: "New signing secret for #{@source.name}. The old one no longer works."
  end

  private

  def set_source
    @source = Source.find(params[:id])
  end

  def render_form(source)
    products = Product.active.or(Product.where(id: source.default_product_id)).ordered
    render inertia: "sources/form", props: {
      source: source.slice(:id, :kind, :name, :selector, :default_product_id)
        .merge(monthly_limit: source.monthly_limit&.to_f),
      kinds: Source.kinds.keys,
      products: products.map { |product| product.slice(:id, :name) },
      webhook: (webhook_props(source) if source.custom? && source.persisted?)
    }
  end

  def source_row(source)
    source.slice(:id, :kind, :name, :selector, :status, :last_error).merge(
      default_product_name: source.default_product&.name,
      last_message_at: source.last_message_at&.iso8601,
      last_error_at: source.last_error_at&.iso8601,
      monthly_limit: source.monthly_limit&.to_f,
      month_spend: current_month_spend(source),
      webhook_url: (webhooks_custom_url(source.public_token) if source.custom?)
    )
  end

  def webhook_props(source)
    { url: webhooks_custom_url(source.public_token), signing_secret: source.signing_secret }
  end

  def limit_raised_above_spend?(source)
    source.paused_for_budget? && source.monthly_limit_changed? &&
      (source.monthly_limit.nil? || source.monthly_limit > current_month_spend(source))
  end

  def current_month_spend(source)
    return unless source.x?

    source.month_key == Time.current.strftime("%Y-%m") ? source.month_spend.to_f : 0.0
  end
end
