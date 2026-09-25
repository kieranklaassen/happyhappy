# frozen_string_literal: true

require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  include AnomalyHelper

  test "the mood dashboard needs a signed-in person" do
    get root_path

    assert_redirected_to new_session_path
  end

  test "GET / renders the mood dashboard with the scene and today's summary" do
    sign_in_as users(:one)

    get root_path

    assert_response :success
    assert_inertia_component "home/index"
    assert_equal %w[Cora Sparkle], inertia.props[:scene].map { |group| group.dig("product", "name") }
    assert_equal 3, inertia.props.dig(:today, "people")
    assert_equal({ "range" => "24h", "product" => nil }, inertia.props[:filters])
  end

  test "the product and range filters pass through" do
    sign_in_as users(:one)

    get root_path, params: { product: "cora", range: "7d" }

    assert_equal({ "range" => "7d", "product" => "cora" }, inertia.props[:filters])
    assert_equal [ "Cora" ], inertia.props[:scene].map { |group| group.dig("product", "name") }
  end

  test "an unknown product shows everyone" do
    sign_in_as users(:one)

    get root_path, params: { product: "nope" }

    assert_nil inertia.props.dig(:filters, "product")
  end

  test "InertiaController shares flash and locale with every page" do
    sign_in_as users(:one)

    get root_path

    assert inertia.props.key?("flash"), "flash should be shared on every Inertia page"
    assert_inertia_props({ locale: "en" })
  end

  test "active anomalies are grouped by product slug for the dashboard callouts" do
    sign_in_as users(:one)
    anomaly = create_anomaly!
    create_anomaly!(status: :ended, ended_at: Time.current)

    get root_path

    assert_equal [ "cora" ], inertia.props[:anomalies].keys
    assert_equal [ anomaly.id ], inertia.props[:anomalies]["cora"].map { |row| row["id"] }
  end
end
