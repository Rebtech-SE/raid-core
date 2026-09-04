# Judge Evaluation Prompt Template

This template is used by the orchestrator to dispatch batched LLM-as-judge evaluation calls. Each judge sub-agent evaluates a batch of sampled output items and returns structured JSON scores.

The orchestrator:
1. Reads the experiment's output
2. Selects samples per the stratification config (using fixed seed)
3. Groups samples into batches of `judge.batch_size`
4. Dispatches `ceil(sample_size / batch_size)` parallel sub-agents using this template
5. Aggregates returned JSON scores

---

## Item Evaluation Template

```
You are a quality judge evaluating output items for an optimization experiment.

Your job is to score each item using the rubric below and return structured JSON. Be consistent and calibrated -- the same quality level should get the same score across items.

<rubric>
{rubric}
</rubric>

<items>
{items_json}
</items>

<output-contract>
Return ONLY a valid JSON array. No prose, no markdown, no explanation outside the JSON.

Each element must have:
- "item_id": the identifier of the item being evaluated (string or number, matching the input)
- All fields requested by the rubric (scores, counts, etc.)
- "ambiguous": true if you cannot confidently score this item (e.g., insufficient context, borderline case). When ambiguous, still provide your best-guess score but flag it.

Example output format (adapt field names to match the rubric):
[
  {"item_id": "rule-42", "score": 4, "false_positive_risk": "low", "business_rule_match": true, "ambiguous": false},
  {"item_id": "rule-17", "score": 2, "false_positive_risk": "high", "business_rule_match": false, "ambiguous": false},
  {"item_id": "rule-99", "score": 3, "false_positive_risk": "medium", "business_rule_match": true, "ambiguous": true}
]

Rules:
- Evaluate each item independently
- Score based on the rubric, not on how other items in this batch scored
- If an item is empty or has only 1 element when it should have more, score it based on what is present
- For very large items (many elements), focus on a representative subset and note if quality varies across the item
- Every item in the batch MUST appear in your output
</output-contract>
```

## Coverage / False-Negative Evaluation Template

Use this template when the optimization goal involves coverage -- it judges items the
experiment LEFT UNCOVERED (a table that got no data-quality rule, a row the anomaly
detector did not flag, a column that got no description) to catch false negatives.

```
You are a quality judge evaluating UNCOVERED items -- items the system did NOT act on (no rule generated, not flagged, not described).

Your job is to determine whether each uncovered item should have been covered, or whether leaving it uncovered is correct. Return structured JSON.

<rubric>
{singleton_rubric}
</rubric>

<uncovered-items>
{singletons_json}
</uncovered-items>

<coverage-context>
A summary of what the system DID cover, for reference (names/themes only, not full contents):
{cluster_summaries}
</coverage-context>

<output-contract>
Return ONLY a valid JSON array. No prose, no markdown, no explanation outside the JSON.

Each element must have:
- "item_id": the identifier of the uncovered item
- All fields requested by the rubric (should_cover, reason, confidence, etc.)

Example output format (adapt field names to match the rubric):
[
  {"item_id": "table.fct_payments", "should_cover": true, "reason": "financial mart with no null/uniqueness check", "confidence": 4},
  {"item_id": "table.stg_debug_scratch", "should_cover": false, "reason": "transient staging table", "confidence": 5}
]

Rules:
- An item that genuinely does not need coverage should get should_cover: false
- An item that clearly should have been covered should get should_cover: true with the reason
- High confidence (4-5) means you are very sure. Low confidence (1-2) means borderline.
- Every uncovered item in the batch MUST appear in your output
</output-contract>
```

## Variable Reference

| Variable | Source | Description |
|----------|--------|-------------|
| `{rubric}` | Spec `metric.judge.rubric` | User-defined scoring rubric |
| `{items_json}` | Sampled output items | JSON array of items to evaluate (one batch worth) |
| `{singleton_rubric}` | Spec `metric.judge.singleton_rubric` | User-defined rubric for singleton evaluation |
| `{singletons_json}` | Sampled singleton items | JSON array of singleton items to evaluate |
| `{cluster_summaries}` | Experiment output | Summary of existing clusters (titles/themes) for singleton reference |

## Notes

- Designed for Haiku by default -- prompts are concise and well-structured for smaller models
- The rubric is part of the immutable measurement harness -- the experiment agent cannot modify it
- The `ambiguous` flag on items helps the orchestrator identify noisy evaluations without forcing bad scores
- For singleton evaluation, the orchestrator provides cluster summaries (not full contents) to keep judge context lean
- Each sub-agent evaluates one batch independently -- sub-agents do not see each other's results
