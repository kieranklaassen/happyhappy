# frozen_string_literal: true

require "test_helper"

class InertiaSSRTimeoutTest < ActiveSupport::TestCase
  test "the SSR request connects and reads with the 2-second default when env is unset" do
    http = ssr_connection

    assert_equal [ 2.0, 2.0 ], [ http.open_timeout, http.read_timeout ]
  end

  test "ordinary HTTP keeps Net::HTTP's own timeouts" do
    stub_request(:get, "http://example.test/").to_return(body: "ok")

    http = connections { Net::HTTP.start("example.test", 80) { |client| client.get("/") } }.sole

    assert_equal [ 60, 60 ], [ http.open_timeout, http.read_timeout ]
  end

  private

  # The connection SSRRenderer really opens under this app's configuration. Only
  # the built bundle check is lifted, because tests do not build one.
  def ssr_connection
    stub_request(:post, "#{InertiaRails.configuration.ssr_url}/render")
      .to_return(body: { head: [], body: "<div></div>" }.to_json)
    config = InertiaRails.configuration.merge(InertiaRails::Configuration.new(ssr_bundle: nil))

    connections do
      rendered = InertiaRails::SSRRenderer.new(config, page: { component: "home/index" }).render
      assert_equal "<div></div>", rendered["body"]
    end.sole
  end

  # Every Net::HTTP connection started while the block runs.
  def connections(&block)
    started = []
    trace = TracePoint.new(:call) do |point|
      started << point.self if point.method_id == :start && point.self.is_a?(Net::HTTP)
    end
    trace.enable(target_thread: Thread.current, &block)
    started.uniq(&:object_id)
  end
end

class InertiaDevtoolsTest < ActiveSupport::TestCase
  test "DevTools stays off in every environment, development included" do
    assert_equal false, InertiaRails.configuration.devtools.enabled
  end
end

class InertiaSSRDisabledByDefaultTest < ActionDispatch::IntegrationTest
  test "SSR is disabled by default" do
    refute InertiaRails.configuration.ssr_enabled,
      "SSR must ship disabled by default (enable via INERTIA_SSR_ENABLED)"
  end

  test "a public page still renders the client-side Inertia component" do
    get new_session_path

    assert_response :success
    assert_inertia_component "auth/sign_in"
  end
end
