# Conventions Cheat Sheet

- **Architecture style:** Hexagonal / Ports & Adapters, CQRS where useful, domain
  events for decoupling.
- **Design:** SOLID, Favor composition over inheritance, GoF patterns (Strategy,
  Factory, Adapter, Facade, Observer, Repository, Specification).
- **Domain modeling:** DDD with clear bounded contexts and anti-corruption layers
  between contexts.
- **Versioning:** APIs, events, and schemas versioned; explicit deprecation
  policies.
- **Resilience:** Idempotency on side-effecting operations; retry/backoff; circuit
  breakers as needed.
- **Data:** Backwards-compatible migrations (expand → migrate → contract), data
  retention policies, privacy by design.
- **Contracts:** Consumer-driven contract tests before service coding begins.
- **Quality:** Test pyramid, property-based tests for domain rules, mutation
  testing targets for critical modules.
- **Ops:** SLOs with alert rules; runbooks; cost budgets.
- **Docs:** ADRs for key decisions; living docs; code ownership.
