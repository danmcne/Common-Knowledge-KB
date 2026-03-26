# Common Knowledge KB

A foundation schema for a probabilistic, temporal, source-aware knowledge base
designed to support Bayesian and logical reasoning over common knowledge.

Early research artifact — schema, predicate kernel, and object/statement kernel. v0.2.

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

**Beta belief on every statement.** Rather than a confidence float, each
statement carries `(belief_alpha, belief_beta)` — the parameters of a Beta
distribution over P(statement is true). Mean belief = α/(α+β). Evidence
accumulates by incrementing α (supporting evidence) or β (contradicting
evidence), weighted by the source's credibility. At high α with negligible β,
belief collapses to crisp logical truth. This is not metaphor — it is the
formal limit of the Beta distribution.

**Fuzzy temporal bounds.** Every fact has a temporal scope
(`eternal`, `always`, `interval`, `point`, `default`). Temporal bounds are
not timestamps but fuzzy triples `(best, lo, hi, granularity)` — representing
that Caesar crossed the Rubicon *around* 49 BCE, probably between 50 and 48
BCE, is a first-class value, not a workaround.

**Source credibility as a Beta distribution.** Sources have credibility scores
per context/domain, also stored as Beta parameters. A source that has been
verified correct 19 times and wrong once has a credibility mean of 0.95 *and*
a meaningful confidence interval around that estimate. New sources start at
the uniform prior (α=1, β=1). Credibility updates via Bayes after verification.

**Everything is an object.** Persons, institutions, concepts, predicates,
contexts, and sources all live in a single `objects` table with a kind tag.
This means you can make statements *about* predicates and sources using the
same machinery — a predicate is just another object.

**A minimal basis predicate set.** Rather than an unbounded flat list of
relations, the schema ships with 55 carefully chosen basis predicates drawn
from ConceptNet, Wikidata property vocabularies, Allen's interval algebra,
and the Event Calculus. Every user-defined predicate is intended to be
decomposed as a weighted combination of these basis predicates, controlling
predicate explosion.

**Contexts as first-class objects.** "True in the Star Wars universe" and
"true in the domain of Newtonian mechanics" use the same mechanism —
a context object with an optional parent context from which it inherits
facts unless overridden. The default context is `reality`.

**A foundational object and statement kernel.** Beyond the predicate
vocabulary, the KB ships with a populated kernel: ~40 abstract concept objects
(the type hierarchy from `entity` down to `person`, `integer`, `place`, etc.),
~45 eternal axiomatic statements encoding the type hierarchy and logical laws,
10 named domain contexts for source credibility scoping, and typicality
statements that encode prototype knowledge with graded belief.

---

## What this is not (yet)

This is a schema, a predicate kernel, and a foundational object/statement
kernel. It is not yet:

