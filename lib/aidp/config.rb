# frozen_string_literal: true

require 'yaml'

module Aidp
  class Config
    DEFAULTS = {
      'provider' => nil, # auto-detect
      'outputs' => {
        'prd' => ['docs/PRD.md'],
        'nfrs' => ['docs/NFRs.md'],
        'arch' => ['docs/Architecture.md', 'docs/architecture.mmd']
      },
      'gates' => %w[prd arch]
    }.freeze

    def self.load(project_dir = Dir.pwd)
      user = File.expand_path('~/.aidp/config.yml')
      repo = File.join(project_dir, 'aidp.yml')
      cfg = DEFAULTS.dup
      [user, repo].each do |p|
        next unless File.exist?(p)

        cfg = deep_merge(cfg, YAML.load_file(p) || {})
      end
      cfg['provider'] = ENV['AIDP_PROVIDER'] if ENV['AIDP_PROVIDER']
      cfg
    end

    def self.templates_root
      File.expand_path('../../templates', __dir__)
    end

    def self.deep_merge(a, b)
      a.merge(b) { |_, v1, v2| v1.is_a?(Hash) && v2.is_a?(Hash) ? deep_merge(v1, v2) : v2 }
    end
  end
end
