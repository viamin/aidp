# AIDP Configuration Examples

This directory contains example configuration files for the AIDP (AI Dev Pipeline) harness system. Choose the configuration that best fits your needs and copy it to your project root as `aidp.yml`.

## Available Configuration Files

### 1. `aidp.yml.example` - Complete Configuration
**Best for**: Production use, comprehensive setups, advanced users

This is the most comprehensive configuration file that demonstrates all available harness features including:
- Complete harness configuration with all options
- Multiple provider configurations (Cursor, Claude, Gemini)
- Advanced features like circuit breakers, load balancing, health checks
- Environment-specific configurations
- Mode-specific configurations (analyze vs execute)
- Feature flags
- Time-based configurations
- Step-specific configurations
- User-specific configurations
- Comprehensive monitoring and logging
- Security configurations

### 2. `aidp-minimal.yml.example` - Minimal Configuration
**Best for**: Getting started, simple setups, basic usage

This is a minimal configuration file that includes only the essential settings:
- Basic harness configuration
- Two providers (Cursor and Claude)
- Essential features only
- Simple retry and fallback configuration

### 3. `aidp-production.yml.example` - Production Configuration
**Best for**: Production deployments, enterprise use, high availability

This configuration is optimized for production use with:
- Comprehensive monitoring and alerting
- Robust error handling and retry logic
- Circuit breaker patterns for fault tolerance
- Load balancing and health checks
- Security configurations
- Cost tracking and budgeting
- Audit logging
- Performance optimizations

### 4. `aidp-development.yml.example` - Development Configuration
**Best for**: Development, testing, debugging

This configuration is optimized for development with:
- Relaxed timeouts and retry settings
- Enhanced logging and debugging
- Disabled rate limiting for testing
- Fast feedback loops
- Detailed error reporting
- Request/response logging

## Quick Start

1. **Choose a configuration file** based on your needs
2. **Copy it to your project root** as `aidp.yml`:
   ```bash
   cp templates/aidp-minimal.yml.example aidp.yml
   ```
3. **Set up your API keys** in environment variables:
   ```bash
   export ANTHROPIC_API_KEY="your_api_key_here"
   export GEMINI_API_KEY="your_api_key_here"
   ```
4. **Customize the configuration** for your specific needs
5. **Run AIDP** with the harness:
   ```bash
   aidp analyze
   aidp execute
   ```

## Configuration Sections

### Harness Configuration
The `harness` section controls the overall behavior of the harness system:
- `default_provider`: Primary provider to use
- `fallback_providers`: Backup providers in order of preference
- `max_retries`: Number of retry attempts
- `request_timeout`: Global request timeout
- `auto_switch_on_error`: Automatically switch providers on errors
- `auto_switch_on_rate_limit`: Automatically switch providers on rate limits

### Provider Configuration
The `providers` section defines individual provider settings:
- `type`: Provider type (package, api, byok)
- `priority`: Provider priority (higher = more preferred)
- `models`: Available models for the provider
- `features`: Provider capabilities
- `auth`: Authentication configuration
- `endpoints`: API endpoints
- `monitoring`: Monitoring and metrics
- `rate_limit`: Rate limiting settings
- `retry`: Retry configuration
- `circuit_breaker`: Circuit breaker settings
- `cost`: Cost tracking
- `health_check`: Health check configuration
- `log`: Logging configuration
- `cache`: Caching configuration
- `security`: Security settings

### Advanced Features

#### Environment-Specific Configuration
Use the `environments` section to have different settings for different environments:
```yaml
environments:
  development:
    harness:
      max_retries: 1
  production:
    harness:
      max_retries: 3
```

#### Mode-Specific Configuration
Use the `analyze_mode` and `execute_mode` sections for different execution modes:
```yaml
analyze_mode:
  harness:
    request_timeout: 600
execute_mode:
  harness:
    request_timeout: 300
```

#### Feature Flags
Use the `features` section to enable/disable functionality:
```yaml
features:
  debugging:
    harness:
      log_errors: true
```

#### Time-Based Configuration
Use the `time_based` section for different settings based on time:
```yaml
time_based:
  hours:
    9..17:  # Business hours
      harness:
        max_retries: 2
```

## Provider Types

### Package Providers
- **Type**: `package`
- **Pricing**: Fixed monthly/yearly subscription
- **Examples**: Cursor Pro
- **Configuration**: No API keys needed

### API Providers
- **Type**: `api`
- **Pricing**: Pay-per-use based on tokens
- **Examples**: Claude, Gemini
- **Configuration**: Requires API keys

### BYOK Providers
- **Type**: `byok`
- **Pricing**: User provides their own API key
- **Examples**: OpenAI, custom APIs
- **Configuration**: User manages API keys

## Best Practices

### Security
- Store API keys in environment variables, not in the config file
- Use `restrict_to_non_byok: true` to avoid BYOK providers
- Enable SSL verification in production
- Configure allowed/blocked hosts appropriately

### Performance
- Enable caching for frequently used responses
- Use appropriate timeouts for different models
- Configure rate limits based on your API plans
- Enable parallel processing for better throughput

### Reliability
- Configure fallback providers for automatic failover
- Enable circuit breakers for fault tolerance
- Set up health checks for all providers
- Configure appropriate retry strategies

### Monitoring
- Enable metrics collection in production
- Set up log rotation and retention
- Configure monitoring intervals appropriately
- Enable audit logging for compliance

### Cost Management
- Configure cost tracking for API providers
- Set appropriate token limits
- Monitor usage and costs regularly
- Use cost-effective models when possible

## Troubleshooting

### Common Issues

1. **Provider not working**: Check API keys and endpoints
2. **Rate limiting**: Adjust rate limit settings or use fallback providers
3. **Timeout errors**: Increase timeout values
4. **Configuration errors**: Validate your YAML syntax
5. **Permission errors**: Check file permissions for log files

### Validation

Use the AIDP configuration validator to check your configuration:
```bash
aidp config validate
```

### Debugging

Enable debug logging to troubleshoot issues:
```yaml
providers:
  your_provider:
    log:
      level: "debug"
      log_requests: true
      log_responses: true
```

## Support

For more information about AIDP configuration, see:
- [AIDP Documentation](https://github.com/your-org/aidp/docs)
- [Configuration Schema](https://github.com/your-org/aidp/docs/configuration-schema.md)
- [Provider Guide](https://github.com/your-org/aidp/docs/providers.md)

## Contributing

To contribute new configuration examples or improve existing ones:
1. Fork the repository
2. Create a new configuration file or modify an existing one
3. Test your configuration thoroughly
4. Submit a pull request with your changes
