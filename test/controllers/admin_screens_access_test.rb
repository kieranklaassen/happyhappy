# frozen_string_literal: true

require "test_helper"

class AdminScreensAccessTest < ActionDispatch::IntegrationTest
  test "every admin screen requires a signed-in user" do
    product = products(:cora)
    category = categories(:bug)
    source = sources(:slack_community)

    requests = [
      [ :get, products_path ], [ :get, new_product_path ], [ :post, products_path ],
      [ :get, edit_product_path(product) ], [ :patch, product_path(product) ],
      [ :patch, retire_product_path(product) ], [ :patch, restore_product_path(product) ],
      [ :get, categories_path ], [ :post, categories_path ], [ :patch, category_path(category) ],
      [ :patch, retire_category_path(category) ], [ :patch, restore_category_path(category) ],
      [ :get, sources_path ], [ :get, new_source_path ], [ :post, sources_path ],
      [ :get, edit_source_path(source) ], [ :patch, source_path(source) ],
      [ :patch, rotate_secret_source_path(sources(:cora_app_webhook)) ],
      [ :get, settings_path ], [ :patch, settings_path ]
    ]

    requests.each do |verb, path|
      send(verb, path)
      assert_redirected_to new_session_path, "#{verb.upcase} #{path} should require sign-in"
    end
    assert_nil products(:cora).reload.retired_at
    assert_equal "hhsec_cora-app-test-secret", sources(:cora_app_webhook).reload.signing_secret
  end
end
