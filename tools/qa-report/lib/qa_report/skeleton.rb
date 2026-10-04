# frozen_string_literal: true

require_relative "source"

module QaReport
  # The empty source `new` writes: every top-level key present, empty, and marked client or internal.
  module Skeleton
    SCHEMA_VERSION = 1

    module_function

    def to_yaml(card:)
      Source::SCHEMA.fetch(:top).map { |key, field| "#{key}:#{value_for(key, field, card)}  # #{field.klass}" }.join("\n") + "\n"
    end

    def value_for(key, field, card)
      return " #{SCHEMA_VERSION}" if key == "schema_version"
      return " #{card.to_s.dump}" if key == "card"

      case Array(field.type).first
      when :list then " []"
      when :shape then " {}"
      else ""
      end
    end
  end
end
