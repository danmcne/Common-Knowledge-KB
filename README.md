# Common Knowledge KB

A foundation schema for a probabilistic, temporal, source-aware knowledge base
designed to support Bayesian and logical reasoning over common knowledge.

Early research artifact — schema and predicate kernel, v0.1.

---

## What this is

Most knowledge bases make a hard choice: either they are *large and shallow*
(Wikidata, ConceptNet) or *deep and narrow* (domain ontologies). Most use crisp
logic — a fact is either true or false, with no native representation of
uncertainty, evidence strength, or source trustworthiness. Nearly all treat time
as an afterthought.

This project is an attempt to build the foundation of something different: a
knowledge base where every fact carries a *degree of belief*, a *temporal scope*,
and a *source with a credibility score* — and where logical certainty is the
limiting case of probabilistic belief rather than a separate regime.

The core ideas:

- **Beta belief on every statement.** Rather than a confidence float, each
  statement carries `(belief_alpha, belief_beta)` — the parameters of a Beta
  distribution over P(statement is true). Mean belief = α/(α+β). Evidence
  accumulates by incrementing α (supporting evidence) or β (contradicting
  evidence), weighted by the source's credibility. At high α with negligible β,
  belief collapses to crisp logical truth. This is not metaphor — it is the
  formal limit of the Beta distribution.

- **Fuzzy temporal bounds.** Every fact has a temporal scope
  (`eternal`, `always`, `interval`, `point`, `default`). Temporal bounds are
  not timestamps but fuzzy triples `(best, lo, hi, granularity)` — representing
  that Caesar crossed the Rubicon *around* 49 BCE, probably between 50 and 48
  BCE, is a first-class value, not a workaround.

- **Source credibility as a Beta distribution.** Sources have credibility scores
  per context/domain, also stored as Beta parameters. A source that has been
  verified correct 19 times and wrong once has a credibility mean of 0.95 *and*
  a meaningful confidence interval around that estimate. New sources start at
  the uniform prior (α=1, β=1). Credibility updates via Bayes after verification.

- **Everything is an object.** Persons, institutions, concepts, predicates,
  contexts, and sources all live in a single `objects` table with a kind tag.
  This means you can make statements *about* predicates and sources using the
  same machinery — a predicate is just another object.

- **A minimal basis predicate set.** Rather than an unbounded flat list of
  relations, the schema ships with ~55 carefully chosen basis predicates drawn
  from ConceptNet, Wikidata property vocabularies, Allen's interval algebra,
  and the Event Calculus. Every user-defined predicate is decomposed as a
  weighted combination of these basis predicates, controlling predicate
  explosion.

- **Contexts as first-class objects.** "True in the Star Wars universe" and
  "true in the domain of Newtonian mechanics" use the same mechanism —
  a context object with an optional parent context from which it inherits
  facts unless overridden. The default context is `reality`.

---

## What this is not (yet)

This is a schema and a predicate kernel. It is not yet:

