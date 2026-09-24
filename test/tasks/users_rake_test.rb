require "test_helper"
require "rake"

class UsersRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("users:create")
    Rake::Task["users:create"].reenable
  end

  teardown do
    ENV.delete("EMAIL")
    ENV.delete("NAME")
  end

  test "users:create pre-provisions an every.to person with no password" do
    ENV["EMAIL"] = "rake-created@every.to"
    ENV["NAME"] = "Rake Person"

    assert_difference -> { User.count }, 1 do
      assert_output(/Created user rake-created@every.to/) { Rake::Task["users:create"].invoke }
    end

    user = User.find_by!(email_address: "rake-created@every.to")
    assert_equal "Rake Person", user.name
    assert_nil user.every_user_id
  end

  test "users:create refuses an address outside every.to" do
    ENV["EMAIL"] = "someone@gmail.com"

    assert_no_difference -> { User.count } do
      assert_raises(SystemExit) { capture_io { Rake::Task["users:create"].invoke } }
    end
  end

  test "no open registration route exists" do
    helpers = Rails.application.routes.url_helpers

    assert_not helpers.respond_to?(:users_path), "there must be no users create/registration route"
    assert_not helpers.respond_to?(:new_user_registration_path)
  end
end
