# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Execute::Steps do
  describe "SPEC" do
    it "defines execute mode steps" do
      expect(Aidp::Execute::Steps::SPEC).to be_a(Hash)
      expect(Aidp::Execute::Steps::SPEC.keys).not_to be_empty
    end

    it "includes all required step attributes" do
      Aidp::Execute::Steps::SPEC.each do |step_name, spec|
        expect(spec).to have_key("templates")
        expect(spec).to have_key("outs")
        expect(spec).to have_key("gate")
        expect(spec).to have_key("agent")
      end
    end

    it "has valid step names" do
      Aidp::Execute::Steps::SPEC.keys.each do |step_name|
        expect(step_name).to match(/^\d{2}[A-Z]?_[A-Z_]+$/)
      end
    end
  end
end
