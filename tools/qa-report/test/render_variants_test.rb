require_relative "test_helper"
require "qa_report/build"

# B-R1, B-R13, B-R15, B-R18: one source, two files that differ only by marked internal regions.
class RenderVariantsTest < Minitest::Test
  BANNER = "INTERNAL — contains operational detail. Do not send to the client."

  def banner(html) = text(with_class(html, "banner-int") || flunk("the internal file has no banner"))

  def footer(html) = element(html, "footer") || flunk("the report has no footer")

  # AC1 (B-R1)
  def test_internal_minus_marked_regions_is_the_client_file_byte_for_byte
    %i[pass_with_notes fail].each do |name|
      internal = internal_html(name)

      assert_operator internal.scan("<!--int-->").size, :>, 0, "#{name}: the internal file marks no internal regions"
      assert_equal internal.scan("<!--int-->").size, internal.scan("<!--/int-->").size, "#{name}: unbalanced markers"
      assert strip_internal(internal) == client_html(name), "#{name}: internal minus <!--int--> regions != client"
    end
  end

  # B-R1: markers never nest, so a plain non-greedy strip is exact.
  def test_internal_markers_never_nest
    internal_html(:fail).scan(%r{<!--int-->(.*?)<!--/int-->}m).flatten.each do |region|
      refute_includes region, "<!--int-->"
    end
  end

  # B-R13 and the canary contract: the client file carries no mock chrome and nothing internal.
  def test_client_file_has_no_toolbar_template_markers_or_canaries
    %i[pass_with_notes fail].each do |name|
      html = client_html(name)

      refute_match(/role="toolbar"|mock-bar|mock-banner/, html, "#{name}: mock chrome leaked")
      refute_includes html, "<template", "#{name}: the client file has no template elements"
      refute_includes html, "<!--int", "#{name}: the client file has no internal markers"
      refute_includes html, "/int-->"
      refute_includes html, "CANARY", "#{name}: an internal string reached the client file"
      refute_includes html, "TRACKER-", "#{name}: the card id is internal"
      refute_includes html, "check=1", "#{name}: the mock check script leaked"
      refute_includes html, "banner-int"
    end
  end

  # B-R13: neither file carries the mock's toolbar or template machinery.
  def test_internal_file_has_no_mock_chrome_either
    html = internal_html(:fail)

    refute_match(/role="toolbar"|mock-bar|mock-banner|check=1/, html)
    refute_includes html, "<template"
  end

  # AC23 (B-R18)
  def test_approved_banner_links_to_the_client_file_by_name
    html = internal_html(:pass_with_notes)

    assert banner(html).start_with?(BANNER), banner(html)
    assert_includes banner(html), "Client version: #{CLIENT_FILE}"
    assert_match(/<a\b[^>]*href="#{Regexp.escape(CLIENT_FILE)}"/, with_class(html, "banner-int"))
    assert_operator html.index(with_class(html, "banner-int")), :<, html.index(/<header\b/)
  end

  # AC35 (B-R18)
  def test_awaiting_banner_names_the_approve_command
    command = QaReport::Build.approve_command("/project/QA/#{STEM}.qa.yml")
    html = internal_html(:pass_with_notes, status: QaReport::ClientStatus.awaiting(command: command))

    assert_match(%r{\A#{Regexp.escape(Shellwords.escape(RbConfig.ruby))} /\S+/bin/qa-report approve /project/QA/#{STEM}\.qa\.yml\z}, command)
    assert_equal "#{BANNER} Client version: awaiting owner approval — run #{command}", banner(html),
      "the banner must show the runnable approve command verbatim"
  end

  # AC35 (B-R18)
  def test_stale_banner_asks_for_re_approval
    html = internal_html(:pass_with_notes, status: QaReport::ClientStatus.stale)

    assert_equal "#{BANNER} Client version: approval out of date — re-approve", banner(html)
  end

  # AC35 (B-R18): the block reason is escaped like any other text.
  def test_blocked_banner_names_the_first_reason
    reason = "summary.found matched a denied host <app.example.test>"
    html = internal_html(:pass_with_notes, status: QaReport::ClientStatus.blocked(reason))

    assert_equal "#{BANNER} Client version: blocked — #{reason}; see build output", banner(html)
    refute_includes html, "<app.example.test>"
  end

  # AC34 (B-R4, B-R15, B-R18)
  def test_internal_only_project_has_no_prepared_for_row_and_an_internal_footer
    html = internal_html(:pass_with_notes, client: nil, status: nil)
    cover = with_class(html, "cover")

    refute_includes text(cover), "Prepared for"
    assert_includes text(footer(html)), "Internal report — for Northwind Studio use only."
    refute_includes text(footer(html)), "Confidential — prepared for"
    assert_equal "#{BANNER} Client version: none (internal-only project).", banner(html)
  end

  # AC19 (B-R15)
  def test_client_footer_names_the_brand_contact_and_confidentiality
    words = text(footer(client_html(:pass_with_notes)))

    assert_includes words, "Prepared by Northwind Studio"
    assert_includes words, "Contact: hello@example.com"
    assert_includes words, "Confidential — prepared for #{CLIENT_NAME} as part of our engagement. " \
                           "Please share only within your team."
    refute_match(/\+?\d[\d ().-]{7,}\d/, words.gsub(/[0-9a-f]{64}/, ""), "the footer carries no phone number")
  end

  # AC19 (B-R15): the internal stamp is the source digest and schema version, never a clock time.
  def test_internal_footer_stamps_the_source_digest_and_schema_version
    words = text(footer(internal_html(:pass_with_notes)))

    assert_includes words, Digest::SHA256.file(fixture_path(:pass_with_notes)).hexdigest
    assert_match(/schema (version )?1\b/i, words)
    refute_match(/\b\d{1,2}:\d{2}\b/, words, "the stamp must not carry a clock time")
    refute_includes text(footer(client_html(:pass_with_notes))), Digest::SHA256.file(fixture_path(:pass_with_notes)).hexdigest
  end
end
