require "test_helper"

class Slack::EscalationMessageTest < ActiveSupport::TestCase
  test "shows the quote, product, source, customer handle, and item link" do
    payload = Slack::EscalationMessage.new(escalations(:angry_slack_posted)).to_h
    rendered = payload[:blocks].map { |block| block.dig(:text, :text) || block[:elements].sole[:text] }.join("\n")
    item = items(:angry_slack)

    assert_equal "Angry Cora customer ana_customer on Every community Slack", payload[:text]
    assert_includes rendered, "&gt; Cora deleted half my inbox this morning"
    assert_includes rendered, "*Product:* Cora"
    assert_includes rendered, "*Source:* Every community Slack"
    assert_includes rendered, "*Customer:* ana_customer"
    assert_includes rendered, "*Anger:* 86%"
    assert_includes rendered, "/items/#{item.id}|Open in happyhappy>"
    assert_includes rendered, "<#{item.permalink}|View original>"
  end

  test "escapes Slack control characters in customer text" do
    escalation = escalations(:angry_slack_posted)
    escalation.message.update!(body: "<!channel> refunds & <https://evil.example|click>")

    quote = Slack::EscalationMessage.new(escalation).to_h[:blocks].second.dig(:text, :text)

    assert_equal "&gt; &lt;!channel&gt; refunds &amp; &lt;https://evil.example|click&gt;", quote
  end

  test "escapes the customer handle in the notification fallback text" do
    escalation = escalations(:angry_slack_posted)
    escalation.item.update!(author_handle: "<!channel>")

    assert_equal "Angry Cora customer &lt;!channel&gt; on Every community Slack",
      Slack::EscalationMessage.new(escalation).to_h[:text]
  end

  test "falls back to the email address when the customer has no handle" do
    escalation = Escalation.new(item: items(:claimed_intercom), product: products(:cora), slack_channel_id: "C0CORASUPPORT")

    payload = Slack::EscalationMessage.new(escalation).to_h

    assert_includes payload[:text], "bo@example.com"
    assert_includes payload[:blocks].second.dig(:text, :text), "I was charged twice"
  end
end
