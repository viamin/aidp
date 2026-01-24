# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Interfaces::BinaryCheckerInterface do
  describe "interface contract" do
    let(:bare_class) do
      Class.new do
        include Aidp::Interfaces::BinaryCheckerInterface
      end
    end

    it "requires #available? to be implemented" do
      instance = bare_class.new
      expect { instance.available?("ruby") }
        .to raise_error(NotImplementedError, /must implement #available\?/)
    end

    it "requires #path_for to be implemented" do
      instance = bare_class.new
      expect { instance.path_for("ruby") }
        .to raise_error(NotImplementedError, /must implement #path_for/)
    end
  end
end

RSpec.describe Aidp::Interfaces::NullBinaryChecker do
  subject(:checker) { described_class.new }

  describe "interface compliance" do
    it "includes BinaryCheckerInterface" do
      expect(described_class.included_modules).to include(Aidp::Interfaces::BinaryCheckerInterface)
    end
  end

  describe "#available?" do
    it "returns false for any binary" do
      expect(checker.available?("ruby")).to be false
      expect(checker.available?("nonexistent")).to be false
    end
  end

  describe "#path_for" do
    it "returns nil for any binary" do
      expect(checker.path_for("ruby")).to be_nil
      expect(checker.path_for("nonexistent")).to be_nil
    end
  end
end

RSpec.describe Aidp::Interfaces::StubBinaryChecker do
  describe "interface compliance" do
    it "includes BinaryCheckerInterface" do
      expect(described_class.included_modules).to include(Aidp::Interfaces::BinaryCheckerInterface)
    end
  end

  describe "#available?" do
    it "returns configured availability" do
      checker = described_class.new(available: {"ruby" => true, "python" => false})

      expect(checker.available?("ruby")).to be true
      expect(checker.available?("python")).to be false
    end

    it "returns false for unconfigured binaries" do
      checker = described_class.new(available: {"ruby" => true})

      expect(checker.available?("unknown")).to be false
    end

    it "converts binary names to strings" do
      checker = described_class.new(available: {"ruby" => true})

      expect(checker.available?(:ruby)).to be true
    end
  end

  describe "#path_for" do
    it "returns configured paths" do
      checker = described_class.new(paths: {"ruby" => "/usr/bin/ruby"})

      expect(checker.path_for("ruby")).to eq("/usr/bin/ruby")
    end

    it "returns nil for unconfigured binaries" do
      checker = described_class.new(paths: {"ruby" => "/usr/bin/ruby"})

      expect(checker.path_for("unknown")).to be_nil
    end
  end
end

RSpec.describe Aidp::Interfaces::PathBinaryChecker do
  subject(:checker) { described_class.new }

  describe "interface compliance" do
    it "includes BinaryCheckerInterface" do
      expect(described_class.included_modules).to include(Aidp::Interfaces::BinaryCheckerInterface)
    end
  end

  describe "#available?" do
    it "returns true for system binaries" do
      # These should exist on any Unix-like system
      expect(checker.available?("sh")).to be true
    end

    it "returns false for nonexistent binaries" do
      expect(checker.available?("definitely_not_a_real_binary_xyz123")).to be false
    end
  end

  describe "#path_for" do
    it "returns the path for system binaries" do
      path = checker.path_for("sh")

      expect(path).not_to be_nil
      expect(File.executable?(path)).to be true
    end

    it "returns nil for nonexistent binaries" do
      expect(checker.path_for("definitely_not_a_real_binary_xyz123")).to be_nil
    end

    it "returns nil for empty binary names" do
      expect(checker.path_for("")).to be_nil
      expect(checker.path_for(nil)).to be_nil
    end
  end
end

RSpec.describe Aidp::Interfaces::CachingBinaryChecker do
  let(:inner_checker) { Aidp::Interfaces::StubBinaryChecker.new(available: {"ruby" => true}, paths: {"ruby" => "/usr/bin/ruby"}) }
  subject(:checker) { described_class.new(inner_checker, ttl: 1) }

  describe "interface compliance" do
    it "includes BinaryCheckerInterface" do
      expect(described_class.included_modules).to include(Aidp::Interfaces::BinaryCheckerInterface)
    end
  end

  describe "#available?" do
    it "delegates to inner checker" do
      expect(checker.available?("ruby")).to be true
      expect(checker.available?("unknown")).to be false
    end

    it "caches results" do
      spy_checker = instance_double(Aidp::Interfaces::PathBinaryChecker)
      allow(spy_checker).to receive(:available?).with("ruby").and_return(true)

      caching = described_class.new(spy_checker, ttl: 60)

      # First call
      expect(caching.available?("ruby")).to be true
      # Second call should use cache
      expect(caching.available?("ruby")).to be true

      # Should only have called the inner checker once
      expect(spy_checker).to have_received(:available?).with("ruby").once
    end

    it "expires cache after TTL" do
      spy_checker = instance_double(Aidp::Interfaces::PathBinaryChecker)
      allow(spy_checker).to receive(:available?).with("ruby").and_return(true)

      caching = described_class.new(spy_checker, ttl: 0.1)

      expect(caching.available?("ruby")).to be true
      sleep 0.15 # Wait for cache to expire
      expect(caching.available?("ruby")).to be true

      # Should have called twice due to expiration
      expect(spy_checker).to have_received(:available?).with("ruby").twice
    end
  end

  describe "#path_for" do
    it "delegates to inner checker" do
      expect(checker.path_for("ruby")).to eq("/usr/bin/ruby")
      expect(checker.path_for("unknown")).to be_nil
    end

    it "caches results" do
      spy_checker = instance_double(Aidp::Interfaces::PathBinaryChecker)
      allow(spy_checker).to receive(:path_for).with("ruby").and_return("/usr/bin/ruby")

      caching = described_class.new(spy_checker, ttl: 60)

      # First call
      expect(caching.path_for("ruby")).to eq("/usr/bin/ruby")
      # Second call should use cache
      expect(caching.path_for("ruby")).to eq("/usr/bin/ruby")

      # Should only have called the inner checker once
      expect(spy_checker).to have_received(:path_for).with("ruby").once
    end
  end

  describe "#clear_cache!" do
    it "clears all cached results" do
      spy_checker = instance_double(Aidp::Interfaces::PathBinaryChecker)
      allow(spy_checker).to receive(:available?).with("ruby").and_return(true)

      caching = described_class.new(spy_checker, ttl: 60)

      expect(caching.available?("ruby")).to be true
      caching.clear_cache!
      expect(caching.available?("ruby")).to be true

      # Should have called twice due to cache clear
      expect(spy_checker).to have_received(:available?).with("ruby").twice
    end
  end

  describe "#clear!" do
    it "clears cached result for specific binary" do
      spy_checker = instance_double(Aidp::Interfaces::PathBinaryChecker)
      allow(spy_checker).to receive(:available?).with("ruby").and_return(true)
      allow(spy_checker).to receive(:available?).with("python").and_return(true)

      caching = described_class.new(spy_checker, ttl: 60)

      expect(caching.available?("ruby")).to be true
      expect(caching.available?("python")).to be true

      caching.clear!("ruby")

      expect(caching.available?("ruby")).to be true
      expect(caching.available?("python")).to be true

      # Ruby should have been called twice, python only once
      expect(spy_checker).to have_received(:available?).with("ruby").twice
      expect(spy_checker).to have_received(:available?).with("python").once
    end
  end
end

RSpec.describe Aidp::Interfaces::AidpBinaryChecker do
  subject(:checker) { described_class.new }

  describe "interface compliance" do
    it "includes BinaryCheckerInterface" do
      expect(described_class.included_modules).to include(Aidp::Interfaces::BinaryCheckerInterface)
    end
  end

  describe "#available?" do
    it "delegates to Aidp::Util.which" do
      expect(Aidp::Util).to receive(:which).with("ruby").and_return("/usr/bin/ruby")
      expect(checker.available?("ruby")).to be true
    end

    it "returns false when Aidp::Util.which returns nil" do
      expect(Aidp::Util).to receive(:which).with("nonexistent").and_return(nil)
      expect(checker.available?("nonexistent")).to be false
    end
  end

  describe "#path_for" do
    it "delegates to Aidp::Util.which" do
      expect(Aidp::Util).to receive(:which).with("ruby").and_return("/usr/bin/ruby")
      expect(checker.path_for("ruby")).to eq("/usr/bin/ruby")
    end
  end
end
