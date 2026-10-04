require_relative "test_helper"

# A-R2: the client view is a new hash built from allowlisted keys, never a scrubbed copy of the source.
class ProjectionTest < Minitest::Test
  CLIENT_KEYS = {
    top: %w[feature_title_plain project_plain tested_on status_as_of environment_label build_plain summary
            how_we_tested_plain requirements coverage journeys issues notes screenshots verdict],
    summary: %w[lead tested found means next],
    requirement: %w[id text_plain result journeys],
    coverage: %w[columns rows],
    coverage_row: %w[area_plain cells],
    journey: %w[id title_plain description_plain result evidence evidence_note_plain],
    issue: %w[id severity status title_plain impact_plain steps_plain expected_plain actual_plain screenshot
              fixed_in retested_on status_reason_plain],
    note: %w[id title_plain body_plain recommendation_plain coverage_column],
    screenshot: %w[id file group_plain variant alt caption focal dpr sha256]
  }.freeze

  def assert_only_client_keys(hash, kind)
    extra = hash.keys - CLIENT_KEYS.fetch(kind)
    assert_empty extra, "client #{kind} carries non-client keys #{extra.inspect}"
  end

  def assert_client_shape(client)
    assert_only_client_keys client, :top
    assert_only_client_keys client["summary"], :summary
    assert_only_client_keys client["coverage"], :coverage
    client["coverage"]["rows"].each { |row| assert_only_client_keys row, :coverage_row }
    client["requirements"].each { |item| assert_only_client_keys item, :requirement }
    client["journeys"].each { |item| assert_only_client_keys item, :journey }
    client["issues"].each { |item| assert_only_client_keys item, :issue }
    client["notes"].each { |item| assert_only_client_keys item, :note }
    client["screenshots"].each { |item| assert_only_client_keys item, :screenshot }
  end

  def each_hash(value, &block)
    case value
    when Hash
      block.call(value)
      value.each_value { |child| each_hash(child, &block) }
    when Array then value.each { |child| each_hash(child, &block) }
    end
  end

  def test_the_pass_with_notes_fixture_client_view_holds_only_allowlisted_keys
    assert_client_shape QaReport::Projection.client(load_fixture(:pass_with_notes))
  end

  def test_the_fail_fixture_client_view_holds_only_allowlisted_keys
    assert_client_shape QaReport::Projection.client(load_fixture(:fail))
  end

  def test_the_client_view_is_a_new_hash_that_shares_no_objects_with_the_source
    data = fixture_data(:fail)
    source = QaReport::Source.new(data, root: QaReportTestHelper::FIXTURES)
    source_hashes = []
    each_hash(data) { |hash| source_hashes << hash.object_id }

    each_hash(QaReport::Projection.client(source)) do |hash|
      refute_includes source_hashes, hash.object_id, "client view reuses a source hash: #{hash.keys.inspect}"
    end
  end

  # AC2 (A-R2)
  def test_the_fail_fixture_client_view_keeps_journey_1_plain_text_and_drops_every_canary
    client = QaReport::Projection.client(load_fixture(:fail))
    journey = find_by_id(client["journeys"], 1)
    json = JSON.generate(client)

    assert_equal "Set up the proposal in steps", journey["title_plain"]
    assert_equal "PASS", journey["result"]
    refute_includes json, "CANARY-INT-FAIL"
    refute_includes json, "CANARY-TECH-1"
    refute_includes json, "CANARY-INTERNAL"
  end

  def test_the_pass_with_notes_fixture_client_view_drops_every_canary
    refute_includes JSON.generate(QaReport::Projection.client(load_fixture(:pass_with_notes))), "CANARY"
  end

  def test_the_internal_view_keeps_the_canaries
    json = JSON.generate(QaReport::Projection.internal(load_fixture(:fail)))

    assert_includes json, "CANARY-INT-FAIL"
    assert_includes json, "CANARY-TECH-1"
  end

  def test_the_client_view_omits_notes_that_are_not_client_facing
    source = source_from(:pass_with_notes) { |data| find_by_id(data["notes"], "N1")["client_facing"] = false }

    assert_equal %w[N2], QaReport::Projection.client(source)["notes"].map { |note| note["id"] }
  end

  def test_the_client_view_omits_screenshots_with_internal_visibility
    source = source_from(:pass_with_notes) do |data|
      find_by_id(data["screenshots"], "2b").merge!("visibility" => "internal", "internal_reason" => "Shows the admin side.")
    end
    ids = QaReport::Projection.client(source)["screenshots"].map { |shot| shot["id"] }

    assert_equal %w[1a 1b 1c 2a 3a], ids
    refute_includes find_by_id(QaReport::Projection.client(source)["journeys"], 4)["evidence"], "2b"
  end

  def test_the_client_view_carries_the_computed_verdict
    assert_equal "PASS WITH NOTES", QaReport::Projection.client(load_fixture(:pass_with_notes))["verdict"]
    assert_equal "FAIL", QaReport::Projection.client(load_fixture(:fail))["verdict"]
  end
end

# Architecture §7: the approval digest covers the client projection and the raw screenshot bytes.
class DigestTest < Minitest::Test
  def digest_of(source)
    QaReport::Projection.digest(source)
  end

  def test_the_digest_is_a_stable_sha256_hex
    first = digest_of(load_fixture(:pass_with_notes))

    assert_match(/\A\h{64}\z/, first)
    assert_equal first, digest_of(load_fixture(:pass_with_notes))
  end

  def test_the_digest_changes_when_a_client_field_changes
    base = digest_of(load_fixture(:pass_with_notes))

    edits = [
      ->(data) { data["feature_title_plain"] = "Sections keep order" },
      ->(data) { find_by_id(data["journeys"], 3)["title_plain"] = "View it" },
      ->(data) { find_by_id(data["notes"], "N1")["body_plain"] = "Changed." }
    ]

    edits.each { |edit| refute_equal base, digest_of(source_from(:pass_with_notes) { |data| instance_exec(data, &edit) }) }
  end

  def test_the_digest_changes_when_a_client_screenshots_bytes_change
    base = digest_of(load_fixture(:pass_with_notes))

    with_fixture_copy(:pass_with_notes) do |root|
      File.binwrite(File.join(root, "pass_with_notes/screenshots/1a.png"), QaReportTestHelper.png(255, 0, 0))

      refute_equal base, digest_of(source_from(:pass_with_notes, root: root))
    end
  end

  def test_the_digest_ignores_internal_only_edits
    base = digest_of(load_fixture(:fail))

    edited = source_from(:fail) do |data|
      data["internal"]["environment"] = "CANARY-INTERNAL-ENV something else entirely"
      data["internal"]["cleanup"] = "CANARY-INTERNAL-CLEANUP nothing left behind"
      data["card"] = 9999
      find_by_id(data["journeys"], 1)["technical_detail"] = "CANARY-TECH-1 rewritten"
      find_by_id(data["issues"], "D3")["root_cause"] = "CANARY-INTERNAL-D3 rewritten"
    end

    assert_equal base, digest_of(edited)
  end

  def test_the_digest_ignores_a_change_to_the_override_reason
    with_reason = ->(reason) do
      source_from(:pass_with_notes) { |data| data["verdict_override"] = { "verdict" => "PASS", "reason" => reason } }
    end

    assert_equal digest_of(with_reason.call("Accepted by owner")), digest_of(with_reason.call("Owner accepted on call"))
  end
end
