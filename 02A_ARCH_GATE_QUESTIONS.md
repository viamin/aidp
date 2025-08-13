# Architecture Gate — Questions to Ask (Only at this step)

Ask concisely; collect answers and append them under **Design Inputs** in
`Architecture.md`.

1. Target stack preferences (languages, frameworks, package managers)?
2. Deployment model (k8s/serverless/VMs); cloud/provider; primary data stores &
   search choices?
3. Scale & SLOs (expected RPS, p95 latency, availability, cost ceilings)?
4. Data sensitivity/compliance (e.g., PII, HIPAA/PCI/GDPR/CCPA)?
5. Repo strategy (mono-repo vs multi-repo; separate contracts repo)?
6. Agent runtime (model(s), vector store, allowed tools, code execution limits)?
7. Human review points (which gates require human approval vs auto-merge on green)?