- A working reasoner. The intended reasoning stack is
  [ProbLog](https://problog.readthedocs.io/) for probabilistic inference over
  retrieved KB subsets, with [SWI-Prolog](https://www.swi-prolog.org/) for
  high-performance logical queries and Event Calculus. Neither is wired up here.

- A populated knowledge base. The seed data contains sources, contexts, and
  placeholder concepts. Domain content (history, science, geography) must be
  ingested — Wikidata's SPARQL endpoint is the intended bootstrap source for
  common factual knowledge.

- An NL interface. The intended architecture uses a small local LLM
  (Qwen2.5-7B or Phi-4) to translate natural language queries into formal
  queries against the KB, with the predicate registry retrieved via embedding
  similarity to supply the relevant schema context. This is not implemented.

- A contradiction resolver. The `conflicts` table is defined. The detection and
  resolution logic is not yet written.

---

## Files

```
common_knowledge_schema.sql   — PostgreSQL schema: tables, types, indexes,
                                views, functions, and seed data.

basis_predicates.sql          — ~55 basis predicate INSERT statements,
                                organised into 12 semantic groups.
```

Run them in order against a fresh PostgreSQL database:

```bash
psql -d your_database -f common_knowledge_schema.sql
psql -d your_database -f basis_predicates.sql
```

### Prerequisites

- PostgreSQL 15 or later
- [pgvector](https://github.com/pgvector/pgvector) extension
  (`CREATE EXTENSION vector`)
- `btree_gist` extension (ships with PostgreSQL,
  `CREATE EXTENSION btree_gist`)

Both extensions are installed automatically by the schema file if present.
pgvector must be installed at the OS/package level first:

```bash
# Ubuntu / Debian
sudo apt install postgresql-15-pgvector

# macOS via Homebrew
brew install pgvector
```

---

## Schema overview

### Core tables

| Table | Purpose |
|---|---|
| `objects` | Every entity: persons, concepts, predicates, sources, contexts |
| `predicates` | Extension of `objects` for kind=`predicate` — arity, arg types, domains |
| `contexts` | Extension of `objects` for kind=`context` — parent context, kind |
| `statements` | The KB body — reified facts with belief, time scope, and provenance |
| `attestations` | Links statements to the sources that assert them |
| `source_credibility` | Beta distribution (α, β) per (source, context) |
| `predicate_subsumption` | Probabilistic subproperty hierarchy |
| `type_membership` | Fuzzy class membership P(object ∈ class) |
| `conflicts` | Detected contradictions awaiting resolution |

### Key views

| View | What it gives you |
|---|---|
| `statement_belief` | Mean, variance, 95% CI for every statement's Beta belief |
| `statement_view` | Statements with predicate and context names resolved |
| `statement_credibility` | Weighted source credibility per statement |
| `source_credibility_score` | Mean, CI for each (source, context) credibility |

### Key functions

| Function | What it does |
|---|---|
| `update_belief(statement_id, weight, supports)` | Bayesian belief update — increments α or β by source credibility weight |
| `update_trust(source_id, context_id, correct)` | Bayesian trust update — increments α or β of source credibility |
| `holds_at(predicate_id, object_args, time, context_id)` | Returns statements matching predicate+args that hold at a given timestamp |
| `belief_mean(statement_id)` | Current mean belief for a statement |
| `year_to_jd(year)` | Converts a year (negative = BCE) to Julian Day Number |
| `jd_to_tstz(jd)` | Converts a Julian Day Number to a timestamptz safely |

---

## Basis predicate groups

| Group | Count | Examples |
|---|---|---|
| Taxonomic / type | 5 | `is_a`, `subtype_of`, `has_property`, `same_as` |
| Mereology | 4 | `part_of`, `has_part`, `member_of`, `contains` |
| Spatial | 3 | `located_in`, `adjacent_to`, `origin_of` |
| Temporal | 5 | `before`, `after`, `during`, `simultaneous_with`, `has_duration` |
| Causal / functional | 6 | `causes`, `enables`, `prevents`, `used_for`, `capable_of` |
| Agentive / social | 6 | `agent_of`, `created_by`, `held_office`, `affiliated_with` |
| Quantitative | 3 | `has_quantity`, `greater_than`, `approximately_equal` |
| Epistemic / modal | 5 | `knows`, `believes`, `desires`, `possible`, `necessary` |
| Linguistic | 3 | `named`, `symbol_for`, `language_of` |
| Event Calculus core | 4 | `initiates`, `terminates`, `happens_at`, `holds_at` |
| Physical / lifecycle | 7 | `made_of`, `has_state`, `born_in`, `died_in`, `affects` |
| Inferential / correlational | 4 | `implies`, `correlated_with`, `typical_of`, `occurs_in` |

Basis predicates are mapped to their ConceptNet, Wikidata, RDF/OWL, and Event
Calculus equivalents where they exist. Every predicate has a natural-language
description and a FOL definition in terms of more primitive predicates where
applicable.

---

## Design decisions worth knowing about

**Why Beta rather than a confidence float?**
A single float loses information about how much evidence supports a belief.
Two sources independently asserting the same fact should produce higher
confidence than one source asserting it twice — but a float cannot represent
this distinction. Beta parameters α and β track both the estimated probability
and the evidence strength. Sequential Bayesian updating is trivial: add the
source's credibility mean to α (supporting) or β (contradicting). At
α=1000, β=0.001 (kernel axioms), the distribution is essentially a spike at
1.0 — logical certainty is not a special case but an extreme of the same model.

**Why fuzzy temporal bounds as a composite type rather than two timestamps?**
Historical and scientific knowledge is frequently uncertain in its temporal
extent. Storing only `valid_from` and `valid_to` timestamps forces false
precision. The `fuzzy_time` composite `(best, lo, hi, granularity)` lets the
KB represent "this was true sometime in the 4th century BCE" without
collapsing to a point or discarding the fact.

**Why is `held_office` a quaternary (4-argument) basis predicate?**
Most basis predicates are binary. `held_office(person, role, organisation, n)`
is an exception because the combination is universally needed for
political/historical reasoning and decomposing it into three binary predicates
creates join complexity in every query. It is flagged in the file as borderline
and can be demoted to a derived predicate in a later version.

**Why not OWL / RDFS directly?**
OWL is the right choice for a pure ontology layer. This schema is not an
ontology — it is an assertional KB with probabilistic belief and temporal scope.
OWL's crisp semantics and closed-world assumption conflict with both
requirements. The schema maps predicates to their OWL/RDF equivalents via
`source_predicate` for interoperability, but does not use OWL as the native
formalism.

**Why PostgreSQL rather than a triple store?**
Triple stores (Jena, Blazegraph) are optimised for RDF graphs with crisp
semantics. The Beta belief parameters, fuzzy temporal bounds, and derivation
metadata do not map cleanly to RDF triples without heavy reification — which is
exactly what the `statements` table already provides, with full SQL query
support, GiST indexes on temporal ranges, and pgvector for embedding search.

---

## Intended reasoning architecture

The long-term architecture this schema is designed to support:

```
Natural language query
    → small local LLM (Qwen2.5-7B / Phi-4 via ollama)
        — translates to formal query using retrieved predicate schema
    → PostgreSQL KB (this schema)
        — retrieves relevant statement subset
    → ProbLog / SWI-Prolog
        — probabilistic inference over retrieved subset
        — holds_at() for temporal queries
        — belief propagation weighted by source credibility
    → LLM output synthesiser
        — renders result with confidence expression
        — traces provenance on request
```

The LLM does not reason — it translates and renders. The reasoning is formal
and auditable.

---

## Relationship to existing projects

| Project | Relation |
|---|---|
| **Wikidata** | Intended bootstrap source for factual content. Properties mapped via `source_predicate`. Does not support probabilistic belief or fuzzy time natively. |
| **ConceptNet** | Source for ~18 of the 55 basis predicates. ConceptNet relations are shallow (no FOL definitions, no temporal scope, no belief). |
| **OpenCyc / ResearchCyc** | Closest prior attempt at a general-purpose formal KB. Uses crisp logic only; predicate vocabulary is idiosyncratic; largely abandoned. |
| **ProbLog** | Intended inference engine. This schema is designed so retrieved statement subsets can be serialised to ProbLog syntax for inference. |
| **NELL** | Machine-learned KB; no formal predicate definitions, no temporal scope, no user-controlled belief. |

---

## Contributing

Contributions welcome. Most useful at this stage:

- Review of the basis predicate set — redundancies, missing universals,
  argument type corrections
- A Python ingestion script (Wikidata → statements inserts)
- A ProbLog serialiser (statements subset → ProbLog program)
- Domain-specific predicate sets (biology, law, mathematics)
- Test suite for the `holds_at()` function and belief update functions

Please open an issue before large structural changes to the schema — the design
decisions above are load-bearing and some apparent simplifications break the
probabilistic model.

---

## License

MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
