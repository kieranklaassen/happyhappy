class WebhookEndpointsController < InertiaController
  RECENT_DELIVERIES = 50

  before_action :set_endpoint, only: %i[show edit update destroy test_send rotate_secret]

  def index
    endpoints = WebhookEndpoint.ordered.to_a
    last_deliveries = WebhookDelivery.where(id: WebhookDelivery.group(:webhook_endpoint_id).select("MAX(id)"))
      .index_by(&:webhook_endpoint_id)

    render inertia: "webhook_endpoints/index", props: {
      endpoints: endpoints.map { |endpoint| endpoint_row(endpoint, last_deliveries[endpoint.id]) }
    }
  end

  def show
    response.headers["Cache-Control"] = "no-store"
    render inertia: "webhook_endpoints/show", props: {
      endpoint: endpoint_row(@endpoint, @endpoint.deliveries.first).merge(secret: @endpoint.secret),
      filters: filter_labels(@endpoint),
      deliveries: @endpoint.deliveries.limit(RECENT_DELIVERIES).map { |delivery| delivery_row(delivery) }
    }
  end

  def new
    render_form WebhookEndpoint.new(events: %w[item.classified])
  end

  def create
    endpoint = WebhookEndpoint.new(endpoint_params)
    if endpoint.save
      redirect_to webhook_endpoint_path(endpoint), notice: "#{endpoint.name} created. Copy its signing secret below."
    else
      redirect_to new_webhook_endpoint_path, inertia: { errors: endpoint.errors }
    end
  end

  def edit
    render_form @endpoint
  end

  def update
    if @endpoint.update(endpoint_params)
      redirect_to webhook_endpoint_path(@endpoint), notice: "#{@endpoint.name} saved."
    else
      redirect_to edit_webhook_endpoint_path(@endpoint), inertia: { errors: @endpoint.errors }
    end
  end

  def destroy
    @endpoint.destroy!
    redirect_to webhook_endpoints_path, notice: "#{@endpoint.name} deleted."
  end

  # Sends one sample event right away, without retries, so the result shows on the page.
  def test_send
    delivery = @endpoint.deliveries.create!(event: Webhooks::Payload::TEST_EVENT, payload: Webhooks::Payload.sample,
      test: true)
    if delivery.attempt!
      redirect_to webhook_endpoint_path(@endpoint), notice: "Test event delivered (HTTP #{delivery.response_code})."
    else
      delivery.failed!
      redirect_to webhook_endpoint_path(@endpoint), alert: "Test event failed: #{delivery.last_error}"
    end
  end

  def rotate_secret
    @endpoint.rotate_secret!
    redirect_to webhook_endpoint_path(@endpoint), notice: "Secret rotated. The old secret no longer signs deliveries."
  end

  private

  def set_endpoint
    @endpoint = WebhookEndpoint.find(params[:id])
  end

  def endpoint_params
    params.expect(webhook_endpoint: [ :name, :url, :active,
      events: [], product_ids: [], category_ids: [], sentiments: [] ])
  end

  def render_form(endpoint)
    products = Product.active.or(Product.where(id: endpoint.product_ids)).ordered
    categories = Category.active.or(Category.where(id: endpoint.category_ids)).ordered
    render inertia: "webhook_endpoints/form", props: {
      endpoint: endpoint.slice(:id, :name, :url, :active, :events, :product_ids, :category_ids, :sentiments),
      events: WebhookEndpoint::EVENTS,
      products: products.map { |product| product.slice(:id, :name) },
      categories: categories.map { |category| category.slice(:id, :name) },
      sentiments: Item.sentiments.keys
    }
  end

  def endpoint_row(endpoint, last_delivery)
    endpoint.slice(:id, :name, :url, :active, :events, :product_ids, :category_ids, :sentiments).merge(
      last_delivery: last_delivery && delivery_row(last_delivery)
    )
  end

  def filter_labels(endpoint)
    {
      products: Product.where(id: endpoint.product_ids).ordered.pluck(:name),
      categories: Category.where(id: endpoint.category_ids).ordered.pluck(:name),
      sentiments: endpoint.sentiments
    }
  end

  def delivery_row(delivery)
    delivery.slice(:id, :event, :status, :attempts, :response_code, :last_error, :test, :item_event_id).merge(
      item_id: delivery.payload.dig("item", "id").presence,
      created_at: delivery.created_at.iso8601,
      last_attempted_at: delivery.last_attempted_at&.iso8601
    )
  end
end
