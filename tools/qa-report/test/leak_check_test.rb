require_relative "test_helper"
require "qa_report/leak_check"
require "qa_report/config"

# the client file's text, attributes, title and file name are scanned before anything is written.
class LeakCheckTest < Minitest::Test
  CLEAN_NAME = "example-outfitters-qa-report-2026-10-01-authoring-a-proposal-that-matches-the-approved-design.html"
  PROJECT_DENY = ["Example Co staging"].freeze

  # The fail fixture plus a second internal host, as the AC seeds it.
  def fail_source
    source_from(:fail) { |data| data["internal"]["process_notes"] << "Seeded CANARY-HOST.test for the scan." }
  end

  def scanner(source = fail_source, deny: PROJECT_DENY) = QaReport::LeakCheck.new(source, deny: deny)

  def clean_client_html = @clean_client_html ||= client_html(fail_source)

  # Seeds visible text into the client's first summary paragraph, so the leak sits inside real client markup.
  def with_text(html, text) = html.sub("<p>", "<p>#{text} ")

  # What the build actually scans: the client page with placeholder images.
  def scan_html(source) = renderer_for(source).client_scan_html

  def hits(html, name: CLEAN_NAME, source: fail_source, deny: PROJECT_DENY)
    scanner(source, deny: deny).hits(html, file_name: name)
  end

  def assert_caught(found, needle, where)
    refute_empty found, "#{needle.inspect} in the client #{where} reached a client file unblocked"
    assert found.any? { |hit| hit.downcase.include?(needle.downcase) },
      "the hit report must name #{needle.inspect}, got #{found.inspect}"
  end

  def test_the_real_client_files_of_both_fixtures_are_clean
    assert_empty hits(clean_client_html), "the fail fixture's own client prose tripped the scan"

    pass = load_fixture(:pass_with_notes)
    assert_empty hits(client_html(pass), source: pass, name: "example-outfitters-qa-report-2026-10-02-x.html"),
      "the pass_with_notes fixture's own client prose tripped the scan"
  end

  # One seeded leak per run, so each deny source is proven on its own.
  SEEDED = ["CANARY-INT-FAIL", "CANARY-HOST.test", "Example Co staging", "/Users/", "file://", "ApiToken", "Fizzy",
            "proposal.rb:12", "bin/rails", "db/schema"].freeze

  SEEDED.each_with_index do |leak, index|
    define_method("test_seeded_leak_#{index + 1}_in_client_text_is_caught") do
      assert_empty hits(clean_client_html), "precondition: the unseeded client file is clean"
      assert_caught hits(with_text(clean_client_html, "See #{leak} here.")), leak, "text"
    end
  end

  def test_every_built_in_pattern_is_caught_case_insensitively
    ["obsidian vault", "LOCALHOST", "127.0.0.1", "admin.example.local", "db.example.internal", "app.example.test",
     "apitoken", "FIZZY", "app/models/", "app/controllers/", "app/views/", "app/components/", "app/services/",
     "/users/", "FILE://", "BIN/RAILS", "DB/SCHEMA", "Proposal.RB:40"].each do |leak|
      assert_caught hits(with_text(clean_client_html, "Look at #{leak} now.")), leak, "text"
    end
  end

  def test_values_from_the_internal_block_are_caught
    pass = load_fixture(:pass_with_notes)
    html = client_html(pass)
    ["qa@example.com", "app.example.test", "CANARY-INTERNAL-CLEANUP"].each do |leak|
      assert_caught hits(with_text(html, "Contact #{leak} please."), source: pass, name: "x.html"), leak, "text"
    end
  end

  # Derived tokens shorter than 4 characters are ignored, so internal counts never block client stat lines.
  def test_a_short_number_from_the_internal_block_does_not_block_client_prose
    source = source_from(:fail) { |data| data["internal"]["process_notes"] << "Retried 3 times; 7 rows checked." }
    html = with_text(client_html(source), "Journeys passed: 3 of 7.")

    assert_empty hits(html, source: source), "a bare '3' from internal text must not block '3 of 7'"
  end

  def test_a_four_digit_internal_id_blocks_client_text
    assert_includes fail_source.data["internal"]["environment"], "9003", "precondition: the internal block holds 9003"

    assert_caught hits(with_text(clean_client_html, "Record 9003 was checked.")), "9003", "text"
  end

  def test_a_leak_in_an_attribute_is_caught
    html = clean_client_html.sub(/alt="/, 'alt="Seen on admin.example.local, ')
    assert_caught hits(html), "admin.example.local", "alt attribute"

    html = clean_client_html.sub(/<a href="#/, '<a data-from="CANARY-INT-FAIL" href="#')
    assert_caught hits(html), "CANARY-INT-FAIL", "data attribute"
  end

  def test_a_leak_in_the_title_is_caught
    html = clean_client_html.sub("<title>", "<title>Fizzy ")
    assert_caught hits(html), "Fizzy", "title"
  end

  def test_a_leak_in_the_file_name_is_caught
    assert_caught hits(clean_client_html, name: "fizzy-co-qa-report-2026-10-01-x.html"), "fizzy", "file name"
    assert_caught hits(clean_client_html, name: "example-co-staging-qa-report-2026-10-01-x.html",
                       deny: ["example-co-staging"]), "example-co-staging", "file name"
  end

  def test_the_scan_rendering_differs_from_the_real_client_file_only_in_payloads
    %i[pass_with_notes fail].each do |name|
      renderer = renderer_for(name)
      real = renderer.client_html
      scanned = renderer.client_scan_html

      assert_includes real, "data:image/", "precondition: the real client file embeds its screenshots"
      refute_includes scanned, "base64", "#{name}: the scan rendering still carries an embedded payload"
      assert_equal strip_payloads(real), strip_payloads(scanned), "#{name}: the scan read different text than the client file holds"
    end
  end

  def test_a_non_base64_data_uri_is_still_scanned
    html = clean_client_html.sub("<p>", %(<p><a href="data:text/plain,see file:///Users/qa/notes">notes</a>))
    refute_empty hits(html), "only base64 payloads are exempt; readable data: content can still leak"
  end

  def test_a_data_base64_prefix_in_client_prose_does_not_hide_a_leak
    assert_caught hits(with_text(clean_client_html, "See data:;base64,Fizzy here.")), "Fizzy", "text"
  end

  def test_an_internal_hex_token_not_in_the_build_line_blocks_client_text
    hex = "9f86d081884c7d659a2feaa0c55ad015"
    source = source_from(:fail) { |data| data["internal"]["environment"] += " Session #{hex}." }

    assert_caught hits(with_text(client_html(source), "Ref #{hex}."), source: source), hex, "text"
  end

  def test_the_commit_hash_on_the_client_build_line_does_not_block
    source = load_fixture(:fail)
    html = client_html(source)
    assert_includes html, "a1b2c3d", "precondition: the client build line shows the commit"
    assert_includes source.data["internal"]["sources"], "a1b2c3d", "precondition: the internal block names it too"

    assert_empty hits(html, source: source)
  end

  def test_the_test_date_in_the_internal_block_does_not_block
    source = source_from(:pass_with_notes) { |data| data["internal"]["process_notes"] << "Ran on 2026-10-02." }
    name = "example-outfitters-qa-report-2026-10-02-proposal-sections-keep-their-order.html"

    assert_empty hits(client_html(source), source: source, name: name), "the tested_on date is in the file name by design"
  end

  def test_generic_words_do_not_trip_the_scan
    prose = "Our local team tested the internal review on a test server with a staging token. " \
            "We ran the last test. Testing continued in the app, and the schema of the database held. " \
            "Users can rail against it; the vault was not opened. We checked 12 rows."
    assert_empty hits(with_text(clean_client_html, prose)), "ordinary client words must not block a client file"
  end

  def test_a_hit_reports_the_term_with_40_characters_of_context
    before = "Everything worked as expected for all of"
    after = "and nothing else came up during the round"
    found = hits(with_text(clean_client_html, "#{before} CANARY-INT-FAIL #{after}."))

    assert_equal 1, found.size, "one leak gives one hit, got #{found.inspect}"
    hit = found.first
    assert_includes hit, "CANARY-INT-FAIL"
    assert_includes hit, before[-30..], "the hit must carry the text just before the leak"
    assert_includes hit, after[0, 30], "the hit must carry the text just after the leak"
    refute_includes hit, "Everything worked", "context is capped at 40 characters each side, not the whole page"
  end

  # A deny phrase must not slip through because the words are split by other whitespace.
  { "a newline" => "\n", "two spaces" => "  ", "a non-breaking space" => "\u00A0", "an &nbsp; entity" => "&nbsp;" }.each do |label, gap|
    define_method("test_a_deny_phrase_split_by_#{label.delete("&;").tr(" -", "__")}_is_caught") do
      found = hits(with_text(clean_client_html, "Met Tom#{gap}Smith today."), deny: ["Tom Smith"])
      refute_empty found, "\"Tom Smith\" split by #{label} reached the client text unblocked"
    end
  end

  def test_a_deny_phrase_with_a_single_space_is_caught
    assert_caught hits(with_text(clean_client_html, "Met Tom Smith today."), deny: ["Tom Smith"]), "Tom Smith", "text"
  end

  [["\\b", "a word boundary"], ["(?=x)", "a lookahead"]].each do |pattern, label|
    define_method("test_a_zero_width_deny_pattern_like_#{label.tr(" ", "_")}_fails_closed_naming_the_pattern") do
      error = assert_raises(QaReport::ConfigError, "deny #{pattern.inspect} was silently dropped, so the scan ran without it") do
        hits(clean_client_html, deny: [{ "pattern" => pattern }])
      end
      assert error.problems.any? { |problem| problem.include?(pattern) }, "the error must name #{pattern.inspect}: #{error.problems.inspect}"
    end
  end

  def test_check_raises_a_client_block_that_exits_2
    error = assert_raises(QaReport::ClientBlocked) do
      scanner.check!(with_text(clean_client_html, "Fizzy"), file_name: CLEAN_NAME)
    end
    assert_equal 2, error.exit_code
    assert error.problems.any? { |problem| problem.include?("Fizzy") }, error.problems.inspect
  end

  def test_check_passes_a_clean_file
    assert_nil scanner.check!(clean_client_html, file_name: CLEAN_NAME)
  end

  # Canary: every internal string the source holds is absent from the client output.
  def test_no_internal_string_reaches_the_client_file
    %i[pass_with_notes fail].each do |name|
      source = load_fixture(name)
      html = client_html(source)
      internal_strings(source).each do |value|
        refute_includes html, value, "#{name}: an internal value reached the client file"
      end
      assert_empty hits(html, source: source, name: "x.html")
    end
  end

  # A lookahead passes any fixed-sample check, so the scan itself must refuse a match it would otherwise drop.
  def test_a_lookahead_deny_pattern_on_text_containing_its_phrase_is_a_config_error_not_a_clean_scan
    pattern = "(?=Project Falcon)"
    html = with_text(clean_client_html, "Codename Project Falcon is on track.")

    error = assert_raises(QaReport::ConfigError, "a lookahead deny entry let 'Project Falcon' through with no hits") do
      hits(html, deny: [{ "pattern" => pattern }])
    end
    assert_includes error.message, pattern, "the config error must name the deny pattern the operator wrote"
  end

  def test_the_config_check_matches_case_insensitively_like_the_scan
    config = QaReport::Config.new({ "deny" => [{ "pattern" => "(?=Q)" }] }, Dir.tmpdir)

    error = assert_raises(QaReport::ConfigError, "(?=Q) is zero-width on any 'q' once case is ignored, as the scan ignores it") do
      config.check_usable!
    end
    assert_includes error.message, "(?=Q)", "the config error must name the deny pattern the operator wrote"
  end

  # Prose dressed up as an embedded payload is still prose the client reads.
  PAYLOAD_IMITATIONS = {
    "Notes in url(data:x;base64,/Users/example/Fizzy" => [[], %w[/Users/ Fizzy]],
    "Card url(data:a;base64,Fizzy board" => [[], %w[Fizzy]],
    "url(data:x;base64,Brightwater" => [%w[Brightwater], %w[Brightwater]]
  }.freeze

  PAYLOAD_IMITATIONS.each_with_index do |(prose, (deny, terms)), index|
    define_method("test_prose_imitating_an_embedded_payload_#{index + 1}_is_still_scanned") do
      assert_empty hits(clean_client_html, deny: PROJECT_DENY + deny), "precondition: the unseeded client file is clean"
      found = hits(with_text(clean_client_html, prose), deny: PROJECT_DENY + deny)

      refute_empty found, "#{prose.inspect} in client prose reached a client file unblocked"
      assert terms.any? { |term| found.join.downcase.include?(term.downcase) },
        "the hit report must name one of #{terms.inspect} for #{prose.inspect}, got #{found.inspect}"
    end
  end

  # Accidental invisible characters inside a term must not split it out of the scan.
  INVISIBLE = {
    "a soft hyphen" => ["Fiz\u00ADzy board", [], "Fizzy"],
    "a zero-width space" => ["see /Users\u200B/qa", [], "/Users/"],
    "a word joiner" => ["Fizz\u2060y", [], "Fizzy"],
    "a zero-width joiner in a configured deny" => ["Bright\u200Dwater", ["Brightwater"], "Brightwater"],
    "a zero-width space in a derived token" => ["CANARY-\u200BINT-FAIL", [], "CANARY-INT-FAIL"]
  }.freeze

  INVISIBLE.each do |label, (text, deny, term)|
    define_method("test_#{label.tr(" -", "__")}_inside_a_term_is_still_caught") do
      assert_empty hits(clean_client_html, deny: PROJECT_DENY + deny), "precondition: the unseeded client file is clean"
      assert_caught hits(with_text(clean_client_html, "Note #{text} here."), deny: PROJECT_DENY + deny), term, "text"
    end
  end

  # A deny literal copied from somewhere with invisible or full-width characters still means the plain word.
  { "full-width" => "\uFF22\uFF52\uFF49\uFF47\uFF48\uFF54\uFF57\uFF41\uFF54\uFF45\uFF52",
    "zero-width" => "Bright\u200Bwater" }.each do |label, literal|
    define_method("test_a_#{label.tr("-", "_")}_deny_literal_matches_the_plain_term") do
      assert_empty hits(clean_client_html, deny: [literal]), "precondition: the unseeded client file is clean"
      assert_caught hits(with_text(clean_client_html, "Met Brightwater today."), deny: [literal]), "Brightwater", "text"
    end
  end

  def test_an_internal_token_written_with_an_invisible_character_still_blocks_its_plain_form
    source = source_from(:fail) { |data| data["internal"]["process_notes"] << "Seeded CANARY-\u200BSEED-TOKEN for the scan." }

    assert_caught hits(with_text(client_html(source), "See CANARY-SEED-TOKEN here."), source: source), "CANARY-SEED-TOKEN", "text"
  end

  # Only the internal block's own text is minimal, so a token can reach the scan only through the field under test.
  MINIMAL_INTERNAL = { "environment" => "Staging only." }.freeze

  def with_minimal_internal(fixture)
    source_from(fixture) do |data|
      data["internal"] = MINIMAL_INTERNAL.dup
      yield data
    end
  end

  INTERNAL_FIELDS = {
    "card" => [:pass_with_notes, "ZORK-4821", ->(data, token) { data["card"] = token }],
    "journey technical detail" => [:pass_with_notes, "JRNY-7731",
                                   ->(data, token) { data["journeys"][0]["technical_detail"] = "Seen via #{token} only." }],
    "issue root cause hash" => [:fail, "7f3a9c21b",
                                ->(data, token) { data["issues"][0]["root_cause"] = "Broke at #{token} on ops.example.org." }],
    "issue root cause host" => [:fail, "ops.example.org",
                                ->(data, token) { data["issues"][0]["root_cause"] = "Broke at 7f3a9c21b on #{token}." }],
    "internal screenshot caption" => [:pass_with_notes, "SHOT-CAP-5150",
                                      ->(data, token) { find_by_id(data["screenshots"], "4a")["caption"] = "Token list #{token}" }],
    "internal screenshot alt" => [:pass_with_notes, "SHOT-ALT-6262",
                                  ->(data, token) { find_by_id(data["screenshots"], "4a")["alt"] = "Admin list #{token}" }],
    "internal screenshot reason" => [:pass_with_notes, "SHOT-WHY-7373",
                                     ->(data, token) { find_by_id(data["screenshots"], "4a")["internal_reason"] = "Shows #{token} rows." }],
    "non-client note title" => [:pass_with_notes, "NOTE-TTL-8484",
                                ->(data, token) { find_by_id(data["notes"], "N3")["title_plain"] = "Paging #{token} at 25" }],
    "non-client note body" => [:pass_with_notes, "NOTE-BDY-9595",
                               ->(data, token) { find_by_id(data["notes"], "N3")["body_plain"] = "Seen on #{token} only." }]
  }.freeze

  INTERNAL_FIELDS.each do |label, (fixture, token, seed)|
    define_method("test_a_token_from_the_#{label.tr(" -", "__")}_pasted_into_client_text_is_caught") do
      source = with_minimal_internal(fixture) { |data| instance_exec(data, token, &seed) }
      html = client_html(source)
      assert_empty hits(html, source: source, name: "x.html"), "precondition: the unseeded client file is clean"

      assert_caught hits(with_text(html, "Ref #{token} here."), source: source, name: "x.html"), token, "text (from the #{label})"
    end
  end

  def test_the_build_line_commit_named_in_a_root_cause_still_does_not_block
    source = with_minimal_internal(:fail) { |data| data["issues"][0]["root_cause"] = "Fixed after a1b2c3d landed." }
    html = client_html(source)
    assert_includes html, "a1b2c3d", "precondition: the client build line shows the commit"

    assert_empty hits(html, source: source, name: "x.html"), "the public commit on the build line was blocked as an internal token"
  end

  # Smart punctuation and dash variants are what copy-paste produces; they must not hide a leak.
  PUNCTUATION = {
    "a curly apostrophe against a straight deny" => ["Met Dan O’Brien today.", ["Dan O'Brien"], "Brien"],
    "curly quotes against a straight-quoted deny" => ["About Project “Falcon” today.", ['Project "Falcon"'], "Falcon"],
    "a straight apostrophe against a curly deny" => ["Met Dan O'Brien today.", ["Dan O’Brien"], "Brien"],
    "non-breaking hyphens in a derived token" => ["See CANARY‑INT‑FAIL here.", [], "INT"],
    "en dashes in a derived token" => ["See CANARY–INT–FAIL here.", [], "INT"]
  }.freeze

  PUNCTUATION.each do |label, (text, deny, term)|
    define_method("test_#{label.tr(" -", "__")}_is_caught") do
      assert_empty hits(clean_client_html, deny: PROJECT_DENY + deny), "precondition: the unseeded client file is clean"
      assert_caught hits(with_text(clean_client_html, text), deny: PROJECT_DENY + deny), term, "text"
    end
  end

  # Invisibles go before composition, or a joiner left between a letter and its accent keeps them apart.
  def test_a_joiner_between_a_letter_and_its_accent_does_not_hide_a_deny_phrase
    deny = ["Café Noir"]
    assert_empty hits(clean_client_html, deny: deny), "precondition: the unseeded client file is clean"

    assert_caught hits(with_text(clean_client_html, "Met at Cafe‍́ Noir today."), deny: deny), "Noir", "text"
  end

  # Identifiers wrapped in markup, punctuation or a URL must still yield the part a writer would copy into client prose.
  IDENTIFIERS = {
    "a controller action" => ["Broke in InvoicesController#create on submit.", "InvoicesController#create"],
    "an environment variable" => ["Rotated WAVE_API_KEY after the run.", "WAVE_API_KEY"],
    "a backticked host" => ["Ran against `staging.example.org` only.", "staging.example.org"],
    "a possessive host" => ["Seen on staging.example.org's login page.", "staging.example.org"],
    "a named email address" => ["Reported by Jane <jane@example.org> today.", "jane@example.org"],
    "a host inside a URL" => ["Opened https://staging.example.org/admin/users first.", "staging.example.org"],
    "a CamelCase class" => ["The PaymentReconciler skipped a row.", "PaymentReconciler"],
    "a namespaced class" => ["Traced to Billing::Ledger during cleanup.", "Billing::Ledger"]
  }.freeze

  IDENTIFIERS.each do |label, (internal, shown)|
    define_method("test_#{label.tr(" -", "__")}_from_internal_text_pasted_into_client_text_is_caught") do
      source = with_minimal_internal(:fail) { |data| data["internal"]["process_notes"] = [internal] }
      html = client_html(source)
      assert_empty hits(html, source: source, name: "x.html"), "precondition: the unseeded client file is clean"

      assert_caught hits(with_text(html, "Ref #{shown} here."), source: source, name: "x.html"), shown, "text (from #{internal.inspect})"
    end
  end

  def test_an_identifier_in_an_issue_root_cause_pasted_into_client_text_is_caught
    source = with_minimal_internal(:fail) { |data| data["issues"][0]["root_cause"] = "Nil total in InvoicesController#create." }
    html = client_html(source)
    assert_empty hits(html, source: source, name: "x.html"), "precondition: the unseeded client file is clean"

    assert_caught hits(with_text(html, "Fixed InvoicesController#create today."), source: source, name: "x.html"),
      "InvoicesController#create", "text (from the root cause)"
  end

  # YAML reads an unquoted card number as an Integer, which must not drop it from the scan.
  def test_an_unquoted_integer_card_number_in_client_text_is_caught
    source = with_minimal_internal(:pass_with_notes) { |data| data["card"] = 1027 }
    html = client_html(source)
    assert_empty hits(html, source: source, name: "x.html"), "precondition: the unseeded client file is clean"

    assert_caught hits(with_text(html, "Fixed under card 1027."), source: source, name: "x.html"), "1027", "text (from card: 1027)"
  end

  # A derived token matches whole tokens only: digits inside a longer value (data-w="1024", a date) are not that token.
  { "an_integer_card_1024" => 1024, "a_string_card_2026" => "2026" }.each do |label, card|
    define_method("test_#{label}_does_not_block_the_clean_client_file") do
      source = with_minimal_internal(:pass_with_notes) { |data| data["card"] = card }

      assert_empty hits(scan_html(source), source: source, name: "x.html"),
        "card: #{card.inspect} blocked a clean client file by matching inside a longer value"
    end
  end

  # The scan reads text, not markup: prose that decodes to data-w="1027" is client text and must still block.
  def test_a_card_number_in_prose_shaped_like_a_data_w_attribute_is_caught
    source = with_minimal_internal(:pass_with_notes) do |data|
      data["card"] = 1027
      data["summary"]["lead"] = 'Measured at data-w="1027" on the cover.'
    end

    assert_caught hits(scan_html(source), source: source, name: "x.html"), "1027", "lead (from card: 1027)"
  end

  WHOLE_TOKENS = {
    "a standalone card number" => [->(data) { data["card"] = 1024 }, "Fixed under card 1024 today.", "1024"],
    "a card id inside a sentence" => [->(data) { data["card"] = "ZORK-4821" }, "We shipped ZORK-4821 with the cover fix.", "ZORK-4821"],
    "a host before a possessive" => [->(data) { data["internal"]["process_notes"] = ["Ran on staging.example.org only."] },
                                     "Seen on staging.example.org's login page.", "staging.example.org"],
    "a host before a full stop" => [->(data) { data["internal"]["process_notes"] = ["Ran on staging.example.org only."] },
                                    "It ran on staging.example.org.", "staging.example.org"]
  }.freeze

  WHOLE_TOKENS.each do |label, (seed, text, token)|
    define_method("test_#{label.tr(" ", "_")}_is_still_caught_as_a_whole_token") do
      source = with_minimal_internal(:pass_with_notes, &seed)
      html = scan_html(source)
      assert_empty hits(html, source: source, name: "x.html"), "precondition: the unseeded client file is clean"

      assert_caught hits(with_text(html, text), source: source, name: "x.html"), token, "text"
    end
  end

  card_id = ->(data) { data["card"] = "ZORK-4821" }
  host = ->(data) { data["internal"]["process_notes"] = ["Ran on staging.example.org only."] }
  url_host = ->(data) { data["internal"]["process_notes"] = ["Checked https://corp.example.com/x first."] }
  deploy_tag = ->(data) { data["internal"]["process_notes"] = ["Ran deploy-2026 first."] }

  # A derived token copied verbatim next to ordinary punctuation is still that token.
  TOKENS_BESIDE_PUNCTUATION = {
    "a card id between em dashes" => [card_id, "Shipped fix—ZORK-4821—today.", "ZORK-4821"],
    "a card id before an ellipsis" => [card_id, "Shipped ZORK-4821... finally.", "ZORK-4821"],
    "a card id after a hash" => [card_id, "Shipped #ZORK-4821 today.", "ZORK-4821"],
    "a card id after a colon label" => [card_id, "Shipped card:ZORK-4821 today.", "ZORK-4821"],
    "a card id after a slash" => [card_id, "Shipped under /ZORK-4821 today.", "ZORK-4821"],
    "a card id before a slash" => [card_id, "Shipped ZORK-4821/ today.", "ZORK-4821"],
    "a card number after a hash" => [->(data) { data["card"] = 1027 }, "Fixed under card #1027 today.", "1027"],
    "a host inside a url" => [host, "Seen on https://staging.example.org today.", "staging.example.org"],
    "a host before a path" => [host, "Seen on staging.example.org/login today.", "staging.example.org"],
    "an email inside a mailto" => [->(data) { data["internal"]["process_notes"] = ["Paged jane@example.org about it."] },
                                   "Write to mailto:jane@example.org today.", "jane@example.org"],
    "a card id after an at sign" => [card_id, "Shipped @ZORK-4821 today.", "ZORK-4821"],
    "a card id before an at sign" => [card_id, "Shipped ZORK-4821@ today.", "ZORK-4821"],
    "a card id after a year prefix" => [card_id, "Shipped x 2026-ZORK-4821 x today.", "ZORK-4821"],
    "a card id after an en dash range" => [card_id, "Shipped 4800\u2013ZORK-4821 today.", "ZORK-4821"],
    "a card id after a numbered dot" => [card_id, "Shipped 1.ZORK-4821 today.", "ZORK-4821"],
    "a card number after an at sign" => [->(data) { data["card"] = 4821 }, "Fixed under @4821 today.", "4821"],
    "a url host inside an email" => [url_host, "Write to ops@corp.example.com today.", "corp.example.com"],
    "a url host inside a mailto email" => [url_host, "Write to mailto:ops@corp.example.com today.", "corp.example.com"],
    "a card id before an em dash and a digit" => [card_id, "Shipped ZORK-4821\u20142 fixes left.", "ZORK-4821"],
    "a card id starting an en dash range" => [card_id, "Shipped ZORK-4821\u20134830 today.", "ZORK-4821"],
    "a derived tag before an em dash and a digit" => [deploy_tag, "Shipped deploy-2026\u20145 ok today.", "deploy-2026"]
  }.freeze

  TOKENS_BESIDE_PUNCTUATION.each do |label, (seed, text, token)|
    define_method("test_#{label.tr(" ", "_")}_is_caught_beside_punctuation") do
      source = with_minimal_internal(:pass_with_notes, &seed)
      html = scan_html(source)
      assert_empty hits(html, source: source, name: "x.html"), "precondition: the unseeded client file is clean"

      assert_caught hits(with_text(html, text), source: source, name: "x.html"), token, "text"
    end
  end

  # The bounding must not widen into longer values: a derived 4821 inside a number, date or version is not 4821.
  ["See ref 48210 here.", "Logged 4821-10-01 here.", "Logged 2026-10-4821 here.", "Shipped v1.4821 here."].each do |text|
    define_method("test_derived_4821_is_not_caught_in_#{text[/\S*4821\S*/].tr("-.", "__")}") do
      source = with_minimal_internal(:pass_with_notes) { |data| data["internal"]["process_notes"] = ["Checked on build 4821."] }

      assert_empty hits(with_text(client_html(source), text), source: source, name: "x.html"), "derived 4821 matched inside #{text.inspect}"
    end
  end

  # Trade-off: a dash-joined 4821 stays uncaught so the 2026-10-4821 date guard holds.
  def test_an_all_digit_token_is_not_caught_at_the_end_of_a_dashed_range
    source = with_minimal_internal(:pass_with_notes) { |data| data["internal"]["process_notes"] = ["Checked on build 4821."] }

    assert_empty hits(with_text(client_html(source), "Closed cards 4800-4821 here."), source: source, name: "x.html"),
      "derived 4821 matched inside the range 4800-4821"
  end

  # 4821 is not the tested_on year, so only word-bounding can keep it from matching inside a longer number.
  def test_a_derived_number_does_not_match_inside_a_longer_number_or_a_dashed_date
    source = with_minimal_internal(:pass_with_notes) { |data| data["internal"]["process_notes"] = ["Checked on build 4821."] }
    html = client_html(source)
    assert_caught hits(with_text(html, "See build 4821 here."), source: source, name: "x.html"), "4821", "text (precondition: 4821 is derived)"

    ["See ref 48210 here.", "Logged 4821-10-01 here."].each do |text|
      assert_empty hits(with_text(html, text), source: source, name: "x.html"), "derived 4821 matched inside #{text.inspect}"
    end
  end

  # Documents the limit: a plain word is indistinguishable from prose, so only the operator's deny list can block it.
  def test_a_plain_word_codename_in_internal_text_is_blocked_only_once_listed_in_deny
    source = with_minimal_internal(:fail) { |data| data["internal"]["process_notes"] = ["Brightwater rollout checked."] }
    html = with_text(client_html(source), "Part of Brightwater now.")

    assert_empty hits(html, source: source, name: "x.html", deny: []), "a plain word in internal text is not derived; deny is the operator's tool"
    assert_caught hits(html, source: source, name: "x.html", deny: ["Brightwater"]), "Brightwater", "text (listed in deny)"
  end

  def test_capitalised_english_words_in_internal_text_do_not_block_client_prose
    source = with_minimal_internal(:fail) { |data| data["internal"]["process_notes"] = ["Checked the Staging Server manually."] }
    html = with_text(client_html(source), "Checked on Staging the Server held up.")

    assert_empty hits(html, source: source, name: "x.html"), "ordinary capitalised words from internal text blocked the client file"
  end

  private

  # data-w is measured from the image bytes, which the scan rendering swaps for a placeholder.
  def strip_payloads(html) = html.gsub(/data:[^"')\s]*/, "data:").gsub(/data-w="\d+"/, 'data-w=""')

  def internal_strings(source)
    data = source.data
    values = strings(data["internal"])
    values += source.journeys.filter_map { |journey| journey["technical_detail"] }
    values += source.issues.filter_map { |issue| issue["root_cause"] }
    values += source.screenshots.reject { |shot| shot["visibility"] == "client" }
                    .flat_map { |shot| shot.values_at("caption", "alt", "internal_reason").compact }
    values += source.notes.reject { |note| note["client_facing"] == true }.map { |note| note["title_plain"] }
    values.map(&:to_s).reject { |value| value.strip.length < 8 }.uniq
  end

  def strings(value)
    case value
    when Hash then value.values.flat_map { |child| strings(child) }
    when Array then value.flat_map { |child| strings(child) }
    when String then [value]
    else []
    end
  end
end
