**# Common Knowledge KB**

A foundation schema for a **probabilistic, temporal, source-aware** knowledge base  
designed to support Bayesian and logical reasoning over common knowledge.

**v0.5** — test schema with normalized arguments, open-world reasoning, provenance graphs, and explicit conflict handling.

---

## What this is

Most knowledge bases force a hard choice: either *large and shallow* (Wikidata, ConceptNet) or *deep and narrow* (domain ontologies). Most use crisp logic with no native support for uncertainty, evidence strength, or source trustworthiness. Nearly all treat time as an afterthought.

This project is the foundation for something different: a knowledge base where **every fact carries a degree of belief (Beta distribution), a fuzzy temporal scope, a source with credibility, and an epistemic interpretation** — and where logical certainty is the natural limiting case of probabilistic belief.

### Core Ideas (unchanged in spirit, refined in v0.5)

- **Beta belief on every statement**  
  Every statement stores `(belief_alpha, belief_beta)`. Mean belief = α/(α+β). Evidence accumulates by weighted increments from source credibility. High α + near-zero β collapses naturally to crisp logical truth.

- **Fuzzy temporal bounds**  
  Every fact has a `temporal_kind` (`eternal`, `always`, `interval`, `point`, `default`) and optional `fuzzy_time` triples `(best, lo, hi, granularity)`.

- **Source credibility as Beta distributions**  
  Sources have per-context credibility `(α, β)`. New sources start at uniform prior (1,1). `update_trust()` performs Bayesian updates; protected kernel sources require explicit override.

- **Everything is an object**  
  Persons, concepts, predicates, contexts, and sources all live in a single `objects` table. Fine-grained typing lives in `subtype_of` + `type_membership` statements (not the coarse `kind` column).

- **Minimal basis predicate set**  
  57 carefully chosen basis predicates across 13 semantic groups. Every user predicate is intended to decompose into these.

- **Contexts as first-class objects**  
  Tree-structured inheritance (`reality` is the root). Domain contexts scope source credibility.

- **Three-layer type system (new in v0.5)**  
  - Coarse infrastructure: `object.kind` (`entity`/`source`/`context`/`predicate`)  
  - Ontological hierarchy: `subtype_of` statements  
  - Probabilistic membership: `type_membership` (Beta)  
  - Epistemic tagging: `statement_interpretation` (`ontological` / `modeling` / `legal_fiction` / `metaphorical`)

---

## What this is not (yet)

- A full working reasoner (ProbLog + SWI-Prolog + Event Calculus integration planned)  
- A massively populated KB (Wikidata SPARQL ingestion script is next)  
- A natural-language interface (small local LLM + pgvector predicate retrieval planned)  
- Automated contradiction resolution (the `conflicts` table and detector queries are ready)

---

## Files

```
common_knowledge_schema.sql      — PostgreSQL schema, tables, enums, triggers,
                                   views, functions, and seed data
common_predicates_kernel.sql     — 57 basis predicates (13 groups) with
                                   arg_type_ids, FOL definitions, and metadata
common_objects_kernel.sql        — Ontological backbone, type hierarchy,
                                   domain contexts, axiomatic statements,
                                   typicality, disjointness, and logical rules
examples.sql                     — 60+ worked queries and inserts demonstrating
                                   every major v0.5 feature
```

### Installation order (run exactly in this sequence)

```bash
psql -d your_database -f common_knowledge_schema.sql
psql -d your_database -f common_predicates_kernel.sql
psql -d your_database -f common_objects_kernel.sql
```

Then explore interactively:

```bash
psql -d your_database -f examples.sql
```

### Prerequisites

- PostgreSQL 15+  
- `pgvector`, `btree_gist`, `pgcrypto` extensions (created automatically)

---

## Schema Overview (v0.5)

### Core Tables (key changes highlighted)

| Table                    | Purpose                                                                 | v0.5 Highlight |
|--------------------------|-------------------------------------------------------------------------|----------------|
| `objects`                | Unified namespace for everything                                        | `kind` now only 4 coarse values |
| `predicates`             | Predicate metadata                                                      | `arg_type_ids`, `domain_strictness` |
| `statements`             | Reified facts                                                           | `belief_mean` stored column, `interpretation`, no `negated` |
| `statement_args`         | Normalized per-position arguments (authoritative)                       | **New** + sync trigger |
| `attestations`           | Source → statement links                                                | `evidence_group_id` for correlated sources |
| `source_credibility`     | Beta credibility per (source, context)                                  | `is_protected` flag |
| `statement_dependencies` | Authoritative provenance graph                                          | **New** (replaces weak `derived_from[]` cache) |
| `type_membership`        | Probabilistic class membership                                          | Primary fine typing mechanism |
| `conflicts`              | Detected contradictions                                                 | **Negation lives here** (`direct_negation`) |
| `object_equivalence`     | Probabilistic `same_as` links                                           | **New** for entity resolution |

