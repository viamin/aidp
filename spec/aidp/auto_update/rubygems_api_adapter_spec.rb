# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/auto_update/rubygems_api_adapter"

RSpec.describe Aidp::AutoUpdate::RubyGemsAPIAdapter do
  subject(:adapter) { described_class.new }

  describe "#latest_version_for" do
    let(:gem_name) { "aidp" }
    let(:api_url) { "https://rubygems.org/api/v1/gems/#{gem_name}.json" }

    before do
      allow(Aidp).to receive(:log_debug)
      allow(Aidp).to receive(:log_warn)
      allow(Aidp).to receive(:log_error)
    end

    context "when API request succeeds with stable version" do
      let(:response_body) { '{"version":"1.2.3"}' }
      let(:http_response) { instance_double(Net::HTTPSuccess, body: response_body, is_a?: true) }

      before do
        allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: http_response))
      end

      it "returns the latest version" do
        version = adapter.latest_version_for(gem_name)
        expect(version).to eq(Gem::Version.new("1.2.3"))
      end

      it "logs debug information" do
        adapter.latest_version_for(gem_name)
        expect(Aidp).to have_received(:log_debug).with("rubygems_api", "checking_gem_version", hash_including(gem: gem_name))
        expect(Aidp).to have_received(:log_debug).with("rubygems_api", "found_version", hash_including(gem: gem_name, version: "1.2.3"))
      end
    end

    context "when API request succeeds with prerelease version" do
      let(:response_body) { '{"version":"1.2.3.pre1"}' }
      let(:http_response) { instance_double(Net::HTTPSuccess, body: response_body, is_a?: true) }

      before do
        allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: http_response))
      end

      it "returns the prerelease version when allow_prerelease is true" do
        version = adapter.latest_version_for(gem_name, allow_prerelease: true)
        expect(version).to eq(Gem::Version.new("1.2.3.pre1"))
      end

      it "returns nil when allow_prerelease is false" do
        version = adapter.latest_version_for(gem_name, allow_prerelease: false)
        expect(version).to be_nil
      end

      it "logs skipping prerelease when not allowed" do
        adapter.latest_version_for(gem_name, allow_prerelease: false)
        expect(Aidp).to have_received(:log_debug).with("rubygems_api", "skipping_prerelease", hash_including(gem: gem_name, version: "1.2.3.pre1"))
      end
    end

    context "when API response has no version field" do
      let(:response_body) { '{"name":"aidp"}' }
      let(:http_response) { instance_double(Net::HTTPSuccess, body: response_body, is_a?: true) }

      before do
        allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: http_response))
      end

      it "returns nil" do
        version = adapter.latest_version_for(gem_name)
        expect(version).to be_nil
      end

      it "logs no version in response" do
        adapter.latest_version_for(gem_name)
        expect(Aidp).to have_received(:log_debug).with("rubygems_api", "no_version_in_response", hash_including(gem: gem_name))
      end
    end

    context "when API request fails with non-success status" do
      let(:http_response) { instance_double(Net::HTTPNotFound, is_a?: false) }

      before do
        allow(http_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: http_response))
      end

      it "returns nil" do
        version = adapter.latest_version_for(gem_name)
        expect(version).to be_nil
      end
    end

    context "when API response has invalid JSON" do
      let(:response_body) { "not json" }
      let(:http_response) { instance_double(Net::HTTPSuccess, body: response_body, is_a?: true) }

      before do
        allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: http_response))
      end

      it "returns nil" do
        version = adapter.latest_version_for(gem_name)
        expect(version).to be_nil
      end

      it "logs JSON parse error" do
        adapter.latest_version_for(gem_name)
        expect(Aidp).to have_received(:log_error).with("rubygems_api", "json_parse_failed", hash_including(gem: gem_name))
      end
    end

    context "when API response has invalid version string" do
      let(:response_body) { '{"version":"invalid-version"}' }
      let(:http_response) { instance_double(Net::HTTPSuccess, body: response_body, is_a?: true) }

      before do
        allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: http_response))
      end

      it "returns nil" do
        version = adapter.latest_version_for(gem_name)
        expect(version).to be_nil
      end

      it "logs invalid version error" do
        adapter.latest_version_for(gem_name)
        expect(Aidp).to have_received(:log_error).with("rubygems_api", "invalid_version", hash_including(gem: gem_name))
      end
    end

    context "when request times out" do
      before do
        allow(Net::HTTP).to receive(:start).and_raise(Timeout::Error)
      end

      it "returns nil" do
        version = adapter.latest_version_for(gem_name)
        expect(version).to be_nil
      end

      it "logs timeout warning" do
        adapter.latest_version_for(gem_name)
        expect(Aidp).to have_received(:log_warn).with("rubygems_api", "request_timeout", hash_including(timeout: 5))
      end
    end

    context "when connection is refused" do
      before do
        allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)
      end

      it "returns nil" do
        version = adapter.latest_version_for(gem_name)
        expect(version).to be_nil
      end

      it "logs connection failure warning" do
        adapter.latest_version_for(gem_name)
        expect(Aidp).to have_received(:log_warn).with("rubygems_api", "connection_failed", hash_including(uri: api_url))
      end
    end

    context "when socket error occurs" do
      before do
        allow(Net::HTTP).to receive(:start).and_raise(SocketError.new("getaddrinfo failed"))
      end

      it "returns nil" do
        version = adapter.latest_version_for(gem_name)
        expect(version).to be_nil
      end

      it "logs connection failure warning" do
        adapter.latest_version_for(gem_name)
        expect(Aidp).to have_received(:log_warn).with("rubygems_api", "connection_failed", hash_including(error: "getaddrinfo failed"))
      end
    end

    context "when generic error occurs" do
      before do
        allow(Net::HTTP).to receive(:start).and_raise(StandardError.new("unknown error"))
      end

      it "returns nil" do
        version = adapter.latest_version_for(gem_name)
        expect(version).to be_nil
      end

      it "logs API request failure" do
        adapter.latest_version_for(gem_name)
        expect(Aidp).to have_received(:log_error).with("rubygems_api", "api_request_failed", hash_including(gem: gem_name, error: "unknown error"))
      end
    end
  end
end
