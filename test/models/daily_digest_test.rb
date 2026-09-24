require "test_helper"

class DailyDigestTest < ActiveSupport::TestCase
  test "uses the digests table" do
    assert_equal "digests", DailyDigest.table_name
    assert_equal products(:cora), digests(:cora_yesterday).product
  end

  test "one digest per product per day" do
    duplicate = DailyDigest.new(product: products(:cora), date: Date.yesterday)

    refute duplicate.valid?
    assert DailyDigest.new(product: products(:spiral), date: Date.yesterday).valid?
  end
end
