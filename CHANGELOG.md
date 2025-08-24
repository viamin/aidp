# Changelog

## [0.5.0](https://github.com/viamin/aidp/compare/v0.4.0...v0.5.0) (2025-08-24)


### Features

* add background job option and update analysis steps in CLI ([ae8780c](https://github.com/viamin/aidp/commit/ae8780c6002517bd608eceea76073f2314b8ef93))
* add initial Claude Code workflow configuration for issue and pull request interactions ([f5b07c8](https://github.com/viamin/aidp/commit/f5b07c8fac811c1760b60cc3cb2b164455d6507b))
* add PostgreSQL service configuration to CI workflow with health checks ([160206e](https://github.com/viamin/aidp/commit/160206e48e127ce587a761ea325891e8c594a10a))
* enhance database connection handling with mutex for thread safety; improve job ID extraction in ProviderExecutionJob; add timeout constants in SupervisedBase; refine database helper methods for test database management ([4ce96fb](https://github.com/viamin/aidp/commit/4ce96fb5680c22e3e4edbb215fb2c60658b8d58d))
* enhance job management and documentation for background processing ([a53dd96](https://github.com/viamin/aidp/commit/a53dd96891df05f28e5d7aab90921a6ea8231fcb))
* enhance job troubleshooting guide and CLI job management with output viewing and hung job detection ([2b99e92](https://github.com/viamin/aidp/commit/2b99e92c6bd210a98ccd47a1f30c7658d0977d41))
* implement database connection setup for background jobs and improve job data handling in CLI ([4320e23](https://github.com/viamin/aidp/commit/4320e23807f9d903c5f8d2ed54d50744ea378a88))
* implement flag-based reset and approve options in CLI commands; enhance database connection cleanup with mutex for thread safety; update tests for new command syntax ([8937fff](https://github.com/viamin/aidp/commit/8937fff94528cd3f0f2439c46e8aff48bbfb8964))
* implement provider management and enhance CLI analysis functionality ([71d266c](https://github.com/viamin/aidp/commit/71d266c9f5d7b2c7dea7dda51759c6cda693f29b))
* update release-please configuration for Ruby; add changelog sections and pull request title pattern ([b7d01e0](https://github.com/viamin/aidp/commit/b7d01e0c66fe56b6bc777099ebb06f2b67d9024f))


### Bug Fixes

* correct key name from "version-file" to "version_file" in release configuration ([2202349](https://github.com/viamin/aidp/commit/2202349463854228165ff64c84a4cbbd0740c14f))
* remove redundant "release-type" key from release configuration ([f74f5c1](https://github.com/viamin/aidp/commit/f74f5c19277b11dfe9745815ffb1fad71516d8b1))
* rspec setup for testing ([0233047](https://github.com/viamin/aidp/commit/02330472cfe8cef2c024ccee5989d82f825de3ff))


### Improvements

* clean up whitespace and improve job management in CLI ([32e84b2](https://github.com/viamin/aidp/commit/32e84b219777dffdcc7afb7794d7102fa33189f2))
* improve error handling in RubyMaat integration and error handler; remove mock data fallback and raise errors with installation guidance; refine mock mode usage in runner ([b90ba76](https://github.com/viamin/aidp/commit/b90ba76a9a7985718c343997af18ffde26eda4d0))
* streamline job command error handling and enhance database cleanup process in tests ([d6e42f1](https://github.com/viamin/aidp/commit/d6e42f1b82046e2a27245e43e70f585a03c82530))
* update documentation and integration references from Code Maat to ruby-maat ([65f38bb](https://github.com/viamin/aidp/commit/65f38bba9a116af3dec9fd88b7be2adcff6ff938))
* update documentation and integration references from Code Maat to ruby-maat ([263d741](https://github.com/viamin/aidp/commit/263d741d085137bb1d1bb7b23676e40171eca799))

## [0.4.0](https://github.com/viamin/aidp/compare/v0.3.0...v0.4.0) (2025-08-18)

### Features

* add step to update Gemfile.lock before releasing gem ([292c1f7](https://github.com/viamin/aidp/commit/292c1f78e75c606ddba99512f1dc80312dec7db4))
* enhance analyze command with step resolution and user feedback ([96ce3bb](https://github.com/viamin/aidp/commit/96ce3bb440d94bf6f688931c887f9d43c2d4328f))
* enhance analyze command with step resolution and user feedback ([4a1d177](https://github.com/viamin/aidp/commit/4a1d177981f766fc57eeb13351032e918bd6e870))

## [0.3.0](https://github.com/viamin/aidp/compare/v0.2.0...v0.3.0) (2025-08-17)

### Features

* update publish workflow and remove legacy release workflow; bump aidp version to 0.2.0 ([07dc9c7](https://github.com/viamin/aidp/commit/07dc9c761a7d5e989fa3418af85935e5e98168c5))

## [0.2.0](https://github.com/viamin/aidp/compare/v0.1.0...v0.2.0) (2025-08-17)

### Features

* add release configuration files for automated versioning ([ec1b113](https://github.com/viamin/aidp/commit/ec1b11305a625c61912ae5d33eff85e900241bae))
* Introduce new providers and refactor existing structure ([bf493ef](https://github.com/viamin/aidp/commit/bf493ef8cebec413a49131759693c90dea72a573))
* refactor existing structure by removing the shared namespace ([e084735](https://github.com/viamin/aidp/commit/e084735fbf9cf49366431aae06de8b03fad47bf3))

### Bug Fixes

* enhance regex patterns for time and size parsing to prevent ReDoS ([d3d7641](https://github.com/viamin/aidp/commit/d3d764127f70df6cafc335e06b759263c3d02787))
