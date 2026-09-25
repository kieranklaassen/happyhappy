require "test_helper"

class CIWorkflowTest < ActiveSupport::TestCase
  WORKFLOW = YAML.load_file(Rails.root.join(".github/workflows/ci.yml")).freeze
  SHA_PIN = %r{\A[\w.-]+/[\w.-]+(/[\w.-]+)*@[0-9a-f]{40}\z}

  test "the workflow parses and defines the four-job skeleton" do
    assert_equal %w[check_js lint scan_ruby test], WORKFLOW.fetch("jobs").keys.sort
  end

  test "every action is pinned to a 40-character commit SHA" do
    WORKFLOW.fetch("jobs").each do |job_name, job|
      job.fetch("steps").each do |step|
        uses = step["uses"]
        next unless uses

        assert_match SHA_PIN, uses, "#{job_name}: #{uses.inspect} must be pinned to a commit SHA"
      end
    end
  end

  test "every Verification Contract gate runs in CI" do
    commands = WORKFLOW.fetch("jobs").values.flat_map { |job| job.fetch("steps").filter_map { |step| step["run"] } }

    [ "bin/brakeman --no-pager", "bin/bundler-audit", "bin/rubocop", "npm run check",
      "npm audit --omit=dev --audit-level=moderate", "bin/rails db:test:prepare test" ].each do |gate|
      assert commands.any? { |command| command.include?(gate) }, "CI does not run #{gate}"
    end
  end

  test "the test job builds the Vite test assets before the parallel test run" do
    runs = WORKFLOW.dig("jobs", "test", "steps").filter_map { |step| step["run"] }
    build = runs.index { |command| command.include?("bin/vite build --mode test") }
    tests = runs.index { |command| command.include?("bin/rails db:test:prepare test") }

    assert build, "the test job must build the Vite test assets"
    assert_operator build, :<, tests
  end
end
