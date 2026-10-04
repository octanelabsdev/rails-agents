require_relative "test_helper"

# Exact-byte snapshots of both files for both fixtures; any drift is reviewed, never absorbed.
class GoldenTest < Minitest::Test
  %i[pass_with_notes fail].each do |name|
    define_method("test_#{name}_client_html_matches_its_golden_file") do
      assert_golden "#{name}-client.html", client_html(name)
    end

    define_method("test_#{name}_internal_html_matches_its_golden_file") do
      assert_golden "#{name}-internal.html", internal_html(name)
    end
  end

  # Only an internal file with a blocked client copy can render the "—" cell, so this pins it.
  def test_fail_internal_html_with_a_blocked_client_matches_its_golden_file
    source = source_from(:fail) { |data| data["journeys"][3].delete("evidence_note_plain") }
    html = internal_html(source, status: QaReport::ClientStatus.blocked("journeys[4].evidence needs a client-visible screenshot"))

    assert_includes html, "No screenshot"
    assert_golden "fail-blocked-client-internal.html", html
  end

  # QA: with no client screenshots there is no 05 Screenshots, How we tested is 05 and Contents has 5 links.
  def test_fail_without_client_screenshots_client_html_matches_its_golden_file
    client = client_html(without_client_screenshots)

    refute_includes client, "05 · Screenshots"
    assert_includes client, "05 · How we tested"
    assert_golden "fail-no-client-screenshots-client.html", client
  end

  # One golden per test, because update mode skips right after writing.
  def test_fail_without_client_screenshots_internal_html_matches_its_golden_file
    assert_golden "fail-no-client-screenshots-internal.html", internal_html(without_client_screenshots)
  end

  private

  def without_client_screenshots
    source_from(:fail) do |data|
      data["screenshots"].each { |shot| shot.merge!("visibility" => "internal", "internal_reason" => "Shows the admin side.") }
      data["journeys"].each { |journey| journey["evidence_note_plain"] ||= "Checked directly" }
    end
  end
end
