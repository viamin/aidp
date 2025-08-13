# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Aidp::Util do
  describe '.which' do
    it 'finds existing executables' do
      # Should find ruby in PATH
      expect(described_class.which('ruby')).to be_a(String)
    end

    it 'returns nil for non-existent executables' do
      expect(described_class.which('nonexistent_executable_12345')).to be_nil
    end
  end

  describe '.macos?' do
    it 'returns boolean value' do
      expect([true, false]).to include(described_class.macos?)
    end
  end

  describe '.ensure_dirs' do
    let(:temp_dir) { Dir.mktmpdir('aidp_test') }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it 'creates directories for paths' do
      paths = ['docs/subdir', 'contracts/nested/dir']
      described_class.ensure_dirs(paths, temp_dir)

      # ensure_dirs creates parent directories, not the full paths
      expect(Dir.exist?(File.join(temp_dir, 'docs'))).to be true
      expect(Dir.exist?(File.join(temp_dir, 'contracts', 'nested'))).to be true
    end

    it 'does not create directories that already exist' do
      existing_dir = File.join(temp_dir, 'docs')
      FileUtils.mkdir_p(existing_dir)

      expect { described_class.ensure_dirs(['docs'], temp_dir) }.not_to raise_error
    end
  end
end
