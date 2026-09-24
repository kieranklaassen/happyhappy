# frozen_string_literal: true

class HomeController < InertiaController
  def index
    redirect_to items_path
  end
end
