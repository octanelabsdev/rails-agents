require_relative "test_helper"

# Review: element ids are slugs of authored ids, so two ids that slug alike would give the page duplicate anchors.
class DomIdTest < Minitest::Test
  def journeys_named(*ids)
    source_from(:pass_with_notes) do |data|
      ids.each_with_index { |id, index| data["journeys"][index]["id"] = id }
      data["requirements"][0]["journeys"] = ids
      data["requirements"].drop(1).each { |requirement| requirement["journeys"] -= [1, 2] }
    end
  end

  def assert_id_rejected(&block)
    error = assert_raises(QaReport::InvalidSource, &block)
    assert_equal 1, error.exit_code
    assert error.problems.any? { |problem| problem.match?(/\Ajourneys\[[^\]]*\]\.id\b/) },
      "expected a problem at journeys[…].id, got #{error.problems.inspect}"
  end

  def test_journey_ids_whose_slugs_collide_reject_the_source
    assert_id_rejected { journeys_named("J-1", "J 1") }
  end

  def test_a_journey_id_that_slugs_to_nothing_rejects_the_source
    assert_id_rejected { journeys_named("!!", 2) }
  end

  # The slug rule must not reject ids that only look alike to a reader.
  def test_distinct_slugs_still_load
    assert_kind_of QaReport::Source, journeys_named("J-1", "J-2")
  end
end
