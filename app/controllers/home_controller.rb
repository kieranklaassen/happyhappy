# frozen_string_literal: true

# The home page is the mood dashboard: a watercolor crowd of today's customers.
class HomeController < InertiaController
  def index
    product = Product.find_by(slug: params[:product]) if params[:product].present?
    render inertia: "home/index", props: MoodScene.new(range: params[:range], product: product).props
  end
end
