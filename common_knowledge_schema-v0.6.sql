-- =============================================================
-- Common Knowledge KB — PostgreSQL Schema (v0.6)
-- =============================================================
--
-- CANONICAL POLICY DECISIONS                              [Fix #16]
-- These five invariants are load-bearing. All schema design,
-- trigger logic, and inference code must respect them.
-- ─────────────────────────────────────────────────────────────
-- 1. OPEN-WORLD ASSUMPTION (default)
--    Absence of a statement does not imply falsity. holds_at()
--    defaults to 'open_world' mode: only positively supported
--    statements (belief_mean > p_threshold) are returned.
--    Absence of evidence is not evidence of absence.
--
-- 2. instance_of / is_a IS THE CANONICAL TYPE MECHANISM
--    instance_of statements are the authoritative source of type
--    membership. type_membership is a derived materialized cache,
--    populated automatically by trigger (trg_sync_type_membership)
--    on instance_of insert/update. Never assert type_membership
--    rows directly — they will be silently overwritten.
--    The subtype_of hierarchy is separate and not reflected in
--    type_membership rows; transitive closure is the reasoner's job.
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
--
-- 4. CONFLICTS REPRESENT EVIDENTIAL OPPOSITION, NOT LOGICAL NEGATION
--    direct_negation in conflicts identifies statements that are
--    evidentially opposed. It does NOT mean one statement is the
--    logical negation of the other. True logical negation is resolved
--    at inference time by the reasoning layer using belief_mean
--    thresholds and CI bounds. There is no negated boolean on
--    statements (removed in v0.5).
--
-- 5. KERNEL STATEMENTS ARE CORRECTABLE BUT PROTECTED FROM PASSIVE DRIFT
--    system_kernel source has is_protected = true. update_trust()
--    requires p_override = true to modify kernel credibility. Kernel
--    facts can be corrected by deliberate human action but will not
--    drift from passive evidence accumulation.
-- ─────────────────────────────────────────────────────────────
--
-- Changes from v0.5:
--
--   TYPING                                                [Fix #1]
--   • type_membership is now a derived cache of instance_of / is_a
--     statements. Trigger trg_sync_type_membership populates and
--     updates it on instance_of insert/update. Direct assertion is
--     deprecated; rows asserted directly will be silently overwritten
--     on the next instance_of update for the same (object, type) pair.
--     Invariant documented in policy decision #2 above.
--
--   INFERENCE                                            [Fix #2]
--   • holds_at() gains p_threshold (DEFAULT 0.5) and p_min_evidence
--     (DEFAULT 0.0) parameters for the open_world branch. The hard
--     cutoff at 0.5 caused silent failures for weak-but-uncontested
--     facts; callers may now lower p_threshold and require a minimum
--     evidence mass via p_min_evidence.
--
--   TIME REPRESENTATION                                  [Fix #3]
--   • Schema comment added (policy decision #3): time-object args are
--     a category error. Use fuzzy_time fields on statements for all
--     temporal encoding. See comment on fuzzy_time composite type.
--
--   ONTOLOGY                                             [Fix #4]
--   • process ⊂ entity direct backbone link is preserved in v0.6 seed
--     but marked for removal in v0.7. The objects kernel adds
--     process ⊂ event ⊂ abstract ⊂ entity; the direct link produces
--     duplicate paths in hierarchy traversal. See migration note in
--     the seed data section below.
--
--   SENTINEL                                             [Fix #5]
--   • no_scope sentinel entity seeded. Use has_role(X, role, no_scope)
--     when a role genuinely has no institutional scope, as distinct
--     from a scope whose identity is unknown (for which leave the arg
--     absent or use a dedicated unknown_scope marker). The existing
--     `unknown` entity is an epistemic state, not a scope placeholder.
--
--   DERIVED BELIEF                                       [Fix #6]
--   • compute_derived_belief(parent_ids, chain_length, combination)
--     function added. Computes (alpha, beta) for forward-chained
--     statements from parent belief distributions using either
--     min-of-means (conservative default) or log-odds combination
--     for independent parents. Chain-length discount (0.9^depth)
--     reflects that longer inference chains are less reliable.
--
--   CREDIBILITY                                          [Fix #7]
--   • statement_credibility view updated: each evidence_group_id
--     now contributes at most its single highest-weight attestation
--     to the credibility sum. This prevents silent confidence
--     inflation from correlated sources (same study repackaged,
--     same author in multiple outlets, etc.).
--
--   CONFLICT SEMANTICS                                   [Fix #8]
--   • direct_negation enum value carries an explicit schema comment:
--     evidential opposition only, not logical negation. See enum
--     definition and policy decision #4.
--
--   CONFLICT DETECTION                                   [Fix #9]
--   • detect_conflicts(context_id) function added. Identifies
--     statement pairs with non-overlapping 95% Beta CIs for the same
--     predicate + object_args, inserts them into conflicts as
--     direct_negation. More principled than a 0.5 threshold: catches
--     cases where both statements have moderate belief but are clearly
--     statistically distinct.
--
--   DOMAIN ENFORCEMENT                                  [Fix #10]
--   • trg_soft_domain_check AFTER INSERT trigger added on statements.
--     Checks object_args against predicate arg_type_ids via
--     type_membership. Hard violations still raise an exception.
--     Soft violations insert a type_mismatch conflict and allow the
--     statement through for belief attenuation by the reasoner.
--     Requires type_membership to be populated (Fix #1).
--
--   PROVENANCE                                          [Fix #11]
--   • trg_enforce_provenance DEFERRABLE INITIALLY DEFERRED constraint
--     trigger added on statements. Any forward_chained or abduced
--     statement must have at least one statement_dependencies row by
--     commit time. derived_from uuid[] remains a fast cache computed
--     from the dependency graph, not an independent source of truth.
--
--   DISJOINTNESS                                        [Fix #12]
--   • Seeding of disjoint_with statements (abstract ⊥ concrete and
--     their descendants) is in common_objects_kernel.sql. The
--     disjoint_with predicate object is seeded in
--     common_predicates_kernel.sql. See Fix #12 note in seed section.
--
--   API / QUERY                                         [Fix #14]
--   • tell_about(entity_id) convenience function added. Returns all
--     statements where the entity appears in any arg position,
--     ordered by belief_mean DESC with predicate and arg names resolved.
--
--                                                       [Fix #15]
--   • why(statement_id) provenance function added. Wraps the
--     statement_dependencies recursive CTE into a named function
--     returning the full explanation graph (depth, predicate, args,
--     belief, rule, edge weight) for any derived statement.
--
-- =============================================================


-- ── Extensions ───────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";
CREATE EXTENSION IF NOT EXISTS "btree_gist";


-- ── Stable UUID helper ────────────────────────────────────────
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
-- time by the reasoning layer using belief_mean thresholds and CI
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
-- Bare year-objects (e.g. "1815_birth_time") are a category error:
-- they conflate a named object with a time coordinate.
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
    fol_definition    text,
    nl_description    text,
    source_predicate  text,
    is_basis          boolean            NOT NULL DEFAULT false,
    domain_strictness domain_strictness  NOT NULL DEFAULT 'soft',
    status            predicate_status   NOT NULL DEFAULT 'proposed',
    introduced_by     uuid               REFERENCES objects (id),
    introduced_at     timestamptz        NOT NULL DEFAULT now()
);

CREATE INDEX idx_predicates_basis   ON predicates (is_basis) WHERE is_basis;
CREATE INDEX idx_predicates_status  ON predicates (status);


-- ── Context metadata ──────────────────────────────────────────
-- Tree structure (parent_id). DAG generalisation deferred to v0.7+
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
-- Negation policy (v0.5+, unchanged in v0.6):
--   The negated boolean has been removed. Logical negation and evidential
--   opposition are expressed via the conflicts table with conflict_kind =
--   'direct_negation'. Two competing statements P(a) and its evidential
--   opposite are stored as two positive statements; their conflict is
--   registered explicitly and the reasoner weighs them by belief_mean.
--
-- Argument caching policy:
--   object_args and literal_args are denormalized caches for fast
--   tuple-matching. The authoritative normalized form is statement_args.
--   Trigger trg_sync_statement_args keeps them consistent.
--
-- Provenance policy (v0.6):                             [Fix #11]
--   derived_from uuid[] is a fast cache of parent statement IDs.
--   The authoritative provenance record is statement_dependencies.
--   For forward_chained and abduced statements, at least one
--   statement_dependencies row must exist by commit time (enforced by
--   the DEFERRABLE trigger trg_enforce_provenance).
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

CREATE INDEX idx_stmt_predicate     ON statements (predicate_id);
CREATE INDEX idx_stmt_context       ON statements (context_id);
CREATE INDEX idx_stmt_t_kind        ON statements (t_kind);
CREATE INDEX idx_stmt_deriv_type    ON statements (derivation_type);
CREATE INDEX idx_stmt_belief_mean   ON statements (belief_mean DESC);
CREATE INDEX idx_stmt_object_args   ON statements USING GIN (object_args);
CREATE INDEX idx_stmt_derived_from  ON statements USING GIN (derived_from);
CREATE INDEX idx_stmt_interp        ON statements (interpretation);

CREATE INDEX idx_stmt_temporal_range ON statements USING GIST (
    tstzrange(
        coalesce(t_start_ts, '-infinity'::timestamptz),
        coalesce(t_end_ts,   'infinity'::timestamptz),
        '[)'
    )
) WHERE t_kind IN ('interval', 'point');

CREATE INDEX idx_stmt_eternal ON statements (predicate_id)
    WHERE t_kind = 'eternal';

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
-- but NOT transitive closure via subtype_of — the reasoner handles that.
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
-- type_mismatch conflicts may be self-referential (statement_a = statement_b)
--   when a single statement violates a soft domain constraint; there is no
--   opposing statement, only the violated constraint. The resolution_note
--   records which argument and expected type were mismatched.
CREATE TABLE conflicts (
    id              uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
    statement_a     uuid          NOT NULL REFERENCES statements (id),
    statement_b     uuid          NOT NULL REFERENCES statements (id),
    conflict_kind   conflict_kind,
    resolved        boolean       NOT NULL DEFAULT false,
    resolution_note text,
    created_at      timestamptz   NOT NULL DEFAULT now()
);

CREATE INDEX idx_conflicts_a        ON conflicts (statement_a);
CREATE INDEX idx_conflicts_b        ON conflicts (statement_b);
CREATE INDEX idx_conflicts_resolved ON conflicts (resolved) WHERE NOT resolved;


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
-- Soft domain violations are handled by trg_soft_domain_check (AFTER).
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
-- populated before soft domain checks (trg_soft_domain_check) fire on
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


-- ── [Fix #10] Soft domain violation check ────────────────────
-- Fires AFTER INSERT on statements. Checks each object argument
-- against the predicate's arg_type_ids via type_membership.
-- Hard violations raise an exception (caught by the BEFORE trigger
-- validate_statement_args for arity; extended here for type checks).
-- Soft violations insert a type_mismatch conflict with statement_a =
-- statement_b = the offending statement, plus a description in
-- resolution_note. The statement is allowed through for belief
-- attenuation by the reasoning layer.
--
-- Prerequisite: type_membership must be populated (Fix #1).
-- If type_membership has no row for (object, expected_type), the
-- check conservatively treats it as a soft violation for 'soft'
-- predicates and an exception for 'hard' predicates.
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

        -- Check type_membership (derived from instance_of statements)
        SELECT EXISTS (
            SELECT 1 FROM type_membership tm
            WHERE tm.object_id = v_actual_obj
              AND tm.type_id   = v_expected_type
              AND (tm.alpha / (tm.alpha + tm.beta)) > 0.5
        ) INTO v_type_ok;

        IF NOT v_type_ok THEN
            IF v_strictness = 'hard' THEN
                RAISE EXCEPTION
                    'Hard domain violation on statement %: arg at position % (object %) '
                    'is not a confirmed member of expected type %',
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
                        'is not a confirmed member of expected type %s',
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
CREATE TRIGGER trg_z_soft_domain_check
    AFTER INSERT ON statements
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
-- Parameters:
--   p_threshold    (DEFAULT 0.5) — open_world mode only. Minimum
--     belief_mean required to consider a statement as holding. Lower
--     values recover weak-but-uncontested facts that 0.5 would suppress.
--   p_min_evidence (DEFAULT 0.0) — open_world mode only. Minimum
--     evidence mass (alpha + beta) required. Set > 2.0 to exclude
--     uniform-prior statements with no real evidence.
--
-- p_mode options:
--   'open_world'        — returns statements with belief_mean > p_threshold
--                         AND evidence_strength >= p_min_evidence.
--                         No default-true assumption. Absence of evidence
--                         is not evidence of absence.
--   'default_true'      — original v0.4 behaviour. 'default' t_kind
--                         statements are treated as true until a
--                         direct_negation conflict exists.
--   'evidence_weighted' — returns all matching statements regardless of
--                         belief_mean, ordered by belief_mean DESC.
--                         Intended for the reasoning layer to aggregate.
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
        SELECT sub.sid, sub.bmean, sub.estr, sub.interp
        FROM (
            SELECT s.id, s.belief_mean, s.belief_alpha + s.belief_beta, s.interpretation
            FROM statements s
            WHERE s.predicate_id = p_predicate_id
              AND s.object_args  = p_object_args
              AND s.context_id   = v_context_id
              AND s.t_kind IN ('eternal', 'always')

            UNION ALL

            SELECT s.id, s.belief_mean, s.belief_alpha + s.belief_beta, s.interpretation
            FROM statements s
            WHERE s.predicate_id = p_predicate_id
              AND s.object_args  = p_object_args
              AND s.context_id   = v_context_id
              AND s.t_kind IN ('interval', 'point')
              AND tstzrange(
                      coalesce(s.t_start_ts, '-infinity'::timestamptz),
                      coalesce(s.t_end_ts,   'infinity'::timestamptz), '[)'
                  ) @> p_time

            UNION ALL

            SELECT s.id, s.belief_mean, s.belief_alpha + s.belief_beta, s.interpretation
            FROM statements s
            WHERE s.predicate_id = p_predicate_id
              AND s.object_args  = p_object_args
              AND s.context_id   = v_context_id
              AND s.t_kind       = 'default'
        ) sub(sid, bmean, estr, interp)
        ORDER BY bmean DESC;

    ELSIF p_mode = 'default_true' THEN
        RETURN QUERY
        SELECT sub.sid, sub.bmean, sub.estr, sub.interp
        FROM (
            SELECT s.id, s.belief_mean, s.belief_alpha + s.belief_beta, s.interpretation
            FROM statements s
            WHERE s.predicate_id = p_predicate_id
              AND s.object_args  = p_object_args
              AND s.context_id   = v_context_id
              AND s.t_kind IN ('eternal', 'always')

            UNION ALL

            SELECT s.id, s.belief_mean, s.belief_alpha + s.belief_beta, s.interpretation
            FROM statements s
            WHERE s.predicate_id = p_predicate_id
              AND s.object_args  = p_object_args
              AND s.context_id   = v_context_id
              AND s.t_kind       = 'default'
              AND s.t_end_ts     IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM conflicts c
                  WHERE c.conflict_kind = 'direct_negation'
                    AND (c.statement_a = s.id OR c.statement_b = s.id)
                    AND c.resolved = false
              )

            UNION ALL

            SELECT s.id, s.belief_mean, s.belief_alpha + s.belief_beta, s.interpretation
            FROM statements s
            WHERE s.predicate_id = p_predicate_id
              AND s.object_args  = p_object_args
              AND s.context_id   = v_context_id
              AND s.t_kind IN ('interval', 'point')
              AND tstzrange(
                      coalesce(s.t_start_ts, '-infinity'::timestamptz),
                      coalesce(s.t_end_ts,   'infinity'::timestamptz), '[)'
                  ) @> p_time
        ) sub(sid, bmean, estr, interp)
        ORDER BY bmean DESC;

    ELSE
        -- Default: 'open_world'
        -- [Fix #2] Use p_threshold and p_min_evidence instead of hardcoded 0.5.
        RETURN QUERY
        SELECT sub.sid, sub.bmean, sub.estr, sub.interp
        FROM (
            SELECT s.id, s.belief_mean, s.belief_alpha + s.belief_beta, s.interpretation
            FROM statements s
            WHERE s.predicate_id                  = p_predicate_id
              AND s.object_args                   = p_object_args
              AND s.context_id                    = v_context_id
              AND s.belief_mean                   > p_threshold
              AND s.belief_alpha + s.belief_beta >= p_min_evidence
              AND s.t_kind IN ('eternal', 'always')

            UNION ALL

            SELECT s.id, s.belief_mean, s.belief_alpha + s.belief_beta, s.interpretation
            FROM statements s
            WHERE s.predicate_id                  = p_predicate_id
              AND s.object_args                   = p_object_args
              AND s.context_id                    = v_context_id
              AND s.belief_mean                   > p_threshold
              AND s.belief_alpha + s.belief_beta >= p_min_evidence
              AND s.t_kind IN ('interval', 'point')
              AND tstzrange(
                      coalesce(s.t_start_ts, '-infinity'::timestamptz),
                      coalesce(s.t_end_ts,   'infinity'::timestamptz), '[)'
                  ) @> p_time

            UNION ALL

            SELECT s.id, s.belief_mean, s.belief_alpha + s.belief_beta, s.interpretation
            FROM statements s
            WHERE s.predicate_id                  = p_predicate_id
              AND s.object_args                   = p_object_args
              AND s.context_id                    = v_context_id
              AND s.belief_mean                   > p_threshold
              AND s.belief_alpha + s.belief_beta >= p_min_evidence
              AND s.t_kind                        = 'default'
        ) sub(sid, bmean, estr, interp)
        ORDER BY bmean DESC;

    END IF;
END;
$$;


-- ── [Fix #6] compute_derived_belief ──────────────────────────
-- Computes (alpha, beta) for a forward-chained or abduced statement
-- from its parent statement IDs.
--
-- p_combination options:
--   'min'      (default) — conservative: result mean = min(parent means),
--              discounted by chain length. Use when parents are not
--              independent or when the weakest link dominates.
--   'log_odds' — log-odds combination for independent parents:
--              log_odds(result) = mean(log_odds(parent_i)), then
--              discounted by chain length. Use when parents are
--              genuinely independent evidence sources.
--
-- Discount factor: 0.9^p_chain_length applied to the result mean.
-- Reflects that longer inference chains produce less certain conclusions.
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
BEGIN
    IF p_parent_ids IS NULL OR cardinality(p_parent_ids) = 0 THEN
        RETURN QUERY SELECT 1.0::double precision, 1.0::double precision;
        RETURN;
    END IF;

    -- Discount per chain step; 0.9^depth
    v_discount := pow(0.9, GREATEST(p_chain_length, 0));

    IF p_combination = 'log_odds' THEN
        FOR v_alpha, v_beta IN
            SELECT s.belief_alpha, s.belief_beta
            FROM statements s
            WHERE s.id = ANY(p_parent_ids)
        LOOP
            v_mean     := v_alpha / (v_alpha + v_beta);
            -- Clamp away from 0 and 1 to keep log-odds finite
            v_mean     := GREATEST(1e-6, LEAST(1.0 - 1e-6, v_mean));
            v_log_odds := v_log_odds + ln(v_mean / (1.0 - v_mean));
            v_n        := v_n + 1;
        END LOOP;

        -- Average log-odds prevents unbounded compounding for large n
        v_result_mean := 1.0 / (1.0 + exp(-(v_log_odds / v_n))) * v_discount;

    ELSE
        -- Conservative min-of-means
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

    -- Map back to (alpha, beta) with evidence_strength = 2
    RETURN QUERY SELECT
        (v_result_mean * 2.0)::double precision,
        ((1.0 - v_result_mean) * 2.0)::double precision;
END;
$$;


-- ── [Fix #9] detect_conflicts ─────────────────────────────────
-- Scans statements for pairs with the same predicate + object_args
-- whose 95% Beta confidence intervals do not overlap, and inserts
-- them into conflicts as direct_negation.
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
-- bulk ingestion.
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
        WHERE s.context_id = v_context_id
    ),
    conflict_pairs AS (
        SELECT a.id AS stmt_a, b.id AS stmt_b
        FROM belief_ci a
        JOIN belief_ci b
          ON b.predicate_id = a.predicate_id
         AND b.object_args  = a.object_args
         -- Canonical ordering prevents duplicate (a,b) and (b,a) pairs
         AND b.id > a.id
        WHERE
            -- CIs are disjoint: a is entirely below b OR b entirely below a
            (a.ci_high < b.ci_low OR b.ci_high < a.ci_low)
            -- Not already recorded in either direction
            AND NOT EXISTS (
                SELECT 1 FROM conflicts c
                WHERE (c.statement_a = a.id AND c.statement_b = b.id)
                   OR (c.statement_a = b.id AND c.statement_b = a.id)
            )
    )
    INSERT INTO conflicts (statement_a, statement_b, conflict_kind)
    SELECT stmt_a, stmt_b, 'direct_negation'
    FROM conflict_pairs;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    RETURN v_inserted;
END;
$$;


-- ── [Fix #14] tell_about ──────────────────────────────────────
-- Returns all statements in which p_entity_id appears in any object
-- arg position, ordered by belief_mean DESC. Predicates and arg names
-- are resolved to canonical_name for readability.
--
-- This is the primary "what do we know about X?" query. It covers
-- statements where the entity is subject, object, or any positional
-- argument. Literal-only statements (no object_args) are excluded
-- since the entity cannot appear in them.
CREATE OR REPLACE FUNCTION tell_about(
    p_entity_id  uuid,
    p_context_id uuid    DEFAULT NULL,
    p_threshold  float   DEFAULT 0.0
) RETURNS TABLE (
    statement_id      uuid,
    predicate         text,
    arg_names         text[],
    literal_args      jsonb,
    belief_mean       double precision,
    evidence_strength double precision,
    interpretation    statement_interpretation,
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
        s.belief_mean,
        s.belief_alpha + s.belief_beta,
        s.interpretation,
        s.t_kind,
        s.t_start,
        s.t_end,
        c.canonical_name,
        s.derivation_type
    FROM statements s
    JOIN objects p ON p.id = s.predicate_id
    JOIN objects c ON c.id = s.context_id
    LEFT JOIN LATERAL (
        SELECT array_agg(o.canonical_name ORDER BY ord) AS names
        FROM unnest(s.object_args) WITH ORDINALITY AS u(oid, ord)
        JOIN objects o ON o.id = u.oid
    ) arg_names ON true
    WHERE p_entity_id = ANY(s.object_args)
      AND (p_context_id IS NULL OR s.context_id = p_context_id)
      AND s.belief_mean >= p_threshold
    ORDER BY s.belief_mean DESC;
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
    rule_name       text,
    edge_weight     double precision,
    derivation_type derivation_type
) LANGUAGE sql STABLE AS $$
    WITH RECURSIVE provenance AS (
        -- Base case: the target statement itself
        SELECT
            0                               AS depth,
            s.id                            AS statement_id,
            s.predicate_id,
            s.object_args,
            s.belief_mean,
            NULL::text                      AS rule_name,
            NULL::double precision          AS edge_weight,
            s.derivation_type,
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
            sd.rule_name,
            sd.weight,
            s.derivation_type,
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
        pr.rule_name,
        pr.edge_weight,
        pr.derivation_type
    FROM provenance pr
    JOIN objects p ON p.id = pr.predicate_id
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
     'NOT a scope placeholder — use no_scope for unscoped roles.'),

    -- [Fix #5] no_scope sentinel
    -- Distinct from unknown: use when a role genuinely has no institutional
    -- scope (e.g. an itinerant scholar), not when the scope is merely
    -- unknown to the asserting agent. For unknown scope, either leave
    -- the scope argument absent or assert a separate uncertainty statement.
    (stable_uuid('no_scope', 'entity'), 'entity', 'no_scope', 'No Scope',
     'Sentinel: this role or relation has no institutional scope. '
     'Use has_role(X, role, no_scope) when the role is genuinely unscoped. '
     'Distinct from unknown scope: unknown means the scope exists but is '
     'not known; no_scope means there is no scope by design.');


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

INSERT INTO statements
    (id, predicate_id, object_args, belief_alpha, belief_beta,
     interpretation, t_kind, context_id, derivation_type, derivation_depth)
VALUES
    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('concrete','entity'),  stable_uuid('entity','entity')],
     999,1,'ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('abstract','entity'),  stable_uuid('entity','entity')],
     999,1,'ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('living','entity'),    stable_uuid('concrete','entity')],
     999,1,'ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('animate','entity'),   stable_uuid('living','entity')],
     999,1,'ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('sapient','entity'),   stable_uuid('animate','entity')],
     999,1,'ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('person','entity'),    stable_uuid('sapient','entity')],
     999,1,'ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('artifact','entity'),  stable_uuid('concrete','entity')],
     999,1,'ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    -- [Fix #4] Transitional direct link — remove in v0.7 after objects kernel migration.
    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('process','entity'),   stable_uuid('entity','entity')],
     999,1,'ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('group','entity'),     stable_uuid('entity','entity')],
     999,1,'ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('number','entity'),    stable_uuid('abstract','entity')],
     999,1,'ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('relation','entity'),  stable_uuid('abstract','entity')],
     999,1,'ontological','eternal',stable_uuid('reality','context'),'axiomatic',0);

COMMIT;
