# frozen_string_literal: true

require "yaml"

module Aidp
  module Harness
    # Configuration schema and validation for harness
    class ConfigSchema
      # Define the complete configuration schema
      SCHEMA = {
        harness: {
          type: :hash,
          required: true,
          properties: {
            max_retries: {
              type: :integer,
              required: false,
              default: 2,
              min: 0,
              max: 10
            },
            default_provider: {
              type: :string,
              required: true,
              pattern: /^[a-zA-Z0-9_-]+$/
            },
            fallback_providers: {
              type: :array,
              required: false,
              default: [],
              items: {
                type: :string,
                pattern: /^[a-zA-Z0-9_-]+$/
              }
            },
            no_api_keys_required: {
              type: :boolean,
              required: false,
              default: false
            },
            provider_weights: {
              type: :hash,
              required: false,
              default: {},
              pattern_properties: {
                /^[a-zA-Z0-9_-]+$/ => {
                  type: :integer,
                  min: 1,
                  max: 10
                }
              }
            },
            circuit_breaker: {
              type: :hash,
              required: false,
              default: {
                enabled: true,
                failure_threshold: 5,
                timeout: 300,
                half_open_max_calls: 3
              },
              properties: {
                enabled: {
                  type: :boolean,
                  required: false,
                  default: true
                },
                failure_threshold: {
                  type: :integer,
                  required: false,
                  default: 5,
                  min: 1,
                  max: 100
                },
                timeout: {
                  type: :integer,
                  required: false,
                  default: 300,
                  min: 60,
                  max: 3600
                },
                half_open_max_calls: {
                  type: :integer,
                  required: false,
                  default: 3,
                  min: 1,
                  max: 10
                }
              }
            },
            retry: {
              type: :hash,
              required: false,
              default: {
                enabled: true,
                max_attempts: 3,
                base_delay: 1.0,
                max_delay: 60.0,
                exponential_base: 2.0,
                jitter: true
              },
              properties: {
                enabled: {
                  type: :boolean,
                  required: false,
                  default: true
                },
                max_attempts: {
                  type: :integer,
                  required: false,
                  default: 3,
                  min: 1,
                  max: 10
                },
                base_delay: {
                  type: :number,
                  required: false,
                  default: 1.0,
                  min: 0.1,
                  max: 60.0
                },
                max_delay: {
                  type: :number,
                  required: false,
                  default: 60.0,
                  min: 1.0,
                  max: 3600.0
                },
                exponential_base: {
                  type: :number,
                  required: false,
                  default: 2.0,
                  min: 1.1,
                  max: 5.0
                },
                jitter: {
                  type: :boolean,
                  required: false,
                  default: true
                }
              }
            },
            rate_limit: {
              type: :hash,
              required: false,
              default: {
                enabled: true,
                default_reset_time: 3600,
                burst_limit: 10,
                sustained_limit: 5
              },
              properties: {
                enabled: {
                  type: :boolean,
                  required: false,
                  default: true
                },
                default_reset_time: {
                  type: :integer,
                  required: false,
                  default: 3600,
                  min: 60,
                  max: 86400
                },
                burst_limit: {
                  type: :integer,
                  required: false,
                  default: 10,
                  min: 1,
                  max: 1000
                },
                sustained_limit: {
                  type: :integer,
                  required: false,
                  default: 5,
                  min: 1,
                  max: 100
                }
              }
            },
            load_balancing: {
              type: :hash,
              required: false,
              default: {
                enabled: true,
                strategy: "weighted_round_robin",
                health_check_interval: 30,
                unhealthy_threshold: 3
              },
              properties: {
                enabled: {
                  type: :boolean,
                  required: false,
                  default: true
                },
                strategy: {
                  type: :string,
                  required: false,
                  default: "weighted_round_robin",
                  enum: ["round_robin", "weighted_round_robin", "least_connections", "random"]
                },
                health_check_interval: {
                  type: :integer,
                  required: false,
                  default: 30,
                  min: 10,
                  max: 300
                },
                unhealthy_threshold: {
                  type: :integer,
                  required: false,
                  default: 3,
                  min: 1,
                  max: 10
                }
              }
            },
            model_switching: {
              type: :hash,
              required: false,
              default: {
                enabled: true,
                auto_switch_on_error: true,
                auto_switch_on_rate_limit: true,
                fallback_strategy: "sequential"
              },
              properties: {
                enabled: {
                  type: :boolean,
                  required: false,
                  default: true
                },
                auto_switch_on_error: {
                  type: :boolean,
                  required: false,
                  default: true
                },
                auto_switch_on_rate_limit: {
                  type: :boolean,
                  required: false,
                  default: true
                },
                fallback_strategy: {
                  type: :string,
                  required: false,
                  default: "sequential",
                  enum: ["sequential", "random", "weighted"]
                }
              }
            },
            health_check: {
              type: :hash,
              required: false,
              default: {
                enabled: true,
                interval: 60,
                timeout: 10,
                failure_threshold: 3,
                success_threshold: 2
              },
              properties: {
                enabled: {
                  type: :boolean,
                  required: false,
                  default: true
                },
                interval: {
                  type: :integer,
                  required: false,
                  default: 60,
                  min: 10,
                  max: 600
                },
                timeout: {
                  type: :integer,
                  required: false,
                  default: 10,
                  min: 1,
                  max: 60
                },
                failure_threshold: {
                  type: :integer,
                  required: false,
                  default: 3,
                  min: 1,
                  max: 10
                },
                success_threshold: {
                  type: :integer,
                  required: false,
                  default: 2,
                  min: 1,
                  max: 5
                }
              }
            },
            metrics: {
              type: :hash,
              required: false,
              default: {
                enabled: true,
                retention_days: 30,
                aggregation_interval: 300,
                export_interval: 3600
              },
              properties: {
                enabled: {
                  type: :boolean,
                  required: false,
                  default: true
                },
                retention_days: {
                  type: :integer,
                  required: false,
                  default: 30,
                  min: 1,
                  max: 365
                },
                aggregation_interval: {
                  type: :integer,
                  required: false,
                  default: 300,
                  min: 60,
                  max: 3600
                },
                export_interval: {
                  type: :integer,
                  required: false,
                  default: 3600,
                  min: 300,
                  max: 86400
                }
              }
            },
            session: {
              type: :hash,
              required: false,
              default: {
                enabled: true,
                timeout: 1800,
                sticky_sessions: true,
                session_affinity: "provider_model"
              },
              properties: {
                enabled: {
                  type: :boolean,
                  required: false,
                  default: true
                },
                timeout: {
                  type: :integer,
                  required: false,
                  default: 1800,
                  min: 300,
                  max: 7200
                },
                sticky_sessions: {
                  type: :boolean,
                  required: false,
                  default: true
                },
                session_affinity: {
                  type: :string,
                  required: false,
                  default: "provider_model",
                  enum: ["provider_model", "provider", "model", "none"]
                }
              }
            },
            work_loop: {
              type: :hash,
              required: false,
              default: {
                enabled: true,
                max_iterations: 50,
                test_commands: [],
                lint_commands: []
              },
              properties: {
                enabled: {
                  type: :boolean,
                  required: false,
                  default: true
                },
                max_iterations: {
                  type: :integer,
                  required: false,
                  default: 50,
                  min: 1,
                  max: 200
                },
                test_commands: {
                  type: :array,
                  required: false,
                  default: [],
                  items: {
                    type: :string
                  }
                },
                lint_commands: {
                  type: :array,
                  required: false,
                  default: [],
                  items: {
                    type: :string
                  }
                },
                guards: {
                  type: :hash,
                  required: false,
                  default: {
                    enabled: false
                  },
                  properties: {
                    enabled: {
                      type: :boolean,
                      required: false,
                      default: false
                    },
                    include_files: {
                      type: :array,
                      required: false,
                      default: [],
                      items: {
                        type: :string
                      }
                    },
                    exclude_files: {
                      type: :array,
                      required: false,
                      default: [],
                      items: {
                        type: :string
                      }
                    },
                    confirm_files: {
                      type: :array,
                      required: false,
                      default: [],
                      items: {
                        type: :string
                      }
                    },
                    max_lines_per_commit: {
                      type: :integer,
                      required: false,
                      min: 1,
                      max: 10000
                    },
                    bypass: {
                      type: :boolean,
                      required: false,
                      default: false
                    }
                  }
                }
              }
            }
          }
        },
        providers: {
          type: :hash,
          required: false,
          default: {},
          pattern_properties: {
            /^[a-zA-Z0-9_-]+$/ => {
              type: :hash,
              properties: {
                type: {
                  type: :string,
                  required: true,
                  enum: ["usage_based", "subscription", "passthrough"]
                },
                priority: {
                  type: :integer,
                  required: false,
                  default: 1,
                  min: 1,
                  max: 10
                },
                max_tokens: {
                  type: :integer,
                  required: false,
                  min: 1000,
                  max: 1_000_000
                },
                default_flags: {
                  type: :array,
                  required: false,
                  default: [],
                  items: {
                    type: :string
                  }
                },
                models: {
                  type: :array,
                  required: false,
                  default: [],
                  items: {
                    type: :string,
                    pattern: /^[a-zA-Z0-9._-]+$/
                  }
                },
                model_weights: {
                  type: :hash,
                  required: false,
                  default: {},
                  pattern_properties: {
                    /^[a-zA-Z0-9._-]+$/ => {
                      type: :integer,
                      min: 1,
                      max: 10
                    }
                  }
                },
                models_config: {
                  type: :hash,
                  required: false,
                  default: {},
                  pattern_properties: {
                    /^[a-zA-Z0-9._-]+$/ => {
                      type: :hash,
                      properties: {
                        flags: {
                          type: :array,
                          required: false,
                          default: [],
                          items: {
                            type: :string
                          }
                        },
                        max_tokens: {
                          type: :integer,
                          required: false,
                          min: 1000,
                          max: 1_000_000
                        },
                        timeout: {
                          type: :integer,
                          required: false,
                          min: 30,
                          max: 3600
                        }
                      }
                    }
                  }
                },
                auth: {
                  type: :hash,
                  required: false,
                  default: {},
                  properties: {
                    api_key_env: {
                      type: :string,
                      required: false,
                      pattern: /^[A-Z_][A-Z0-9_]*$/
                    },
                    api_key: {
                      type: :string,
                      required: false
                    }
                  }
                },
                endpoints: {
                  type: :hash,
                  required: false,
                  default: {},
                  properties: {
                    default: {
                      type: :string,
                      required: false,
                      format: :uri
                    }
                  }
                },
                features: {
                  type: :hash,
                  required: false,
                  default: {},
                  properties: {
                    file_upload: {
                      type: :boolean,
                      required: false,
                      default: false
                    },
                    code_generation: {
                      type: :boolean,
                      required: false,
                      default: true
                    },
                    analysis: {
                      type: :boolean,
                      required: false,
                      default: true
                    },
                    vision: {
                      type: :boolean,
                      required: false,
                      default: false
                    }
                  }
                },
                monitoring: {
                  type: :hash,
                  required: false,
                  default: {
                    enabled: true,
                    metrics_interval: 60
                  },
                  properties: {
                    enabled: {
                      type: :boolean,
                      required: false,
                      default: true
                    },
                    metrics_interval: {
                      type: :integer,
                      required: false,
                      default: 60,
                      min: 10,
                      max: 3600
                    }
                  }
                }
              }
            }
          }
        }
      }.freeze

      # Validate configuration against schema
      def self.validate(config)
        errors = []
        warnings = []

        # Validate top-level structure
        unless config.is_a?(Hash)
          errors << "Configuration must be a hash"
          return {valid: false, errors: errors, warnings: warnings}
        end

        # Validate harness section
        if config.key?(:harness) || config.key?("harness")
          harness_errors, harness_warnings = validate_section(
            config[:harness] || config["harness"],
            SCHEMA[:harness],
            "harness"
          )
          errors.concat(harness_errors)
          warnings.concat(harness_warnings)
        elsif SCHEMA[:harness][:required]
          errors << "harness: section is required"
        end

        # Validate providers section
        if config.key?(:providers) || config.key?("providers")
          providers_errors, providers_warnings = validate_section(
            config[:providers] || config["providers"],
            SCHEMA[:providers],
            "providers"
          )
          errors.concat(providers_errors)
          warnings.concat(providers_warnings)
        end

        # Cross-validation
        cross_validation_errors, cross_validation_warnings = cross_validate(config)
        errors.concat(cross_validation_errors)
        warnings.concat(cross_validation_warnings)

        {
          valid: errors.empty?,
          errors: errors,
          warnings: warnings
        }
      end

      # Apply defaults to configuration
      def self.apply_defaults(config)
        result = deep_dup(config)

        # Apply harness defaults
        if result.key?(:harness) || result.key?("harness")
          harness_section = result[:harness] || result["harness"]
          result[:harness] = apply_section_defaults(harness_section, SCHEMA[:harness])
        else
          result[:harness] = apply_section_defaults({}, SCHEMA[:harness])
        end

        # Apply provider defaults
        if result.key?(:providers) || result.key?("providers")
          providers_section = result[:providers] || result["providers"]
          result[:providers] = apply_providers_defaults(providers_section)
        else
          result[:providers] = {}
        end

        result
      end

      # Generate example configuration
      def self.generate_example
        {
          harness: {
            max_retries: 2,
            default_provider: "cursor",
            fallback_providers: ["cursor"],
            no_api_keys_required: false,
            provider_weights: {
              "cursor" => 3,
              "anthropic" => 2,
              "macos" => 1
            },
            circuit_breaker: {
              enabled: true,
              failure_threshold: 5,
              timeout: 300,
              half_open_max_calls: 3
            },
            retry: {
              enabled: true,
              max_attempts: 3,
              base_delay: 1.0,
              max_delay: 60.0,
              exponential_base: 2.0,
              jitter: true
            },
            rate_limit: {
              enabled: true,
              default_reset_time: 3600,
              burst_limit: 10,
              sustained_limit: 5
            },
            load_balancing: {
              enabled: true,
              strategy: "weighted_round_robin",
              health_check_interval: 30,
              unhealthy_threshold: 3
            },
            model_switching: {
              enabled: true,
              auto_switch_on_error: true,
              auto_switch_on_rate_limit: true,
              fallback_strategy: "sequential"
            },
            health_check: {
              enabled: true,
              interval: 60,
              timeout: 10,
              failure_threshold: 3,
              success_threshold: 2
            },
            metrics: {
              enabled: true,
              retention_days: 30,
              aggregation_interval: 300,
              export_interval: 3600
            },
            session: {
              enabled: true,
              timeout: 1800,
              sticky_sessions: true,
              session_affinity: "provider_model"
            }
          },
          providers: {
            cursor: {
              type: "subscription",
              priority: 1,
              default_flags: [],
              models: ["cursor-default", "cursor-fast", "cursor-precise"],
              model_weights: {
                "cursor-default" => 3,
                "cursor-fast" => 2,
                "cursor-precise" => 1
              },
              models_config: {
                "cursor-default" => {
                  flags: [],
                  timeout: 600
                },
                "cursor-fast" => {
                  flags: ["--fast"],
                  timeout: 300
                },
                "cursor-precise" => {
                  flags: ["--precise"],
                  timeout: 900
                }
              },
              features: {
                file_upload: true,
                code_generation: true,
                analysis: true
              },
              monitoring: {
                enabled: true,
                metrics_interval: 60
              }
            },
            anthropic: {
              type: "usage_based",
              priority: 2,
              max_tokens: 100_000,
              default_flags: ["--dangerously-skip-permissions"],
              models: ["claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022"],
              model_weights: {
                "claude-3-5-sonnet-20241022" => 3,
                "claude-3-5-haiku-20241022" => 2
              },
              models_config: {
                "claude-3-5-sonnet-20241022" => {
                  flags: ["--dangerously-skip-permissions"],
                  max_tokens: 200_000,
                  timeout: 300
                },
                "claude-3-5-haiku-20241022" => {
                  flags: ["--dangerously-skip-permissions"],
                  max_tokens: 200_000,
                  timeout: 180
                }
              },
              auth: {
                api_key_env: "ANTHROPIC_API_KEY"
              },
              endpoints: {
                default: "https://api.anthropic.com/v1/messages"
              },
              features: {
                file_upload: true,
                code_generation: true,
                analysis: true,
                vision: true
              },
              monitoring: {
                enabled: true,
                metrics_interval: 60
              }
            },
            macos: {
              type: "passthrough",
              priority: 4,
              underlying_service: "cursor",
              models: ["cursor-chat"],
              features: {
                file_upload: false,
                code_generation: true,
                analysis: true,
                interactive: true
              }
            }
          }
        }
      end

      def self.validate_section(data, schema, path)
        errors = []
        warnings = []

        # Check if section is required
        if schema[:required] && data.nil?
          errors << "#{path}: section is required"
          return [errors, warnings]
        end

        # Check if string is empty and required
        if schema[:required] && schema[:type] == :string && data.is_a?(String) && data.empty?
          errors << "#{path}: is required"
          return [errors, warnings]
        end

        # For non-hash types, validate the type and return
        unless data.is_a?(Hash)
          # Validate type
          if schema[:type] == :array && !data.is_a?(Array)
            errors << "#{path}: must be an array"
          elsif schema[:type] == :string && !data.is_a?(String)
            errors << "#{path}: must be a string"
          elsif schema[:type] == :integer && !data.is_a?(Integer)
            errors << "#{path}: must be an integer"
          elsif schema[:type] == :number && !data.is_a?(Numeric)
            errors << "#{path}: must be a number"
          elsif schema[:type] == :boolean && !data.is_a?(TrueClass) && !data.is_a?(FalseClass)
            errors << "#{path}: must be a boolean"
          end

          # Validate string pattern if specified
          if schema[:type] == :string && data.is_a?(String) && schema[:pattern] && !data.match?(schema[:pattern])
            errors << "#{path}: must match pattern"
          end

          # Validate enum values
          if schema[:enum] && !schema[:enum].include?(data)
            errors << "#{path}: must be one of #{schema[:enum].join(", ")}"
          end

          # Validate numeric constraints
          if schema[:type] == :integer && data.is_a?(Integer)
            if schema[:min] && data < schema[:min]
              errors << "#{path}: must be >= #{schema[:min]}"
            end
            if schema[:max] && data > schema[:max]
              errors << "#{path}: must be <= #{schema[:max]}"
            end
          end

          return [errors, warnings]
        end

        # Validate hash type
        if schema[:type] == :hash && !data.is_a?(Hash)
          errors << "#{path}: must be a hash"
          return [errors, warnings]
        end

        # Validate properties for hash types
        if schema[:type] == :hash && schema[:properties]
          schema[:properties].each do |prop_name, prop_schema|
            prop_path = "#{path}.#{prop_name}"

            if data.key?(prop_name) || data.key?(prop_name.to_s)
              prop_value = data.key?(prop_name) ? data[prop_name] : data[prop_name.to_s]
              prop_errors, prop_warnings = validate_section(prop_value, prop_schema, prop_path)
              errors.concat(prop_errors)
              warnings.concat(prop_warnings)
            elsif prop_schema[:required]
              errors << "#{prop_path}: is required"
            end
          end
        end

        # Validate pattern properties for hash types
        if schema[:type] == :hash && schema[:pattern_properties]
          data.each do |key, value|
            # Find matching pattern
            matching_pattern = nil
            matching_schema = nil

            schema[:pattern_properties].each do |pattern, pattern_schema|
              if key.to_s.match?(pattern)
                matching_pattern = pattern
                matching_schema = pattern_schema
                break
              end
            end

            if matching_schema
              prop_path = "#{path}.#{key}"
              prop_errors, prop_warnings = validate_section(value, matching_schema, prop_path)
              errors.concat(prop_errors)
              warnings.concat(prop_warnings)
            end
          end
        end

        # Validate array items
        if schema[:type] == :array && schema[:items] && data.is_a?(Array)
          data.each_with_index do |item, index|
            item_errors, item_warnings = validate_section(item, schema[:items], "#{path}[#{index}]")
            errors.concat(item_errors)
            warnings.concat(item_warnings)
          end
        end

        # Validate constraints
        if data.is_a?(Numeric)
          if schema[:min] && data < schema[:min]
            errors << "#{path}: must be >= #{schema[:min]}"
          end
          if schema[:max] && data > schema[:max]
            errors << "#{path}: must be <= #{schema[:max]}"
          end
        end

        if data.is_a?(String)
          if schema[:pattern] && !data.match?(schema[:pattern])
            errors << "#{path}: must match pattern #{schema[:pattern]}"
          end
          if schema[:enum] && !schema[:enum].include?(data)
            errors << "#{path}: must be one of #{schema[:enum].join(", ")}"
          end
          if schema[:format] == :uri && !valid_uri?(data)
            errors << "#{path}: must be a valid URI"
          end
        end

        [errors, warnings]
      end

      def self.cross_validate(config)
        errors = []
        warnings = []

        # Validate that default_provider exists in providers
        harness_config = config[:harness] || config["harness"]
        providers_config = config[:providers] || config["providers"]

        if harness_config && providers_config
          default_provider = harness_config[:default_provider] || harness_config["default_provider"]
          if default_provider
            unless providers_config.key?(default_provider) || providers_config.key?(default_provider.to_sym)
              errors << "Default provider '#{default_provider}' not found in providers configuration"
            end
          end

          # Validate fallback providers exist
          fallback_providers = harness_config[:fallback_providers] || harness_config["fallback_providers"] || []
          fallback_providers.each do |provider|
            unless providers_config.key?(provider) || providers_config.key?(provider.to_sym)
              errors << "Fallback provider '#{provider}' not found in providers configuration"
            end
          end

          # Validate provider weights reference existing providers
          provider_weights = harness_config[:provider_weights] || harness_config["provider_weights"] || {}
          provider_weights.each do |provider, _weight|
            unless providers_config.key?(provider) || providers_config.key?(provider.to_sym)
              warnings << "Provider weight specified for non-existent provider '#{provider}'"
            end
          end
        end

        # Validate that models in model_weights exist in models array
        providers_config&.each do |provider_name, provider_config|
          models = provider_config[:models] || provider_config["models"] || []
          model_weights = provider_config[:model_weights] || provider_config["model_weights"] || {}

          model_weights.each do |model, _weight|
            unless models.include?(model)
              warnings << "Model weight specified for model '#{model}' not in models array for provider '#{provider_name}'"
            end
          end
        end

        [errors, warnings]
      end

      def self.apply_section_defaults(data, schema)
        result = data.dup

        schema[:properties]&.each do |prop_name, prop_schema|
          if result.key?(prop_name) || result.key?(prop_name.to_s)
            prop_value = result[prop_name] || result[prop_name.to_s]
            if prop_schema[:type] == :hash && prop_schema[:properties]
              result[prop_name] = apply_section_defaults(prop_value, prop_schema)
            end
          elsif prop_schema[:default]
            result[prop_name] = prop_schema[:default]
          elsif prop_schema[:type] == :hash && prop_schema[:properties]
            result[prop_name] = apply_section_defaults({}, prop_schema)
          end
        end

        result
      end

      def self.apply_providers_defaults(providers_data)
        result = providers_data.dup

        providers_schema = SCHEMA[:providers][:pattern_properties][/^[a-zA-Z0-9_-]+$/]

        result.each do |provider_name, provider_config|
          result[provider_name] = apply_section_defaults(provider_config, providers_schema)
        end

        result
      end

      def self.valid_uri?(uri_string)
        require "uri"
        URI.parse(uri_string)
        true
      rescue URI::InvalidURIError
        false
      end

      def self.deep_dup(obj)
        case obj
        when Hash
          obj.transform_values { |v| deep_dup(v) }
        when Array
          obj.map { |v| deep_dup(v) }
        else
          begin
            obj.dup
          rescue
            obj
          end
        end
      end

      private_class_method :validate_section, :apply_providers_defaults, :valid_uri?, :deep_dup
    end
  end
end
