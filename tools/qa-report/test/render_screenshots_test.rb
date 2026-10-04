require_relative "test_helper"

# C-R6 to C-R8: 05 Screenshots and the lightbox markup contract. Real key and focus behaviour is QA's browser check.
class RenderScreenshotsTest < Minitest::Test
  SHOTS = "05 · Screenshots"
  CLIENT_IDS = %w[1a 1b 1c 2a 2b 3a].freeze

  def thumbs(fragment) = all_with_class(fragment, "thumb", tag: "button")

  def thumb_id(button) = button[/\bid="shot-([^"]+)"/, 1]

  def lightbox(html) = element(html, "dialog", /\bid="lb"/) || flunk("the file has no lightbox dialog")

  def script(html) = html.scan(%r{<script\b([^>]*)>(.*?)</script>}m)

  # AC: both files show the same 6 client thumbnails, grouped by subject (C-R6).
  def test_both_files_show_the_same_client_thumbnails_in_groups
    client = section(client_html(:pass_with_notes), SHOTS)
    internal = section(internal_html(:pass_with_notes), SHOTS)

    assert_equal CLIENT_IDS, thumbs(client).map { |button| thumb_id(button) }
    assert_equal client, internal, "05 must be identical in both files"
    groups = all_with_class(client, "shot-group", tag: "div")
    assert_equal ["Proposal preview", "Roadmap section", "Older proposal"], groups.map { |group| text(element(group, "h3")) }
    assert_equal [3, 2, 1], groups.map { |group| thumbs(group).size }
  end

  # AC: an internal screenshot never reaches either body; A7 lists it (C-R6, C-R10).
  def test_an_internal_screenshot_stays_out_of_both_bodies
    [client_html(:pass_with_notes), internal_html(:pass_with_notes)].each do |html|
      body = strip_internal(html)

      refute_includes body, "shot-4a"
      refute_includes body, "CANARY-INTERNAL-CAPTION"
    end
    a7 = section(internal_html(:pass_with_notes), "A · Internal appendix")
    assert_equal ["4a"], thumbs(a7).map { |button| thumb_id(button) }
  end

  # AC: each thumbnail is a button with its authored alt text and an Expand label, and no placeholder chip (C-R6).
  def test_each_thumbnail_is_a_button_with_alt_text_and_an_expand_label
    shots = load_fixture(:pass_with_notes).screenshots.to_h { |shot| [shot["id"], shot] }

    thumbs(section(client_html(:pass_with_notes), SHOTS)).each do |button|
      shot = shots.fetch(thumb_id(button))
      assert_match(/\A<button\b[^>]*\btype="button"/, button)
      image = button[/<img\b[^>]*>/] || flunk("thumbnail #{shot["id"]} has no image")
      assert_includes image, %(alt="#{ERB::Util.html_escape(shot["alt"])}")
      assert_match(%r{src="data:image/png;base64,[A-Za-z0-9+/=]+"}, image)
      assert_includes text(button), "Expand"
      assert_includes text(button.sub(%r{<span\b[^>]*aria-hidden="true".*?</span>}m, "")), "View full size: #{shot["caption"]}"
      refute_match(/placeholder|sample capture/i, button)
    end
  end

  # C-R6: each figure carries its caption.
  def test_each_figure_has_its_caption
    figures = elements(section(client_html(:pass_with_notes), SHOTS), "figure")

    assert_equal 6, figures.size
    assert_includes text(element(figures.first, "figcaption")), "Preview, light theme"
  end

  # C-R6, decision 6: neither file carries placeholder or sample-capture labels anywhere.
  def test_no_placeholder_labels_in_either_file
    [client_html(:pass_with_notes), internal_html(:pass_with_notes)].each do |html|
      refute_match(/Placeholder|Sample capture|flag-ph/i, text(html) + html.scan(/class="[^"]*"/).join)
    end
  end

  # AC: each image's encoded data occurs exactly once; the lightbox reuses the thumbnail (C-R8).
  def test_each_image_is_embedded_exactly_once
    html = internal_html(:pass_with_notes)
    uris = html.scan(%r{data:image/png;base64,[A-Za-z0-9+/=]+})

    assert_equal 7, uris.size, "6 client thumbnails plus the A7 capture"
    uris.each { |uri| assert_equal 1, html.scan(uri).size, "an image is embedded more than once" }
    refute_match(/\bsrc="data:/, lightbox(html), "the lightbox image must be filled from the thumbnail at runtime")
  end

  # AC: with scripting disabled every thumbnail is visible (C-R8).
  def test_thumbnails_are_visible_without_scripting
    html = internal_html(:pass_with_notes)

    assert_equal 7, thumbs(html).size
    thumbs(html).each { |button| refute_match(/\bhidden\b|display:\s*none/, button[/\A<button\b[^>]*>/]) }
    hiding = css_rules(css(html)).reject(&:in_print?).select { |rule| rule.value("display") == "none" }
    %w[.shots figure button.thumb .shot-group].each do |selector|
      refute hiding.any? { |rule| rule.matches?(selector) }, "#{selector} is hidden on screen, so no-script readers lose it"
    end
  end

  # C-R7: the lightbox markup the script drives: caption, counter, Prev/Next/Close buttons and one image slot.
  def test_lightbox_markup_contract
    [client_html(:pass_with_notes), internal_html(:pass_with_notes)].each do |html|
      dialog = lightbox(html)

      assert_match(/\A<dialog\b[^>]*\baria-labelledby="lb-cap"/, dialog)
      %w[lb-cap lb-count lb-img].each { |id| assert_match(/\bid="#{id}"/, dialog) }
      { "lb-prev" => "Prev", "lb-next" => "Next", "lb-close" => "Close" }.each do |id, word|
        button = element(dialog, "button", /\bid="#{id}"/) || flunk("lightbox has no #{word} button")
        assert_match(/\btype="button"/, button)
        assert_equal word, text(button)
      end
      assert_match(/\baria-live="polite"/, dialog, "the counter change is announced")
      assert_equal 1, html.scan(/<dialog\b/).size
    end
  end

  # C-R7: Prev, Next and Close are at least 44 by 44 px.
  def test_lightbox_buttons_are_at_least_44_px
    rules = css_rules(css(client_html(:pass_with_notes))).select { |rule| rule.matches?(".lb-btns button") }
    size = ->(value) { value.to_s.end_with?("rem") ? value.to_f * 16 : value.to_f }

    assert rules.any? { |rule| size.call(rule.value("min-width")) >= 44 && size.call(rule.value("min-height")) >= 44 },
      "the lightbox buttons need min-width and min-height of 44 px (2.75rem)"
  end

  # C-R7: thumbnails carry what the lightbox reads: their id, caption and natural width.
  def test_thumbnails_carry_the_lightbox_data_attributes
    thumbs(section(client_html(:pass_with_notes), SHOTS)).each do |button|
      assert_match(/\bdata-cap="[^"]+"/, button)
      assert_match(/\bdata-w="\d+"/, button)
    end
  end

  # C-R7: the script is inline, identical in both files, and wires the keys, counter and focus return.
  def test_lightbox_script_is_inline_and_handles_keys_counter_and_focus
    client = script(client_html(:pass_with_notes))
    internal = script(strip_internal(internal_html(:pass_with_notes)))

    refute_empty client, "the file has no lightbox script"
    assert_equal client, internal
    client.each { |attributes, _| refute_match(/\bsrc=/, attributes, "the lightbox script must be inline") }
    code = client.map(&:last).join("\n")
    %w[showModal Escape ArrowLeft ArrowRight keydown .focus( lb-count].each do |needle|
      assert_includes code, needle, "the lightbox script does not handle #{needle}"
    end
    assert_match(/ of /, code, "the counter reads {n} of {total}")
  end

  # C-R7: the full-size image is shown at its natural width and scrolls vertically.
  def test_lightbox_image_shows_at_natural_width
    rules = css_rules(css(client_html(:pass_with_notes))).reject(&:in_print?)

    assert rules.any? { |rule| rule.matches?(".lb-body img") && rule.value("max-width") == "none" }
    assert rules.any? { |rule| rule.matches?(".lb-body") && rule.value("overflow") == "auto" }
  end

  # C-R6, C-R17: with every capture internal the client file has no thumbnail at all.
  def test_no_client_screenshots_means_no_thumbnails_in_the_client_file
    source = source_from(:pass_with_notes) do |data|
      data["screenshots"].each { |shot| shot.merge!("visibility" => "internal", "internal_reason" => "Staging only.") }
      data["journeys"].each { |journey| journey["evidence_note_plain"] ||= "Checked directly" }
    end

    assert_empty thumbs(client_html(source))
  end

  # QA: thumbnails carry real images, and data-w is the width that was actually encoded.
  def test_thumbnails_embed_real_images_at_their_encoded_width
    thumbs(internal_html(:pass_with_notes)).each do |button|
      width = button[/\bdata-w="(\d+)"/, 1].to_i
      bytes = button[%r{src="data:image/png;base64,([A-Za-z0-9+/=]+)"}, 1].to_s.unpack1("m0")

      refute_equal 1, width, "#{thumb_id(button)} is a 1 px placeholder"
      assert bytes.start_with?("\x89PNG\r\n\x1A\n".b), "#{thumb_id(button)} does not embed a PNG"
      assert_equal width, QaReportTestHelper.png_size(bytes).first, "#{thumb_id(button)} data-w is not the encoded width"
    end
    widths = thumbs(section(client_html(:pass_with_notes), SHOTS)).to_h { |button| [thumb_id(button), button[/\bdata-w="(\d+)"/, 1]] }
    assert_equal({ "1a" => "1024", "1b" => "390", "1c" => "1024", "2a" => "1024", "2b" => "390", "3a" => "390" }, widths)
  end

  # Arrow keys inside the scrollable image pane scroll it rather than change pictures.
  def test_arrow_keys_are_left_alone_inside_the_image_pane
    code = script(client_html(:pass_with_notes)).map(&:last).join("\n")

    pane_check = /body\.contains\(\s*(?:e|event)\.target\s*\)|(?:e|event)\.target\.closest\(\s*['"]\.lb-body['"]\s*\)|(?:e|event)\.target\s*===\s*body\b/
    handler = code[/addEventListener\(\s*['"]keydown['"].*?ArrowRight/m] || flunk("no keydown handler handles ArrowRight")

    assert_match pane_check, handler, "arrow keys must be ignored when the key was pressed inside .lb-body"
  end

  # The scrollable pane is a named region for screen readers.
  def test_image_pane_is_a_labelled_region
    body = with_class(lightbox(client_html(:pass_with_notes)), "lb-body") || flunk("the lightbox has no .lb-body")
    open_tag = body[/\A<[^>]+>/]

    assert_match(/\brole="region"/, open_tag)
    assert_match(/\baria-label="[^"]+"/, open_tag)
  end
end
