# Waterfall Planning Initialization

You are initializing a waterfall-style project planning workflow. Your task is to determine whether the user has existing documentation to ingest, or if we need to generate documentation from scratch.

## Your Tasks

1. **Ask the user**: Do they have existing documentation (PRD, design docs, ADRs, task lists)?

2. **If YES (Ingestion Path)**:
   - Ask for the path(s) to their documentation files
   - Ask what gaps exist in their documentation that need to be filled
   - Create a file `.aidp/docs/.waterfall_mode` with content: `mode: ingestion`
   - List the files to be ingested

3. **If NO (Generation Path)**:
   - Inform them we'll guide them through requirements elicitation
   - Create a file `.aidp/docs/.waterfall_mode` with content: `mode: generation`
   - Prepare to gather requirements via Q&A

## Output Format

Create `.aidp/docs/.waterfall_mode` with:

```yaml
mode: ingestion  # or 'generation'
docs_path: /path/to/docs  # if ingestion
gaps: []  # list of gaps to fill
timestamp: <ISO8601 timestamp>
```

## Important Notes

- Be conversational and helpful
- Explain what waterfall planning provides (WBS, Gantt, personas)
- If they're unsure, explain both paths
- Create the `.aidp/docs/` directory if it doesn't exist

## Example Dialogue

**For Ingestion:**
```
User: I have a PRD and some design notes
Assistant: Great! Please provide the path to your PRD and design documentation.
          I'll parse them and identify any gaps we need to fill via Q&A.

          What gaps exist? For example:
          - Missing technical architecture details?
          - No task breakdown yet?
          - Missing decision records?
```

**For Generation:**
```
User: I'm starting from scratch
Assistant: Perfect! I'll guide you through creating a comprehensive project plan.
          We'll start with requirements gathering, then move through:
          - Product Requirements Document (PRD)
          - Technical Design
          - Work Breakdown Structure (WBS)
          - Gantt Chart with timeline
          - Task assignments to personas

          Let's begin with some questions about your project...
```

---

**Remember**: This is a GATE step - wait for user input before proceeding!
