# frozen_string_literal: true

# The home page is the mood dashboard: a watercolor crowd of today's customers.
class HomeController < InertiaController
  ANOMALIES_PER_PRODUCT = 2

  def index
    product = Product.find_by(slug: params[:product]) if params[:product].present?
    mood = MoodScene.new(range: params[:range], product: product)

    # Lambdas, so a partial reload computes only the props it asks for. Live
    # reloads and the 30-second poll ask for `scene` and `today`.
    render inertia: "home/index", props: {
      scene: -> { mood.scene },
      today: -> { mood.today },
      filters: mood.filters,
      options: -> { mood.options },
      anomalies: -> { active_anomalies }
    }
  end

  private

  def active_anomalies
    DetectedAnomaly.active.includes(:product, :source).recent_first.group_by { |anomaly| anomaly.product.slug }
      .transform_values do |anomalies|
        # Product-wide, bad news, and stronger first; the index keeps ties most recent first.
        anomalies.sort_by.with_index { |anomaly, index| [ anomaly.source_id ? 1 : 0, anomaly.negative? ? 0 : 1, -anomaly.strength, index ] }
          .first(ANOMALIES_PER_PRODUCT).map(&:to_props)
      end
  end
end
