<div align="center">
   <img src="/img/logo.svg?raw=true" width=600 style="background-color:white;">
</div>

# Data Engineer — Take-home Assignment: Customer data pipeline

## Context

We operate a batch data pipeline that ingests jsonl files from upstream sources, writes them to output tables, and then has a downstream Data Sync Job upsert the data into our tripla DB.

The overall data flow:

```
[Upstream jsonl files]
        │
        ▼
┌─────────────────────────────────────────┐
│           Scope of this assignment      │
│                                         │
│  [1] ingest.py: ingest jsonl            │
│            │                            │
│            ▼                            │
│  [2] Output Tables (DuckDB)             │
│       - customer_profile                │
│       - membership                      │
│            │                            │
│            ▼                            │
│  [3] prepare_sync.py: extract & validate│
│            │                            │
│            ▼                            │
│  [4] Sync-ready jsonl output            │
│                                         │
└─────────────────────────────────────────┘
        │
        ▼
[Data Sync Job]    (out of scope)
        │
        ▼
[tripla DB]        (out of scope)
```

You are responsible for the four steps inside the box: use `ingest.py` to ingest the upstream jsonl into the DuckDB output tables you design (steps 1–2), then use `prepare_sync.py` to extract and validate the data and produce the final sync-ready jsonl (steps 3–4). The downstream Sync Job and tripla DB are out of scope.

### Upstream Data Overview

- **customer_profile**: contains a `guest_type` field with possible values `member` or `non_member`.
    - A `member` must be linked to membership data via `source_type` + `source_id`.
    - A `non_member` does not require membership data.
- **membership**: contains fields such as `program_id`, `rank_name`, etc. A single member can hold multiple membership programs simultaneously.

### Unique Identifier Definitions

- **customer_profile**: `(source_type, source_id)`
- **membership**: `(source_type, source_id, program_id, membership_id)`

### Sample Data & Schema

- customer_profile jsonl sample: `src/data/input/customer_profile.jsonl`
- membership jsonl sample: `src/data/input/membership.jsonl`
- Detailed field schema: `DE-Assignment-SPEC-v1.0.md`
- Reference structure for the sync-ready jsonl output: `reference_output_structure.json`

---

## Constraints

Please account for the following real-world conditions in your design:

1. **Independent arrival**: customer_profile and membership jsonl files are delivered independently by upstream. A member's customer_profile may have arrived while their corresponding membership data has not yet (or vice versa).
2. **Duplicate rows**: every incoming batch will inevitably contain rows that are **completely unchanged** — upstream does not classify rows as new / update / unchanged and simply re-sends everything. Your design must handle this noise.
3. **Field-level rules**: refer to `DE-Assignment-SPEC-v1.0.md` for per-field constraints and validation requirements.

---

## Assignment

Build an end-to-end mini pipeline that:

1. Ingests the provided customer_profile and membership jsonl files into DuckDB tables you design.
2. Maintains the output tables such that the requirements below are met.
3. Produces a **sync-ready jsonl output** that contains only **valid, sync-eligible** customers, each enriched with their associated membership data (denormalized; see reference output structure).

### Output Table Requirements

Your `customer_profile` and `membership` output tables must satisfy:

1. **Historical traceability**: every row ingested from jsonl must be preserved, so that any historical version of a given unique identifier can be queried at any point in time.
2. **Current-state lookup**: the latest version of any unique identifier must be queryable efficiently (no full table scan).
3. **Delta identification**: it must be straightforward to extract rows that have **actually changed in content** (inserts or updates) compared to the current latest version. Rows that haven't changed **must not** appear in the delta.
4. **Idempotency**: re-running the pipeline against the same input must not affect the final result (result consistency; performance optimization is not required).
5. **Reasonable partitioning design**, with clear justification.

### Sync-ready Output Requirements

The final jsonl output must:

- Contain only customers that are **valid** under the field-level rules in the Constraints section.
- Contain only customers that are **sync-eligible** under the business rules in the Constraints section.
- Be **denormalized**: each customer record is enriched with its associated membership data (see reference structure).
- Be deterministic and reproducible: re-running the pipeline on the same input must produce the same output.

How you enforce the rules (in-pipeline validation, SQL constraints, separate validation step, etc.) is your design choice. Please document your approach and reasoning.

### Technology

- **Language**: Python
- **Storage**: **DuckDB** (please set up locally; the assignment must run end-to-end on your machine)
- **Partitioning**: implement in DuckDB if your design maps cleanly to it. If your partitioning strategy is specific to a cloud DWH (BigQuery / Snowflake / etc.), document the design in writing and skip the local implementation — do not force-fit it into DuckDB.

### Deliverables

In your forked repository, please include:

- **Runnable code**: two Python scripts with clear, separate responsibilities:
    - `src/ingest.py` — reads the input JSONL files (`customer_profile.jsonl`, `membership.jsonl`) and ingests them into DuckDB.
    - `src/prepare_sync.py` — reads from DuckDB, applies validation rules, and produces the sync-ready JSONL output under `src/data/output/`.
- **`requirements.txt`** (or equivalent dependency manifest).
- **`SOLUTION.md`** documenting:
    - How to run the pipeline
    - Your table schemas (DDL or equivalent)
    - Your design choices: partitioning strategy, history retention approach, delta extraction logic, validation approach
    - Assumptions, trade-offs, and future improvements
- **Sync-ready jsonl output** generated from the sample inputs, checked into the repo.

---

## Evaluation Criteria

1. **Data Modeling**
    
    - Coverage of the 5 output-table requirements (the more, the better).
    - Generality of the design — minimal assumptions about downstream query patterns, and ease of accommodating future use cases.
    - Trade-off articulation — clear reasoning behind each design choice (partition key, primary key, history retention strategy, etc.).
2. **Output Correctness**
    
    - Whether the sync-ready jsonl correctly excludes invalid / ineligible customers under all constraints.
    - Coverage of validation across multiple dimensions (schema / format / business rule / uniqueness / cross-entity dependency).
    - Whether the validation approach is reasonable, feasible, and traceable (e.g., can a reviewer tell _why_ a given row was excluded?).
3. **Communication**
    
    - Whether assumptions, limitations, and future improvements are clearly documented.
    - Whether the overall solution is well-structured and easy to review.

---

## Submission

Please follow these steps to submit your work:

1. Create a new, public repository on your personal GitHub or GitLab account.
2. Copy the assignment code into your new repository. You can do this by cloning our repository and pushing it to your new one, or by downloading the code as a ZIP and committing it.
3. Email the link to your personal repository to the person who sent you the assignment.

**Important**: Please do not fork our repository or open a pull request. We use pull requests to manage and update the assignments, not to review candidate submissions.

Clarification questions before submission are welcome.