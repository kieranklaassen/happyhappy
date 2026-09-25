# frozen_string_literal: true

# The home page is the mood dashboard: a watercolor crowd of today's customers.
class HomeController < InertiaController
  def index
    product = Product.find_by(slug: params[:product]) if params[:product].present?
    render inertia: "home/index", props: MoodScene.new(range: params[:range], product: product).props
      .merge(anomalies: active_anomalies)
  end

  private

  ANOMALIES_PER_PRODUCT = 2

  def active_anomalies
    DetectedAnomaly.active.includes(:product, :source).recent_first.group_by { |anomaly| anomaly.product.slug }
      .transform_values { |anomalies| anomalies.first(ANOMALIES_PER_PRODUCT).map(&:to_props) }
  end
end
