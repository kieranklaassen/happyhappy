require "test_helper"

class ReportItemToolTest < ActiveSupport::TestCase
  def call(**arguments)
    ReportItemTool.call(item_id: items(:claimed_intercom).id, server_context: { agent: agents(:cursor) }, **arguments)
  end

  test "an in progress report keeps the claim" do
    payload = call(summary: "Asked billing for the invoice.", status: "in_progress").structured_content["item"]

    assert_equal "in_progress", payload["status"]
    assert_equal "Cursor", payload["claimed_by"]
    assert_equal "reported", payload["timeline"].last["kind"]
  end

  test "an invalid status or link is a tool error" do
    assert_equal "Status must be one of: in_progress, handled.",
      call(summary: "Done", status: "dismissed").content.first[:text]
    assert_equal "The link must be an http or https URL.",
      call(summary: "Done", status: "handled", link: "javascript:alert(1)").content.first[:text]
    assert items(:claimed_intercom).reload.status_claimed?
  end
end
