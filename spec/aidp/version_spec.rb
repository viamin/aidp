# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp do
  describe "VERSION" do
    it "is defined" do
      expect(Aidp::VERSION).to be_a(String)
    end

    it "follows semantic versioning format" do
      expect(Aidp::VERSION).to match(/\A\d+\.\d+\.\d+/)
    end

    it "is not empty" do
      expect(Aidp::VERSION).not_to be_empty
    end
  end
end
