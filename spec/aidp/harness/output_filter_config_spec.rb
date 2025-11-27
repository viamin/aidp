# frozen_string_literal: true

RSpec.describe Aidp::Harness::OutputFilterConfig do
  describe "#initialize" do
    it "creates config with default values" do
      config = described_class.new

      expect(config.mode).to eq(:full)
      expect(config.include_context).to eq(true)
      expect(config.context_lines).to eq(3)
      expect(config.max_lines).to eq(500)
    end

    it "creates config with custom values" do
      config = described_class.new(
        mode: :failures_only,
        include_context: false,
        context_lines: 5,
        max_lines: 200
      )

      expect(config.mode).to eq(:failures_only)
      expect(config.include_context).to eq(false)
      expect(config.context_lines).to eq(5)
      expect(config.max_lines).to eq(200)
    end

    it "freezes the config object" do
      config = described_class.new
      expect(config).to be_frozen
    end

    context "mode validation" do
      it "accepts :full mode" do
        expect { described_class.new(mode: :full) }.not_to raise_error
      end

      it "accepts :failures_only mode" do
        expect { described_class.new(mode: :failures_only) }.not_to raise_error
      end

      it "accepts :minimal mode" do
        expect { described_class.new(mode: :minimal) }.not_to raise_error
      end

      it "converts string mode to symbol" do
        config = described_class.new(mode: "failures_only")
        expect(config.mode).to eq(:failures_only)
      end

      it "raises error for invalid mode" do
        expect { described_class.new(mode: :invalid) }
          .to raise_error(ArgumentError, /Invalid mode/)
      end
    end

    context "include_context validation" do
      it "accepts true" do
        expect { described_class.new(include_context: true) }.not_to raise_error
      end

      it "accepts false" do
        expect { described_class.new(include_context: false) }.not_to raise_error
      end

      it "raises error for non-boolean" do
        expect { described_class.new(include_context: "yes") }
          .to raise_error(ArgumentError, /must be a boolean/)
      end
    end

    context "context_lines validation" do
      it "accepts 0" do
        config = described_class.new(context_lines: 0)
        expect(config.context_lines).to eq(0)
      end

      it "accepts 20" do
        config = described_class.new(context_lines: 20)
        expect(config.context_lines).to eq(20)
      end

      it "raises error for negative values" do
        expect { described_class.new(context_lines: -1) }
          .to raise_error(ArgumentError, /context_lines must be an integer/)
      end

      it "raises error for values over 20" do
        expect { described_class.new(context_lines: 21) }
          .to raise_error(ArgumentError, /context_lines must be an integer/)
      end
    end

    context "max_lines validation" do
      it "accepts 10" do
        config = described_class.new(max_lines: 10)
        expect(config.max_lines).to eq(10)
      end

      it "accepts 10000" do
        config = described_class.new(max_lines: 10_000)
        expect(config.max_lines).to eq(10_000)
      end

      it "raises error for values under 10" do
        expect { described_class.new(max_lines: 9) }
          .to raise_error(ArgumentError, /max_lines must be an integer/)
      end

      it "raises error for values over 10000" do
        expect { described_class.new(max_lines: 10_001) }
          .to raise_error(ArgumentError, /max_lines must be an integer/)
      end
    end
  end

  describe ".from_hash" do
    it "creates config from hash with symbol keys" do
      hash = {
        mode: :minimal,
        include_context: false,
        context_lines: 5,
        max_lines: 100
      }

      config = described_class.from_hash(hash)

      expect(config.mode).to eq(:minimal)
      expect(config.include_context).to eq(false)
      expect(config.context_lines).to eq(5)
      expect(config.max_lines).to eq(100)
    end

    it "creates config from hash with string keys" do
      hash = {
        "mode" => "failures_only",
        "include_context" => true,
        "context_lines" => 3,
        "max_lines" => 200
      }

      config = described_class.from_hash(hash)

      expect(config.mode).to eq(:failures_only)
      expect(config.include_context).to eq(true)
    end

    it "uses defaults for missing keys" do
      config = described_class.from_hash({})

      expect(config.mode).to eq(:full)
      expect(config.include_context).to eq(true)
      expect(config.context_lines).to eq(3)
      expect(config.max_lines).to eq(500)
    end

    it "uses defaults for nil values" do
      config = described_class.from_hash({mode: nil, max_lines: nil})

      expect(config.mode).to eq(:full)
      expect(config.max_lines).to eq(500)
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      config = described_class.new(
        mode: :failures_only,
        include_context: false,
        context_lines: 5,
        max_lines: 100
      )

      hash = config.to_h

      expect(hash).to eq({
        mode: :failures_only,
        include_context: false,
        context_lines: 5,
        max_lines: 100
      })
    end
  end

  describe "#filtering_enabled?" do
    it "returns false for full mode" do
      config = described_class.new(mode: :full)
      expect(config.filtering_enabled?).to eq(false)
    end

    it "returns true for failures_only mode" do
      config = described_class.new(mode: :failures_only)
      expect(config.filtering_enabled?).to eq(true)
    end

    it "returns true for minimal mode" do
      config = described_class.new(mode: :minimal)
      expect(config.filtering_enabled?).to eq(true)
    end
  end

  describe "#==" do
    it "returns true for identical configs" do
      config1 = described_class.new(mode: :minimal, max_lines: 100)
      config2 = described_class.new(mode: :minimal, max_lines: 100)

      expect(config1).to eq(config2)
    end

    it "returns false for different modes" do
      config1 = described_class.new(mode: :minimal)
      config2 = described_class.new(mode: :full)

      expect(config1).not_to eq(config2)
    end

    it "returns false for different max_lines" do
      config1 = described_class.new(max_lines: 100)
      config2 = described_class.new(max_lines: 200)

      expect(config1).not_to eq(config2)
    end

    it "returns false when comparing to non-config object" do
      config = described_class.new
      expect(config).not_to eq({mode: :full})
    end
  end

  describe "#hash" do
    it "returns same hash for equal configs" do
      config1 = described_class.new(mode: :minimal, max_lines: 100)
      config2 = described_class.new(mode: :minimal, max_lines: 100)

      expect(config1.hash).to eq(config2.hash)
    end

    it "can be used in Hash/Set" do
      config1 = described_class.new(mode: :minimal)
      config2 = described_class.new(mode: :minimal)

      set = Set.new([config1])
      expect(set).to include(config2)
    end
  end
end
