# frozen_string_literal: true

require "digest"
require "json"
require "yaml"
require_relative "client_file"
require_relative "projection"

module QaReport
  # The renderer version an approval records; a different one makes the approval stale.
  RENDERER = "qa-report 0.2"

  # Reads and compares approvals; the approve command is the tool's only writer.
  module Approval
    SUFFIX = ".approval.yml"
    Status = Struct.new(:kind, :approved_digest, :current_digest, :approved_renderer)

    module_function

    # Internal-only edits never reach the client projection, so they never change this digest.
    def digest(source, client:, brand: nil)
      Digest::SHA256.hexdigest(JSON.generate([Projection.digest(source), client, brand_parts(brand)]))
    end

    def path_for(source_path)
      source_path.sub(/\.qa\.yml\z/, SUFFIX).tap { |path| raise ArgumentError, "#{source_path} does not end in .qa.yml" if path == source_path }
    end

    def status(source_path, source, client:, brand: nil)
      current = digest(source, client: client, brand: brand)
      path = path_for(source_path)
      approved = stored_digest(path)
      renderer = stored_renderer(path)
      Status.new(kind_of(approved, current, renderer), approved, current, renderer)
    end

    def kind_of(approved, current, renderer)
      if approved.nil? then :awaiting
      elsif approved == current && renderer == RENDERER then :approved
      else :stale
      end
    end

    # Everything the client file renders from the brand, so a rebrand needs a fresh approval.
    def brand_parts(brand)
      return unless brand

      fonts = brand.fonts.map { |font| [font.family, font.weight, Digest::SHA256.hexdigest(font.data)] }
      [brand.name, brand.contact_email, brand.view_box, brand.wordmark_on_dark, brand.wordmark_on_light, fonts]
    end

    def stored_digest(path) = stored(path, "client_digest")

    def stored_renderer(path) = stored(path, "renderer")

    def stored(path, key)
      data = YAML.safe_load_file(path, permitted_classes: [Date])
      data[key] if data.is_a?(Hash)
    rescue SystemCallError, Psych::Exception
      nil
    end
  end
end
