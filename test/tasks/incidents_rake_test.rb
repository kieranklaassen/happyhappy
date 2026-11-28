require "test_helper"
require "rake"

class IncidentsRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("incidents:preview")
    Rake::Task["incidents:preview"].reenable
  end

  test "IncidentPreview.page wraps variants in an HTML document with embedded styles" do
    payload = {
      text: "Cora spike detected",
      blocks: [
        { type: "section", text: { type: "mrkdwn", text: ":rotating_light: *Spike*" } }
      ]
    }

    html = IncidentPreview.page([ [ "Open incident", payload ], [ "Resolved incident", payload ] ])

    assert_includes html, "<!doctype html>"
    assert_includes html, "<title>Incident ping preview</title>"
    assert_includes html, "<style>"
    assert_includes html, "<h2>Open incident</h2>"
    assert_includes html, "<h2>Resolved incident</h2>"
    assert_includes html, "🚨 <b>Spike</b><br>"
  end

  test "IncidentPreview.message renders blocks and escapes titles and fallback text" do
    payload = {
      text: "Alert <script>alert(1)</script> & details",
      blocks: [
        { type: "section", text: { type: "mrkdwn", text: "Body line" } }
      ]
    }

    html = IncidentPreview.message("Title <tag> & \"quotes\"", payload)

    assert_includes html, "<h2>Title &lt;tag&gt; &amp; &quot;quotes&quot;</h2>"
    assert_includes html, '<div class="section">Body line<br></div>'
    assert_includes html, '<p class="fallback">Notification text: Alert &lt;script&gt;alert(1)&lt;/script&gt; &amp; details</p>'
  end

  test "IncidentPreview.block renders section, context, actions, and ignores unknown block types" do
    section = IncidentPreview.block({ type: "section", text: { type: "mrkdwn", text: "*Alert*" } })
    context = IncidentPreview.block({
      type: "context",
      elements: [ { type: "mrkdwn", text: "First" }, { type: "mrkdwn", text: ":warning: Second" } ]
    })
    actions = IncidentPreview.block({
      type: "actions",
      elements: [ { text: { text: "Resolve" }, action_id: "resolve_incident", style: "primary" } ]
    })
    unknown = IncidentPreview.block({ type: "divider" })

    assert_equal '<div class="section"><b>Alert</b><br></div>', section
    assert_equal '<div class="context">First<br> ⚠️ Second<br></div>', context
    assert_equal '<div class="actions"><span class="button primary" title="action resolve_incident">Resolve</span></div>', actions
    assert_equal "", unknown
  end

  test "IncidentPreview.button renders link and action variants and escapes labels and titles" do
    link_button = IncidentPreview.button(
      text: { text: "Open <incident> & review" },
      url: 'https://example.com/incidents/1?a=1&b="2"',
      style: "primary"
    )
    action_button = IncidentPreview.button(
      text: { text: "Mark resolved" },
      action_id: 'resolve&"now"'
    )

    assert_equal(
      '<span class="button primary" title="link to https://example.com/incidents/1?a=1&amp;b=&quot;2&quot;">' \
      "Open &lt;incident&gt; &amp; review</span>",
      link_button
    )
    assert_equal(
      '<span class="button " title="action resolve&amp;&quot;now&quot;">Mark resolved</span>',
      action_button
    )
  end

  test "IncidentPreview.mrkdwn converts mentions, subteams, links, formatting, quotes, and emoji" do
    input = [
      ":rotating_light: *Cora incident* ~old~ for <@U0AGQDHRV8U> and <@W99XYZ> cc <!subteam^S0BINGSU01>",
      "&gt; Quote with <https://example.com/incidents/42|View details> :white_check_mark: :warning: :unknown_emoji:",
      "Keep foo*bar*baz and a~b~c intact"
    ].join("\n")

    html = IncidentPreview.mrkdwn(input)

    assert_equal(
      '🚨 <b>Cora incident</b> <s>old</s> for <span class="mention">@U0AGQDHRV8U</span> ' \
      'and <span class="mention">@W99XYZ</span> cc <span class="mention">@on-call group S0BINGSU01</span><br>' \
      '<blockquote>Quote with <a href="https://example.com/incidents/42">View details</a> ✅ ⚠️ :unknown_emoji:</blockquote>' \
      "Keep foo*bar*baz and a~b~c intact<br>",
      html
    )
    assert_equal "", IncidentPreview.mrkdwn(nil)
  end

  test "incidents:preview aborts outside development" do
    _, err = capture_io do
      assert_raises(SystemExit) { Rake::Task["incidents:preview"].invoke }
    end

    assert_includes err, "incidents:preview only runs in development"
  end
end
