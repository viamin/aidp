# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::CLI do
  let(:cli) { described_class.new }

  describe "#detect" do
    it "outputs provider name" do
      expect { cli.detect }.to output(/Provider:/).to_stdout
    end
  end

  describe "#execute" do
    it "raises error for invalid step" do
      expect { cli.execute("invalid_step") }.to raise_error(SystemExit)
    end
  end
end