**A working reasoner.** The intended reasoning stack is
[ProbLog](https://problog.readthedocs.io/) for probabilistic inference over
retrieved KB subsets, with [SWI-Prolog](https://www.swi-prolog.org/) for
high-performance logical queries and Event Calculus. Neither is wired up here.
The `holds_at()` SQL function provides temporal reasoning directly in Postgres
for simple queries.

**A populated knowledge base.** The kernel contains the type hierarchy and
logical axioms. Domain content (history, science, geography) must be
ingested — Wikidata's SPARQL endpoint is the intended bootstrap source.
The examples file shows how to add facts manually and is the template for
an automated ingestion script.

**An NL interface.** The intended architecture uses a small local LLM
(Qwen2.5-7B or Phi-4 via ollama) to translate natural language queries
into formal queries against the KB, with the predicate registry retrieved
via embedding similarity to supply the relevant schema context.

**A contradiction resolver.** The `conflicts` table is defined and the
examples show how to detect direct contradictions with a SQL query.
Automated detection and resolution logic is not yet written.

---

## Files

```
common_knowledge_schema.sql      — PostgreSQL schema: tables, enums, types,
                                   indexes, views, functions, and seed data
                                   for the four built-in sources.

common_predicates_kernel.sql     — 55 basis predicate INSERT statements
                                   across 12 semantic groups, with domain
                                   tags and FOL definitions.

common_objects_kernel.sql        — Foundational object concepts (entity,
                                   person, number, place, time…), the type
                                   hierarchy as eternal statements, logical
                                   axioms, domain contexts, and typicality
                                   statements.

examples.sql                     — 19 worked interaction examples: inspection
                                   queries, boolean and binding queries,
                                   inserting objects and statements, temporal
                                   queries, Bayesian belief and trust updates,
                                   provenance queries, and conflict detection.
```

### Installation order

Run in this exact order against a fresh PostgreSQL database:

```bash
psql -d your_database -f common_knowledge_schema.sql
psql -d your_database -f common_predicates_kernel.sql
psql -d your_database -f common_objects_kernel.sql
```

The examples file can be run interactively in psql or any Postgres client:

```bash
psql -d your_database -f examples.sql
# or interactively:
psql -d your_database
\i examples.sql
```

### Prerequisites

- PostgreSQL 15 or later
- [pgvector](https://github.com/pgvector/pgvector) extension
- `btree_gist` extension (ships with PostgreSQL)

```bash
# Ubuntu / Debian
sudo apt install postgresql-16-pgvector

# macOS via Homebrew
brew install pgvector
```

Both extensions are created automatically by the schema file.

---

## Schema overview

### Core tables

| Table | Purpose |
|---|---|
| `objects` | Every entity: persons, concepts, predicates, sources, contexts |
| `predicates` | Extension of `objects` for kind=`predicate` — arity, arg types, domains |
| `contexts` | Extension of `objects` for kind=`context` — parent context, kind |
| `statements` | The KB body — reified facts with Beta belief, time scope, provenance |
| `attestations` | Links statements to the sources that assert them |
| `source_credibility` | Beta distribution (α, β) per (source, context/domain) |
| `predicate_subsumption` | Probabilistic subproperty hierarchy |
| `type_membership` | Fuzzy class membership P(object ∈ class) |
| `conflicts` | Detected contradictions awaiting resolution |

### Key views

| View | What it gives you |
|---|---|
| `statement_belief` | Mean, variance, 95% CI for every statement's Beta belief |
| `statement_view` | Statements with predicate and context names resolved |
| `statement_credibility` | Weighted source credibility per statement |
| `source_credibility_score` | Mean and CI for each (source, context) pair |

### Key functions

| Function | What it does |
|---|---|
| `update_belief(stmt_id, weight, supports)` | Bayesian belief update — increments α or β by source credibility weight |
| `update_trust(src_id, ctx_id, correct)` | Bayesian trust update — increments α or β of source credibility |
| `holds_at(pred_id, object_args, time, ctx_id)` | Statements matching predicate+args that hold at a given timestamp |
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

Each predicate carries: arity, expected argument kinds, a natural-language
description, a FOL definition in terms of more primitive predicates where
applicable, domain tags (`temporal`, `causal`, `social`, etc.), and a
mapping to its ConceptNet, Wikidata, RDF/OWL, or Event Calculus equivalent.

---

## Kernel object hierarchy

The `common_objects_kernel.sql` file populates:

**Abstract concept objects** (37 total across these groups):

```
entity
├── abstract_thing
│   ├── concept_type
│   ├── property
│   ├── relation
│   ├── proposition
│   ├── event_type
│   │   ├── process
│   │   └── action
│   ├── state
│   ├── quantity
│   │   ├── number
│   │   │   ├── real_number
│   │   │   │   └── integer
│   │   │   │       └── natural_number
│   │   ├── measurement
│   │   └── duration
│   ├── time
│   │   ├── time_interval
│   │   └── time_point
│   ├── symbol
│   │   ├── language
│   │   ├── word
│   │   └── sentence
│   └── truth_value
│       ├── true
│       ├── false
│       └── unknown
└── physical_thing
    ├── organism
    │   └── animal
    │       └── mammal
    │           └── person  (also: agent)
    ├── physical_object
    └── place
        ├── region
        └── location
```

**Domain contexts** (10): `domain_history`, `domain_science`,
`domain_mathematics`, `domain_geography`, `domain_biology`, `domain_physics`,
`domain_law`, `domain_linguistics`, `domain_social`, `domain_technology`.
These are used to scope source credibility — a source can be trusted highly
in `domain_history` and only moderately in `domain_science`.

**Axiomatic statements**: the type hierarchy above encoded as `subtype_of`
statements with `t_kind='eternal'` and `belief_alpha=1000, belief_beta=0.001`
(near-certain). Plus logical axioms such as `opposite_of(true, false)` and
`implies(is_a(X, mammal), is_a(X, animal))`.

**Typicality statements**: graded `typical_of` assertions — a person is a
more typical agent (typicality ≈ 0.9) than an institution (≈ 0.6).
These use `t_kind='always'` and belief < 1.0 by design.

**One intentionally non-certain axiom**: `implies(is_a(X, person), mortal(X))`
has `belief_alpha=95, belief_beta=5` (mean 0.95, `t_kind='always'`). It is a
strong empirical generalisation, not a logical truth, and the schema represents
that distinction.

---

## Worked interaction examples

After loading all three files, `examples.sql` demonstrates:

**Inspection** — count objects by kind, list predicates with domains, print
the full type hierarchy with belief scores.

**Boolean query** — "Is a mammal an animal?" Returns the statement with
`belief_mean ≈ 1.0000`, confidence interval, and `t_kind = eternal`.

**Binding query** — "What is `person` a subtype of?" Returns all supertypes
(`mammal`, `agent`, `organism`, `animal`, `entity`) ordered by belief.

**Reverse binding** — "What are all subtypes of `entity`?" Returns the full
first-level list.

**Typicality query** — "How typical is a person as an agent?" Returns graded
typicality scores for all `typical_of` statements.

**Inserting a named individual** — adds `john_tyler` as a `person` object
with Wikidata external ID, then `usa` and `president` as concepts.

**Asserting a temporal fact** — inserts `held_office(john_tyler, president,
usa, 10)` as an `interval` statement with fuzzy temporal bounds for 1841–1845,
initial belief seeded from Wikidata's credibility prior.

**Temporal queries** — `holds_at(held_office, [tyler, president, usa],
1843-06-15)` returns the statement with its belief. The same query for
`1850-01-01` returns empty — Tyler's term had ended.

**Bayesian belief update** — a second source (history textbook, credibility
0.80) confirms the Tyler fact. `update_belief()` increments `belief_alpha`
by 0.80. Belief mean rises from 0.867 to 0.879 — a small update because the
evidence base was already substantial. This is correct Bayesian behaviour.

**Trust penalty** — `update_trust(llm_generated, domain_history, false)`
penalises the LLM source after a wrong claim. Its credibility mean drops and
the confidence interval widens.

**Derived statement** — a forward-chained statement (`derivation_type =
'forward_chained'`, `derivation_depth = 1`) is inserted with a reference to
the source statement in `derived_from[]`.

**Provenance query** — retrieves all `held_office` statements with their
sources aggregated, belief, and derivation metadata.

**Conflict detection** — a SQL query finds pairs of statements with the same
predicate and args where one is `negated = true` and one is not.

**Aggregate view** — statement counts broken down by `t_kind` and
`derivation_type`, showing the distribution of the KB contents.

**Introspection** — "what does the KB believe about `person`?" — finds all
statements in which the `person` concept appears as any argument and returns
them with their predicates and belief scores.

A brief Python equivalent (using `psycopg2`) is included as a comment at the
end of the examples file, showing how to parameterise queries and call
`update_belief()` from application code.

---

## Design decisions

**Why Beta rather than a confidence float?**
A single float loses information about evidence strength. Two independent
sources confirming a fact should produce higher confidence than one source
confirming it twice — but a float cannot represent this. Beta parameters
α and β track both the estimated probability and the sample size. Sequential
updating is trivial: add the source credibility mean to α or β. At α=1000,
β=0.001 (kernel axioms), the distribution is essentially a spike at 1.0 —
logical certainty emerges naturally as an extreme of the probabilistic model.

**Why fuzzy temporal bounds?**
Historical and scientific knowledge is frequently uncertain in its temporal
extent. The `fuzzy_time` composite `(best, lo, hi, granularity)` lets the
KB represent "this was true sometime in the 4th century BCE" without forcing
false precision. The `granularity` field (`year`, `decade`, `century`…)
prevents spurious exactness in downstream reasoning.

**Why is the temporal index built over `jd_to_tstz()` rather than a generated
column?**
The naive approach of converting Julian Day Numbers directly to Unix epochs
inside a `GENERATED ALWAYS AS` expression produces silently wrong dates for
historical facts (BCE years, pre-1970 dates). `jd_to_tstz()` uses correct
epoch arithmetic and clamps to the PostgreSQL timestamp range, making the GiST
range index both correct and efficient.

**Why reify statements rather than store raw triples?**
Triple stores optimise for RDF graphs with crisp semantics. The Beta belief
parameters, fuzzy temporal bounds, derivation type, and derivation depth do
not map cleanly to RDF triples without heavy manual reification — which is
exactly what the `statements` table already provides, with full SQL query
support and GiST indexing.

**Why is `held_office` a quaternary (4-argument) predicate in the basis set?**
Most basis predicates are binary. `held_office(person, role, organisation, n)`
is an exception because it is universally needed for political and historical
reasoning and decomposing it into three binary predicates creates join
complexity everywhere. It is flagged in the file as borderline and can be
demoted to a derived predicate in a later version without schema changes.

**Why not use OWL / RDFS directly?**
OWL is the right choice for a pure ontology layer. This schema is an
assertional KB with probabilistic belief and fuzzy temporal scope. OWL's crisp
semantics and closed-world assumption conflict with both. The schema maps
predicates to OWL/RDF equivalents via `source_predicate` for interoperability
but does not use OWL as the native formalism.

---

## Intended reasoning architecture

The long-term architecture this schema is designed to support:

```
Natural language query
    → small local LLM (Qwen2.5-7B / Phi-4 via ollama)
        — translates to formal query using retrieved predicate schema
        — predicate schema retrieved by embedding similarity (pgvector)
    → PostgreSQL KB (this schema)
        — holds_at() for temporal queries
        — object_args @> array for argument matching
        — statement_belief view for posterior belief and CI
    → ProbLog / SWI-Prolog  (not yet implemented)
        — probabilistic inference over retrieved statement subset
        — belief propagation weighted by source credibility
    → LLM output synthesiser
        — renders result with confidence expression
        — traces provenance on request via derived_from[]
```

The LLM translates and renders. The reasoning is formal and auditable.

---

## Relationship to existing projects

| Project | Relation |
|---|---|
| **Wikidata** | Intended bootstrap source for factual content. Properties mapped via `source_predicate`. No probabilistic belief or fuzzy time natively. |
| **ConceptNet** | Source for ~18 of the 55 basis predicates. ConceptNet relations are shallow — no FOL definitions, temporal scope, or belief. |
| **OpenCyc / ResearchCyc** | Closest prior attempt at a general-purpose formal KB. Crisp logic only; idiosyncratic vocabulary; largely abandoned. |
| **ProbLog** | Intended inference engine. The schema is designed so retrieved statement subsets serialise naturally to ProbLog syntax. |
| **NELL** | Machine-learned KB; no formal predicate definitions, temporal scope, or user-controlled belief. |

---

## Contributing

Contributions welcome. Most useful at this stage:

- Review of the basis predicate set — redundancies, missing universals,
  argument type corrections
- A Python ingestion script (Wikidata SPARQL → statements inserts)
- A ProbLog serialiser (statement subset → ProbLog program)
- Domain-specific predicate and object sets (biology, law, mathematics)
- A test suite for `holds_at()`, `update_belief()`, and `update_trust()`
- An automated conflict detector that populates the `conflicts` table

Please open an issue before large structural changes to the schema — the
design decisions above are load-bearing and some apparent simplifications
break the probabilistic model.

---

## Repository structure

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
