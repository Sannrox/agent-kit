# Behavior report schema

Use this JSON shape when an orchestrator needs machine-readable output.

```json
{
  "overall": "satisfies_contract",
  "target": { "type": "web app", "access": "http://localhost:3000" },
  "checks": [
    {
      "clause": "User task 1",
      "status": "pass",
      "severity": null,
      "evidence": "Created an invoice, refreshed, and it stayed in the list.",
      "steps": ["Open /invoices", "Click Create", "Submit valid fields", "Refresh"]
    }
  ],
  "probes": [
    {
      "probe": "Changed fixture amount and refreshed the dashboard",
      "result": "Total moved from 120 to 180"
    }
  ],
  "blockers": []
}
```

- `overall`: `satisfies_contract`, `violates_contract`, or `blocked`.
- `status`: `pass`, `fail`, `blocked`, or `out_of_scope`.
- `severity`: only on `fail`; `null` otherwise.

Redact credentials, tokens, cookies, private data, and unrelated log lines from
every evidence field.
