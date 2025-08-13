# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Aidp do
  it 'has a version number' do
    expect(Aidp::VERSION).not_to be nil
  end

  it 'can be required without errors' do
    expect { require 'aidp' }.not_to raise_error
  end
end