### Key Views & Functions

- `statement_belief`, `statement_view`, `statement_credibility`, `source_credibility_score`
- `update_belief()`, `update_trust(p_override)`  
- `holds_at(predicate_id, object_args, time, context_id, p_mode)`  
  - `'open_world'` (default) — only `belief_mean > 0.5`  
  - `'evidence_weighted'` — all statements ordered by belief  
  - `'default_true'` — v0.4 legacy behaviour

---

## Basis Predicate Groups (57 total)

13 semantic groups (full list with arities and mappings in `common_predicates_kernel.sql`):

| Group                        | Count | Examples |
|-----------------------------|-------|----------|
| Taxonomic / Type            | 5     | `is_a`, `subtype_of`, `has_property`, `same_as` |
| Mereology                   | 4     | `part_of`, `has_part`, `member_of`, `contains` |
| Spatial                     | 4     | `located_in` (ternary), `adjacent_to`, `origin_of`, `transferred_to` |
| Temporal                    | 5     | Allen’s algebra + `has_duration` |
| Causal / Functional         | 6     | `causes` (ternary), `enables`, `prevents` … |
| Agentive / Social           | 6     | `has_role` (ternary), `affiliated_with`, `agent_of` … |
| Quantitative                | 3     | `has_quantity`, `greater_than`, `approximately_equal` |
| Epistemic / Modal           | 5     | `knows`, `believes`, `possible` (unary) … |
| Linguistic                  | 3     | `named`, `symbol_for`, `language_of` |
| Event Calculus Core         | 4     | `initiates`, `terminates`, `holds_at_ec` |
| Physical / Lifecycle        | 4     | `made_of`, `has_state`, `affects` … |
| Inferential / Correlational | 4     | `implies`, `typical_of`, `correlated_with` |
| Structural / Logical        | 3     | `equivalent_to`, `disjoint_with` (hard), `has_value` (ternary) |

---

## Kernel Object Hierarchy

**Coarse backbone** (seeded in schema, enriched here):

```
entity
├── concrete
│   ├── living → animate → sapient → person
│   ├── organism → animal → mammal → person
│   ├── artifact → physical_object
│   ├── place → region / location
│   └── physical_object
├── abstract
│   ├── concept_type, property, attribute, relation_type
│   ├── proposition, information, knowledge_state
│   ├── norm → rule
│   ├── goal, role, symbol → language / word / sentence
│   ├── quantity → number → real_number → integer → natural_number
│   ├── time → time_interval / time_point
│   ├── truth_value → true / false / unknown
│   └── event_type → change_event / action / process / state
└── group, institution, agent (role-type)
```

**10 domain contexts** (`domain_history`, `domain_science`, …) for credibility scoping.

**Axiomatic statements** (~50 `subtype_of`, disjointness, logical `implies` rules, typicality, etc.) — all eternal or always, attested to protected `system_kernel`.

---

## Design Decisions (v0.5)

- **Negation via conflicts table** — two positive statements + explicit `direct_negation` link preserves evidential gradation.
- **Normalized `statement_args`** — FK safety + fast tuple matching; denormalized cache retained for performance.
- **Open-world default** — `holds_at()` returns only positively supported facts (`belief_mean > 0.5`).
- **Protected kernel** — `system_kernel` cannot be passively updated.
- **Three-layer typing** — coarse `kind` + ontological `subtype_of` + probabilistic `type_membership`.
- **Literal args support** — `has_value`, FOL-style rules, etc.

---

## Intended Reasoning Architecture

```
Natural language query
    → small local LLM (Qwen2.5-7B / Phi-4 via ollama)
        → predicate retrieval via pgvector embeddings
        → formal query
    → PostgreSQL KB
        → holds_at(), statement_belief, statement_view
    → ProbLog / SWI-Prolog
        → probabilistic inference + belief propagation
    → LLM synthesis + provenance trace
```

---

## Relationship to Existing Projects

| Project       | Relation |
|---------------|----------|
| **Wikidata**  | Primary bootstrap source (via SPARQL) |
| **ConceptNet**| ~20 basis predicates drawn from it |
| **ProbLog**   | Target inference engine |
| **Event Calculus** | Core predicates + `holds_at_ec` |

---

## Contributing

Most useful right now:
- Wikidata SPARQL ingestion script
- ProbLog serialiser
- Automated conflict detector / resolver triggers
- Domain-specific predicate or object extensions
- Test suite for new v0.5 functions

Open an issue before large schema changes — the design decisions above are load-bearing.

---

## Repository Structure

```
common-knowledge-kb/
├── README.md
├── LICENSE
└── schema/
    ├── common_knowledge_schema.sql
    ├── common_predicates_kernel.sql
    ├── common_objects_kernel.sql
    └── examples.sql
```

---

## License

MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
