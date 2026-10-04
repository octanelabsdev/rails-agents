# frozen_string_literal: true

require_relative "source"

module QaReport
  # The client file name carries the client, the date and the feature, never the card number.
  module ClientFile
    MAX_FEATURE = 60

    module_function

    def stem(client:, tested_on:, title:)
      "#{Source.slug(client)}-qa-report-#{tested_on.iso8601}-#{feature_slug(title)}"
    end

    def pdf_for(name) = name.sub(/\.html\z/, ".pdf")

    def feature_slug(title)
      slug = Source.slug(title)
      return slug if slug.length <= MAX_FEATURE

      # One character of lookahead, so a hyphen at the limit counts as a word break.
      window = slug[0, MAX_FEATURE + 1]
      boundary = window.rindex("-")
      (boundary ? window[0, boundary] : slug[0, MAX_FEATURE]).sub(/-+\z/, "")
    end
  end
end
