# Changelog

## [0.17.1](https://github.com/viamin/aidp/compare/aidp/v0.17.0...aidp/v0.17.1) (2025-10-24)


### Bug Fixes

* **cli:** use ProviderInfo#info instead of get_info and update specs ([e5722a0](https://github.com/viamin/aidp/commit/e5722a08d6abc4409da7bf2135bf9e87d3b723e3))
* **cli:** use ProviderInfo#info instead of get_info and update specs ([#164](https://github.com/viamin/aidp/issues/164)) ([4538538](https://github.com/viamin/aidp/commit/45385384f90bdf3a0f05edc3c435f83a7a59a83e))
* **logger, tests:** use Kernel.warn on logger creation failure; mock Aidp.logger in WorkLoopRunner spec to avoid filesystem init ([5df887a](https://github.com/viamin/aidp/commit/5df887aedd055ec45956ca6bc9fbbe680758aa28))
* **logger, tests:** use Kernel.warn on logger creation failure; mock Aidp.logger in WorkLoopRunner spec to avoid filesystem init ([#169](https://github.com/viamin/aidp/issues/169)) ([8f99ba4](https://github.com/viamin/aidp/commit/8f99ba4fdc55240dde909903eddfe3b34a7a356c))


### Improvements

* **cli:** centralize TTY::Prompt creation for test DI; update callers & specs ([e175197](https://github.com/viamin/aidp/commit/e175197bdd9098c4da74566cdf7e24f330a4ed3a))
* **harness, jobs, spec, docs:** add DI for progress tracker & background display; eliminate any_instance_of usage ([44bac3d](https://github.com/viamin/aidp/commit/44bac3d535aa75c9faf8ff41c35395eeae79b591))
* **harness, skills, message_display:** inject TTY::Prompt for test DI; centralize prompt usage ([8199559](https://github.com/viamin/aidp/commit/8199559c68161b8ad6ccddc3344925db3f0a81aa))
* **harness, spec:** add sleep DI and validator injection; update tests ([c1d10d1](https://github.com/viamin/aidp/commit/c1d10d1919dfe6022fd6a3d33472fe23a74e41af))
* **harness, spec:** make provider CLI availability deterministic in ProviderManager spec ([9328e97](https://github.com/viamin/aidp/commit/9328e97efcf099843c684a4b8739697be570b0ce))
* **harness/state:** require explicit skip_persistence; add in-memory test state; use Concurrency backoff for locking; update specs ([3c1176b](https://github.com/viamin/aidp/commit/3c1176b737f06ea8f8c059f11b252692f39074ce))
* **providers:** rename send to send_message across providers, harness, and specs ([edead6a](https://github.com/viamin/aidp/commit/edead6a851b12e8a43233b9d98617f80a724646d)), closes [#160](https://github.com/viamin/aidp/issues/160)
* **providers:** rename send to send_message across providers, harness, and specs ([#166](https://github.com/viamin/aidp/issues/166)) ([1fcb82f](https://github.com/viamin/aidp/commit/1fcb82f005d6d878705ea4110aa333b3364e00d9))
* **testing:** remove test-aware gating; add explicit DI flags for persistence & async control ([567ee15](https://github.com/viamin/aidp/commit/567ee151aab6430f6cbe5060e9de771245abf5ed))
* **watch, harness, spec, docs:** add BinaryChecker & Sleeper DI; remove any_instance_of gh/sleep stubs ([aa06b1b](https://github.com/viamin/aidp/commit/aa06b1b9de5a27b1daa306a2348f4c56a31d480f))
* **workflows/guided_agent:** remove legacy analyze/recommendation flow and tests ([3c412d5](https://github.com/viamin/aidp/commit/3c412d530613a8f6262c0cd2fa0c421f4aa8596f))
* **workstream_executor, spec, docs, lint:** add runner_factory DI; update tests & docs ([7d4de24](https://github.com/viamin/aidp/commit/7d4de2441aaeca921f7a0d1e40db712c8f62bff7))


### Documentation

* **mocking_audit_report:** expand P2 guidance for removing private-method tests and preserving coverage ([8574617](https://github.com/viamin/aidp/commit/8574617e39d050615b3f34204ba054160c01fb65))

## [0.17.0](https://github.com/viamin/aidp/compare/aidp/v0.16.0...aidp/v0.17.0) (2025-10-22)


### Features

* **skills:** add Skill Authoring Wizard, routing, templates, CLI/REPL commands, docs, and tests ([7913c08](https://github.com/viamin/aidp/commit/7913c087113ac4ce5aec0fbc44b26c139a3c57fa)), closes [#149](https://github.com/viamin/aidp/issues/149)
* **skills:** add Skill Authoring Wizard, routing, templates, CLI/REPL commands, docs, and tests ([#161](https://github.com/viamin/aidp/issues/161)) ([50f30f9](https://github.com/viamin/aidp/commit/50f30f9774d7ee1c361fa3fac006499e629e2ac3))

## [0.16.0](https://github.com/viamin/aidp/compare/aidp/v0.15.2...aidp/v0.16.0) (2025-10-20)


### Features

* **skills:** add skills subsystem and integrate with CLI, runners & REPL ([a4838fc](https://github.com/viamin/aidp/commit/a4838fcac0db0260e98e68d6550a82ebb35d59ee)), closes [#148](https://github.com/viamin/aidp/issues/148)
* **skills:** add skills subsystem and integrate with CLI, runners & REPL ([#155](https://github.com/viamin/aidp/issues/155)) ([15c3d38](https://github.com/viamin/aidp/commit/15c3d383ca8a59d24c8b9409d24bacac6dfeb54a))
* **workstreams,cli,repl,harness:** add parallel workstream execution ([c559a37](https://github.com/viamin/aidp/commit/c559a370264b84fd678dcfc2005b020b7c9c7805))
* **workstreams,cli,repl,harness:** add workstream controls, state mirroring and REPL/TUI integration ([d4ea68d](https://github.com/viamin/aidp/commit/d4ea68dc6a81ba49b7e9ce7ba094d0e433c776c8))
* **workstreams:** add parallel workstreams using git worktrees with CLI, REPL, state & watch integration ([4b9f0d9](https://github.com/viamin/aidp/commit/4b9f0d9119e51008e03624c806d02d64f35952e7)), closes [#119](https://github.com/viamin/aidp/issues/119)
* **workstreams:** add parallel workstreams using git worktrees with CLI, REPL, state & watch integration ([#152](https://github.com/viamin/aidp/issues/152)) ([ebc28a6](https://github.com/viamin/aidp/commit/ebc28a607120b32a40d058548157287bfe968946))
* **workstreams:** add per-workstream state and integrate across CLI, REPL, worktree & harness ([f15f2fc](https://github.com/viamin/aidp/commit/f15f2fcf0bf1cfbaaba06bed9c44b6417392100f))


### Improvements

* add Concurrency primitives and migrate ad-hoc sleeps ([8f65549](https://github.com/viamin/aidp/commit/8f65549b75496a076336674e6cad702fa1b9ce60))
* add Concurrency primitives and migrate ad-hoc sleeps ([#156](https://github.com/viamin/aidp/issues/156)) ([f3a4a97](https://github.com/viamin/aidp/commit/f3a4a972840c7ea17d7d996e8692ee5c1be936cb))

## [0.15.2](https://github.com/viamin/aidp/compare/aidp/v0.15.1...aidp/v0.15.2) (2025-10-16)


### Bug Fixes

* map github_copilot provider to 'copilot' CLI instead of 'gh' ([e261812](https://github.com/viamin/aidp/commit/e261812f196d295db8eee8fe774044c545fc0a2b))


### Improvements

* simplify ProjectAnalyzer detection, tidy Runner, normalize docs spacing ([0621a21](https://github.com/viamin/aidp/commit/0621a21f9947559ccb48f51762dad55ded2b225a))


### Documentation

* add logging hints to STYLE_GUIDE and LLM_STYLE_GUIDE ([64f3823](https://github.com/viamin/aidp/commit/64f3823163fc179bbb30a69d5557436bc2467392))
* remove auto-generated init files ([c3fa74b](https://github.com/viamin/aidp/commit/c3fa74b8876f3adf1faae7bc941c57cd7e102adc))
* roll back changes to LLM_STYLE_GUIDE ([49ad53c](https://github.com/viamin/aidp/commit/49ad53cf5f0e3d93a3cc2183c85d519f20b727f7))

## [0.15.1](https://github.com/viamin/aidp/compare/aidp/v0.15.0...aidp/v0.15.1) (2025-10-15)


### Bug Fixes

* pre-select fallback providers in setup wizard using display names ([730f688](https://github.com/viamin/aidp/commit/730f688ea2211c46ca69bb358430a4de7cbdf136))
* pre-select fallback providers in setup wizard using display names ([#138](https://github.com/viamin/aidp/issues/138)) ([cfb5ac3](https://github.com/viamin/aidp/commit/cfb5ac366d4dca52d90fcd0111be25b67967a31e))

## [0.15.0](https://github.com/viamin/aidp/compare/aidp/v0.14.2...aidp/v0.15.0) (2025-10-15)


### Features

* add deterministic work loop units and hybrid scheduling ([a5554ee](https://github.com/viamin/aidp/commit/a5554ee9c887fead3054f56b8fd50452d79445d6))
* add deterministic work loop units and hybrid scheduling ([#136](https://github.com/viamin/aidp/issues/136)) ([b4bb948](https://github.com/viamin/aidp/commit/b4bb94818d63c245a65424c15c539d2e05ff42a8))


### Bug Fixes

* ensure coverage badge updates properly ([d59c996](https://github.com/viamin/aidp/commit/d59c9960489bf91268a954720de9302522569ae2))
* ensure coverage badge updates properly ([#137](https://github.com/viamin/aidp/issues/137)) ([2ac9c65](https://github.com/viamin/aidp/commit/2ac9c65c427d4c3aefe9dba3132ba116eb05d3ee))


### Improvements

* **cli/docs:** make Copilot the default interactive mode and update docs ([717542f](https://github.com/viamin/aidp/commit/717542fe8b6e1485e9edb6e9c2d1418f18d3e9b0))
* **cli/docs:** make Copilot the default interactive mode and update docs ([#133](https://github.com/viamin/aidp/issues/133)) ([de460b4](https://github.com/viamin/aidp/commit/de460b4a4b4c11d0c6b4ef1ab639287dde325a9e))
* fix codeql violation ([8d2d8dd](https://github.com/viamin/aidp/commit/8d2d8dd580dda50dff518532e9db7522ab35f3c3))

## [0.14.2](https://github.com/viamin/aidp/compare/aidp/v0.14.1...aidp/v0.14.2) (2025-10-14)


### Bug Fixes

* fix provider fallback, setup wizard billing, and guided-agent resiliency ([b4c9e77](https://github.com/viamin/aidp/commit/b4c9e77ae14964a91d6e65bf91f2484bca2d0cb3))
* fix provider fallback, setup wizard billing, and guided-agent resiliency ([#130](https://github.com/viamin/aidp/issues/130)) ([6baedaf](https://github.com/viamin/aidp/commit/6baedaf67f06916d4559ce85967bfb86ebb20453))


### Improvements

* consolidate logging to Aidp::Logger, remove DebugLogger, add RescueLogging and instrument components; update docs & specs ([502b5f0](https://github.com/viamin/aidp/commit/502b5f02eefee3fb7c0acddce2d782cdcf87fe32))
* consolidate logging to Aidp::Logger, remove DebugLogger, add RescueLogging and instrument components; update docs & specs ([#132](https://github.com/viamin/aidp/issues/132)) ([00b9c29](https://github.com/viamin/aidp/commit/00b9c295bbe3b144fdb83ee6d607056a61f33aa4))

## [0.14.1](https://github.com/viamin/aidp/compare/aidp/v0.14.0...aidp/v0.14.1) (2025-10-13)


### Bug Fixes

* save selected primary provider and deduplicate fallback providers ([520059a](https://github.com/viamin/aidp/commit/520059ac980ca64dfa9989a401edcd52fd563230))
* save selected primary provider and deduplicate fallback providers ([#125](https://github.com/viamin/aidp/issues/125)) ([ff542bb](https://github.com/viamin/aidp/commit/ff542bbf5cfe6da5ffa7623644a37c7cedcf8147))


### Improvements

* use explicit rescue for ratchet JSON parse and remove markdownlint fence-normalizer ([64e60d3](https://github.com/viamin/aidp/commit/64e60d37b351577afdb8515632259af2ed58904d))


### Documentation

* revert troubleshooting headings, fix MD036/MD026, update markdownlint config ([0ffe3cc](https://github.com/viamin/aidp/commit/0ffe3cc909b367e29f83178af2efc453a389d766))

## [0.14.0](https://github.com/viamin/aidp/compare/aidp/v0.13.0...aidp/v0.14.0) (2025-10-13)

### Features

* add daemon support with process management and logging ([60ee5d2](https://github.com/viamin/aidp/commit/60ee5d2046394b5ab02b9971883d772a3540cb14))
* add daemon support with process management and logging ([#120](https://github.com/viamin/aidp/issues/120)) ([79f1dbc](https://github.com/viamin/aidp/commit/79f1dbc187cc24337411a11628bc7cbccd6426e3))
* Add GitHub issue import functionality to AIDP ([6487c17](https://github.com/viamin/aidp/commit/6487c17d2d7f7f48285f6d397a4a3afdce4f0737))
* Add GitHub issue import functionality to AIDP ([#109](https://github.com/viamin/aidp/issues/109)) ([716d07d](https://github.com/viamin/aidp/commit/716d07da2be91c920dbc37bd12860c188175d6e1))
* add interactive REPL for async work loop control ([9eebeb0](https://github.com/viamin/aidp/commit/9eebeb07016c8f3abca0d845767801722fe906e7))
* add interactive REPL for async work loop control ([#118](https://github.com/viamin/aidp/issues/118)) ([2979c30](https://github.com/viamin/aidp/commit/2979c304112adfa81120fe3a9d22a62e7765e72c))
* add interactive setup wizard for AIDP configuration ([5a127f5](https://github.com/viamin/aidp/commit/5a127f53cec8b9e3e29191baac1ca1ca9e1ac97e))
* add interactive setup wizard for AIDP configuration ([#122](https://github.com/viamin/aidp/issues/122)) ([3585202](https://github.com/viamin/aidp/commit/3585202cb89b568f5fcd47bbc420754629a398b6))
* add REPL macros for enhanced control during work loops ([f784fdd](https://github.com/viamin/aidp/commit/f784fdd9eafb02a7e1dc8a3182e9c46933b47dc4))
* add REPL macros for enhanced control during work loops ([#112](https://github.com/viamin/aidp/issues/112)) ([098bc23](https://github.com/viamin/aidp/commit/098bc232d019bec93c9d72c9d9754e1471aefdce))
* add watch mode functionality to aidp ([f10854f](https://github.com/viamin/aidp/commit/f10854f38c30c4a766bbac205678ea77998cfaf6))
* add watch mode functionality to aidp ([#114](https://github.com/viamin/aidp/issues/114)) ([b5f928b](https://github.com/viamin/aidp/commit/b5f928bfea71988449a2f1facefc4eda005b0c8b))
* add work notes and backlog ([e838c75](https://github.com/viamin/aidp/commit/e838c75c78f724e88d4f6777161acae3c55e500e))
* add work notes and backlog ([#115](https://github.com/viamin/aidp/issues/115)) ([1663c41](https://github.com/viamin/aidp/commit/1663c419b442ece44cd1b5e2b3ff8a48c7d869ef))
* enhance workflow selection and add simple task execution template ([4a6c22d](https://github.com/viamin/aidp/commit/4a6c22dffb669a68de91edb6854fbcbd701b9544))
* Implement bootstrap process for GitHub issue imports with tooling detection ([c3ca190](https://github.com/viamin/aidp/commit/c3ca190f3ddb2036a4abc00b229811cca40f77e4))
* Implement bootstrap process for GitHub issue imports with tooling detection ([#110](https://github.com/viamin/aidp/issues/110)) ([1b7f1dd](https://github.com/viamin/aidp/commit/1b7f1dd485612a066d2df3ee33eadf913e52e332))
* implement fix-forward pattern in work loop execution and add state machine tracking ([883bde6](https://github.com/viamin/aidp/commit/883bde6a92d708dff12f84297fb12e2702e53022))
* implement project bootstrapping with aidp init command and documentation generation ([918a78e](https://github.com/viamin/aidp/commit/918a78ea5561b36c34655e95ab055e3f98cd4eec))
* implement project bootstrapping with aidp init command and documentation generation ([#116](https://github.com/viamin/aidp/issues/116)) ([35e44a3](https://github.com/viamin/aidp/commit/35e44a3ea1c2e11053a0eeef12a622608c3b9359))
* Implement safety guards configuration and enforcement in AIDP ([d936291](https://github.com/viamin/aidp/commit/d936291bb27980ab130b23a74bbf6a0f23f6dafb))
* Implement safety guards configuration and enforcement in AIDP ([#111](https://github.com/viamin/aidp/issues/111)) ([acb0c5f](https://github.com/viamin/aidp/commit/acb0c5fb9456ecdef30c553aa10f6db111d56065))
* implement unified logging system and remove deprecated daemon logger ([13d5700](https://github.com/viamin/aidp/commit/13d570017b03a87a295dd5d2fa773b250ddd9a16))
* implement unified logging system and remove deprecated daemon logger ([#121](https://github.com/viamin/aidp/issues/121)) ([9af95c9](https://github.com/viamin/aidp/commit/9af95c96080eb40b20a2d659f8bbc3aacac12c04))

### Bug Fixes

* handle invalid file encodings in project file search ([8434a81](https://github.com/viamin/aidp/commit/8434a819ae955914c0301e7e6b465161a7a07a77))

### Improvements

* enhance pattern matching in matches_pattern? method for improved glob support ([fa768b4](https://github.com/viamin/aidp/commit/fa768b465bb07ec64d92bcbc1387471a417ec3d7))

## [0.13.0](https://github.com/viamin/aidp/compare/aidp/v0.12.1...aidp/v0.13.0) (2025-10-11)

### Features

* add enhanced input handling with Reline key bindings ([71c50d4](https://github.com/viamin/aidp/commit/71c50d449a9ea42d72fbd844db7f037fb5c69465))

### Improvements

* enhance MCP server management across providers ([ad6a6b7](https://github.com/viamin/aidp/commit/ad6a6b72312a092e9dd5741b2ee29314148bb6ce))
* enhance MCP server management across providers ([#91](https://github.com/viamin/aidp/issues/91)) ([244d938](https://github.com/viamin/aidp/commit/244d938cb6fd92873a87c56de9092a5821cfbd63))
* enhance test isolation and environment management in CLI specs ([383dca6](https://github.com/viamin/aidp/commit/383dca65c0d84e350300b76b5f7ea5d81f309cca))
* standardize method names and improve provider interactions ([229d2ba](https://github.com/viamin/aidp/commit/229d2ba106d864c2676371aa523be8251d7435c1))
* standardize method naming and improve configuration management ([67377f2](https://github.com/viamin/aidp/commit/67377f217e8f9618f6e7e598f77f6777352688f3))

## [0.12.1](https://github.com/viamin/aidp/compare/aidp/v0.12.0...aidp/v0.12.1) (2025-10-09)

### Improvements

* centralize configuration path management in ConfigPaths module ([12b5dab](https://github.com/viamin/aidp/commit/12b5dabcc1968ba77ddeb117a64f295ed3f1250f))
* centralize configuration path management in ConfigPaths module ([#89](https://github.com/viamin/aidp/issues/89)) ([fa03694](https://github.com/viamin/aidp/commit/fa03694d2cd40b59b5a90fb5915d30ce8deb4d73))

### Documentation

* update CHANGELOG and documentation for improved clarity and structure ([ba04fb4](https://github.com/viamin/aidp/commit/ba04fb4498bfe1fc62e7cdc3ac774bc885f06184))

## [0.12.0](https://github.com/viamin/aidp/compare/aidp/v0.11.0...aidp/v0.12.0) (2025-10-09)

### Features

* add detailed provider information and refresh capabilities to CLI ([22f9627](https://github.com/viamin/aidp/commit/22f9627c4e7c9e3ce86c4413903374d52aa80802))
* add detailed provider information and refresh capabilities to CLI ([#86](https://github.com/viamin/aidp/issues/86)) ([750c2eb](https://github.com/viamin/aidp/commit/750c2eb5f8a09d3f7d2efecc058d1f59e926a370))
* introduce Guided Workflow feature to assist users in selecting appropriate workflows ([ca21795](https://github.com/viamin/aidp/commit/ca217952a8cdf095a06d8ec2f25cb7dc442e9599))
* introduce Guided Workflow feature to assist users in selecting appropriate workflows ([#88](https://github.com/viamin/aidp/issues/88)) ([0cf1665](https://github.com/viamin/aidp/commit/0cf1665ee6d2d7422c54b776939d9553057848e3))

## [0.11.0](https://github.com/viamin/aidp/compare/aidp/v0.10.0...aidp/v0.11.0) (2025-10-07)

### Features

* add Codex provider with enhanced execution and timeout management ([7d05121](https://github.com/viamin/aidp/commit/7d05121a535a82a0e008bcfd025701e980075b10))
* add Codex provider with enhanced execution and timeout management ([#71](https://github.com/viamin/aidp/issues/71)) ([95f0d8e](https://github.com/viamin/aidp/commit/95f0d8ed2e84c7f8f0c39b14f5325d619ad6e9a0))
* add comprehensive templates for analysis, implementation, and planning processes ([6b78c6a](https://github.com/viamin/aidp/commit/6b78c6a256002aba6ea7c7fd2449e34c7d171c85))
* add work loop iteration, allowing more autonomous, longer term operations ([#78](https://github.com/viamin/aidp/issues/78)) ([4481429](https://github.com/viamin/aidp/commit/44814297a9207476a66e350e18cf6dba8f5cdde7))
* Add workflows and selector for enhanced project management ([de37207](https://github.com/viamin/aidp/commit/de37207fbf2f1dabc39c929447a37a7c4b157f00))
* Add workflows and selector for enhanced project management ([#81](https://github.com/viamin/aidp/issues/81)) ([5f6cfdf](https://github.com/viamin/aidp/commit/5f6cfdfb289f3ab37e03a950fb2502ce277a930d))
* Implement checkpoint management system for work loop execution ([8314a4e](https://github.com/viamin/aidp/commit/8314a4e8602138bd358c333d08d532d3c96cbf43))
* Implement checkpoint management system for work loop execution ([#80](https://github.com/viamin/aidp/issues/80)) ([fe6ea09](https://github.com/viamin/aidp/commit/fe6ea09767413e3562afa8ab41999454efb355e3))

### Improvements

* configuration management to use unified .aidp directory structure ([650358a](https://github.com/viamin/aidp/commit/650358a3eedf46afe0d7a63bf9ac1d1ceb7d7e5c))
* configuration management to use unified .aidp directory structure ([#85](https://github.com/viamin/aidp/issues/85)) ([01170e3](https://github.com/viamin/aidp/commit/01170e3502fe82c94cc0c480ae73bb19ec7ba4f5))
* consolidate stderr printing logic into a helper method ([ec9fbce](https://github.com/viamin/aidp/commit/ec9fbceb259e2343dd4bb48e29519e15a68e29dc))
* enhance provider CLI availability checks for testing environment ([63253ea](https://github.com/viamin/aidp/commit/63253eaba13bd295ff44131c41d1fb673fa75fd1))
* enhance provider functionality with timeout management and activity display ([36b857e](https://github.com/viamin/aidp/commit/36b857e63fcdacf2aa3af1338d123f3f16c77701))
* enhance provider functionality with timeout management and activity display ([#74](https://github.com/viamin/aidp/issues/74)) ([273219f](https://github.com/viamin/aidp/commit/273219f541d61ec1a39240b37fc233813ad3420e))
* enhance test setup with temporary directories and mock provider CLI availability ([b4daffd](https://github.com/viamin/aidp/commit/b4daffd449654cdcfd52b442c3d34f876b9cb8e4))
* error handling and add retry mechanism ([b56f20c](https://github.com/viamin/aidp/commit/b56f20c835db906fe201a6c0e9250956f2caac25))
* error handling and add retry mechanism ([#76](https://github.com/viamin/aidp/issues/76)) ([e5418f5](https://github.com/viamin/aidp/commit/e5418f50f9880514d44fe9939adba49ce4a572c5))
* implement cleanup method for activity display and spinner in providers ([60bfcbb](https://github.com/viamin/aidp/commit/60bfcbbf2426c5490b0bd53682b855995dc93b7c))
* implement display_name method for provider classes to enhance user experience ([a97a82f](https://github.com/viamin/aidp/commit/a97a82f98bd375f809a0650aae42c3ab365ddf24))
* implement MessageDisplay mixin for consistent message handling across classes ([e099a50](https://github.com/viamin/aidp/commit/e099a507dfdaba86be8c0e27ee20ec7b755f90e0))
* unify spinner status updates across providers ([c88e1c8](https://github.com/viamin/aidp/commit/c88e1c893ba460a5b03ab24022385035d575e861))

## [0.10.0](https://github.com/viamin/aidp/compare/aidp/v0.9.6...aidp/v0.10.0) (2025-09-27)

### Features

* add GitHub Copilot provider and integration ([00e0c85](https://github.com/viamin/aidp/commit/00e0c85492aa314b3f0ca8030b8d15120f4b228a))
* add GitHub Copilot provider and integration ([#68](https://github.com/viamin/aidp/issues/68)) ([6cdf8b3](https://github.com/viamin/aidp/commit/6cdf8b3b6d3536b1354f05f0daf1915850f3dd2e))

### Bug Fixes

* use correct template naming conventions in analysis steps ([3ab5f2a](https://github.com/viamin/aidp/commit/3ab5f2af54109ea6377f81d4ad2baef487cf1a6f))

### Improvements

* enhance GitHub Copilot provider with prompt integration and standardized message display ([6f2f257](https://github.com/viamin/aidp/commit/6f2f257fbbfa9ad6174e892567b52d70a764fe92))
* enhance user interface with TTY::Prompt integration ([7db024d](https://github.com/viamin/aidp/commit/7db024de7bea18c775fa2929567f42cd448942cb))
* integrate TTY::Prompt for consistent message handling across components ([f3d3a1f](https://github.com/viamin/aidp/commit/f3d3a1f8cf61a43c6d7be0796847f8c6c03b78f4))
* move analysis files into analyze namespace and refactor more puts calls ([5742d09](https://github.com/viamin/aidp/commit/5742d0992e9b4dd9ad79dd14b67957e2c6855c0c))
* standardize output handling across UI components ([e2d686f](https://github.com/viamin/aidp/commit/e2d686f34213ede95d6a46e8beb74de7286f1c4b))

## [0.9.6](https://github.com/viamin/aidp/compare/aidp/v0.9.5...aidp/v0.9.6) (2025-09-25)

### Bug Fixes

* implement missing job management methods in EnhancedTUI ([75defba](https://github.com/viamin/aidp/commit/75defbad7e64473fa3aeeb86584c32a820d9f54c))
* implement missing job management methods in EnhancedTUI ([#65](https://github.com/viamin/aidp/issues/65)) ([1b01242](https://github.com/viamin/aidp/commit/1b0124274e57547ebbc3808f0b7f6d1aa798611d))

## [0.9.5](https://github.com/viamin/aidp/compare/aidp/v0.9.4...aidp/v0.9.5) (2025-09-25)

### Bug Fixes

* update first run wizard for quick configuration setup ([f01ff70](https://github.com/viamin/aidp/commit/f01ff7092879683062693b593c6be7247516137c))

### Improvements

* enhance user interface with TTY::Prompt integration ([8d876c7](https://github.com/viamin/aidp/commit/8d876c74d8b7c11955d82b490712d0f174f16ca6))

## [0.9.4](https://github.com/viamin/aidp/compare/aidp/v0.9.3...aidp/v0.9.4) (2025-09-24)

### Bug Fixes

* standardize provider types from package to subscription and api to usage_based ([f3bad0b](https://github.com/viamin/aidp/commit/f3bad0be94f86a394f8c03e35ca25166b91a7a42))
* standardize provider types from package to subscription and api to usage_based ([#61](https://github.com/viamin/aidp/issues/61)) ([8875e17](https://github.com/viamin/aidp/commit/8875e17c0a44e54c9fe2a5376a9544684161e5cc))

## [0.9.3](https://github.com/viamin/aidp/compare/aidp/v0.9.2...aidp/v0.9.3) (2025-09-24)

### Bug Fixes

* update provider types from package to subscription and api to usage_based ([b4d661c](https://github.com/viamin/aidp/commit/b4d661c3112375bf9c925295735731da8366c28d))
* update provider types from package to subscription and api to usage_based ([#59](https://github.com/viamin/aidp/issues/59)) ([29b9f3c](https://github.com/viamin/aidp/commit/29b9f3cef588c147c94a1b39dff0bb6e9001f6a6))

## [0.9.2](https://github.com/viamin/aidp/compare/aidp/v0.9.1...aidp/v0.9.2) (2025-09-23)

### Bug Fixes

* improve number format validation in user interface ([286e9e3](https://github.com/viamin/aidp/commit/286e9e3bbbebc989b9d34f70c871d1ceec821caf))
* improve number format validation in user interface ([#57](https://github.com/viamin/aidp/issues/57)) ([3461bb6](https://github.com/viamin/aidp/commit/3461bb6200d4a8aad6c0def527f549abb1201864))

## [0.9.1](https://github.com/viamin/aidp/compare/aidp/v0.9.0...aidp/v0.9.1) (2025-09-23)

### Bug Fixes

* update aidp configuration structure and provider validation ([0c43a99](https://github.com/viamin/aidp/commit/0c43a99217263e4fc3105884d2d2204e3564d134))
* update aidp configuration structure and provider validation ([#55](https://github.com/viamin/aidp/issues/55)) ([d8be9fb](https://github.com/viamin/aidp/commit/d8be9fb763b21543efc1d25f38e52a5843fb76e4))

## [0.9.0](https://github.com/viamin/aidp/compare/aidp/v0.8.3...aidp/v0.9.0) (2025-09-23)

### Features

* introduce first-time setup wizard for aidp configuration ([2d5125f](https://github.com/viamin/aidp/commit/2d5125f5bd60a0afed5ad894d94f3006754bbb6b))
* introduce first-time setup wizard for aidp configuration ([#53](https://github.com/viamin/aidp/issues/53)) ([6c403cf](https://github.com/viamin/aidp/commit/6c403cfd78df006d202d2d8e18c414761b03a077))

## [0.8.3](https://github.com/viamin/aidp/compare/aidp/v0.8.2...aidp/v0.8.3) (2025-09-22)

### Improvements

* implement SimpleUserInterface for streamlined user feedback collection ([23bbf06](https://github.com/viamin/aidp/commit/23bbf066621da38da6ed030fb7e16473949ad07d))
* implement SimpleUserInterface for streamlined user feedback collection ([#49](https://github.com/viamin/aidp/issues/49)) ([d2ff754](https://github.com/viamin/aidp/commit/d2ff754e1829623b31d925ea6e1edb0f50a9dbba))

## [0.8.2](https://github.com/viamin/aidp/compare/aidp/v0.8.1...aidp/v0.8.2) (2025-09-20)

### Bug Fixes

* better handling of TTY::Prompt for input ([ea39c88](https://github.com/viamin/aidp/commit/ea39c88a7e8e9dc1dc7b57900e524339e3915418))

## [0.8.1](https://github.com/viamin/aidp/compare/aidp/v0.8.0...aidp/v0.8.1) (2025-09-20)

### Bug Fixes

* add Pathname requirement to tree_sitter_grammar_loader.rb ([30ab408](https://github.com/viamin/aidp/commit/30ab4085a36ef5145ac6704ac795ddd4bb685e0d))
* add Pathname requirement to tree_sitter_grammar_loader.rb ([#46](https://github.com/viamin/aidp/issues/46)) ([95b8564](https://github.com/viamin/aidp/commit/95b8564c8d6c53b81b6257d9850f86d401e88d6e))

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
