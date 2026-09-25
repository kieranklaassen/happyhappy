# frozen_string_literal: true

require "test_helper"

class ProductsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:every_ana) }

  test "index lists active and retired products with their settings" do
    get products_path

    assert_response :success
    assert_inertia_component "products/index"
    active = inertia.props[:products].map { |product| product[:name] }
    assert_equal %w[Cora Sparkle Spiral], active
    assert_equal %w[Lex], inertia.props[:retired_products].map { |product| product[:name] }

    spiral = inertia.props[:products].find { |product| product[:slug] == "spiral" }
    assert_equal %w[spiral draft writing], spiral[:hint_words]
    assert_equal 0.7, spiral[:escalation_threshold]
    assert_equal 17, spiral[:digest_hour]
    assert_equal "C0SPIRALSUPPORT", spiral[:slack_channel_id]
    assert_nil inertia.props[:products].find { |product| product[:slug] == "cora" }[:escalation_threshold]
    assert_equal 0.8, inertia.props[:default_escalation_threshold]
  end

  test "new renders an empty form with the default digest hour" do
    get new_product_path

    assert_inertia_component "products/form"
    assert_nil inertia.props[:product][:id]
    assert_equal 9, inertia.props[:product][:digest_hour]
    assert_equal 0.8, inertia.props[:default_escalation_threshold]
  end

  test "creating a product with hint words lists it and feeds classification criteria" do
    assert_difference -> { Product.count }, 1 do
      post products_path, params: { product: {
        name: "Monologue", description: "Dictation app.", hint_words: "monologue, dictation\nvoice, dictation",
        slack_channel_id: "C0MONO", escalation_threshold: "0.75", digest_hour: "8"
      } }
    end

    assert_redirected_to products_path
    product = Product.find_by!(name: "Monologue")
    assert_equal "monologue", product.slug
    assert_equal %w[monologue dictation voice], product.hint_words
    assert_equal 0.75, product.escalation_threshold
    assert_equal 8, product.digest_hour
    assert_includes Product.active, product

    follow_redirect!
    assert_includes inertia.props[:products].map { |row| row[:name] }, "Monologue"
    assert_equal "Monologue created.", inertia.props[:flash]["notice"]
  end

  test "a blank escalation threshold falls back to the global default" do
    post products_path, params: { product: { name: "Monologue", escalation_threshold: "", digest_hour: "9" } }

    assert_nil Product.find_by!(name: "Monologue").escalation_threshold
  end

  test "a duplicate product name shows a validation error" do
    assert_no_difference -> { Product.count } do
      post products_path, params: { product: { name: "Cora", digest_hour: "9" } }
    end

    assert_redirected_to new_product_path
    follow_redirect!
    assert_inertia_component "products/form"
    assert_equal [ "has already been taken" ], inertia.props[:errors]["name"]
  end

  test "a duplicate slug shows a validation error" do
    post products_path, params: { product: { name: "Cora Two", slug: "cora", digest_hour: "9" } }

    follow_redirect!
    assert_equal [ "has already been taken" ], inertia.props[:errors]["slug"]
  end

  test "edit renders the product with hint words" do
    get edit_product_path(products(:cora))

    assert_inertia_component "products/form"
    assert_equal products(:cora).id, inertia.props[:product][:id]
    assert_equal %w[cora brief inbox screener], inertia.props[:product][:hint_words]
  end

  test "update changes a product" do
    patch product_path(products(:cora)), params: { product: { description: "Inbox assistant.", digest_hour: "7" } }

    assert_redirected_to products_path
    assert_equal "Inbox assistant.", products(:cora).reload.description
    assert_equal 7, products(:cora).digest_hour
  end

  test "an out of range escalation threshold is rejected on update" do
    patch product_path(products(:cora)), params: { product: { escalation_threshold: "1.5" } }

    assert_redirected_to edit_product_path(products(:cora))
    follow_redirect!
    assert inertia.props[:errors]["escalation_threshold"].present?
    assert_nil products(:cora).reload.escalation_threshold
  end

  test "retiring a product keeps its items readable and restoring brings it back" do
    item = items(:angry_slack)
    product = item.product

    patch retire_product_path(product)

    assert_redirected_to products_path
    assert product.reload.retired?
    assert_not_includes Product.active, product
    assert_equal product, item.reload.product

    patch restore_product_path(product)

    assert_not product.reload.retired?
  end
end
