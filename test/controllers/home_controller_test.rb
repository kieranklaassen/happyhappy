# frozen_string_literal: true

require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "GET / sends a signed-in person to the feed" do
    sign_in_as users(:every_ana)

    get root_path

    assert_redirected_to items_path
  end

  test "GET / asks a signed-out visitor to sign in" do
    get root_path

    assert_redirected_to new_session_path
  end

  test "InertiaController shares flash and locale with every page" do
    get new_session_path

    assert inertia.props.key?("flash"), "flash should be shared on every Inertia page"
    assert_inertia_props({ locale: "en" })
  end
end
