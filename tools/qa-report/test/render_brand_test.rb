require_relative "test_helper"

# B-R17: the brand comes from config; with none, the neutral default names no real company.
class RenderBrandTest < Minitest::Test
  def wordmarks(html) = elements(with_class(html, "cover").to_s, "svg").select { |svg| svg.include?("NORTHWIND") }

  # AC21 (B-R17): with no brand config the report is signed by the neutral default and nothing else.
  def test_default_brand_is_the_neutral_example_studio
    default = QaReport::Brand.default

    assert_equal "Example Studio", default.name
    assert_equal "hello@example.com", default.contact_email
    %i[pass_with_notes fail].each do |name|
      [client_html(name, brand: default), internal_html(name, brand: default)].each do |html|
        assert_includes text(element(html, "footer")), "Prepared by Example Studio"
        assert_includes text(element(html, "footer")), "Contact: hello@example.com"
        refute_includes html, "Northwind", "#{name}: the test brand leaked into the default"
      end
    end
  end

  # QA on card B: the default mark was cropped to "EXAMPLE STUD"; 0.72 em per heavy capital is a generous width.
  def test_default_wordmark_text_fits_its_view_box
    svg = QaReport::Brand.default.wordmark(:light, class_name: "wm")
    _, _, width, height = svg[/\bviewBox="([^"]+)"/, 1].split.map(&:to_f)
    label = text(element(svg, "text"))
    size = svg[/\bfont-size="([\d.]+)"/, 1].to_f
    x = svg[/<text\b[^>]*\bx="([\d.]+)"/, 1].to_f

    assert_equal "EXAMPLE STUDIO", label
    assert_operator width, :>=, x + label.size * size * 0.72, "the wordmark text runs past its viewBox"
    assert_operator height, :>=, size, "the wordmark text is taller than its viewBox"
  end

  # QA: the test brand's last letter ran under its accent bar; text, then bar, must both sit inside the crop.
  def test_test_brand_wordmark_text_clears_its_bar_and_fits_its_view_box
    svg = neutral_brand.wordmark(:light, class_name: "wm")
    left, _, width, = svg[/\bviewBox="([^"]+)"/, 1].split.map(&:to_f)
    label = text(element(svg, "text"))
    text_end = svg[/<text\b[^>]*\bx="([\d.]+)"/, 1].to_f + label.size * svg[/\bfont-size="([\d.]+)"/, 1].to_f * 0.72
    bar = svg[/<rect\b[^>]*\bx="[\d.]+"[^>]*>/] || flunk("the test wordmark has no accent bar")
    bar_x = bar[/\bx="([\d.]+)"/, 1].to_f

    assert_operator bar_x, :>=, text_end, "the wordmark text runs under its accent bar"
    assert_operator left + width, :>=, bar_x + bar[/\bwidth="([\d.]+)"/, 1].to_f, "the crop cuts off the accent bar"
  end

  # B-R17 with the neutral test brand: the configured name and wordmark render.
  def test_configured_brand_renders_on_the_cover
    marks = wordmarks(client_html(:pass_with_notes))

    refute_empty marks, "the cover shows no wordmark"
    assert marks.any? { |svg| svg.match?(/role="img"/) && svg.match?(/aria-label="Northwind Studio"/) }
  end

  # AC22 (B-R17): the full-bleed background rect is stripped and the configured viewBox applied.
  def test_wordmark_background_rect_is_stripped_and_view_box_applied
    wordmarks(client_html(:pass_with_notes)).each do |svg|
      assert_match(/\A<svg\b[^>]*\bviewBox="10 20 350 60"/, svg)
      refute_match(/<rect\b(?![^>]*\bx=)[^>]*\bwidth="400"[^>]*\bheight="100"/, svg, "background rect survived")
      assert_match(/<rect\b[^>]*\bx="350"/, svg, "the accent bar is part of the mark and must stay")
    end
  end

  # A wordmark exported with an XML prolog and a comment still inlines as a clean <svg>.
  def test_wordmark_prolog_and_comment_stay_out_of_the_inline_svg
    with_brand_copy do |dir, config|
      File.write(File.join(dir, "wordmark-on-dark.svg"),
        %(<?xml version="1.0" encoding="UTF-8"?>\n<!-- exported by a drawing tool -->\n) +
        File.read(File.join(dir, "wordmark-on-dark.svg")))
      html = client_html(:pass_with_notes, brand: QaReport::Brand.load(config))

      refute_empty wordmarks(html)
      wordmarks(html).each do |svg|
        refute_includes svg, "<?xml"
        refute_includes svg, "exported by a drawing tool"
      end
      refute_includes html, "<?xml", "an XML prolog inside HTML is invalid markup"
    end
  end

  # A wordmark file with no <svg> is a config error naming the file, not a crash mid-render.
  def test_a_wordmark_with_no_svg_tag_is_a_brand_config_error
    with_brand_copy do |dir, config|
      File.write(File.join(dir, "wordmark-on-dark.svg"), "<p>not a drawing</p>\n")

      assert_brand_error(config) { client_html(:pass_with_notes, brand: QaReport::Brand.load(config)) }
    end
  end

  # A numeric font family is a config error, not a NoMethodError.
  def test_a_non_text_font_family_is_a_brand_config_error
    with_brand_copy(edit: ->(data) { data["fonts"][0]["family"] = 123 }) do |_, config|
      assert_brand_error(config) { QaReport::Brand.load(config) }
    end
  end

  # An empty brand.yml is a config error, not a NoMethodError on nil.
  def test_an_empty_brand_config_is_a_brand_config_error
    with_brand_copy do |_, config|
      File.write(config, "")

      assert_brand_error(config) { QaReport::Brand.load(config) }
    end
  end

  # A non-numeric font weight names the config file.
  def test_a_non_numeric_font_weight_is_a_brand_config_error
    with_brand_copy(edit: ->(data) { data["fonts"][0]["weight"] = "bold" }) do |_, config|
      assert_brand_error(config) { QaReport::Brand.load(config) }
    end
  end

  private

  def with_brand_copy(edit: nil)
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(Dir[File.join(QaReportTestHelper::FIXTURES, "brand", "*")], dir)
      config = File.join(dir, "brand.yml")
      if edit
        data = YAML.safe_load_file(config)
        edit.call(data)
        File.write(config, YAML.dump(data))
      end
      yield dir, config
    end
  end

  def assert_brand_error(config, &block)
    error = assert_raises(ArgumentError, &block)
    assert_includes error.message, config, "the brand config error must name #{config}"
  end
end
