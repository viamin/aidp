# Changelog

## [0.8.0](https://github.com/viamin/aidp/compare/aidp/v0.7.0...aidp/v0.8.0) (2025-09-19)


### Features

* add Opencode provider for enhanced functionality ([400da5c](https://github.com/viamin/aidp/commit/400da5c99ea0b7de3062c46b416455be6b47ea58))
* enhance CLI with new system tests and improved workflow management ([4f5b284](https://github.com/viamin/aidp/commit/4f5b2842b1ba513ac22070d8dab0980d14176ea3))
* enhance debugging capabilities and add configuration file ([32ed1e2](https://github.com/viamin/aidp/commit/32ed1e2e9942597c6d4ba31fadc58afcda094d33))
* enhance provider and model management with advanced configurations ([7bde12a](https://github.com/viamin/aidp/commit/7bde12ae8db3eed7cdfd6cabc3b7a2e64e7c7902))
* enhance user interface with control features and feedback presentation ([2564103](https://github.com/viamin/aidp/commit/25641030936e8bf66f66d15938963b73df4172bf))
* implement circuit breaker and error handling enhancements ([3c90f22](https://github.com/viamin/aidp/commit/3c90f220b078ed5f8a7a9777e394e6a1dda06bec))
* implement comprehensive tracking systems for progress, provider status, rate limits, and token usage ([d995917](https://github.com/viamin/aidp/commit/d9959176925d09092bdcff3bc8ac873f61f7f0cf))
* implement enhanced harness configuration management and provider integration ([c308ea4](https://github.com/viamin/aidp/commit/c308ea44d44f866bd387b2481e280c33772ed6e8))
* implement harness mode in CLI and enhance configuration management ([e845e2c](https://github.com/viamin/aidp/commit/e845e2c37af65f5198e94dd641666cc1709c0019))
* implement navigation system with keyboard support and menu management ([6b1e86a](https://github.com/viamin/aidp/commit/6b1e86ad0a74bf5e43ddb023d173688c148980e1))
* integrate harness support across job management and execution ([fe377c3](https://github.com/viamin/aidp/commit/fe377c34dda198a338f17ed297081530ebe0e1ee))
* introduce EnhancedRunner and UI components for improved workflow management ([70528a0](https://github.com/viamin/aidp/commit/70528a0a18fbc44ff8f5864e17552dc85704ebc6))
* introduce Harness Mode for autonomous execution and enhanced user interaction ([1f44d48](https://github.com/viamin/aidp/commit/1f44d4833c17d2da360bfe18059e17859a5b6f82))
* introduce job monitoring and management UI components ([00ee7aa](https://github.com/viamin/aidp/commit/00ee7aadbb9d25d73a8e1bf01b79c87d12e1a365))


### Improvements

* enhance state management and UI components with CLI UI integration ([77eabb8](https://github.com/viamin/aidp/commit/77eabb81bdabb04fcc6f0c5a3d24c822d54f22f2))
* enhance user experience with animated spinners and improved error handling ([880237d](https://github.com/viamin/aidp/commit/880237d5bc9a9393daf6cbd83acb3ec34508dd40))
* integrate TTY libraries for enhanced terminal UI experience ([827ed11](https://github.com/viamin/aidp/commit/827ed1110956a1667c16bb1426754be2a7172b37))
* remove database dependencies and switch to async-job ([aa93464](https://github.com/viamin/aidp/commit/aa934644fc3e32947886a130fa41d8cc91ce9a28))
* separate out CI steps into their own workflows ([7a63f24](https://github.com/viamin/aidp/commit/7a63f24a02a9fd67f1c12d9875b0826b356d83c1))
* streamline configuration command structure and enhance error handling ([ca8e935](https://github.com/viamin/aidp/commit/ca8e935811f308f19af892df8704212d024508b0))
* transition to Enhanced TUI and remove TTY dependencies ([b5d4b2e](https://github.com/viamin/aidp/commit/b5d4b2e398cbcab1b92c6d19cf2c29df28ef2192))
* unify spinner management and enhance UI components ([b49f11a](https://github.com/viamin/aidp/commit/b49f11a07662cb2254e8467b8c6292740e9780d7))
* update gemspec and UI components for TTY integration ([1b95a0a](https://github.com/viamin/aidp/commit/1b95a0a5cbfc933cd633cbd3a4e636452d84e0a2))


### Documentation

* update migration guide and style guide for Enhanced TUI integration ([8746a76](https://github.com/viamin/aidp/commit/8746a76ccabb1b54d3778537ac52289ca9dc94ed))
* update README and add LLM style guide ([3932e01](https://github.com/viamin/aidp/commit/3932e01c3aad399a014b49ac79148531c1cf0280))
* update README for CLI command changes and TUI integration ([76cff4b](https://github.com/viamin/aidp/commit/76cff4b44857edc2f4a20995903828af2ad2f52b))

## [0.7.0](https://github.com/viamin/aidp/compare/aidp/v0.6.0...aidp/v0.7.0) (2025-09-07)

### Features

* add Copilot instructions for AIDP project ([2130422](https://github.com/viamin/aidp/commit/21304225b994ed397ab20a5099f29a69aac1eafc))
* add kb_dir option to kb_show and kb_graph commands for customizable knowledge base directory ([4cbf8ff](https://github.com/viamin/aidp/commit/4cbf8ff98d2aa0b147ffeebed15be5ac5c2504fb))
* Add Tree-sitter static analysis capabilities and parser installation ([#36](https://github.com/viamin/aidp/issues/36)) ([467fa35](https://github.com/viamin/aidp/commit/467fa357fd9fbeb410353e12eb5f42b7a6f6adfc))

### Bug Fixes

* enhance error handling by adding PG::Error to database error rescue clauses ([30ed108](https://github.com/viamin/aidp/commit/30ed1088430f2ee49a5925841b4e9a59731cb866))
* update download URL format for Tree-sitter parsers and improve error handling in TreeSitterScan ([e1dc397](https://github.com/viamin/aidp/commit/e1dc397e8dd390dbcfdf7c564e9fec20f8173f49))
* update path separator handling in TreeSitterScan for cross-platform compatibility ([55b4b67](https://github.com/viamin/aidp/commit/55b4b6792a3d90830eab7f9ea3e80cc6faa80a8c))

### Improvements

* improve exception handling across multiple files to specify error types ([99e46c4](https://github.com/viamin/aidp/commit/99e46c48981abd5891b88043e55b220897928de0))
* remove redundant error handling across multiple files ([6498b34](https://github.com/viamin/aidp/commit/6498b341182ce34cbb91f24539654259dcc5073a))
* streamline parser installation script and enhance error handling in TreeSitterScan ([686b10d](https://github.com/viamin/aidp/commit/686b10d13169ed392f8253a491260617342f32c6))

## [0.6.0](https://github.com/viamin/aidp/compare/aidp-v0.5.4...aidp/v0.6.0) (2025-09-05)

### Features

* add background job option and update analysis steps in CLI ([ae8780c](https://github.com/viamin/aidp/commit/ae8780c6002517bd608eceea76073f2314b8ef93))
* add comprehensive analyze mode documentation and sample outputs ([9de981e](https://github.com/viamin/aidp/commit/9de981e45dac7a6d39cd16d280a8be0fbb2571f9))
* add initial Claude Code workflow configuration for issue and pull request interactions ([f5b07c8](https://github.com/viamin/aidp/commit/f5b07c8fac811c1760b60cc3cb2b164455d6507b))
* add logger dependency and enhance version management ([503cbf6](https://github.com/viamin/aidp/commit/503cbf6c550c72021fdd1fd1eb3577b00ca17a89))
* add PostgreSQL service configuration to CI workflow with health checks ([160206e](https://github.com/viamin/aidp/commit/160206e48e127ce587a761ea325891e8c594a10a))
* add release configuration files for automated versioning ([ec1b113](https://github.com/viamin/aidp/commit/ec1b11305a625c61912ae5d33eff85e900241bae))
* add step to update Gemfile.lock before releasing gem ([292c1f7](https://github.com/viamin/aidp/commit/292c1f78e75c606ddba99512f1dc80312dec7db4))
* enhance analysis capabilities with new classes and dependencies ([bc185ab](https://github.com/viamin/aidp/commit/bc185ab077ff5ec928faa2f4782e8202f8d3b2c9))
* enhance analyze command with step resolution and user feedback ([96ce3bb](https://github.com/viamin/aidp/commit/96ce3bb440d94bf6f688931c887f9d43c2d4328f))
* enhance analyze command with step resolution and user feedback ([4a1d177](https://github.com/viamin/aidp/commit/4a1d177981f766fc57eeb13351032e918bd6e870))
* enhance database connection handling with mutex for thread safety; improve job ID extraction in ProviderExecutionJob; add timeout constants in SupervisedBase; refine database helper methods for test database management ([4ce96fb](https://github.com/viamin/aidp/commit/4ce96fb5680c22e3e4edbb215fb2c60658b8d58d))
* enhance job management and documentation for background processing ([a53dd96](https://github.com/viamin/aidp/commit/a53dd96891df05f28e5d7aab90921a6ea8231fcb))
* enhance job troubleshooting guide and CLI job management with output viewing and hung job detection ([2b99e92](https://github.com/viamin/aidp/commit/2b99e92c6bd210a98ccd47a1f30c7658d0977d41))
* implement analysis framework and enhance dependencies ([97f0e53](https://github.com/viamin/aidp/commit/97f0e53832e1fd90fa2d85c644b9fc068f986461))
* implement database connection setup for background jobs and improve job data handling in CLI ([4320e23](https://github.com/viamin/aidp/commit/4320e23807f9d903c5f8d2ed54d50744ea378a88))
* implement flag-based reset and approve options in CLI commands; enhance database connection cleanup with mutex for thread safety; update tests for new command syntax ([8937fff](https://github.com/viamin/aidp/commit/8937fff94528cd3f0f2439c46e8aff48bbfb8964))
* implement provider management and enhance CLI analysis functionality ([71d266c](https://github.com/viamin/aidp/commit/71d266c9f5d7b2c7dea7dda51759c6cda693f29b))
* Introduce new providers and refactor existing structure ([bf493ef](https://github.com/viamin/aidp/commit/bf493ef8cebec413a49131759693c90dea72a573))
* introduce performance optimization system for large codebases ([2f2fa4e](https://github.com/viamin/aidp/commit/2f2fa4eabd0f1829e052e1bb0d53a0d1f0a62fdc))
* refactor existing structure by removing the shared namespace ([e084735](https://github.com/viamin/aidp/commit/e084735fbf9cf49366431aae06de8b03fad47bf3))
* update publish workflow and remove legacy release workflow; bump aidp version to 0.2.0 ([07dc9c7](https://github.com/viamin/aidp/commit/07dc9c761a7d5e989fa3418af85935e5e98168c5))
* update release-please configuration for Ruby; add changelog sections and pull request title pattern ([b7d01e0](https://github.com/viamin/aidp/commit/b7d01e0c66fe56b6bc777099ebb06f2b67d9024f))

### Bug Fixes

* code scanning alert no. 6: Workflow does not contain permissions ([9120c66](https://github.com/viamin/aidp/commit/9120c66d230ae5252aeed7f66a02474b83ce303c))
* correct key name from "version-file" to "version_file" in release configuration ([2202349](https://github.com/viamin/aidp/commit/2202349463854228165ff64c84a4cbbd0740c14f))
* enhance regex patterns for time and size parsing to prevent ReDoS ([d3d7641](https://github.com/viamin/aidp/commit/d3d764127f70df6cafc335e06b759263c3d02787))
* remove redundant "release-type" key from release configuration ([f74f5c1](https://github.com/viamin/aidp/commit/f74f5c19277b11dfe9745815ffb1fad71516d8b1))
* rspec setup for testing ([0233047](https://github.com/viamin/aidp/commit/02330472cfe8cef2c024ccee5989d82f825de3ff))
* update version to match release tags ([d116ead](https://github.com/viamin/aidp/commit/d116ead588d64aae292c0d34c2d57b3dbf6de0e9))
* update version to match release tags ([ae4d96a](https://github.com/viamin/aidp/commit/ae4d96a9e198ead4fb78ded495fa42222bc62b56))

### Improvements

* clean up whitespace and improve job management in CLI ([32e84b2](https://github.com/viamin/aidp/commit/32e84b219777dffdcc7afb7794d7102fa33189f2))
* improve error handling in RubyMaat integration and error handler; remove mock data fallback and raise errors with installation guidance; refine mock mode usage in runner ([b90ba76](https://github.com/viamin/aidp/commit/b90ba76a9a7985718c343997af18ffde26eda4d0))
* replace CodeMaatIntegration with RubyMaatIntegration for enhanced analysis capabilities ([dd2fc51](https://github.com/viamin/aidp/commit/dd2fc515f7f4b555d56d0a48ea45d6238d7fa15c))
* restructure Aidp gem and enhance analysis capabilities ([9274813](https://github.com/viamin/aidp/commit/927481311a5cdd554e247e07eef352fa01ef1939))
* standardize string delimiters and improve code readability in performance_optimizer.rb ([efb2e4c](https://github.com/viamin/aidp/commit/efb2e4c8d5e4a8e43005cab8717d40d59931a53a))
* streamline job command error handling and enhance database cleanup process in tests ([d6e42f1](https://github.com/viamin/aidp/commit/d6e42f1b82046e2a27245e43e70f585a03c82530))
* streamline publish workflow by consolidating gem release steps ([32ab2d0](https://github.com/viamin/aidp/commit/32ab2d0f500bb647997abeb19328ba59f4e56fa0))
* update documentation and integration references from Code Maat to ruby-maat ([65f38bb](https://github.com/viamin/aidp/commit/65f38bba9a116af3dec9fd88b7be2adcff6ff938))
* update documentation and integration references from Code Maat to ruby-maat ([263d741](https://github.com/viamin/aidp/commit/263d741d085137bb1d1bb7b23676e40171eca799))
* update gemspec summary and description for clarity and accuracy ([2554b64](https://github.com/viamin/aidp/commit/2554b64693f895ba85399b377d0d3034079cdf28))

### Maintenance

* add concurrency settings to workflows ([2ad9637](https://github.com/viamin/aidp/commit/2ad9637e2f8463f8363101737ce204de68ef403b))
* add GITHUB_TOKEN to publish workflow for improved permissions ([1c8649a](https://github.com/viamin/aidp/commit/1c8649ad5051eaeed040ddf3d803175cfd366041))
* add RELEASE_TOKEN to publish workflow for enhanced security during releases ([a1b1d8b](https://github.com/viamin/aidp/commit/a1b1d8bfd477a7870b7e7631e34d1395102916b6))
* add schema reference to release-please configuration for improved validation ([18b9a4d](https://github.com/viamin/aidp/commit/18b9a4d4934d139f61a8ab107ff48a403bf80dcd))
* bump version number ([0af9458](https://github.com/viamin/aidp/commit/0af94581036bd32384bcffcb448fce65c9cad610))
* **deps:** bump pg from 1.6.1 to 1.6.2 ([ee68aff](https://github.com/viamin/aidp/commit/ee68aff255aeb3395e4aa51af8ae8577421d7413))
* **deps:** bump pg from 1.6.1 to 1.6.2 ([c500468](https://github.com/viamin/aidp/commit/c500468183f48b5aeccd9b98fee64e285cb832ee))
* **deps:** bump sequel from 5.95.1 to 5.96.0 ([013c8a0](https://github.com/viamin/aidp/commit/013c8a043de4d12e38cecea3294bdb2b28e5ca88))
* enable cancellation of in-progress jobs in CI and publish workflows ([f5eb408](https://github.com/viamin/aidp/commit/f5eb408c947cefa071e3283984369a8f4418697f))
* enhance release-please configuration with sequential calls and improved pull request header ([7d6fd51](https://github.com/viamin/aidp/commit/7d6fd5121e543653c4cb28c7932e1c259c121ff0))
* enhance user interaction and documentation in aidp ([402f5a4](https://github.com/viamin/aidp/commit/402f5a451a8d8ca0fcf88f4e3fb5680ed4550dbd))
* format code for consistency in CLI and spec files ([47d6f36](https://github.com/viamin/aidp/commit/47d6f368588724ed80f1ad246eeea546b36e9b95))
* **main:** release 0.2.0 ([280cfa9](https://github.com/viamin/aidp/commit/280cfa971994f01deaf13c80801a0128d1f1824e))
* **main:** release 0.2.0 ([736ff6d](https://github.com/viamin/aidp/commit/736ff6dbb68f34666f6a32a81b24637238c0c712))
* **main:** release 0.3.0 ([c3a0cd5](https://github.com/viamin/aidp/commit/c3a0cd5e13a31252b4baa6dd56b51a8a58f9ce9e))
* **main:** release 0.4.0 ([c7aff70](https://github.com/viamin/aidp/commit/c7aff70fe345deebfdadb720cb240cc50dab042b))
* **main:** release 0.4.0 ([8d2a501](https://github.com/viamin/aidp/commit/8d2a5015432e0f2a8621f37373c5bc82dbf915b2))
* **main:** release 0.5.4 ([08514e2](https://github.com/viamin/aidp/commit/08514e2e8a58a1c4b9db29ababe7bd8c70bfcd2c))
* **main:** release 0.5.4 ([7973d65](https://github.com/viamin/aidp/commit/7973d65febf672bf0debaf0470cd8e52cf030245))
* mark release 0.5.0 as complete ([44b50ed](https://github.com/viamin/aidp/commit/44b50eda8bcdee175bfaf783f1b1b0f11e4074a8))
* refine publish workflow by optimizing conditions for release steps and updating permissions ([e198d8e](https://github.com/viamin/aidp/commit/e198d8e313ecaff3ec9a6488821185c409afabd1))
* release 0.5.0 ([1954fd3](https://github.com/viamin/aidp/commit/1954fd34d71e852eb409e50e79d156d977ddc8b7))
* release 0.5.0 ([62d7db2](https://github.com/viamin/aidp/commit/62d7db28d385cd5280fb12835878afc5cfb977ab))
* release 0.5.1 ([718ab91](https://github.com/viamin/aidp/commit/718ab915cc248853409c5ebe40191ad792716baa))
* release 0.5.1 ([659cb3d](https://github.com/viamin/aidp/commit/659cb3de062146155f84249e0a966a95c4c3d108))
* release 0.5.2 ([9e0f40c](https://github.com/viamin/aidp/commit/9e0f40c17561cd2bf9160583708bc8e208c7e56a))
* release 0.5.2 ([01e9928](https://github.com/viamin/aidp/commit/01e99288d20845657d9088464f5434ac2a4f616e))
* release 0.5.3 ([bca8448](https://github.com/viamin/aidp/commit/bca8448e0b5454ab9f0dd307ca27801ab5a0a71a))
* release 0.5.3 ([02f16a8](https://github.com/viamin/aidp/commit/02f16a86d26543ce63527c4b80852376fe279843))
* remove Claude Code workflow configuration ([621d7d4](https://github.com/viamin/aidp/commit/621d7d4393398187ee01972ebbb51e13e451fdbc))
* remove example outputs ([5d53ffb](https://github.com/viamin/aidp/commit/5d53ffb2c1d9ad7d66718911fa9f492d76eec052))
* remove pull request title pattern from release-please configuration ([a22a173](https://github.com/viamin/aidp/commit/a22a17384848094e48c1af1fe6f63f0366b6d908))
* simplify publish workflow by removing unused triggers and conditions ([267be3d](https://github.com/viamin/aidp/commit/267be3d6a0afc5145286f13b6c693d674880fbd6))
* simplify publish workflow by removing unused triggers and conditions ([ea8b7c7](https://github.com/viamin/aidp/commit/ea8b7c77610cc6bb55063bcbd93b20814f993709))
* simplify release-please configuration ([f6c5dee](https://github.com/viamin/aidp/commit/f6c5dee41f92547f725c5e4bcd7307dab5d4220b))
* split gem publishing into its own workflow ([408bce6](https://github.com/viamin/aidp/commit/408bce64957dced002e6fe7e4a07990b5e43f2a1))
* update .gitignore to include additional output and configuration files ([a629bd8](https://github.com/viamin/aidp/commit/a629bd80e6e1516a81d979e36aaecb00c4b53fc5))
* update aidp version to 0.4.0 in Gemfile.lock ([e32a4ab](https://github.com/viamin/aidp/commit/e32a4ab28495d0493ac11b96c3aaa57e67f69c74))
* update changelog formatting and release configuration ([5057c89](https://github.com/viamin/aidp/commit/5057c8984a145c1bc7aae649f57e21a48e852d28))
* update changelog formatting and release configuration ([4d0e1f6](https://github.com/viamin/aidp/commit/4d0e1f62fa042cc48b9e454022116b87e194a16f))
* update CI and publish workflows ([fedd33d](https://github.com/viamin/aidp/commit/fedd33d3347af59cc2f1d5259c88245b030ee6f3))
* update CI and publish workflows ([1a8f91b](https://github.com/viamin/aidp/commit/1a8f91b24e246c953eda3e0d1e28ac4033c126f5))
* update configuration and enhance CLI functionality ([bb2d26e](https://github.com/viamin/aidp/commit/bb2d26ea78eef80cfa7c57606bdf8c0685d8e027))
* update dependabot commit messages and release configuration ([e2cf7b7](https://github.com/viamin/aidp/commit/e2cf7b7b1c7ab95878bfd718d1878c40bf62d3c7))
* update Gemfile.lock to version 0.3.0 and remove redundant update step ([93aa10a](https://github.com/viamin/aidp/commit/93aa10a85a5cb16c233e127df8974eb3392e1a41))
* update publish workflow by removing unnecessary permissions and optimizing release conditions ([bb77263](https://github.com/viamin/aidp/commit/bb772631feac9bdfffb429120dc78052bf61ceb9))
* update push_gem workflow to streamline gem release process and enhance permissions ([bd0550a](https://github.com/viamin/aidp/commit/bd0550aaad2d54ef2a5b0293d83056de5ae44025))
* update push_gem workflow to trigger on release publication instead of tag push ([40113d1](https://github.com/viamin/aidp/commit/40113d1b3b07a14ef3453b0c0085168dc2bff733))
* update release configuration and enhance documentation ([c1b55bf](https://github.com/viamin/aidp/commit/c1b55bf83ca59d9848a877c9fef1be9aec368e28))
* update release-please configuration to enable squashing and version tagging ([5c1fc49](https://github.com/viamin/aidp/commit/5c1fc49fb2977720e30af257d35d27e887a40859))
* update release-please configuration to include component in tag and enable merging ([98a8fd9](https://github.com/viamin/aidp/commit/98a8fd92b20426f1a729fc37fbf208d58df58da8))
* update version to 0.4.0 and clean up release configuration ([6403199](https://github.com/viamin/aidp/commit/64031992e7e3274b6bf1d4b2b508a9dac46d988d))
* WIP checkin - working on handling agent timeouts and background jobs ([19f0b6f](https://github.com/viamin/aidp/commit/19f0b6f7332799380f82319cfcaf2c7aba21b501))

## [0.5.4](https://github.com/viamin/aidp/compare/v0.5.3...v0.5.4) (2025-09-03)

### Bug Fixes

* code scanning alert no. 6: Workflow does not contain permissions ([9120c66](https://github.com/viamin/aidp/commit/9120c66d230ae5252aeed7f66a02474b83ce303c))

## [0.5.3](https://github.com/viamin/aidp/compare/v0.5.2...v0.5.3) (2025-09-03)

### Maintenance

* simplify publish workflow by removing unused triggers and conditions ([267be3d](https://github.com/viamin/aidp/commit/267be3d6a0afc5145286f13b6c693d674880fbd6))
* simplify publish workflow by removing unused triggers and conditions ([ea8b7c7](https://github.com/viamin/aidp/commit/ea8b7c77610cc6bb55063bcbd93b20814f993709))

## [0.5.2](https://github.com/viamin/aidp/compare/v0.5.1...v0.5.2) (2025-09-03)

### Maintenance

* enable cancellation of in-progress jobs in CI and publish workflows ([f5eb408](https://github.com/viamin/aidp/commit/f5eb408c947cefa071e3283984369a8f4418697f))
* update CI and publish workflows ([fedd33d](https://github.com/viamin/aidp/commit/fedd33d3347af59cc2f1d5259c88245b030ee6f3))
* update CI and publish workflows ([1a8f91b](https://github.com/viamin/aidp/commit/1a8f91b24e246c953eda3e0d1e28ac4033c126f5))

## [0.5.1](https://github.com/viamin/aidp/compare/v0.5.0...v0.5.1) (2025-09-03)

### Maintenance

* **deps:** bump sequel from 5.95.1 to 5.96.0 ([013c8a0](https://github.com/viamin/aidp/commit/013c8a043de4d12e38cecea3294bdb2b28e5ca88))
* mark release 0.5.0 as complete ([44b50ed](https://github.com/viamin/aidp/commit/44b50eda8bcdee175bfaf783f1b1b0f11e4074a8))
* release 0.5.0 ([1954fd3](https://github.com/viamin/aidp/commit/1954fd34d71e852eb409e50e79d156d977ddc8b7))
* update changelog formatting and release configuration ([5057c89](https://github.com/viamin/aidp/commit/5057c8984a145c1bc7aae649f57e21a48e852d28))
* update changelog formatting and release configuration ([4d0e1f6](https://github.com/viamin/aidp/commit/4d0e1f62fa042cc48b9e454022116b87e194a16f))
* update dependabot commit messages and release configuration ([e2cf7b7](https://github.com/viamin/aidp/commit/e2cf7b7b1c7ab95878bfd718d1878c40bf62d3c7))

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
