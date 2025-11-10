# Decide the Next Work Loop Unit

You are operating inside the Aidp hybrid work loop. Review the recent deterministic outputs, consider the latest agent summary, and choose the next unit by emitting `NEXT_UNIT: <unit_name>` on its own line.

## Deterministic Outputs

{{DETERMINISTIC_OUTPUTS}}

## Previous Agent Summary

{{PREVIOUS_AGENT_SUMMARY}}

## Guidance

- Pick whichever unit will unblock progress the fastest. Options include deterministic unit names (`run_full_tests`, `run_lint`, etc.), `agentic` to resume coding, or `wait_for_github` if the system must await an external event.
- Cite concrete evidence from the outputs above when selecting a unit so future readers understand the decision.
- Keep the rationale tight—two or three sentences max.

## Rationale

Provide the reasoning for your `NEXT_UNIT` decision here.
