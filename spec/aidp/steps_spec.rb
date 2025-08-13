# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Aidp::Steps do
  describe '.list' do
    it 'returns an array of step names' do
      steps = described_class.list
      expect(steps).to be_an(Array)
      expect(steps).to include('prd', 'nfrs', 'arch')
    end

    it 'includes all expected steps' do
      expected_steps = %w[prd nfrs arch adrs domains contracts threat tests tasks scaffold impl static obs delivery docsportal post]
      expect(described_class.list).to match_array(expected_steps)
    end
  end

  describe '.for' do
    it 'returns step specification for valid step' do
      spec = described_class.for('prd')
      expect(spec).to be_a(Hash)
      expect(spec[:templates]).to include('00_PRD.md')
      expect(spec[:outs]).to include('docs/PRD.md')
    end

    it 'raises error for invalid step' do
      expect { described_class.for('invalid_step') }.to raise_error(RuntimeError, /Unknown step/)
    end
  end
end
