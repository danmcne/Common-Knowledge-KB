# Common Knowledge KB (v0.6)

A probabilistic, temporal, and provenance-aware knowledge base for reasoning under uncertainty.

## Overview

This system models knowledge as **statements with degrees of belief**, rather than binary true/false facts. Each statement is:

* **Probabilistic** — represented by a Beta distribution (α, β)
* **Temporal** — valid over a point or interval (with optional uncertainty)
* **Sourced** — supported by attestations with credibility and correlation handling
* **Structured** — expressed via typed predicates with defined argument roles
* **Explainable** — derivations and provenance are explicitly tracked

The goal is not just storage, but **reasoning under uncertainty with auditability**.

---

## Core Design Principles

### 1. Statements Are the Only Source of Truth

All knowledge is represented as rows in `statements`.

Derived structures (e.g. `type_membership`) are **caches**, populated automatically via triggers. They must not be written to directly.

---

### 2. Belief Is First-Class

Each statement has a Beta distribution:

* `belief_mean = α / (α + β)`
* Confidence intervals and variance are derived

Belief reflects **strength of evidence**, not just frequency or truth.

---

### 3. Time Is Separate from Semantics

Temporal information is encoded in:

* `t_kind`: `eternal`, `always`, `interval`, `point`
* `t_start`, `t_end`: fuzzy timestamps

**Important:**
Time is *not* encoded as an argument unless it is a **named semantic object** (e.g. "Victorian era").

---

### 4. Provenance Is Mandatory for Inference

Derived statements must:

* Record parent statements (`derived_from`)
* Register dependencies (`statement_dependencies`)
* Specify rule and depth

This ensures all conclusions are **traceable and explainable**.

---

### 5. Open-World Assumption

Absence of a statement ≠ false.

Queries (e.g. `holds_at`) operate under an open-world model, returning:

* supported facts (above threshold)
* optionally weaker or competing evidence

---

### 6. Evidence Is Weighted and De-correlated

Each statement may have multiple attestations:

* Each source has a **context-dependent credibility**
* Attestations may be grouped via `evidence_group_id`

  * Only the highest-weight item per group contributes
  * Prevents double-counting correlated sources

---

### 7. Conflicts Are Explicit

Conflicting claims are represented as:

* Two competing positive statements
* Linked via a row in `conflicts`

Conflict detection is based on:

* **non-overlapping confidence intervals**

Conflicts are retained for audit; resolution is explicit, not destructive.

---

## Schema Components

### Objects

`objects` represent all entities:

* individuals (e.g. `ada_lovelace`)
* types (e.g. `person`, `mammal`)
* predicates (as objects of kind `predicate`)
* sources, contexts, etc.

All objects use stable UUIDs derived from `(name, kind)`.

---

### Predicates

Defined in `predicates` with:

* arity (1, 2, 3, ...)
* argument labels
* domain strictness (`strict` or `soft`)
* natural language description

Argument semantics are enforced via domain checks and triggers.

---

### Statements

Core table:

```text
(predicate_id, object_args, literal_args, belief_alpha, belief_beta,
 t_kind, t_start, t_end, context_id, derivation_type, ...)
```

Key properties:

* Represent all knowledge uniformly
* May include literal values (`literal_args`)
* Can be user-asserted, ingested, or derived

---

### Type Membership (Derived Cache)

`type_membership` is automatically populated from `is_a` statements.

* Maintained by `trg_sync_type_membership`
* Used for efficient type queries
* Never directly written

---

### Attestations

Link statements to sources:

```text
(statement_id, source_id, confidence_weight, evidence_group_id)
```

Supports:

* multi-source evidence
* correlation control via grouping

---

### Source Credibility

Each `(source, context)` pair has:

* Beta-distributed credibility
* Updated via `update_trust()`

Allows domain-specific trust modeling.

---

### Conflicts

Explicit representation of opposing claims:

```text
(statement_a, statement_b, conflict_kind, resolved, resolution_note)
```

Types include:

* `direct_negation`
* `type_mismatch`

---

### Derived Belief

`compute_derived_belief()` computes belief for inferred statements using:

* `min` mode (conservative)
* `log_odds` mode (assumes independence)

Includes decay by inference chain length.

---

## Key Functions

### `holds_at(...)`

Temporal query:

```sql
holds_at(predicate, args, time, context, mode, p_threshold, p_min_evidence)
```

Returns statements that hold at a given time.

Modes:

* `open_world`: threshold-based filtering
* `evidence_weighted`: returns all matching evidence

---

### `tell_about(entity, context, threshold)`

Primary query interface:

> “What does the KB know about X?”

Returns all statements involving the entity, ranked by belief.

---

### `why(statement_id)`

Returns the full provenance tree:

* parent statements
* inference rules
* belief at each step

---

### `detect_conflicts(context)`

Finds conflicts based on confidence interval non-overlap.

Safe to run repeatedly.

---

### `update_belief(statement_id, new_value, p_override)`

Applies Bayesian update or override.

---

### `update_trust(source, context, correct, weight, p_override)`

Updates source credibility.

---

## Modeling Patterns

### Types

Use:

```text
is_a(entity, type)
subtype_of(child_type, parent_type)
```

Do not insert into `type_membership` directly.

---

### Roles and Relations

Use structured predicates:

```text
has_role(entity, role, scope)
affiliated_with(entity, institution, capacity)
```

Use `no_scope` when a role has no meaningful scope.

---

### Temporal Facts

Encode time in `t_start` / `t_end`, not as arguments:

```text
has_role(ada, programmer, difference_engine)
t_start ≈ 1842, t_end ≈ 1843
```

---

### Values

Use `has_value(entity, attribute, value)` with `literal_args`.

---

### Conflicting Claims

Insert both claims as positive statements.

Let:

* belief
* evidence
* conflict detection

handle resolution.

---

## What v0.6 Fixes (vs v0.5)

* Eliminates direct writes to `type_membership`
* Corrects misuse of time as object arguments
* Introduces explicit `no_scope` sentinel
* Replaces ad-hoc belief derivation with `compute_derived_belief()`
* Adds evidence grouping to prevent correlation bias
* Replaces threshold-based conflict detection with CI-based detection
* Enforces provenance for derived statements
* Introduces `tell_about()` and `why()` as primary query interfaces

---

## Known Limitations / Future Work

* Belief currently mixes ontological, empirical, and statistical uncertainty
* Conflicts do not yet directly adjust belief
* Argument semantics are partially implicit
* Literal values are not fully first-class
* Independence assumptions in inference are user-controlled, not enforced

---

## Summary

v0.6 provides:

* A unified representation of uncertain knowledge
* Temporal reasoning with fuzzy intervals
* Source-aware belief aggregation
* Explicit conflict modeling
* Explainable inference

It is suitable as a foundation for:

* probabilistic knowledge graphs
* reasoning systems under uncertainty
* explainable AI pipelines

Further work should focus on:

* stronger epistemic typing
* tighter integration of conflicts into belief
* richer typing of predicate arguments and values

## License

MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

