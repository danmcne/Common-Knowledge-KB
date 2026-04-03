-- =============================================================
-- Common Knowledge KB — PostgreSQL Schema (v0.7)
-- =============================================================
--
-- CANONICAL POLICY DECISIONS
-- These five invariants are load-bearing. All schema design,
-- trigger logic, and inference code must respect them.
-- ─────────────────────────────────────────────────────────────
-- 1. OPEN-WORLD ASSUMPTION (default)
--    Absence of a statement does not imply falsity. holds_at()
--    defaults to 'open_world' mode: only positively supported
--    statements (effective_mean > p_threshold) are returned.
--    Absence of evidence is not evidence of absence.
--
-- 2. instance_of / is_a IS THE CANONICAL TYPE MECHANISM
--    instance_of statements are the authoritative source of type
--    membership. type_membership is a derived materialized cache,
--    populated automatically by trigger (trg_sync_type_membership)
--    on instance_of insert/update. Never assert type_membership
--    rows directly — they will be silently overwritten.
--    The subtype_of hierarchy is separate; transitive closure is
--    resolved at enforcement time via recursive CTE in the domain
--    check trigger (trg_z_soft_domain_check). Manual materialisation
--    of transitive is_a pairs is no longer required or recommended.
--
-- 3. fuzzy_time IS THE CANONICAL TIME REPRESENTATION
--    All temporal bounds are encoded in statement t_start / t_end
--    fuzzy_time fields. For ternary predicates such as
--    located_in(entity, place, time), the time position MUST use
--    the statement's own fuzzy_time fields, NOT a time-object arg.
--    The third object arg is reserved for named time periods
--    (e.g. "victorian_era") only when that period is genuinely
--    the semantic argument of the predicate. Bare year-objects
--    (e.g. "1815_birth_time") are a category error and must not
--    appear in examples or ingestion pipelines.
--    Scope sentinels: use no_scope for unscoped role arguments;
--    use no_period for ternary predicates (e.g. located_in) when
--    no named period is the semantic argument (Fix #23).
--
-- 4. CONFLICTS REPRESENT EVIDENTIAL OPPOSITION, NOT LOGICAL NEGATION
--    direct_negation in conflicts identifies statements that are
--    evidentially opposed. It does NOT mean one statement is the
--    logical negation of the other. True logical negation is resolved
--    at inference time by the reasoning layer using effective_mean
--    thresholds and CI bounds. There is no negated boolean on
--    statements (removed in v0.5).
--    Conflict severity (Fix #19) quantifies the CI gap; open conflicts
--    penalise effective_mean via statement_effective_belief (Fix #20).
--
-- 5. KERNEL STATEMENTS ARE CORRECTABLE BUT PROTECTED FROM PASSIVE DRIFT
--    system_kernel source has is_protected = true. update_trust()
--    requires p_override = true to modify kernel credibility. Kernel
--    facts can be corrected by deliberate human action but will not
--    drift from passive evidence accumulation.
-- ─────────────────────────────────────────────────────────────
--
-- Changes from v0.6:
--
--   STATEMENT KIND                                       [Fix #17]
--   • statement_kind column added to statements with enum values
--     ontological | empirical | statistical | rule. Defaults to
--     'empirical'. Structural predicates (subtype_of, disjoint_with)
--     default to 'ontological'; rule statements are tagged 'rule'
--     and are opaque to factual query functions. This resolves the
--     FOL-rule opacity problem from v0.6 and provides the foundation
--     for enforcing that statistical statements do not feed logical
--     inference chains (full enforcement in v0.8).
--
--   CONFLICT TEMPORAL GUARD                              [Fix #18]
--   • detect_conflicts self-join now requires temporal overlap before
--     comparing CIs. Two statements in completely non-overlapping time
--     windows are not in conflict. Uses tstzrange && operator.
--     Correctness fix: v0.6 incorrectly flagged temporally disjoint
--     statements as conflicting if their CIs did not overlap.
--
--   CONFLICT SEVERITY                                    [Fix #19]
--   • severity double precision column added to conflicts.
--     detect_conflicts populates it as the normalised CI gap:
--     GREATEST(b.ci_low - a.ci_high, a.ci_low - b.ci_high, 0).
--     Range [0, 1]; higher = more severe statistical incompatibility.
--     Feeds the conflict penalty in statement_effective_belief.
--
--   EFFECTIVE BELIEF VIEW                                [Fix #20]
--   • statement_effective_belief view added. Synthesises raw Beta
--     belief, source credibility, and open conflict severity into a
--     single effective_mean. holds_at() (open_world mode) and
--     tell_about() now filter and sort on effective_mean, closing
--     the conflict → belief feedback loop that was entirely absent
--     in v0.6.
--
--   LOG-ODDS COMBINATION FIX                             [Fix #21]
--   • compute_derived_belief log_odds mode was averaging log-odds
--     across parents (dividing by n), destroying the independence
--     signal. Fixed to accumulate (sum) log-odds increments from a
--     shared uniform prior. Two independent 90%-belief parents now
--     correctly yield a result meaningfully above 90%, not equal to
--     it. The / v_n division is removed; v_n is retained solely as
--     an empty-parent guard.
--
--   TRANSITIVE DOMAIN ENFORCEMENT                        [Fix #22]
--   • check_soft_domain_violations replaces its flat type_membership
--     lookup with a recursive CTE that resolves transitive subtype_of
--     chains at enforcement time. Predicates constraining args to
--     abstract types (e.g. animate) now correctly accept subtypes
--     (e.g. person → sapient → animate) without requiring manual
--     materialisation of every transitive is_a pair.
--   • trg_z_soft_domain_check now fires on INSERT OR UPDATE (was
--     INSERT only), closing the silent bypass where object_args could
--     be swapped to invalid values post-insertion.
--   • With transitive closure in place, the redundant manual is_a
--     rows for role subtypes in common_objects_kernel.sql Section 12
--     (e.g. is_a(mathematician, role)) should be removed in the next
--     objects kernel release. The subtype_of rows in Section 13 are
--     sufficient; the closure will find membership transitively.
--
--   NO_PERIOD SENTINEL                                   [Fix #23]
--   • no_period sentinel entity seeded. Use as the time_period arg
--     of located_in (and similar ternary predicates) when no named
--     period is the semantic argument. Distinct from no_scope, which
--     is restricted to role-scope arguments. no_scope description
--     updated to document this restriction explicitly.
--
--   INVERSE PREDICATE AUTOMATION                         [Fix #24]
--   • inverse_predicate_id uuid column added to predicates.
--     Seed obvious pairs (part_of ↔ has_part, before ↔ after) in
--     common_predicates_kernel.sql after both predicates exist.
--   • trg_zz_auto_inverse_statement trigger added on statements
--     INSERT. For binary predicates whose predicate has an
--     inverse_predicate_id, inserts the inverse statement as
--     forward_chained with a statement_dependencies row pointing to
--     the source. Prevents before(A,B) and after(A,B) from diverging
--     in belief without conflict detection.
--
--   TELL_ABOUT TEMPORAL FILTER                           [Fix #25]
--   • tell_about() gains optional p_time timestamptz DEFAULT NULL.
--     When supplied, filters to statements whose temporal scope
--     includes p_time, matching holds_at() semantics. When NULL,
--     returns all statements as before. Transforms tell_about from
--     a history dump into a "what is true about X right now?" query.
--
--   CONFLICT LOOKUP INDEX                                [Fix #26]
--   • idx_stmt_conflict_lookup composite index added on
--     (context_id, predicate_id, object_args) WHERE t_kind != 'eternal'.
--     Makes detect_conflicts self-join viable at scale. Prerequisite
--     for running detect_conflicts after bulk ingestion.
--
-- Carried forward from v0.6 (unchanged):
--
--   TYPING                                               [Fix #1]
--   INFERENCE                                            [Fix #2]
--   TIME REPRESENTATION                                  [Fix #3]
--   ONTOLOGY                                             [Fix #4]
--   SENTINEL (no_scope)                                  [Fix #5]
--   DERIVED BELIEF (structure)                           [Fix #6]
--   CREDIBILITY                                          [Fix #7]
--   CONFLICT SEMANTICS                                   [Fix #8]
--   CONFLICT DETECTION (CI-based)                        [Fix #9]
--   DOMAIN ENFORCEMENT (trigger structure)               [Fix #10]
--   PROVENANCE                                           [Fix #11]
--   DISJOINTNESS                                         [Fix #12]
--   API / QUERY (tell_about, why)                        [Fix #14, #15]
--   POLICY DECISIONS                                     [Fix #16]
--
-- =============================================================


-- ── Extensions ───────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";
CREATE EXTENSION IF NOT EXISTS "btree_gist";


-- ── Stable UUID helper ────────────────────────────────────────
-- Derives a deterministic UUID v4-shaped value from a text key.
-- The variant bits are fixed to '4xxx' (version 4) per the function
-- but do not set the variant octet correctly (a known RFC 4122 minor
-- deviation deferred to v0.8). Both overloads are IMMUTABLE for
-- index-friendliness.
CREATE OR REPLACE FUNCTION stable_uuid(p_key text)
RETURNS uuid LANGUAGE sql IMMUTABLE STRICT AS $$
    SELECT (
        substring(md5(p_key), 1,  8) || '-' ||
        substring(md5(p_key), 9,  4) || '-4' ||
        substring(md5(p_key), 14, 3) || '-' ||
        substring(md5(p_key), 17, 4) || '-' ||
        substring(md5(p_key), 21, 12)
    )::uuid;
$$;

CREATE OR REPLACE FUNCTION stable_uuid(p_name text, p_kind text)
RETURNS uuid LANGUAGE sql IMMUTABLE STRICT AS $$
    SELECT stable_uuid(p_name || ':' || p_kind);
$$;


-- ── Enums ─────────────────────────────────────────────────────

-- Coarse infrastructure kind only.
-- All domain-level typing lives in subtype_of / type_membership.
CREATE TYPE object_kind AS ENUM (
    'entity',       -- persons, institutions, concepts, events, quantities, etc.
    'predicate',    -- relation/property schema objects
    'context',      -- reasoning contexts (reality, domains, theories, fictions…)
    'source'        -- epistemic sources (users, databases, LLMs, …)
);

CREATE TYPE temporal_kind AS ENUM (
    'eternal',      -- true outside of time (mathematical facts, definitions)
    'always',       -- true for all of recorded/modeled time
    'interval',     -- true during [t_start, t_end)
    'point',        -- true at a single instant
    'default'       -- true until explicitly contradicted (open-world default)
);

CREATE TYPE time_granularity AS ENUM (
    'exact',
    'day',
    'month',
    'year',
    'decade',
    'century',
    'unknown'
);

CREATE TYPE predicate_status AS ENUM (
    'proposed',
    'confirmed',
    'deprecated'
);

-- How strictly predicate domain constraints are enforced.
-- hard → reject insert if domain constraint violated.
-- soft → insert + auto-record type_mismatch conflict for belief attenuation.
-- none → no domain enforcement.
CREATE TYPE domain_strictness AS ENUM (
    'hard',
    'soft',
    'none'
);

CREATE TYPE context_kind AS ENUM (
    'reality',
    'domain',
    'theory',
    'fiction',
    'hypothetical',
    'game'
);

CREATE TYPE derivation_type AS ENUM (
    'axiomatic',
    'user_asserted',
    'source_ingested',
    'forward_chained',
    'abduced',
    'learned'
);

-- [Fix #8] IMPORTANT SEMANTIC CLARIFICATION:
-- direct_negation means two statements are EVIDENTIALLY OPPOSED —
-- i.e. the sources and belief distributions for each pull against the
-- other. It does NOT mean one statement is the logical complement of
-- the other. True logical negation (¬P(a)) is resolved at inference
-- time by the reasoning layer using effective_mean thresholds and CI
-- bounds. Inserting a direct_negation conflict registers the tension
-- for the reasoner; it does not itself constitute a logical proof.
CREATE TYPE conflict_kind AS ENUM (
    'direct_negation',    -- evidential opposition between two competing statements
    'mutual_exclusion',   -- at most one of a set can hold
    'type_violation',     -- argument fails a hard domain constraint (insert rejected)
    'type_mismatch',      -- argument fails a soft domain constraint (conflict recorded)
    'temporal_overlap',   -- two interval statements overlap impossibly
    'value_conflict'      -- literal values are mutually inconsistent
);

-- Epistemic interpretation tag on statements.
-- Prevents silent category errors when modeling conventions differ
-- from ontology.
CREATE TYPE statement_interpretation AS ENUM (
    'ontological',    -- genuine ontological claim
    'modeling',       -- convenient modeling assumption (e.g. "AI is an agent")
    'legal_fiction',  -- legally or conventionally true, not ontologically
    'metaphorical'    -- figurative / analogical
);

-- [Fix #17] Epistemic KIND of a statement — governs inference chain participation.
-- ontological : type-hierarchy and definitional claims (subtype_of, disjoint_with,
--               equivalent_to). May participate in logical inference chains.
-- empirical   : factual claims about the world (is_a, has_role, located_in, etc.).
--               May participate in inference chains alongside ontological parents.
-- statistical : probabilistic patterns without individual-level force (typical_of,
--               correlated_with). Must NOT feed logical inference chains; use only
--               for probabilistic reasoning layers. Enforcement: v0.8.
-- rule        : encoded inference rule stored as a statement. Opaque to all factual
--               query functions (holds_at, tell_about). Queryable by kind.
--
-- Default: 'empirical'. Structural predicates (subtype_of, disjoint_with) should
-- be inserted with statement_kind = 'ontological'.
CREATE TYPE statement_kind AS ENUM (
    'ontological',
    'empirical',
    'statistical',
    'rule'
);


-- ── Composite type: fuzzy timestamp ──────────────────────────
-- best: Julian Day Number of the central estimate
-- lo/hi: Julian Day Numbers of the uncertainty bounds
-- granularity: precision of the best estimate
--
-- [Fix #3] CANONICAL TIME POLICY:
-- This is the ONLY mechanism for encoding temporal bounds on statements.
-- For ternary predicates such as located_in(entity, place, time), encode
-- the temporal scope in the statement's t_start / t_end fuzzy_time fields.
-- The third object arg is reserved for a named time PERIOD (e.g.
-- "victorian_era") only when that period is the genuine semantic argument.
-- When no named period is the semantic argument, use the no_period sentinel
-- (Fix #23). Bare year-objects (e.g. "1815_birth_time") are a category
-- error: they conflate a named object with a time coordinate.
CREATE TYPE fuzzy_time AS (
    best        double precision,   -- JD central estimate
    lo          double precision,   -- JD lower bound
    hi          double precision,   -- JD upper bound
    granularity time_granularity
);

CREATE OR REPLACE FUNCTION year_to_jd(y integer)
RETURNS double precision LANGUAGE sql IMMUTABLE AS $$
    SELECT 365.25 * (y + 4716) - 1524.5;
$$;

CREATE OR REPLACE FUNCTION jd_to_tstz(jd double precision)
RETURNS timestamptz LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN jd IS NULL      THEN NULL
        WHEN jd < 1721425.5  THEN '0001-01-01 00:00:00+00'::timestamptz
        WHEN jd > 5373484.5  THEN '9999-12-31 23:59:59+00'::timestamptz
        ELSE to_timestamp((jd - 2440587.5) * 86400.0)
    END;
$$;


-- ── updated_at trigger ────────────────────────────────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;


-- =============================================================
-- CORE TABLES
-- =============================================================

-- ── Objects ───────────────────────────────────────────────────
-- Unified namespace for every named entity in the KB.
-- Fine-grained typing is expressed via type_membership (derived from
-- instance_of statements) and subtype_of statements, NOT via kind.
CREATE TABLE objects (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    kind            object_kind NOT NULL,
    canonical_name  text        NOT NULL,
    display_name    text,
    aliases         text[]      NOT NULL DEFAULT '{}',
    description     text,
    embedding       vector(768),
    external_ids    jsonb,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT canonical_name_kind_unique UNIQUE (canonical_name, kind)
);

CREATE INDEX idx_objects_kind      ON objects (kind);
CREATE INDEX idx_objects_aliases   ON objects USING GIN (aliases);
CREATE INDEX idx_objects_external  ON objects USING GIN (external_ids);
CREATE INDEX idx_objects_embedding ON objects USING hnsw (embedding vector_cosine_ops);

CREATE TRIGGER trg_objects_updated_at
    BEFORE UPDATE ON objects
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ── Predicate metadata ────────────────────────────────────────
CREATE TABLE predicates (
    id                uuid               PRIMARY KEY
                           REFERENCES objects (id) ON DELETE CASCADE,
    arity             int                NOT NULL CHECK (arity BETWEEN 1 AND 8),
    -- arg_labels: human-readable role names per position
    arg_labels        text[],
    -- arg_type_ids: expected type object IDs per position.
    -- Enforcement follows domain_strictness: hard rejects the insert;
    -- soft inserts and records a type_mismatch conflict.
    arg_type_ids      uuid[],
    -- [Fix #24] Inverse predicate for automatic symmetric assertion.
    -- When set, inserting a binary statement with this predicate will
    -- automatically insert the inverse statement (args reversed) as a
    -- forward_chained statement via trg_zz_auto_inverse_statement.
    -- Seed pairs in common_predicates_kernel.sql after both predicates
    -- are defined (e.g. part_of ↔ has_part, before ↔ after).
    inverse_predicate_id uuid            REFERENCES objects (id),
    fol_definition    text,
    nl_description    text,
    source_predicate  text,
    is_basis          boolean            NOT NULL DEFAULT false,
    domain_strictness domain_strictness  NOT NULL DEFAULT 'soft',
    status            predicate_status   NOT NULL DEFAULT 'proposed',
    introduced_by     uuid               REFERENCES objects (id),
    introduced_at     timestamptz        NOT NULL DEFAULT now()
);

CREATE INDEX idx_predicates_basis    ON predicates (is_basis) WHERE is_basis;
CREATE INDEX idx_predicates_status   ON predicates (status);
CREATE INDEX idx_predicates_inverse  ON predicates (inverse_predicate_id)
    WHERE inverse_predicate_id IS NOT NULL;


-- ── Context metadata ──────────────────────────────────────────
-- Tree structure (parent_id). DAG generalisation deferred to v0.8+
-- when multi-parent context inheritance is concretely needed.
CREATE TABLE contexts (
    id          uuid         PRIMARY KEY
                    REFERENCES objects (id) ON DELETE CASCADE,
    kind        context_kind NOT NULL DEFAULT 'reality',
    parent_id   uuid         REFERENCES contexts (id),
    description text
);


-- ── Orphan-guard triggers ─────────────────────────────────────
CREATE OR REPLACE FUNCTION guard_predicate_object()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.kind = 'predicate' THEN
        IF NOT EXISTS (SELECT 1 FROM predicates WHERE id = NEW.id) THEN
            RAISE EXCEPTION
                'objects row with kind=''predicate'' requires a matching predicates row (id=%)',
                NEW.id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION guard_context_object()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.kind = 'context' THEN
        IF NOT EXISTS (SELECT 1 FROM contexts WHERE id = NEW.id) THEN
            RAISE EXCEPTION
                'objects row with kind=''context'' requires a matching contexts row (id=%)',
                NEW.id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_guard_predicate_object
    AFTER INSERT ON objects
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION guard_predicate_object();

CREATE CONSTRAINT TRIGGER trg_guard_context_object
    AFTER INSERT ON objects
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION guard_context_object();


-- ── Statements ───────────────────────────────────────────────
-- Ground atoms with belief, time, context, and derivation metadata.
--
-- Negation policy (v0.5+, unchanged):
--   The negated boolean has been removed. Logical negation and evidential
--   opposition are expressed via the conflicts table with conflict_kind =
--   'direct_negation'. Two competing statements P(a) and its evidential
--   opposite are stored as two positive statements; their conflict is
--   registered explicitly and the reasoner weighs them by effective_mean.
--
-- Argument caching policy:
--   object_args and literal_args are denormalized caches for fast
--   tuple-matching. The authoritative normalized form is statement_args.
--   Trigger trg_sync_statement_args keeps them consistent.
--
-- Provenance policy (v0.6+):                             [Fix #11]
--   derived_from uuid[] is a fast cache of parent statement IDs.
--   The authoritative provenance record is statement_dependencies.
--   For forward_chained and abduced statements, at least one
--   statement_dependencies row must exist by commit time (enforced by
--   the DEFERRABLE trigger trg_enforce_provenance).
--
-- Statement kind policy (v0.7):                          [Fix #17]
--   statement_kind governs inference chain participation. See enum
--   definition above. Structural statements (subtype_of, disjoint_with)
--   must be inserted with statement_kind = 'ontological'. Rule statements
--   use statement_kind = 'rule'. All other facts default to 'empirical'.
CREATE TABLE statements (
    id               uuid                     PRIMARY KEY DEFAULT gen_random_uuid(),
    predicate_id     uuid                     NOT NULL REFERENCES objects (id),

    -- Denormalized argument cache (authoritative: statement_args)
    object_args      uuid[]                   NOT NULL DEFAULT '{}',
    literal_args     jsonb                    NOT NULL DEFAULT '[]'
                         CHECK (jsonb_typeof(literal_args) = 'array'),

    -- Belief: Beta(alpha, beta) distribution over truth
    belief_alpha     double precision         NOT NULL DEFAULT 1.0
                         CHECK (belief_alpha > 0),
    belief_beta      double precision         NOT NULL DEFAULT 1.0
                         CHECK (belief_beta  > 0),
    belief_mean      double precision         GENERATED ALWAYS AS (
                         belief_alpha / (belief_alpha + belief_beta)
                     ) STORED,

    interpretation   statement_interpretation NOT NULL DEFAULT 'ontological',

    -- [Fix #17] Epistemic kind — governs inference chain participation.
    -- Defaults to 'empirical'. Use 'ontological' for structural predicates
    -- (subtype_of, disjoint_with, equivalent_to). Use 'rule' for stored
    -- inference rules. Use 'statistical' for pattern/correlation claims.
    statement_kind   statement_kind           NOT NULL DEFAULT 'empirical',

    -- Temporal scope
    -- [Fix #3] Encode ALL temporal bounds here. Do not create time-object
    -- args. See canonical policy decision #3 and fuzzy_time comment above.
    t_kind           temporal_kind            NOT NULL DEFAULT 'default',
    t_start          fuzzy_time,
    t_end            fuzzy_time,
    t_start_ts       timestamptz              GENERATED ALWAYS AS (
                         jd_to_tstz((t_start).best)
                     ) STORED,
    t_end_ts         timestamptz              GENERATED ALWAYS AS (
                         jd_to_tstz((t_end).best)
                     ) STORED,

    context_id       uuid                     NOT NULL REFERENCES objects (id),

    -- Provenance
    derivation_type  derivation_type          NOT NULL DEFAULT 'user_asserted',
    derivation_depth int                      NOT NULL DEFAULT 0
                         CHECK (derivation_depth >= 0),
    -- [Fix #11] Denormalized cache only. Authoritative: statement_dependencies.
    -- For forward_chained/abduced statements, this array is kept in sync with
    -- the dependency graph. Do not populate independently.
    derived_from     uuid[]                   NOT NULL DEFAULT '{}',

    created_at       timestamptz              NOT NULL DEFAULT now(),
    updated_at       timestamptz              NOT NULL DEFAULT now(),

    CONSTRAINT args_nonempty CHECK (
        cardinality(object_args) >= 1
        OR jsonb_array_length(literal_args) >= 1
    )
);

CREATE INDEX idx_stmt_predicate      ON statements (predicate_id);
CREATE INDEX idx_stmt_context        ON statements (context_id);
CREATE INDEX idx_stmt_t_kind         ON statements (t_kind);
CREATE INDEX idx_stmt_deriv_type     ON statements (derivation_type);
CREATE INDEX idx_stmt_belief_mean    ON statements (belief_mean DESC);
CREATE INDEX idx_stmt_object_args    ON statements USING GIN (object_args);
CREATE INDEX idx_stmt_derived_from   ON statements USING GIN (derived_from);
CREATE INDEX idx_stmt_interp         ON statements (interpretation);
CREATE INDEX idx_stmt_kind           ON statements (statement_kind);

CREATE INDEX idx_stmt_temporal_range ON statements USING GIST (
    tstzrange(
        coalesce(t_start_ts, '-infinity'::timestamptz),
        coalesce(t_end_ts,   'infinity'::timestamptz),
        '[)'
    )
) WHERE t_kind IN ('interval', 'point');

CREATE INDEX idx_stmt_eternal ON statements (predicate_id)
    WHERE t_kind = 'eternal';

-- [Fix #26] Composite index for detect_conflicts self-join.
-- Covers the (context_id, predicate_id, object_args) lookup that the
-- conflict detection self-join performs. Restricted to non-eternal
-- statements because eternal statements carry their own lightweight index
-- above, and the temporal overlap guard (Fix #18) separates the paths.
CREATE INDEX idx_stmt_conflict_lookup
    ON statements (context_id, predicate_id, object_args)
    WHERE t_kind != 'eternal';

CREATE TRIGGER trg_statements_updated_at
    BEFORE UPDATE ON statements
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ── Normalized argument table ─────────────────────────────────
-- Authoritative per-position argument store.
-- object_id XOR literal_value must be non-null (enforced by CHECK).
-- position is 0-based, must be < predicate arity (enforced by trigger).
CREATE TABLE statement_args (
    statement_id  uuid  NOT NULL REFERENCES statements (id) ON DELETE CASCADE,
    position      int   NOT NULL CHECK (position >= 0),
    object_id     uuid  REFERENCES objects (id),
    literal_value jsonb,
    PRIMARY KEY (statement_id, position),
    CONSTRAINT arg_xor CHECK (
        (object_id IS NOT NULL)::int +
        (literal_value IS NOT NULL)::int = 1
    )
);

CREATE INDEX idx_sargs_object ON statement_args (object_id) WHERE object_id IS NOT NULL;
CREATE INDEX idx_sargs_stmt   ON statement_args (statement_id);


-- =============================================================
-- SUPPORTING TABLES
-- (defined before trigger functions that INSERT into them)
-- =============================================================

-- ── Attestations ─────────────────────────────────────────────
-- Records which sources support which statements, and with what weight.
-- evidence_group_id groups attestations that are not independent
-- (same underlying study, same author, etc.) to prevent double-counting.
-- [Fix #7] The statement_credibility view enforces that each
-- evidence_group_id contributes at most its single highest-weight
-- attestation to the credibility sum. See view definition below.
CREATE TABLE attestations (
    id                uuid             PRIMARY KEY DEFAULT gen_random_uuid(),
    statement_id      uuid             NOT NULL REFERENCES statements (id) ON DELETE CASCADE,
    source_id         uuid             NOT NULL REFERENCES objects (id),
    evidence_group_id uuid,
    confidence_weight double precision NOT NULL DEFAULT 1.0
                          CHECK (confidence_weight BETWEEN 0.0 AND 1.0),
    raw_claim         text,
    url               text,
    accessed_at       timestamptz,
    created_at        timestamptz      NOT NULL DEFAULT now()
);

CREATE INDEX idx_attest_statement      ON attestations (statement_id);
CREATE INDEX idx_attest_source         ON attestations (source_id);
CREATE INDEX idx_attest_evidence_group ON attestations (evidence_group_id)
    WHERE evidence_group_id IS NOT NULL;


-- ── Source credibility ────────────────────────────────────────
-- Beta(alpha, beta) credibility distribution per (source, context).
-- is_protected: if true, update_trust() requires p_override = true.
--   Used for system_kernel and other near-axiomatic sources.
CREATE TABLE source_credibility (
    source_id    uuid             NOT NULL REFERENCES objects (id),
    context_id   uuid             NOT NULL REFERENCES objects (id),
    alpha        double precision NOT NULL DEFAULT 1.0 CHECK (alpha > 0),
    beta         double precision NOT NULL DEFAULT 1.0 CHECK (beta  > 0),
    is_protected boolean          NOT NULL DEFAULT false,
    updated_at   timestamptz      NOT NULL DEFAULT now(),
    PRIMARY KEY (source_id, context_id)
);


-- ── Statement dependencies ────────────────────────────────────
-- Authoritative provenance graph. Records (parent → child) derivation
-- edges with the rule applied and dependency weight.
-- Use for belief propagation (compute_derived_belief), explanation
-- graphs (why()), and audit trails.
-- derived_from on statements is maintained as a fast cache of parent IDs.
CREATE TABLE statement_dependencies (
    parent_id    uuid             NOT NULL REFERENCES statements (id) ON DELETE CASCADE,
    child_id     uuid             NOT NULL REFERENCES statements (id) ON DELETE CASCADE,
    rule_name    text,
    weight       double precision NOT NULL DEFAULT 1.0 CHECK (weight > 0),
    created_at   timestamptz      NOT NULL DEFAULT now(),
    PRIMARY KEY (parent_id, child_id)
);

CREATE INDEX idx_sdep_child  ON statement_dependencies (child_id);
CREATE INDEX idx_sdep_parent ON statement_dependencies (parent_id);


-- ── Predicate subsumption ─────────────────────────────────────
CREATE TABLE predicate_subsumption (
    child_id    uuid             NOT NULL REFERENCES objects (id),
    parent_id   uuid             NOT NULL REFERENCES objects (id),
    alpha       double precision NOT NULL DEFAULT 1.0 CHECK (alpha > 0),
    beta        double precision NOT NULL DEFAULT 1.0 CHECK (beta  > 0),
    context_id  uuid             REFERENCES objects (id),
    PRIMARY KEY (child_id, parent_id)
);


-- ── Type membership ───────────────────────────────────────────
-- [Fix #1] Derived cache of instance_of / is_a statements.
-- INVARIANT: Never assert rows here directly. This table is populated
-- and kept in sync exclusively by trg_sync_type_membership, which fires
-- on INSERT/UPDATE of instance_of and is_a statements.
-- Querying type_membership reflects all committed instance_of assertions
-- but NOT transitive closure via subtype_of.
-- [Fix #22] Transitive closure is resolved at enforcement time by
-- check_soft_domain_violations via recursive CTE over subtype_of
-- statements. Manual materialisation of every transitive is_a pair
-- is no longer required; role-subtype is_a rows in the objects kernel
-- Section 12 should be removed once the kernel is regenerated.
-- Direct assertions will be silently overwritten on the next trigger fire
-- for the same (object_id, type_id) pair.
CREATE TABLE type_membership (
    object_id   uuid             NOT NULL REFERENCES objects (id),
    type_id     uuid             NOT NULL REFERENCES objects (id),
    alpha       double precision NOT NULL DEFAULT 1.0 CHECK (alpha > 0),
    beta        double precision NOT NULL DEFAULT 1.0 CHECK (beta  > 0),
    context_id  uuid             REFERENCES objects (id),
    PRIMARY KEY (object_id, type_id)
);

CREATE INDEX idx_typemem_type   ON type_membership (type_id);
CREATE INDEX idx_typemem_object ON type_membership (object_id);


-- ── Conflicts ─────────────────────────────────────────────────
-- Records detected conflicts between statements.
-- [Fix #8] direct_negation = evidential opposition, not logical negation.
--   See conflict_kind enum comment for full semantics.
-- [Fix #19] severity: normalised CI gap in [0, 1]. NULL for conflicts
--   recorded before v0.7 or for non-direct_negation conflict kinds.
--   Populated by detect_conflicts() as:
--     GREATEST(b.ci_low - a.ci_high, a.ci_low - b.ci_high, 0)
--   Used by statement_effective_belief to penalise effective_mean:
--     effective_mean = belief_mean * (1 - max_open_conflict_severity)
-- type_mismatch conflicts may be self-referential (statement_a = statement_b)
--   when a single statement violates a soft domain constraint; there is no
--   opposing statement, only the violated constraint. The resolution_note
--   records which argument and expected type were mismatched.
CREATE TABLE conflicts (
    id              uuid             PRIMARY KEY DEFAULT gen_random_uuid(),
    statement_a     uuid             NOT NULL REFERENCES statements (id),
    statement_b     uuid             NOT NULL REFERENCES statements (id),
    conflict_kind   conflict_kind,
    -- [Fix #19] severity: normalised CI gap; range [0, 1].
    -- NULL for non-direct_negation kinds or pre-v0.7 records.
    severity        double precision CHECK (severity IS NULL OR severity BETWEEN 0.0 AND 1.0),
    resolved        boolean          NOT NULL DEFAULT false,
    resolution_note text,
    created_at      timestamptz      NOT NULL DEFAULT now()
);

CREATE INDEX idx_conflicts_a        ON conflicts (statement_a);
CREATE INDEX idx_conflicts_b        ON conflicts (statement_b);
CREATE INDEX idx_conflicts_resolved ON conflicts (resolved) WHERE NOT resolved;
CREATE INDEX idx_conflicts_severity ON conflicts (severity DESC)
    WHERE resolved = false AND severity IS NOT NULL;


-- ── Object equivalence ────────────────────────────────────────
-- Probabilistic same-as links for entity resolution.
CREATE TABLE object_equivalence (
    object_a   uuid             NOT NULL REFERENCES objects (id),
    object_b   uuid             NOT NULL REFERENCES objects (id),
    alpha      double precision NOT NULL DEFAULT 1.0 CHECK (alpha > 0),
    beta       double precision NOT NULL DEFAULT 1.0 CHECK (beta  > 0),
    context_id uuid             REFERENCES objects (id),
    PRIMARY KEY (object_a, object_b),
    CONSTRAINT equiv_no_self     CHECK (object_a <> object_b),
    CONSTRAINT equiv_canonical   CHECK (object_a < object_b)
);

CREATE INDEX idx_equiv_b ON object_equivalence (object_b);


-- =============================================================
-- TRIGGER FUNCTIONS
-- =============================================================

-- ── Statement arg validation ──────────────────────────────────
-- Validates arity and duplicate literal positions on INSERT/UPDATE.
-- Hard domain violations are caught here (raise exception).
-- Soft domain violations are handled by trg_z_soft_domain_check (AFTER).
CREATE OR REPLACE FUNCTION validate_statement_args()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_arity    int;
    v_total    int;
    v_dup_pos  int;
BEGIN
    SELECT arity INTO v_arity FROM predicates WHERE id = NEW.predicate_id;

    IF v_arity IS NULL THEN
        RAISE EXCEPTION 'predicate % not found in predicates table', NEW.predicate_id;
    END IF;

    v_total := cardinality(NEW.object_args) + jsonb_array_length(NEW.literal_args);

    IF v_total != v_arity THEN
        RAISE EXCEPTION
            'argument count mismatch: predicate arity=%, got object_args=% + literal_args=%',
            v_arity, cardinality(NEW.object_args), jsonb_array_length(NEW.literal_args);
    END IF;

    SELECT count(*) INTO v_dup_pos
    FROM (
        SELECT elem->>'pos'
        FROM jsonb_array_elements(NEW.literal_args) AS elem
        GROUP BY elem->>'pos'
        HAVING count(*) > 1
    ) dups;

    IF v_dup_pos > 0 THEN
        RAISE EXCEPTION 'literal_args contains duplicate pos values';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_statement_args
    BEFORE INSERT OR UPDATE ON statements
    FOR EACH ROW EXECUTE FUNCTION validate_statement_args();


-- ── Sync trigger: statements → statement_args ─────────────────
CREATE OR REPLACE FUNCTION sync_statement_args()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_pos     int;
    v_elem    jsonb;
    v_lit_pos int;
BEGIN
    DELETE FROM statement_args WHERE statement_id = NEW.id;

    FOR v_pos IN 1 .. cardinality(NEW.object_args) LOOP
        INSERT INTO statement_args (statement_id, position, object_id)
        VALUES (NEW.id, v_pos - 1, NEW.object_args[v_pos]);
    END LOOP;

    FOR v_pos IN 0 .. jsonb_array_length(NEW.literal_args) - 1 LOOP
        v_elem    := NEW.literal_args -> v_pos;
        v_lit_pos := COALESCE((v_elem->>'pos')::int,
                              cardinality(NEW.object_args) + v_pos);
        INSERT INTO statement_args (statement_id, position, literal_value)
        VALUES (NEW.id, v_lit_pos, v_elem);
    END LOOP;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_statement_args
    AFTER INSERT OR UPDATE ON statements
    FOR EACH ROW EXECUTE FUNCTION sync_statement_args();


-- ── [Fix #1] Type membership sync: instance_of → type_membership ─
-- Fires after any statement insert/update. If the predicate is
-- instance_of or is_a (matched by stable_uuid), populates or updates
-- the corresponding type_membership row.
-- This is the SOLE write path for type_membership. Do not INSERT into
-- type_membership directly; those rows will be overwritten here.
--
-- Note on ordering within transactions: if both instance_of statements
-- and other statements are inserted in the same transaction, ensure
-- instance_of statements are inserted first so that type_membership is
-- populated before soft domain checks (trg_z_soft_domain_check) fire on
-- subsequent statements.
CREATE OR REPLACE FUNCTION sync_type_membership_from_is_a()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    -- Only fire for instance_of or is_a predicates.
    -- stable_uuid is IMMUTABLE so this comparison is index-friendly.
    IF NEW.predicate_id NOT IN (
        stable_uuid('instance_of', 'predicate'),
        stable_uuid('is_a',        'predicate')
    ) THEN
        RETURN NEW;
    END IF;

    -- Expect binary predicate: instance_of(object, type)
    IF cardinality(NEW.object_args) < 2 THEN
        RETURN NEW;
    END IF;

    INSERT INTO type_membership (object_id, type_id, alpha, beta, context_id)
    VALUES (
        NEW.object_args[1],
        NEW.object_args[2],
        NEW.belief_alpha,
        NEW.belief_beta,
        NEW.context_id
    )
    ON CONFLICT (object_id, type_id) DO UPDATE
        SET alpha      = EXCLUDED.alpha,
            beta       = EXCLUDED.beta,
            context_id = EXCLUDED.context_id;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_type_membership
    AFTER INSERT OR UPDATE ON statements
    FOR EACH ROW EXECUTE FUNCTION sync_type_membership_from_is_a();


-- ── [Fix #10 / Fix #22] Soft domain violation check ──────────
-- Fires AFTER INSERT OR UPDATE on statements. Checks each object argument
-- against the predicate's arg_type_ids.
--
-- [Fix #22] TRANSITIVE CLOSURE: type membership is resolved via a
-- recursive CTE over subtype_of statements rather than a flat lookup
-- in type_membership. This correctly accepts entities that satisfy a
-- type constraint through inheritance (e.g. person → sapient → animate)
-- without requiring every transitive is_a pair to be manually materialised.
-- The CTE starts from direct type_membership rows and extends through
-- high-belief (> 0.9) subtype_of statements.
--
-- Hard violations raise an exception (insert rejected).
-- Soft violations insert a type_mismatch conflict with statement_a =
-- statement_b = the offending statement, plus a description in
-- resolution_note. The statement is allowed through for belief
-- attenuation by the reasoning layer.
--
-- [Fix #22] Extended to fire on INSERT OR UPDATE (was INSERT only in
-- v0.6). Prevents silent bypass where object_args were swapped to
-- invalid values after initial insertion.
CREATE OR REPLACE FUNCTION check_soft_domain_violations()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_arg_type_ids    uuid[];
    v_strictness      domain_strictness;
    v_pos             int;
    v_expected_type   uuid;
    v_actual_obj      uuid;
    v_type_ok         boolean;
BEGIN
    SELECT p.arg_type_ids, p.domain_strictness
    INTO v_arg_type_ids, v_strictness
    FROM predicates p
    WHERE p.id = NEW.predicate_id;

    -- No enforcement if no type constraints defined or strictness is none
    IF v_arg_type_ids IS NULL OR v_strictness = 'none' THEN
        RETURN NEW;
    END IF;

    FOR v_pos IN 1 .. cardinality(NEW.object_args) LOOP
        v_expected_type := v_arg_type_ids[v_pos];
        v_actual_obj    := NEW.object_args[v_pos];

        CONTINUE WHEN v_expected_type IS NULL;

        -- [Fix #22] Resolve type membership transitively via subtype_of.
        -- Starts from direct type_membership cache rows, then follows
        -- high-confidence subtype_of edges to find inherited memberships.
        -- This handles predicate constraints on abstract types (e.g. animate)
        -- when the object is a concrete subtype (e.g. person).
        WITH RECURSIVE type_closure AS (
            -- Seed: direct memberships already in the flat cache
            SELECT tm.object_id, tm.type_id
            FROM type_membership tm
            WHERE tm.object_id = v_actual_obj
              AND (tm.alpha / (tm.alpha + tm.beta)) > 0.5

            UNION

            -- Extension: follow subtype_of edges from types already in closure
            SELECT tc.object_id, s.object_args[2]
            FROM type_closure tc
            JOIN statements s
              ON s.object_args[1] = tc.type_id
             AND s.predicate_id   = stable_uuid('subtype_of', 'predicate')
             AND s.belief_mean    > 0.9
        )
        SELECT EXISTS (
            SELECT 1 FROM type_closure WHERE type_id = v_expected_type
        ) INTO v_type_ok;

        IF NOT v_type_ok THEN
            IF v_strictness = 'hard' THEN
                RAISE EXCEPTION
                    'Hard domain violation on statement %: arg at position % (object %) '
                    'is not a confirmed member of expected type % '
                    '(checked transitively via subtype_of)',
                    NEW.id, v_pos - 1, v_actual_obj, v_expected_type;
            ELSIF v_strictness = 'soft' THEN
                -- Self-referential type_mismatch conflict (one statement, no opposing statement).
                -- statement_a = statement_b = the offending statement.
                -- The resolution_note carries the diagnostic detail.
                INSERT INTO conflicts (
                    statement_a, statement_b, conflict_kind, resolution_note
                )
                VALUES (
                    NEW.id,
                    NEW.id,
                    'type_mismatch',
                    format(
                        'Soft domain violation: arg at position %s (object %s) '
                        'is not a confirmed member of expected type %s '
                        '(checked transitively via subtype_of)',
                        v_pos - 1, v_actual_obj, v_expected_type
                    )
                );
            END IF;
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

-- Named trg_z_soft_domain_check so it sorts alphabetically AFTER
-- trg_sync_type_membership. PostgreSQL fires AFTER triggers in
-- alphabetical order; sync must populate type_membership before the
-- domain check reads from it.
-- [Fix #22] Fires on INSERT OR UPDATE (was INSERT only in v0.6).
CREATE TRIGGER trg_z_soft_domain_check
    AFTER INSERT OR UPDATE ON statements
    FOR EACH ROW EXECUTE FUNCTION check_soft_domain_violations();


-- ── [Fix #11] Provenance enforcement ─────────────────────────
-- DEFERRABLE INITIALLY DEFERRED constraint trigger.
-- At commit time, verifies that any forward_chained or abduced
-- statement has at least one statement_dependencies row.
-- This enforces statement_dependencies as the authoritative provenance
-- record. Insert dependency rows in the same transaction as the
-- derived statement; the check fires at COMMIT.
CREATE OR REPLACE FUNCTION enforce_provenance_dependencies()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.derivation_type IN ('forward_chained', 'abduced') THEN
        IF NOT EXISTS (
            SELECT 1 FROM statement_dependencies WHERE child_id = NEW.id
        ) THEN
            RAISE EXCEPTION
                'Provenance violation: statement % has derivation_type=% but no '
                'statement_dependencies rows exist. Insert at least one dependency '
                'row in the same transaction before commit.',
                NEW.id, NEW.derivation_type;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_enforce_provenance
    AFTER INSERT ON statements
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION enforce_provenance_dependencies();


-- ── [Fix #24] Inverse predicate automation ───────────────────
-- Fires AFTER INSERT on statements. For binary statements whose
-- predicate has an inverse_predicate_id set, automatically inserts the
-- inverse statement (arguments reversed) as a forward_chained statement,
-- and records the derivation edge in statement_dependencies.
--
-- Recursion safety: the inverse statement will trigger this function too.
-- The EXISTS check prevents re-insertion of the original, so recursion
-- terminates after at most two levels (original → inverse → stop).
--
-- Arity restriction: inverse automation applies only to binary predicates
-- (object_args length = 2). Higher-arity inverses require explicit handling.
--
-- Named trg_zz_auto_inverse_statement to sort alphabetically AFTER both
-- trg_sync_type_membership and trg_z_soft_domain_check, ensuring type
-- membership and domain checks have fired for the source statement before
-- the inverse is derived from it.
CREATE OR REPLACE FUNCTION auto_insert_inverse_statement()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_inverse_pred_id uuid;
    v_inverse_stmt_id uuid;
BEGIN
    -- Only handle binary statements (arity = 2 object args)
    IF cardinality(NEW.object_args) != 2 THEN
        RETURN NEW;
    END IF;

    -- Look up inverse predicate for this predicate
    SELECT p.inverse_predicate_id INTO v_inverse_pred_id
    FROM predicates p
    WHERE p.id = NEW.predicate_id;

    IF v_inverse_pred_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Skip if the inverse statement already exists in this context.
    -- This terminates the recursion: when the inverse fires this trigger,
    -- the original statement already exists and this check short-circuits.
    IF EXISTS (
        SELECT 1 FROM statements s
        WHERE s.predicate_id = v_inverse_pred_id
          AND s.object_args  = ARRAY[NEW.object_args[2], NEW.object_args[1]]
          AND s.context_id   = NEW.context_id
    ) THEN
        RETURN NEW;
    END IF;

    -- Insert the inverse statement. Copies belief, interpretation, temporal
    -- scope, and statement_kind from the source. Derivation is forward_chained
    -- with depth = source depth + 1.
    INSERT INTO statements (
        predicate_id,
        object_args,
        belief_alpha,
        belief_beta,
        interpretation,
        statement_kind,
        t_kind,
        t_start,
        t_end,
        context_id,
        derivation_type,
        derivation_depth,
        derived_from
    )
    VALUES (
        v_inverse_pred_id,
        ARRAY[NEW.object_args[2], NEW.object_args[1]],
        NEW.belief_alpha,
        NEW.belief_beta,
        NEW.interpretation,
        NEW.statement_kind,
        NEW.t_kind,
        NEW.t_start,
        NEW.t_end,
        NEW.context_id,
        'forward_chained',
        NEW.derivation_depth + 1,
        ARRAY[NEW.id]
    )
    RETURNING id INTO v_inverse_stmt_id;

    -- Record the provenance edge. This satisfies trg_enforce_provenance
    -- (DEFERRABLE INITIALLY DEFERRED) by commit time.
    INSERT INTO statement_dependencies (parent_id, child_id, rule_name, weight)
    VALUES (NEW.id, v_inverse_stmt_id, 'inverse_predicate', 1.0);

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_zz_auto_inverse_statement
    AFTER INSERT ON statements
    FOR EACH ROW EXECUTE FUNCTION auto_insert_inverse_statement();


-- =============================================================
-- VIEWS
-- =============================================================

CREATE VIEW statement_belief AS
SELECT
    id,
    belief_alpha,
    belief_beta,
    belief_mean,
    belief_alpha + belief_beta                                AS evidence_strength,
    (belief_alpha * belief_beta)
        / (pow(belief_alpha + belief_beta, 2)
           * (belief_alpha + belief_beta + 1))                AS variance,
    GREATEST(0,
        belief_mean - 1.96 * sqrt(
            (belief_alpha * belief_beta)
            / (pow(belief_alpha + belief_beta, 2)
               * (belief_alpha + belief_beta + 1))
        )
    )                                                         AS ci_low,
    LEAST(1,
        belief_mean + 1.96 * sqrt(
            (belief_alpha * belief_beta)
            / (pow(belief_alpha + belief_beta, 2)
               * (belief_alpha + belief_beta + 1))
        )
    )                                                         AS ci_high,
    interpretation,
    statement_kind,
    t_kind,
    context_id,
    derivation_type,
    derivation_depth
FROM statements;


CREATE VIEW statement_view AS
SELECT
    s.id,
    p.canonical_name                  AS predicate,
    s.object_args,
    arg_names.names                   AS arg_names,
    s.literal_args,
    s.belief_mean,
    s.belief_alpha + s.belief_beta    AS evidence_strength,
    s.interpretation,
    s.statement_kind,
    s.t_kind,
    s.t_start,
    s.t_end,
    c.canonical_name                  AS context,
    s.derivation_type,
    s.derivation_depth,
    s.derived_from,
    s.created_at
FROM statements s
JOIN objects p ON p.id = s.predicate_id
JOIN objects c ON c.id = s.context_id
LEFT JOIN LATERAL (
    SELECT array_agg(o.canonical_name ORDER BY ord) AS names
    FROM unnest(s.object_args) WITH ORDINALITY AS u(oid, ord)
    JOIN objects o ON o.id = u.oid
) arg_names ON true;


CREATE VIEW source_credibility_score AS
SELECT
    source_id,
    context_id,
    alpha / (alpha + beta)                          AS mean,
    alpha + beta                                     AS evidence_strength,
    is_protected,
    GREATEST(0,
        alpha / (alpha + beta)
        - 1.96 * sqrt(alpha * beta
                      / (pow(alpha + beta, 2) * (alpha + beta + 1)))
    )                                                AS ci_low,
    LEAST(1,
        alpha / (alpha + beta)
        + 1.96 * sqrt(alpha * beta
                      / (pow(alpha + beta, 2) * (alpha + beta + 1)))
    )                                                AS ci_high
FROM source_credibility;


-- [Fix #7] statement_credibility: evidence group aggregation rule.
-- RULE: Each evidence_group_id contributes at most its single
-- highest-weight attestation to the credibility sum. Attestations
-- with evidence_group_id IS NULL are always included individually.
-- This prevents confidence inflation from correlated sources (e.g.
-- the same underlying study cited by multiple outlets, or the same
-- author publishing in multiple venues).
CREATE VIEW statement_credibility AS
WITH ranked_attestations AS (
    SELECT
        a.statement_id,
        a.source_id,
        a.confidence_weight,
        a.evidence_group_id,
        coalesce(sc_domain.mean,             sc_reality.mean,             0.5)  AS src_mean,
        coalesce(sc_domain.evidence_strength,sc_reality.evidence_strength, 2.0) AS src_es,
        CASE
            -- Ungrouped attestations always included
            WHEN a.evidence_group_id IS NULL THEN 1
            -- Within each group, rank by confidence_weight DESC; only rank=1 is used
            ELSE ROW_NUMBER() OVER (
                PARTITION BY a.statement_id, a.evidence_group_id
                ORDER BY a.confidence_weight DESC
            )
        END AS group_rank
    FROM attestations a
    JOIN statements s ON s.id = a.statement_id
    LEFT JOIN source_credibility_score sc_domain
           ON sc_domain.source_id  = a.source_id
          AND sc_domain.context_id = s.context_id
    LEFT JOIN source_credibility_score sc_reality
           ON sc_reality.source_id  = a.source_id
          AND sc_reality.context_id = stable_uuid('reality', 'context')
)
SELECT
    statement_id,
    sum(src_mean * src_es * confidence_weight)
        / nullif(sum(src_es * confidence_weight), 0) AS weighted_credibility,
    sum(src_es * confidence_weight)                  AS total_source_weight,
    count(*)                                         AS source_count
FROM ranked_attestations
WHERE group_rank = 1          -- highest-weight attestation per group only
GROUP BY statement_id;


-- [Fix #20] statement_effective_belief: canonical belief view.
-- Synthesises raw Beta belief, source credibility, and open conflict
-- severity into a single effective_mean per statement.
--
-- Columns:
--   raw_mean          — Beta mean (belief_alpha / (alpha + beta))
--   credibility_adjusted — source-credibility-weighted mean (where available)
--   effective_mean    — raw_mean penalised by worst open conflict:
--                       raw_mean * (1 - max_open_severity)
--                       Range [0, 1]; 0 when severity = 1.0 (total conflict).
--   open_conflict_count — number of unresolved conflicts involving this statement
--   conflict_severity — max severity of any open conflict (NULL if none)
--
-- This view is the CANONICAL INPUT for holds_at (open_world mode) and
-- tell_about. All threshold comparisons should use effective_mean, not
-- raw belief_mean, so that open conflicts reduce apparent confidence.
--
-- Implementation note: a statement can appear as statement_a or statement_b
-- in conflicts. Both sides are unioned so that symmetric conflicts penalise
-- both parties. UNION (not UNION ALL) deduplicates self-referential
-- type_mismatch conflicts where statement_a = statement_b.
CREATE VIEW statement_effective_belief AS
SELECT
    s.id,
    s.belief_mean                                                       AS raw_mean,
    COALESCE(sc.weighted_credibility, s.belief_mean)                    AS credibility_adjusted,
    s.belief_mean
        * (1.0 - COALESCE(cp.max_severity, 0.0))                       AS effective_mean,
    sc.total_source_weight,
    sc.source_count,
    COALESCE(cp.open_conflict_count, 0)                                 AS open_conflict_count,
    cp.max_severity                                                     AS conflict_severity
FROM statements s
LEFT JOIN statement_credibility sc ON sc.statement_id = s.id
LEFT JOIN (
    SELECT
        sid,
        COUNT(*)                             AS open_conflict_count,
        MAX(COALESCE(severity, 0.0))         AS max_severity
    FROM (
        -- A statement can appear on either side of a conflict
        SELECT statement_a AS sid, id AS conflict_id, severity
        FROM conflicts
        WHERE resolved = false
        UNION
        SELECT statement_b AS sid, id AS conflict_id, severity
        FROM conflicts
        WHERE resolved = false
    ) both_sides
    GROUP BY sid
) cp ON cp.sid = s.id;


-- =============================================================
-- FUNCTIONS
-- =============================================================

-- ── update_trust ──────────────────────────────────────────────
-- Bayesian update (Beta conjugate) of source credibility.
-- p_override required to modify a protected source.
CREATE OR REPLACE FUNCTION update_trust(
    p_source_id  uuid,
    p_context_id uuid,
    p_correct    boolean,
    p_weight     double precision DEFAULT 1.0,
    p_override   boolean          DEFAULT false
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_protected boolean;
BEGIN
    INSERT INTO source_credibility (source_id, context_id, alpha, beta, is_protected)
    VALUES (p_source_id, p_context_id, 1.0, 1.0, false)
    ON CONFLICT (source_id, context_id) DO NOTHING;

    SELECT is_protected INTO v_protected
    FROM source_credibility
    WHERE source_id = p_source_id AND context_id = p_context_id;

    IF v_protected AND NOT p_override THEN
        RAISE EXCEPTION
            'source % is protected; pass p_override=true to modify', p_source_id;
    END IF;

    IF p_correct THEN
        UPDATE source_credibility
           SET alpha = alpha + p_weight, updated_at = now()
         WHERE source_id = p_source_id AND context_id = p_context_id;
    ELSE
        UPDATE source_credibility
           SET beta  = beta  + p_weight, updated_at = now()
         WHERE source_id = p_source_id AND context_id = p_context_id;
    END IF;
END;
$$;


-- ── update_belief ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_belief(
    p_statement_id uuid,
    p_weight       double precision,
    p_supports     boolean
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_supports THEN
        UPDATE statements
           SET belief_alpha = belief_alpha + p_weight, updated_at = now()
         WHERE id = p_statement_id;
    ELSE
        UPDATE statements
           SET belief_beta  = belief_beta  + p_weight, updated_at = now()
         WHERE id = p_statement_id;
    END IF;
END;
$$;


-- ── [Fix #2] holds_at ─────────────────────────────────────────
-- Returns statements for a predicate+args combination that hold at a
-- given time, in a given context, under a given reasoning mode.
--
-- [Fix #20] In 'open_world' mode, filtering now uses effective_mean from
-- statement_effective_belief rather than raw belief_mean. This means open
-- conflicts reduce a statement's apparent confidence and can suppress it
-- below p_threshold even if its raw Beta mean is high. The returned
-- belief_mean_val column contains effective_mean for open_world mode.
--
-- Parameters:
--   p_threshold    (DEFAULT 0.5) — open_world mode only. Minimum
--     effective_mean required to consider a statement as holding.
--   p_min_evidence (DEFAULT 0.0) — open_world mode only. Minimum
--     evidence mass (alpha + beta) required. Set > 2.0 to exclude
--     uniform-prior statements with no real evidence.
--
-- p_mode options:
--   'open_world'        — returns statements with effective_mean > p_threshold
--                         AND evidence_strength >= p_min_evidence.
--   'default_true'      — v0.4 behaviour. 'default' t_kind statements are
--                         treated as true until a direct_negation conflict exists.
--                         Uses raw belief_mean (no conflict penalty applied).
--   'evidence_weighted' — returns all matching statements regardless of belief,
--                         ordered by effective_mean DESC. For reasoning layer use.
--
-- [Fix #17] Note: statement_kind = 'rule' statements are excluded from all
-- modes. Rule statements are inference schemas, not factual claims. Full
-- kind-based inference chain enforcement is planned for v0.8.
--
-- Default mode: 'open_world'.
CREATE OR REPLACE FUNCTION holds_at(
    p_predicate_id  uuid,
    p_object_args   uuid[],
    p_time          timestamptz,
    p_context_id    uuid    DEFAULT NULL,
    p_mode          text    DEFAULT 'open_world',
    p_threshold     float   DEFAULT 0.5,
    p_min_evidence  float   DEFAULT 0.0
) RETURNS TABLE (
    statement_id    uuid,
    belief_mean_val double precision,
    evidence_str    double precision,
    interp          statement_interpretation
) LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_context_id uuid;
BEGIN
    v_context_id := COALESCE(p_context_id, stable_uuid('reality', 'context'));

    IF p_mode = 'evidence_weighted' THEN
        RETURN QUERY
        SELECT sub.sid, sub.eff_mean, sub.estr, sub.interp
        FROM (
            SELECT s.id,
                   seb.effective_mean,
                   s.belief_alpha + s.belief_beta,
                   s.interpretation
            FROM statements s
            JOIN statement_effective_belief seb ON seb.id = s.id
            WHERE s.predicate_id    = p_predicate_id
              AND s.object_args     = p_object_args
              AND s.context_id      = v_context_id
              AND s.statement_kind != 'rule'
              AND s.t_kind IN ('eternal', 'always')

            UNION ALL

            SELECT s.id,
                   seb.effective_mean,
                   s.belief_alpha + s.belief_beta,
                   s.interpretation
            FROM statements s
            JOIN statement_effective_belief seb ON seb.id = s.id
            WHERE s.predicate_id    = p_predicate_id
              AND s.object_args     = p_object_args
              AND s.context_id      = v_context_id
              AND s.statement_kind != 'rule'
              AND s.t_kind IN ('interval', 'point')
              AND tstzrange(
                      coalesce(s.t_start_ts, '-infinity'::timestamptz),
                      coalesce(s.t_end_ts,   'infinity'::timestamptz), '[)'
                  ) @> p_time

            UNION ALL

            SELECT s.id,
                   seb.effective_mean,
                   s.belief_alpha + s.belief_beta,
                   s.interpretation
            FROM statements s
            JOIN statement_effective_belief seb ON seb.id = s.id
            WHERE s.predicate_id    = p_predicate_id
              AND s.object_args     = p_object_args
              AND s.context_id      = v_context_id
              AND s.statement_kind != 'rule'
              AND s.t_kind          = 'default'
        ) sub(sid, eff_mean, estr, interp)
        ORDER BY eff_mean DESC;

    ELSIF p_mode = 'default_true' THEN
        RETURN QUERY
        SELECT sub.sid, sub.bmean, sub.estr, sub.interp
        FROM (
            SELECT s.id, s.belief_mean, s.belief_alpha + s.belief_beta, s.interpretation
            FROM statements s
            WHERE s.predicate_id    = p_predicate_id
              AND s.object_args     = p_object_args
              AND s.context_id      = v_context_id
              AND s.statement_kind != 'rule'
              AND s.t_kind IN ('eternal', 'always')

            UNION ALL

            SELECT s.id, s.belief_mean, s.belief_alpha + s.belief_beta, s.interpretation
            FROM statements s
            WHERE s.predicate_id    = p_predicate_id
              AND s.object_args     = p_object_args
              AND s.context_id      = v_context_id
              AND s.statement_kind != 'rule'
              AND s.t_kind          = 'default'
              AND s.t_end_ts        IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM conflicts c
                  WHERE c.conflict_kind = 'direct_negation'
                    AND (c.statement_a = s.id OR c.statement_b = s.id)
                    AND c.resolved = false
              )

            UNION ALL

            SELECT s.id, s.belief_mean, s.belief_alpha + s.belief_beta, s.interpretation
            FROM statements s
            WHERE s.predicate_id    = p_predicate_id
              AND s.object_args     = p_object_args
              AND s.context_id      = v_context_id
              AND s.statement_kind != 'rule'
              AND s.t_kind IN ('interval', 'point')
              AND tstzrange(
                      coalesce(s.t_start_ts, '-infinity'::timestamptz),
                      coalesce(s.t_end_ts,   'infinity'::timestamptz), '[)'
                  ) @> p_time
        ) sub(sid, bmean, estr, interp)
        ORDER BY bmean DESC;

    ELSE
        -- Default: 'open_world'
        -- [Fix #2]  Use p_threshold and p_min_evidence.
        -- [Fix #20] Filter on effective_mean from statement_effective_belief
        --           so that open conflicts penalise apparent confidence.
        RETURN QUERY
        SELECT sub.sid, sub.eff_mean, sub.estr, sub.interp
        FROM (
            SELECT s.id,
                   seb.effective_mean,
                   s.belief_alpha + s.belief_beta,
                   s.interpretation
            FROM statements s
            JOIN statement_effective_belief seb ON seb.id = s.id
            WHERE s.predicate_id                  = p_predicate_id
              AND s.object_args                   = p_object_args
              AND s.context_id                    = v_context_id
              AND seb.effective_mean              > p_threshold
              AND s.belief_alpha + s.belief_beta >= p_min_evidence
              AND s.statement_kind               != 'rule'
              AND s.t_kind IN ('eternal', 'always')

            UNION ALL

            SELECT s.id,
                   seb.effective_mean,
                   s.belief_alpha + s.belief_beta,
                   s.interpretation
            FROM statements s
            JOIN statement_effective_belief seb ON seb.id = s.id
            WHERE s.predicate_id                  = p_predicate_id
              AND s.object_args                   = p_object_args
              AND s.context_id                    = v_context_id
              AND seb.effective_mean              > p_threshold
              AND s.belief_alpha + s.belief_beta >= p_min_evidence
              AND s.statement_kind               != 'rule'
              AND s.t_kind IN ('interval', 'point')
              AND tstzrange(
                      coalesce(s.t_start_ts, '-infinity'::timestamptz),
                      coalesce(s.t_end_ts,   'infinity'::timestamptz), '[)'
                  ) @> p_time

            UNION ALL

            SELECT s.id,
                   seb.effective_mean,
                   s.belief_alpha + s.belief_beta,
                   s.interpretation
            FROM statements s
            JOIN statement_effective_belief seb ON seb.id = s.id
            WHERE s.predicate_id                  = p_predicate_id
              AND s.object_args                   = p_object_args
              AND s.context_id                    = v_context_id
              AND seb.effective_mean              > p_threshold
              AND s.belief_alpha + s.belief_beta >= p_min_evidence
              AND s.statement_kind               != 'rule'
              AND s.t_kind                        = 'default'
        ) sub(sid, eff_mean, estr, interp)
        ORDER BY eff_mean DESC;

    END IF;
END;
$$;


-- ── [Fix #6 / Fix #21] compute_derived_belief ────────────────
-- Computes (alpha, beta) for a forward-chained or abduced statement
-- from its parent statement IDs.
--
-- p_combination options:
--   'min'      (default) — conservative: result mean = min(parent means),
--              discounted by chain length. Use when parents are not
--              independent or when the weakest link dominates.
--   'log_odds' — log-odds combination for independent parents.
--              [Fix #21] Accumulates (sums) log-odds increments from a
--              shared uniform prior (log-odds = 0), then applies chain
--              discount. The v0.6 bug of AVERAGING (dividing by n) has
--              been removed. With the correct sum, two independent parents
--              each at 90% belief yield a result meaningfully above 90%,
--              not equal to it, correctly reflecting the independence signal.
--              Use only when parents are genuinely independent.
--
-- [Fix #17] WARNING: if p_parent_ids contains statements with
-- statement_kind = 'statistical', those parents are not appropriate for
-- logical inference chains. A NOTICE is raised. Full enforcement (blocking
-- statistical parents) is planned for v0.8.
--
-- Discount factor: 0.9^p_chain_length applied to the result mean.
-- The returned (alpha, beta) use evidence_strength = 2 (weak prior).
-- Callers may scale alpha and beta upward to reflect stronger confidence
-- in the inference rule.
--
-- Returns (1.0, 1.0) (uniform prior) when p_parent_ids is empty.
CREATE OR REPLACE FUNCTION compute_derived_belief(
    p_parent_ids   uuid[],
    p_chain_length int  DEFAULT 1,
    p_combination  text DEFAULT 'min'
) RETURNS TABLE (out_alpha double precision, out_beta double precision)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_min_mean    double precision := 1.0;
    v_log_odds    double precision := 0.0;
    v_n           int              := 0;
    v_mean        double precision;
    v_alpha       double precision;
    v_beta        double precision;
    v_discount    double precision;
    v_result_mean double precision;
    v_has_stat    boolean;
BEGIN
    IF p_parent_ids IS NULL OR cardinality(p_parent_ids) = 0 THEN
        RETURN QUERY SELECT 1.0::double precision, 1.0::double precision;
        RETURN;
    END IF;

    -- [Fix #17] Warn if any parent is a statistical statement.
    -- Statistical statements should not feed logical inference chains.
    SELECT EXISTS (
        SELECT 1 FROM statements
        WHERE id = ANY(p_parent_ids)
          AND statement_kind = 'statistical'
    ) INTO v_has_stat;

    IF v_has_stat THEN
        RAISE NOTICE
            'compute_derived_belief: one or more parent statements have '
            'statement_kind = ''statistical''. Statistical statements should not '
            'participate in logical inference chains. Full enforcement in v0.8.';
    END IF;

    -- Discount per chain step: 0.9^depth reflects reduced certainty
    -- in longer inference chains.
    v_discount := pow(0.9, GREATEST(p_chain_length, 0));

    IF p_combination = 'log_odds' THEN
        -- [Fix #21] Accumulate log-odds increments from a shared uniform prior.
        -- Starting prior: log-odds = 0 (50% belief). Each parent's log-odds
        -- is added as an independent increment. This correctly models the
        -- independence assumption: n confirming parents at p each push the
        -- combined belief well above p, unlike the v0.6 average which left it
        -- equal to p regardless of n.
        -- The logistic function maps the accumulated value back to [0, 1];
        -- no division by v_n.
        FOR v_alpha, v_beta IN
            SELECT s.belief_alpha, s.belief_beta
            FROM statements s
            WHERE s.id = ANY(p_parent_ids)
        LOOP
            v_mean     := v_alpha / (v_alpha + v_beta);
            -- Clamp away from 0 and 1 to keep log-odds finite
            v_mean     := GREATEST(1e-6, LEAST(1.0 - 1e-6, v_mean));
            -- Accumulate (sum) increments — do NOT divide by n
            v_log_odds := v_log_odds + ln(v_mean / (1.0 - v_mean));
            v_n        := v_n + 1;
        END LOOP;

        -- Apply chain discount to the combined result
        v_result_mean := 1.0 / (1.0 + exp(-v_log_odds)) * v_discount;

    ELSE
        -- Conservative min-of-means: the weakest parent governs.
        FOR v_alpha, v_beta IN
            SELECT s.belief_alpha, s.belief_beta
            FROM statements s
            WHERE s.id = ANY(p_parent_ids)
        LOOP
            v_mean := v_alpha / (v_alpha + v_beta);
            IF v_mean < v_min_mean THEN
                v_min_mean := v_mean;
            END IF;
            v_n := v_n + 1;
        END LOOP;

        v_result_mean := v_min_mean * v_discount;
    END IF;

    IF v_n = 0 THEN
        RETURN QUERY SELECT 1.0::double precision, 1.0::double precision;
        RETURN;
    END IF;

    v_result_mean := GREATEST(1e-6, LEAST(1.0 - 1e-6, v_result_mean));

    -- Map back to (alpha, beta) with evidence_strength = 2 (weak prior).
    -- Callers may multiply both values by a scale factor to express
    -- stronger confidence in the inference rule.
    RETURN QUERY SELECT
        (v_result_mean * 2.0)::double precision,
        ((1.0 - v_result_mean) * 2.0)::double precision;
END;
$$;


-- ── [Fix #9 / Fix #18 / Fix #19] detect_conflicts ────────────
-- Scans statements for pairs with the same predicate + object_args
-- whose 95% Beta confidence intervals do not overlap, and inserts
-- them into conflicts as direct_negation.
--
-- [Fix #18] TEMPORAL GUARD: before comparing CIs, requires that the
-- two statements' time windows overlap. Two statements about the same
-- predicate and args but in non-overlapping time windows — e.g.
-- has_role(Babbage, professor, Cambridge) in 1828 vs 1890 — are NOT
-- in conflict just because their CIs differ; they may both be true in
-- their respective periods. The guard uses tstzrange && (overlaps)
-- operator on the materialised t_start_ts / t_end_ts columns.
-- Eternal and always statements are time-universal and bypass the guard.
--
-- [Fix #19] SEVERITY: each inserted conflict row carries a severity value
-- computed as the normalised CI gap:
--   GREATEST(b.ci_low - a.ci_high, a.ci_low - b.ci_high, 0)
-- Range [0, 1]; higher = stronger statistical incompatibility.
-- Severity feeds the conflict penalty in statement_effective_belief.
--
-- Non-overlapping CIs are a more principled conflict criterion than
-- a belief_mean > 0.5 / < 0.5 split: they catch cases where both
-- statements have moderate belief but are statistically incompatible,
-- and avoid flagging pairs where the intervals overlap despite one
-- having mean > 0.5 and the other < 0.5.
--
-- Pairs already recorded in conflicts are skipped.
-- Returns the number of new conflicts inserted.
--
-- Intended to be called periodically (e.g. via pg_cron) or after
-- bulk ingestion. The idx_stmt_conflict_lookup index (Fix #26) makes
-- the self-join viable at scale.
CREATE OR REPLACE FUNCTION detect_conflicts(
    p_context_id uuid DEFAULT NULL
) RETURNS int LANGUAGE plpgsql AS $$
DECLARE
    v_context_id uuid;
    v_inserted   int;
BEGIN
    v_context_id := COALESCE(p_context_id, stable_uuid('reality', 'context'));

    WITH belief_ci AS (
        SELECT
            s.id,
            s.predicate_id,
            s.object_args,
            s.belief_mean,
            s.t_kind,
            s.t_start_ts,
            s.t_end_ts,
            -- 95% CI via normal approximation to Beta
            GREATEST(0,
                s.belief_mean - 1.96 * sqrt(
                    (s.belief_alpha * s.belief_beta)
                    / (pow(s.belief_alpha + s.belief_beta, 2)
                       * (s.belief_alpha + s.belief_beta + 1))
                )
            ) AS ci_low,
            LEAST(1,
                s.belief_mean + 1.96 * sqrt(
                    (s.belief_alpha * s.belief_beta)
                    / (pow(s.belief_alpha + s.belief_beta, 2)
                       * (s.belief_alpha + s.belief_beta + 1))
                )
            ) AS ci_high
        FROM statements s
        WHERE s.context_id      = v_context_id
          AND s.statement_kind != 'rule'
    ),
    conflict_pairs AS (
        SELECT
            a.id                                                         AS stmt_a,
            b.id                                                         AS stmt_b,
            -- [Fix #19] Severity: normalised CI gap, range [0, 1]
            GREATEST(b.ci_low - a.ci_high, a.ci_low - b.ci_high, 0.0)  AS severity
        FROM belief_ci a
        JOIN belief_ci b
          ON b.predicate_id = a.predicate_id
         AND b.object_args  = a.object_args
         -- Canonical ordering prevents duplicate (a,b) and (b,a) pairs
         AND b.id > a.id
        WHERE
            -- CIs are disjoint: a is entirely below b, or b entirely below a
            (a.ci_high < b.ci_low OR b.ci_high < a.ci_low)

            -- [Fix #18] TEMPORAL OVERLAP GUARD
            -- Statements in non-overlapping time windows are not in conflict.
            -- Eternal/always statements are universal and always pass.
            AND (
                a.t_kind IN ('eternal', 'always')
                OR b.t_kind IN ('eternal', 'always')
                OR tstzrange(
                       coalesce(a.t_start_ts, '-infinity'::timestamptz),
                       coalesce(a.t_end_ts,   'infinity'::timestamptz), '[)'
                   ) &&
                   tstzrange(
                       coalesce(b.t_start_ts, '-infinity'::timestamptz),
                       coalesce(b.t_end_ts,   'infinity'::timestamptz), '[)'
                   )
            )

            -- Not already recorded in either direction
            AND NOT EXISTS (
                SELECT 1 FROM conflicts c
                WHERE (c.statement_a = a.id AND c.statement_b = b.id)
                   OR (c.statement_a = b.id AND c.statement_b = a.id)
            )
    )
    INSERT INTO conflicts (statement_a, statement_b, conflict_kind, severity)
    SELECT stmt_a, stmt_b, 'direct_negation', severity
    FROM conflict_pairs;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    RETURN v_inserted;
END;
$$;


-- ── [Fix #14 / Fix #25] tell_about ───────────────────────────
-- Returns all statements in which p_entity_id appears in any object
-- arg position, ordered by effective_mean DESC. Predicates and arg
-- names are resolved to canonical_name for readability.
--
-- [Fix #20] Filtering and ordering use effective_mean from
-- statement_effective_belief (raw belief_mean penalised by open conflict
-- severity), not raw belief_mean. p_threshold is compared against
-- effective_mean.
--
-- [Fix #25] p_time (DEFAULT NULL): when supplied, restricts results to
-- statements whose temporal scope includes p_time, matching holds_at()
-- semantics. Eternal, always, and default-kind statements are always
-- included when p_time is set (they are not temporally restricted).
-- Interval and point statements are included only if their window @> p_time.
-- When p_time IS NULL, all temporal scopes are returned (original behaviour).
--
-- [Fix #17] Statements with statement_kind = 'rule' are excluded; they are
-- inference schemas, not factual claims about entities.
--
-- This is the primary "what do we know about X?" query interface.
CREATE OR REPLACE FUNCTION tell_about(
    p_entity_id  uuid,
    p_context_id uuid        DEFAULT NULL,
    p_threshold  float       DEFAULT 0.0,
    p_time       timestamptz DEFAULT NULL
) RETURNS TABLE (
    statement_id      uuid,
    predicate         text,
    arg_names         text[],
    literal_args      jsonb,
    effective_mean    double precision,
    raw_mean          double precision,
    evidence_strength double precision,
    open_conflict_count bigint,
    interpretation    statement_interpretation,
    statement_kind    statement_kind,
    t_kind            temporal_kind,
    t_start           fuzzy_time,
    t_end             fuzzy_time,
    context           text,
    derivation_type   derivation_type
) LANGUAGE sql STABLE AS $$
    SELECT
        s.id,
        p.canonical_name,
        arg_names.names,
        s.literal_args,
        seb.effective_mean,
        seb.raw_mean,
        s.belief_alpha + s.belief_beta,
        seb.open_conflict_count,
        s.interpretation,
        s.statement_kind,
        s.t_kind,
        s.t_start,
        s.t_end,
        c.canonical_name,
        s.derivation_type
    FROM statements s
    JOIN statement_effective_belief seb ON seb.id = s.id
    JOIN objects p ON p.id = s.predicate_id
    JOIN objects c ON c.id = s.context_id
    LEFT JOIN LATERAL (
        SELECT array_agg(o.canonical_name ORDER BY ord) AS names
        FROM unnest(s.object_args) WITH ORDINALITY AS u(oid, ord)
        JOIN objects o ON o.id = u.oid
    ) arg_names ON true
    WHERE p_entity_id = ANY(s.object_args)
      AND (p_context_id IS NULL OR s.context_id = p_context_id)
      AND seb.effective_mean  >= p_threshold
      AND s.statement_kind   != 'rule'
      -- [Fix #25] Temporal filter: when p_time is supplied, honour scope
      AND (
          p_time IS NULL
          -- Non-temporal statements always pass
          OR s.t_kind IN ('eternal', 'always', 'default')
          -- Temporal statements must contain p_time
          OR (
              s.t_kind IN ('interval', 'point')
              AND tstzrange(
                      coalesce(s.t_start_ts, '-infinity'::timestamptz),
                      coalesce(s.t_end_ts,   'infinity'::timestamptz), '[)'
                  ) @> p_time
          )
      )
    ORDER BY seb.effective_mean DESC;
$$;


-- ── [Fix #15] why ─────────────────────────────────────────────
-- Returns the full explanation graph for a derived statement as a
-- recursive traversal of statement_dependencies.
-- Each row represents one node in the provenance DAG, with depth
-- (0 = the target statement), the rule applied to derive the child
-- from the parent, and the edge weight.
-- Cycle guard via a visited array prevents infinite loops in the
-- (theoretical) case of circular derivation records.
CREATE OR REPLACE FUNCTION why(
    p_statement_id uuid
) RETURNS TABLE (
    depth           int,
    statement_id    uuid,
    predicate       text,
    arg_names       text[],
    belief_mean     double precision,
    effective_mean  double precision,
    rule_name       text,
    edge_weight     double precision,
    derivation_type derivation_type,
    statement_kind  statement_kind
) LANGUAGE sql STABLE AS $$
    WITH RECURSIVE provenance AS (
        -- Base case: the target statement itself
        SELECT
            0                               AS depth,
            s.id                            AS statement_id,
            s.predicate_id,
            s.object_args,
            s.belief_mean,
            s.statement_kind,
            s.derivation_type,
            NULL::text                      AS rule_name,
            NULL::double precision          AS edge_weight,
            ARRAY[s.id]                     AS visited
        FROM statements s
        WHERE s.id = p_statement_id

        UNION ALL

        -- Recursive case: parents via statement_dependencies
        SELECT
            pr.depth + 1,
            s.id,
            s.predicate_id,
            s.object_args,
            s.belief_mean,
            s.statement_kind,
            s.derivation_type,
            sd.rule_name,
            sd.weight,
            pr.visited || s.id
        FROM provenance pr
        JOIN statement_dependencies sd ON sd.child_id  = pr.statement_id
        JOIN statements s              ON s.id         = sd.parent_id
        WHERE s.id <> ALL(pr.visited)  -- cycle guard
    )
    SELECT
        pr.depth,
        pr.statement_id,
        p.canonical_name                AS predicate,
        arg_names.names                 AS arg_names,
        pr.belief_mean,
        seb.effective_mean,
        pr.rule_name,
        pr.edge_weight,
        pr.derivation_type,
        pr.statement_kind
    FROM provenance pr
    JOIN objects p ON p.id = pr.predicate_id
    JOIN statement_effective_belief seb ON seb.id = pr.statement_id
    LEFT JOIN LATERAL (
        SELECT array_agg(o.canonical_name ORDER BY ord) AS names
        FROM unnest(pr.object_args) WITH ORDINALITY AS u(oid, ord)
        JOIN objects o ON o.id = u.oid
    ) arg_names ON true
    ORDER BY pr.depth, pr.statement_id;
$$;


-- =============================================================
-- SEED DATA
-- =============================================================
-- Wrapped in a single transaction so DEFERRABLE INITIALLY DEFERRED
-- orphan-guard and provenance triggers fire at COMMIT.

BEGIN;

-- ── Infrastructure objects ────────────────────────────────────
INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES

    -- Contexts
    (stable_uuid('reality', 'context'),
     'context', 'reality', 'Reality',
     'The default real-world context'),

    -- Sources
    (stable_uuid('user_parent', 'source'),
     'source', 'user_parent', 'User (parent)',
     'Primary user — highest trust, analogous to a parent'),

    (stable_uuid('wikidata', 'source'),
     'source', 'wikidata', 'Wikidata',
     'Wikidata knowledge graph'),

    (stable_uuid('llm_generated', 'source'),
     'source', 'llm_generated', 'LLM generated',
     'Fact proposed by language model; lower prior trust'),

    (stable_uuid('system_kernel', 'source'),
     'source', 'system_kernel', 'System kernel',
     'Axiomatic facts at KB initialisation. Near-certain (alpha=999). '
     'is_protected=true: update_trust() requires explicit p_override=true. '
     'Kernel facts are correctable by deliberate human action but will '
     'not drift from passive evidence accumulation.'),

    -- Boolean / epistemic sentinels
    (stable_uuid('true',    'entity'), 'entity', 'true',    'True',
     'The Boolean value true'),
    (stable_uuid('false',   'entity'), 'entity', 'false',   'False',
     'The Boolean value false'),
    (stable_uuid('unknown', 'entity'), 'entity', 'unknown', 'Unknown',
     'Epistemic state: identity or value is unknown. '
     'NOT a scope placeholder — use no_scope for unscoped roles. '
     'NOT a time-period placeholder — use no_period for ternary predicates '
     'with no named period argument.'),

    -- [Fix #5] no_scope sentinel
    -- Distinct from unknown: use when a role genuinely has no institutional
    -- scope (e.g. an itinerant scholar), not when the scope is merely
    -- unknown to the asserting agent. For unknown scope, either leave
    -- the scope argument absent or assert a separate uncertainty statement.
    -- [Fix #23] Scope of use restricted to role-scope arguments only.
    -- Do NOT use no_scope as the time_period arg of located_in or similar
    -- ternary predicates — use no_period instead.
    (stable_uuid('no_scope', 'entity'), 'entity', 'no_scope', 'No Scope',
     'Sentinel: this role or relation has no institutional scope. '
     'Use has_role(X, role, no_scope) when the role is genuinely unscoped. '
     'Restricted to role-scope arguments; use no_period for time-period args. '
     'Distinct from unknown scope: unknown means the scope exists but is '
     'not known; no_scope means there is no scope by design.'),

    -- [Fix #23] no_period sentinel
    -- Use as the time_period argument of located_in (and similar ternary
    -- predicates) when no named historical period is the semantic argument
    -- of the predicate. The temporal scope itself is encoded in the
    -- statement's t_start / t_end fuzzy_time fields (policy decision #3).
    -- Distinct from no_scope (for role-scope) and unknown (epistemic state).
    (stable_uuid('no_period', 'entity'), 'entity', 'no_period', 'No Period',
     'Sentinel: this relation has no named time period as a semantic argument. '
     'Use as the time_period arg of located_in(entity, place, no_period) when '
     'the temporal scope is expressed in t_start/t_end, not as a named period. '
     'Distinct from no_scope (role-scope sentinel) and unknown (epistemic state). '
     'Also applies to causes(X, Y, no_period) and other ternary predicates '
     'where the third arg is a period placeholder, not a semantic argument.');


-- ── Ontological backbone objects ──────────────────────────────
INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES

    -- Layer A: top-level ontological categories (hard, minimal, static)
    (stable_uuid('entity',    'entity'), 'entity', 'entity',    'Entity',
     'Top-level ontological category: everything that exists or is modeled'),
    (stable_uuid('concrete',  'entity'), 'entity', 'concrete',  'Concrete',
     'Entities with spatiotemporal existence'),
    (stable_uuid('abstract',  'entity'), 'entity', 'abstract',  'Abstract',
     'Entities without spatiotemporal existence: concepts, numbers, relations'),
    (stable_uuid('living',    'entity'), 'entity', 'living',    'Living',
     'Concrete entities that are or were alive'),
    (stable_uuid('animate',   'entity'), 'entity', 'animate',   'Animate',
     'Living entities capable of self-directed movement'),
    (stable_uuid('sapient',   'entity'), 'entity', 'sapient',   'Sapient',
     'Animate entities with higher cognition'),
    (stable_uuid('artifact',  'entity'), 'entity', 'artifact',  'Artifact',
     'Concrete entities created by agents'),
    -- [Fix #4] process is seeded with the direct process ⊂ entity link below.
    -- MIGRATION NOTE (v0.6 → v0.7): Remove the direct process ⊂ entity
    -- subtype_of statement from the seed once common_objects_kernel.sql
    -- seeds the full chain process ⊂ event ⊂ abstract ⊂ entity. The direct
    -- link produces duplicate paths in hierarchy traversal queries (e.g.
    -- recursive CTEs over subtype_of will return both paths). After the
    -- objects kernel is applied, run:
    --   DELETE FROM statements
    --   WHERE predicate_id = stable_uuid('subtype_of','predicate')
    --     AND object_args  = ARRAY[stable_uuid('process','entity'),
    --                              stable_uuid('entity','entity')]
    --     AND derivation_type = 'axiomatic';
    (stable_uuid('process',   'entity'), 'entity', 'process',   'Process',
     'Events or processes: creation, destruction, transformation, etc. '
     'Full hierarchy (process ⊂ event ⊂ abstract ⊂ entity) is seeded '
     'in common_objects_kernel.sql. Direct link to entity is a v0.6 '
     'transitional stub — see Fix #4 migration note.'),
    (stable_uuid('group',     'entity'), 'entity', 'group',     'Group',
     'Collections of entities. Not automatically an agent — see has_role.'),
    (stable_uuid('person',    'entity'), 'entity', 'person',    'Person',
     'A human individual (subtype of sapient)'),
    (stable_uuid('number',    'entity'), 'entity', 'number',    'Number',
     'Abstract numeric entity'),
    (stable_uuid('relation',  'entity'), 'entity', 'relation',  'Relation',
     'Abstract relational entity'),

    -- Layer B: functional roles (soft, contextual, time-aware)
    (stable_uuid('agent',       'entity'), 'entity', 'agent',       'Agent',
     'Functional role: entity that acts with intention in some context. '
     'Use has_role(X, agent, context) rather than typing X as agent.'),
    (stable_uuid('institution', 'entity'), 'entity', 'institution', 'Institution',
     'Functional role: organised group acting as a unit'),
    (stable_uuid('government',  'entity'), 'entity', 'government',  'Government',
     'Functional role: governing body of a polity');


-- ── Predicate objects and metadata ───────────────────────────
INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES

    (stable_uuid('subtype_of',   'predicate'), 'predicate', 'subtype_of',   'Subtype of',
     'T1 is a subtype of T2. Probabilistic subsumption.'),
    (stable_uuid('instance_of',  'predicate'), 'predicate', 'instance_of',  'Instance of',
     'X is an instance of type T. '
     'CANONICAL TYPE MECHANISM: inserting an instance_of statement '
     'automatically populates or updates the type_membership cache '
     'via trg_sync_type_membership. Do not assert type_membership directly.'),
    (stable_uuid('has_role',     'predicate'), 'predicate', 'has_role',     'Has role',
     'Entity holds a functional role within a scope/context. '
     'Use no_scope as the scope arg when the role is genuinely unscoped.'),
    (stable_uuid('has_capacity', 'predicate'), 'predicate', 'has_capacity', 'Has capacity',
     'Entity possesses a capability. Distinct from roles: capacities are '
     'properties, roles are relational.'),
    (stable_uuid('models_as',    'predicate'), 'predicate', 'models_as',    'Models as',
     'Subject is modeled as a type within a context (non-ontological). '
     'Use interpretation=''modeling'' on such statements.');

INSERT INTO predicates
    (id, arity, arg_labels, nl_description, is_basis, domain_strictness, status)
VALUES
    (stable_uuid('subtype_of',   'predicate'), 2,
     ARRAY['subtype','supertype'],
     'First argument is a subtype of the second.',
     true, 'soft', 'confirmed'),

    (stable_uuid('instance_of',  'predicate'), 2,
     ARRAY['instance','type'],
     'First argument is an instance of the second. '
     'Inserting this statement populates type_membership automatically.',
     true, 'soft', 'confirmed'),

    (stable_uuid('has_role',     'predicate'), 3,
     ARRAY['entity','role','scope'],
     'Entity holds the given functional role within the given scope. '
     'Use no_scope as scope when the role has no institutional scope.',
     false, 'none', 'confirmed'),

    (stable_uuid('has_capacity', 'predicate'), 2,
     ARRAY['entity','capacity'],
     'Entity possesses the given capability.',
     false, 'none', 'confirmed'),

    (stable_uuid('models_as',    'predicate'), 3,
     ARRAY['subject','type','context'],
     'Subject is modeled as a type within a context (non-ontological).',
     false, 'none', 'confirmed');


-- ── Context row ───────────────────────────────────────────────
INSERT INTO contexts (id, kind, parent_id) VALUES
    (stable_uuid('reality', 'context'), 'reality', NULL);


-- ── Source credibility ────────────────────────────────────────
INSERT INTO source_credibility (source_id, context_id, alpha, beta, is_protected) VALUES
    (stable_uuid('user_parent',   'source'),
     stable_uuid('reality',       'context'),  19.0,    1.0,  false),

    (stable_uuid('wikidata',      'source'),
     stable_uuid('reality',       'context'),  13.0,    2.0,  false),

    (stable_uuid('llm_generated', 'source'),
     stable_uuid('reality',       'context'),   3.0,    2.0,  false),

    -- system_kernel: ~99.9% credibility prior; protected from passive drift.
    -- alpha=999, beta=1 → mean ≈ 0.999. Requires p_override=true to update.
    (stable_uuid('system_kernel', 'source'),
     stable_uuid('reality',       'context'), 999.0,    1.0,  true);


-- ── Ontological backbone statements ───────────────────────────
-- Seed the type hierarchy via subtype_of statements.
-- All sourced from system_kernel; axiomatic derivation; eternal.
-- [Fix #17] statement_kind = 'ontological' for all subtype_of assertions.

-- person ⊂ sapient ⊂ animate ⊂ living ⊂ concrete ⊂ entity
-- artifact ⊂ concrete ⊂ entity
-- abstract ⊂ entity
-- number ⊂ abstract; relation ⊂ abstract
-- group ⊂ entity
--
-- [Fix #4] process ⊂ entity: TRANSITIONAL STUB — see migration note
-- on the process object above. Remove after objects kernel is applied.
--
-- [Fix #12] NOTE: disjoint_with statements (abstract ⊥ concrete and
-- their descendants) are seeded in common_objects_kernel.sql after the
-- disjoint_with predicate is defined in common_predicates_kernel.sql.
-- The disjointness lattice is intentionally omitted here to avoid a
-- forward reference to a predicate not yet defined at schema init time.
--
-- [Fix #22] NOTE: The transitive closure of these subtype_of statements
-- is now resolved at domain-enforcement time via recursive CTE in
-- check_soft_domain_violations. Manual is_a materialisation rows in
-- common_objects_kernel.sql Section 12 (e.g. is_a(mathematician, role))
-- are redundant and should be removed in the next kernel release.

INSERT INTO statements
    (id, predicate_id, object_args, belief_alpha, belief_beta,
     interpretation, statement_kind, t_kind, context_id, derivation_type, derivation_depth)
VALUES
    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('concrete','entity'),  stable_uuid('entity','entity')],
     999,1,'ontological','ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('abstract','entity'),  stable_uuid('entity','entity')],
     999,1,'ontological','ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('living','entity'),    stable_uuid('concrete','entity')],
     999,1,'ontological','ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('animate','entity'),   stable_uuid('living','entity')],
     999,1,'ontological','ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('sapient','entity'),   stable_uuid('animate','entity')],
     999,1,'ontological','ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('person','entity'),    stable_uuid('sapient','entity')],
     999,1,'ontological','ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('artifact','entity'),  stable_uuid('concrete','entity')],
     999,1,'ontological','ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    -- [Fix #4] Transitional direct link — remove in v0.7 after objects kernel migration.
    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('process','entity'),   stable_uuid('entity','entity')],
     999,1,'ontological','ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('group','entity'),     stable_uuid('entity','entity')],
     999,1,'ontological','ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('number','entity'),    stable_uuid('abstract','entity')],
     999,1,'ontological','ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('relation','entity'),  stable_uuid('abstract','entity')],
     999,1,'ontological','ontological','eternal',stable_uuid('reality','context'),'axiomatic',0);

COMMIT;
