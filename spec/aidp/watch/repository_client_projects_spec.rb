# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe Aidp::Watch::RepositoryClient do
  let(:owner) { "testowner" }
  let(:repo) { "testrepo" }

  describe "GitHub Projects V2 methods" do
    describe "#fetch_project" do
      context "when gh CLI is not available" do
        let(:client) { described_class.new(owner: owner, repo: repo, gh_available: false) }

        it "raises an error" do
          expect { client.fetch_project("PVT_123") }.to raise_error(RuntimeError, /GitHub CLI not available/)
        end
      end

      context "when gh CLI is available" do
        let(:client) { described_class.new(owner: owner, repo: repo, gh_available: true) }

        before do
          allow(Aidp).to receive(:log_debug)
          allow(Aidp).to receive(:log_warn)
          allow(Aidp).to receive(:log_error)
        end

        it "fetches project successfully" do
          graphql_response = {
            "data" => {
              "node" => {
                "id" => "PVT_123",
                "title" => "Test Project",
                "number" => 1,
                "url" => "https://github.com/orgs/test/projects/1",
                "fields" => {"nodes" => []}
              }
            }
          }
          allow(client).to receive(:execute_graphql_query).and_return(graphql_response)

          result = client.fetch_project("PVT_123")
          expect(result[:id]).to eq("PVT_123")
          expect(result[:title]).to eq("Test Project")
        end

        it "raises error when project not found" do
          graphql_response = {"data" => {"node" => nil}}
          allow(client).to receive(:execute_graphql_query).and_return(graphql_response)

          expect { client.fetch_project("PVT_invalid") }.to raise_error(RuntimeError, /Project not found/)
        end
      end
    end

    describe "#list_project_items" do
      context "when gh CLI is not available" do
        let(:client) { described_class.new(owner: owner, repo: repo, gh_available: false) }

        it "raises an error" do
          expect { client.list_project_items("PVT_123") }.to raise_error(RuntimeError, /GitHub CLI not available/)
        end
      end

      context "when gh CLI is available" do
        let(:client) { described_class.new(owner: owner, repo: repo, gh_available: true) }

        before do
          allow(Aidp).to receive(:log_debug)
          allow(Aidp).to receive(:log_error)
        end

        it "returns empty array when no items" do
          graphql_response = {
            "data" => {
              "node" => {
                "items" => {
                  "pageInfo" => {"hasNextPage" => false, "endCursor" => nil},
                  "nodes" => []
                }
              }
            }
          }
          allow(client).to receive(:execute_graphql_query).and_return(graphql_response)

          result = client.list_project_items("PVT_123")
          expect(result).to eq([])
        end

        it "lists project items successfully" do
          graphql_response = {
            "data" => {
              "node" => {
                "items" => {
                  "pageInfo" => {"hasNextPage" => false, "endCursor" => nil},
                  "nodes" => [
                    {
                      "id" => "PVTI_1",
                      "type" => "ISSUE",
                      "content" => {"number" => 42, "title" => "Test Issue", "state" => "OPEN", "url" => "https://github.com/test/repo/issues/42"},
                      "fieldValues" => {"nodes" => []}
                    }
                  ]
                }
              }
            }
          }
          allow(client).to receive(:execute_graphql_query).and_return(graphql_response)

          result = client.list_project_items("PVT_123")
          expect(result.size).to eq(1)
          expect(result.first[:id]).to eq("PVTI_1")
        end

        it "handles pagination" do
          first_response = {
            "data" => {
              "node" => {
                "items" => {
                  "pageInfo" => {"hasNextPage" => true, "endCursor" => "cursor1"},
                  "nodes" => [{"id" => "PVTI_1", "type" => "ISSUE", "content" => nil, "fieldValues" => {"nodes" => []}}]
                }
              }
            }
          }
          second_response = {
            "data" => {
              "node" => {
                "items" => {
                  "pageInfo" => {"hasNextPage" => false, "endCursor" => nil},
                  "nodes" => [{"id" => "PVTI_2", "type" => "ISSUE", "content" => nil, "fieldValues" => {"nodes" => []}}]
                }
              }
            }
          }
          allow(client).to receive(:execute_graphql_query).and_return(first_response, second_response)

          result = client.list_project_items("PVT_123")
          expect(result.size).to eq(2)
        end
      end
    end

    describe "#link_issue_to_project" do
      context "when gh CLI is not available" do
        let(:client) { described_class.new(owner: owner, repo: repo, gh_available: false) }

        it "raises an error" do
          expect { client.link_issue_to_project("PVT_123", 42) }.to raise_error(RuntimeError, /GitHub CLI not available/)
        end
      end

      context "when gh CLI is available" do
        let(:client) { described_class.new(owner: owner, repo: repo, gh_available: true) }

        before do
          allow(Aidp).to receive(:log_debug)
          allow(Aidp).to receive(:log_warn)
          allow(Aidp).to receive(:log_error)
        end

        it "links issue to project successfully" do
          issue_query_response = {
            "data" => {"repository" => {"issue" => {"id" => "I_123"}}}
          }
          mutation_response = {
            "data" => {"addProjectV2ItemById" => {"item" => {"id" => "PVTI_new"}}}
          }
          allow(client).to receive(:execute_graphql_query).and_return(issue_query_response, mutation_response)

          result = client.link_issue_to_project("PVT_123", 42)
          expect(result).to eq("PVTI_new")
        end

        it "raises error when issue not found" do
          issue_query_response = {
            "data" => {"repository" => {"issue" => nil}}
          }
          allow(client).to receive(:execute_graphql_query).and_return(issue_query_response)

          expect { client.link_issue_to_project("PVT_123", 999) }.to raise_error(RuntimeError, /Issue #999 not found/)
        end
      end
    end

    describe "#update_project_item_field" do
      context "when gh CLI is not available" do
        let(:client) { described_class.new(owner: owner, repo: repo, gh_available: false) }

        it "raises an error" do
          expect { client.update_project_item_field("PVTI_1", "PVTF_1", {text: "value"}) }.to raise_error(RuntimeError, /GitHub CLI not available/)
        end
      end

      context "when gh CLI is available" do
        let(:client) { described_class.new(owner: owner, repo: repo, gh_available: true) }

        before do
          allow(Aidp).to receive(:log_debug)
          allow(Aidp).to receive(:log_error)
        end

        it "updates text field successfully" do
          mutation_response = {
            "data" => {"updateProjectV2ItemFieldValue" => {"projectV2Item" => {"id" => "PVTI_1"}}}
          }
          allow(client).to receive(:execute_graphql_query).and_return(mutation_response)

          result = client.update_project_item_field("PVTI_1", "PVTF_1", {project_id: "PVT_123", text: "new value"})
          expect(result).to eq("PVTI_1")
        end

        it "updates single select field successfully" do
          mutation_response = {
            "data" => {"updateProjectV2ItemFieldValue" => {"projectV2Item" => {"id" => "PVTI_1"}}}
          }
          allow(client).to receive(:execute_graphql_query).and_return(mutation_response)

          result = client.update_project_item_field("PVTI_1", "PVTF_1", {project_id: "PVT_123", option_id: "OPT_1"})
          expect(result).to eq("PVTI_1")
        end
      end
    end

    describe "#fetch_project_fields" do
      context "when gh CLI is not available" do
        let(:client) { described_class.new(owner: owner, repo: repo, gh_available: false) }

        it "raises an error" do
          expect { client.fetch_project_fields("PVT_123") }.to raise_error(RuntimeError, /GitHub CLI not available/)
        end
      end

      context "when gh CLI is available" do
        let(:client) { described_class.new(owner: owner, repo: repo, gh_available: true) }

        before do
          allow(Aidp).to receive(:log_debug)
          allow(Aidp).to receive(:log_error)
        end

        it "fetches project fields successfully" do
          graphql_response = {
            "data" => {
              "node" => {
                "fields" => {
                  "nodes" => [
                    {"id" => "PVTF_1", "name" => "Status", "dataType" => "SINGLE_SELECT", "options" => [{"id" => "OPT_1", "name" => "Todo"}]},
                    {"id" => "PVTF_2", "name" => "Priority", "dataType" => "TEXT"}
                  ]
                }
              }
            }
          }
          allow(client).to receive(:execute_graphql_query).and_return(graphql_response)

          result = client.fetch_project_fields("PVT_123")
          expect(result.size).to eq(2)
          expect(result.first[:name]).to eq("Status")
        end

        it "returns empty array when no fields" do
          graphql_response = {
            "data" => {"node" => {"fields" => {"nodes" => []}}}
          }
          allow(client).to receive(:execute_graphql_query).and_return(graphql_response)

          result = client.fetch_project_fields("PVT_123")
          expect(result).to eq([])
        end
      end
    end

    describe "#create_project_field" do
      context "when gh CLI is not available" do
        let(:client) { described_class.new(owner: owner, repo: repo, gh_available: false) }

        it "raises an error" do
          expect { client.create_project_field("PVT_123", "Status", "SINGLE_SELECT") }.to raise_error(RuntimeError, /GitHub CLI not available/)
        end
      end

      context "when gh CLI is available" do
        let(:client) { described_class.new(owner: owner, repo: repo, gh_available: true) }

        before do
          allow(Aidp).to receive(:log_debug)
          allow(Aidp).to receive(:log_error)
        end

        it "creates text field successfully" do
          mutation_response = {
            "data" => {
              "createProjectV2Field" => {
                "projectV2Field" => {"id" => "PVTF_new", "name" => "Notes", "dataType" => "TEXT"}
              }
            }
          }
          allow(client).to receive(:execute_graphql_query).and_return(mutation_response)

          result = client.create_project_field("PVT_123", "Notes", "TEXT")
          expect(result[:id]).to eq("PVTF_new")
          expect(result[:name]).to eq("Notes")
        end

        it "creates single select field with options" do
          mutation_response = {
            "data" => {
              "createProjectV2Field" => {
                "projectV2Field" => {"id" => "PVTF_new", "name" => "Status", "dataType" => "SINGLE_SELECT"}
              }
            }
          }
          allow(client).to receive(:execute_graphql_query).and_return(mutation_response)

          options = [{name: "Todo"}, {name: "Done"}]
          result = client.create_project_field("PVT_123", "Status", "SINGLE_SELECT", options: options)
          expect(result[:id]).to eq("PVTF_new")
        end
      end
    end

    describe "#create_issue" do
      context "when gh CLI is not available" do
        let(:client) { described_class.new(owner: owner, repo: repo, gh_available: false) }

        it "raises an error" do
          expect { client.create_issue(title: "Test", body: "Body") }.to raise_error(RuntimeError, /GitHub CLI not available/)
        end
      end

      context "when gh CLI is available" do
        let(:client) { described_class.new(owner: owner, repo: repo, gh_available: true) }

        before do
          allow(Aidp).to receive(:log_debug)
          allow(Aidp).to receive(:log_error)
        end

        it "creates issue successfully" do
          # gh issue create returns the issue URL
          gh_output = "https://github.com/test/repo/issues/123"
          allow(Open3).to receive(:capture3).and_return([gh_output, "", double(success?: true)])

          result = client.create_issue(title: "Test Issue", body: "Test body")
          expect(result[:number]).to eq(123)
          expect(result[:url]).to eq("https://github.com/test/repo/issues/123")
        end

        it "creates issue with labels and assignees" do
          gh_output = "https://github.com/test/repo/issues/124"
          allow(Open3).to receive(:capture3).and_return([gh_output, "", double(success?: true)])

          result = client.create_issue(
            title: "Test Issue",
            body: "Test body",
            labels: ["bug", "priority-high"],
            assignees: ["user1"]
          )
          expect(result[:number]).to eq(124)
        end

        it "raises error on CLI failure" do
          allow(Open3).to receive(:capture3).and_return(["", "Error creating issue", double(success?: false)])

          expect { client.create_issue(title: "Test", body: "Body") }.to raise_error(RuntimeError, /Failed to create issue/)
        end
      end
    end

    describe "#merge_pull_request" do
      context "when gh CLI is not available" do
        let(:client) { described_class.new(owner: owner, repo: repo, gh_available: false) }

        it "raises an error" do
          expect { client.merge_pull_request(123) }.to raise_error(RuntimeError, /GitHub CLI not available/)
        end
      end

      context "when gh CLI is available" do
        let(:client) { described_class.new(owner: owner, repo: repo, gh_available: true) }

        before do
          allow(Aidp).to receive(:log_debug)
          allow(Aidp).to receive(:log_info)
          allow(Aidp).to receive(:log_error)
        end

        it "merges PR successfully with squash" do
          allow(Open3).to receive(:capture3).and_return(["", "", double(success?: true)])

          expect { client.merge_pull_request(123, merge_method: "squash") }.not_to raise_error
        end

        it "merges PR successfully with merge" do
          allow(Open3).to receive(:capture3).and_return(["", "", double(success?: true)])

          expect { client.merge_pull_request(123, merge_method: "merge") }.not_to raise_error
        end

        it "raises error on CLI failure" do
          allow(Open3).to receive(:capture3).and_return(["", "Error merging", double(success?: false)])

          expect { client.merge_pull_request(123) }.to raise_error(RuntimeError, /Failed to merge/)
        end
      end
    end
  end
end
