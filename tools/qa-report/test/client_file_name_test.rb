require_relative "test_helper"
require "qa_report/approval"

# the client file name is {client-slug}-qa-report-{date}-{feature-slug} and never carries the card.
class ClientFileNameTest < Minitest::Test
  def stem(title, client: CLIENT_NAME, tested_on: Date.new(2026, 10, 2))
    QaReport::ClientFile.stem(client: client, tested_on: tested_on, title: title)
  end

  def test_the_pass_with_notes_fixture_gets_the_documented_name
    source = load_fixture(:pass_with_notes)
    name = stem(source.data["feature_title_plain"], tested_on: source.data["tested_on"])

    assert_equal "example-outfitters-qa-report-2026-10-02-proposal-sections-keep-their-order", name
    refute_match(/tracker|101/i, name, "the card number must never reach a client file name")
  end

  def test_a_60_character_feature_slug_is_kept_whole
    title = "Sections #{(["section"] * 6).join(" ")} abc"
    assert_equal 60, QaReport::Source.slug(title).length, "precondition: the slug is exactly 60 characters"

    assert stem(title).end_with?("-2026-10-02-#{QaReport::Source.slug(title)}")
  end

  def test_a_longer_feature_slug_is_cut_at_the_last_word_break_within_60
    title = "Sections #{(["section"] * 6).join(" ")} ordered"
    slug = QaReport::Source.slug(title)
    assert_equal 64, slug.length, "precondition: the slug would be 64 characters"
    assert_equal "-", slug[56], "precondition: the word break is character 57"

    feature = stem(title).delete_prefix("example-outfitters-qa-report-2026-10-02-")
    assert_equal slug[0, 56], feature
    refute feature.end_with?("-"), "a cut slug must not end on a hyphen"
  end

  def test_the_client_name_and_date_are_slugged
    assert_equal "example-studio-qa-report-2026-01-05-a-b", stem("A & B!", client: "Example  Studio", tested_on: Date.new(2026, 1, 5))
  end
end
