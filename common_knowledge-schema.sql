-- =============================================================
-- Common Knowledge KB — PostgreSQL Schema  (v2)
-- =============================================================
-- Changes from v1:
--   • statements.confidence (float) replaced by Beta distribution
--     (belief_alpha, belief_beta) — matches source_credibility model,
--     enables clean sequential Bayesian updates, collapses to logic
--     when one parameter dominates.
--   • statements.args (uuid[]) split into object_args (uuid[]) and
--     literal_args (jsonb) — prevents objects-table explosion for
--     numbers, strings, dates.
--   • derivation_type enum + derivation_depth on statements.
--   • domain tags (text[]) on predicates.
--   • Temporal indexing via explicit helper function + GiST index
--     on a computed tstzrange (done safely, avoiding Julian-day
--     arithmetic bugs from the tstzrange generator approach).
--   • statement_belief view exposes mean, variance, CI.
--   • update_belief() function for clean Bayesian evidence ingestion.
--   • Four new basis predicates: implies, correlated_with,
--     typical_of, occurs_in.
--   • Seed sources extended: 'system_kernel' with near-certain prior.
--   • Placeholder concepts: true, false, unknown added to objects.
-- =============================================================

-- ── Extensions ───────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";
CREATE EXTENSION IF NOT EXISTS "btree_gist";   -- needed for GiST on numeric ranges

-- ── Enums ────────────────────────────────────────────────────

CREATE TYPE object_kind AS ENUM (
    'person',
    'institution',
    'concept',
    'predicate',
    'context',
    'source',
    'event',
    'quantity'
);

CREATE TYPE temporal_kind AS ENUM (
    'eternal',     -- mathematical / logical truths; never retracted
    'always',      -- empirical generalisations; revisable
    'interval',    -- true between t_start and t_end
    'point',       -- true at a single moment
    'default'      -- assumed true until contradicted
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

CREATE TYPE context_kind AS ENUM (
    'reality',
    'domain',
    'theory',
    'fiction',
    'hypothetical',
    'game'
);

-- How was a statement introduced into the KB?
CREATE TYPE derivation_type AS ENUM (
    'axiomatic',         -- kernel axiom, treated as certain
    'user_asserted',     -- entered directly by a user
    'source_ingested',   -- extracted from an external source
    'forward_chained',   -- derived by a forward-chaining rule
    'abduced',           -- abductive inference
    'learned'            -- produced by a learning process (LLM extraction etc.)
);

-- ── Composite type: fuzzy timestamp ──────────────────────────
-- All values are Julian Day Numbers (float) for arithmetic ease.
-- NULL best  → unknown point.
-- NULL lo/hi → unbounded in that direction.
CREATE TYPE fuzzy_time AS (
    best        double precision,
    lo          double precision,
    hi          double precision,
    granularity time_granularity
);

-- Convert a proleptic Gregorian year (negative = BCE) to Julian Day.
CREATE OR REPLACE FUNCTION year_to_jd(y integer)
RETURNS double precision LANGUAGE sql IMMUTABLE AS $$
    SELECT 365.25 * (y + 4716) - 1524.5;
$$;

-- Safe conversion of a Julian Day Number to a Postgres timestamptz.
-- Clamps to [0001-01-01, 9999-12-31] so generated expressions stay valid.
CREATE OR REPLACE FUNCTION jd_to_tstz(jd double precision)
RETURNS timestamptz LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN jd IS NULL      THEN NULL
        WHEN jd < 1721425.5  THEN '0001-01-01 00:00:00+00'::timestamptz
        WHEN jd > 5373484.5  THEN '9999-12-31 23:59:59+00'::timestamptz
        ELSE to_timestamp((jd - 2440587.5) * 86400.0)
    END;
$$;

-- ── Core: objects ─────────────────────────────────────────────
CREATE TABLE objects (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    kind            object_kind NOT NULL,
    canonical_name  text        NOT NULL,
    display_name    text,
    aliases         text[]      NOT NULL DEFAULT '{}',
    description     text,
    embedding       vector(768),
    -- Sparse vector over predicate IDs for basis decomposition.
    -- Keys are predicate uuid strings; values are floats.
    basis_weights   jsonb,
    -- External identifiers: {"wikidata":"Q11696","cyc":"..."}
    external_ids    jsonb,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT canonical_name_kind_unique UNIQUE (canonical_name, kind)
);

CREATE INDEX idx_objects_kind      ON objects (kind);
CREATE INDEX idx_objects_aliases   ON objects USING GIN (aliases);
CREATE INDEX idx_objects_external  ON objects USING GIN (external_ids);
CREATE INDEX idx_objects_embedding ON objects USING hnsw (embedding vector_cosine_ops);

-- ── Predicate metadata ────────────────────────────────────────
CREATE TABLE predicates (
    id               uuid             PRIMARY KEY
                         REFERENCES objects (id) ON DELETE CASCADE,
    arity            int              NOT NULL CHECK (arity BETWEEN 1 AND 8),
    arg_kinds        object_kind[],   -- NULL = any kind accepted
    arg_labels       text[],
    fol_definition   text,
    nl_description   text,
    source_predicate text,            -- e.g. "wikidata:P39"
    is_basis         boolean          NOT NULL DEFAULT false,
    -- Semantic domains: {'temporal','causal','social','spatial',...}
    domains          text[]           NOT NULL DEFAULT '{}',
    status           predicate_status NOT NULL DEFAULT 'proposed',
    introduced_by    uuid             REFERENCES objects (id),
    introduced_at    timestamptz      NOT NULL DEFAULT now()
);

CREATE INDEX idx_predicates_basis   ON predicates (is_basis) WHERE is_basis;
CREATE INDEX idx_predicates_domains ON predicates USING GIN (domains);
CREATE INDEX idx_predicates_status  ON predicates (status);

-- ── Context metadata ──────────────────────────────────────────
CREATE TABLE contexts (
    id          uuid         PRIMARY KEY
                    REFERENCES objects (id) ON DELETE CASCADE,
    kind        context_kind NOT NULL DEFAULT 'reality',
    parent_id   uuid         REFERENCES contexts (id),
    description text
);

-- ── Statements ───────────────────────────────────────────────
CREATE TABLE statements (
    id              uuid             PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Logical content
    predicate_id    uuid             NOT NULL REFERENCES objects (id),

    -- Object arguments: FK references into objects table.
    object_args     uuid[]           NOT NULL DEFAULT '{}',

    -- Literal arguments: ordered JSON array of typed values.
    -- Each element: {"pos":2,"type":"integer","value":10}
    -- Types: "string"|"integer"|"float"|"date"|"fuzzy_time"|"bool"
    literal_args    jsonb            NOT NULL DEFAULT '[]',

    -- Positional type manifest, one entry per predicate argument.
    -- "object" or a literal type name.
    -- e.g. ["object","object","object","integer"] for held_office
    arg_types       text[]           NOT NULL DEFAULT '{}',

    -- Epistemic status: Beta distribution over P(statement is true).
    -- Mean = belief_alpha / (belief_alpha + belief_beta).
    -- Uniform prior (new, unverified): alpha=1, beta=1.
    -- Near-certain (kernel axiom):     alpha=1000, beta=0.001.
    -- Update: verified   → belief_alpha += source_credibility_mean
    --         refuted    → belief_beta  += source_credibility_mean
    belief_alpha    double precision NOT NULL DEFAULT 1.0
                        CHECK (belief_alpha > 0),
    belief_beta     double precision NOT NULL DEFAULT 1.0
                        CHECK (belief_beta  > 0),

    -- Explicit negation: asserts predicate does NOT hold.
    negated         boolean          NOT NULL DEFAULT false,

    -- Temporal scope
    t_kind          temporal_kind    NOT NULL DEFAULT 'default',
    t_start         fuzzy_time,
    t_end           fuzzy_time,

    -- Pre-computed timestamptz for range queries (NULL for eternal/always).
    t_start_ts      timestamptz      GENERATED ALWAYS AS (
                        jd_to_tstz((t_start).best)
                    ) STORED,
    t_end_ts        timestamptz      GENERATED ALWAYS AS (
                        jd_to_tstz((t_end).best)
                    ) STORED,

    -- Context
    context_id      uuid             NOT NULL REFERENCES objects (id),

    -- Provenance
    derivation_type  derivation_type NOT NULL DEFAULT 'user_asserted',
    derivation_depth int             NOT NULL DEFAULT 0
                        CHECK (derivation_depth >= 0),
    derived_from    uuid[]           NOT NULL DEFAULT '{}',

    created_at      timestamptz      NOT NULL DEFAULT now(),
    updated_at      timestamptz      NOT NULL DEFAULT now(),

    CONSTRAINT args_nonempty CHECK (
        array_length(object_args, 1) >= 1
        OR jsonb_array_length(literal_args) >= 1
    )
);

CREATE INDEX idx_stmt_predicate    ON statements (predicate_id);
CREATE INDEX idx_stmt_context      ON statements (context_id);
CREATE INDEX idx_stmt_t_kind       ON statements (t_kind);
CREATE INDEX idx_stmt_deriv_type   ON statements (derivation_type);
CREATE INDEX idx_stmt_object_args  ON statements USING GIN (object_args);
CREATE INDEX idx_stmt_derived_from ON statements USING GIN (derived_from);

-- Temporal range index for "what held at time T?" queries.
CREATE INDEX idx_stmt_temporal_range ON statements USING GIST (
    tstzrange(
        coalesce(t_start_ts, '-infinity'::timestamptz),
        coalesce(t_end_ts,   'infinity'::timestamptz),
        '[)'
    )
) WHERE t_kind IN ('interval', 'point');

-- Fast path for eternal truths (very frequent).
CREATE INDEX idx_stmt_eternal ON statements (predicate_id)
    WHERE t_kind = 'eternal';

-- ── Views ────────────────────────────────────────────────────

CREATE VIEW statement_belief AS
SELECT
    id,
    belief_alpha,
    belief_beta,
    belief_alpha / (belief_alpha + belief_beta)        AS mean,
    belief_alpha + belief_beta                          AS evidence_strength,
    (belief_alpha * belief_beta)
        / (pow(belief_alpha + belief_beta, 2)
           * (belief_alpha + belief_beta + 1))          AS variance,
    GREATEST(0,
        belief_alpha / (belief_alpha + belief_beta)
        - 1.96 * sqrt(
            (belief_alpha * belief_beta)
            / (pow(belief_alpha + belief_beta, 2)
               * (belief_alpha + belief_beta + 1))
        )
    )                                                   AS ci_low,
    LEAST(1,
        belief_alpha / (belief_alpha + belief_beta)
        + 1.96 * sqrt(
            (belief_alpha * belief_beta)
            / (pow(belief_alpha + belief_beta, 2)
               * (belief_alpha + belief_beta + 1))
        )
    )                                                   AS ci_high,
    negated,
    t_kind,
    context_id,
    derivation_type,
    derivation_depth
FROM statements;

CREATE VIEW statement_view AS
SELECT
    s.id,
    p.canonical_name                                     AS predicate,
    s.object_args,
    s.literal_args,
    s.arg_types,
    s.belief_alpha / (s.belief_alpha + s.belief_beta)    AS belief_mean,
    s.belief_alpha + s.belief_beta                        AS evidence_strength,
    s.negated,
    s.t_kind,
    s.t_start,
    s.t_end,
    c.canonical_name                                     AS context,
    s.derivation_type,
    s.derivation_depth,
    s.derived_from,
    s.created_at
FROM statements s
JOIN objects p ON p.id = s.predicate_id
JOIN objects c ON c.id = s.context_id;

-- ── Attestations ─────────────────────────────────────────────
CREATE TABLE attestations (
    id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    statement_id uuid        NOT NULL REFERENCES statements (id) ON DELETE CASCADE,
    source_id    uuid        NOT NULL REFERENCES objects (id),
    raw_claim    text,
    url          text,
    accessed_at  timestamptz,
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_attest_statement ON attestations (statement_id);
CREATE INDEX idx_attest_source    ON attestations (source_id);

-- ── Source credibility ───────────────────────────────────────
CREATE TABLE source_credibility (
    source_id   uuid             NOT NULL REFERENCES objects (id),
    context_id  uuid             NOT NULL REFERENCES objects (id),
    alpha       double precision NOT NULL DEFAULT 1.0 CHECK (alpha > 0),
    beta        double precision NOT NULL DEFAULT 1.0 CHECK (beta  > 0),
    updated_at  timestamptz      NOT NULL DEFAULT now(),
    PRIMARY KEY (source_id, context_id)
);

CREATE VIEW source_credibility_score AS
SELECT
    source_id,
    context_id,
    alpha / (alpha + beta)                          AS mean,
    alpha + beta                                     AS evidence_strength,
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

CREATE VIEW statement_credibility AS
SELECT
    a.statement_id,
    sum(sc.mean * sc.evidence_strength)
        / nullif(sum(sc.evidence_strength), 0)  AS weighted_credibility,
    sum(sc.evidence_strength)                    AS total_source_weight,
    count(a.id)                                  AS source_count
FROM attestations a
JOIN statements s   ON s.id  = a.statement_id
JOIN source_credibility_score sc
     ON  sc.source_id  = a.source_id
     AND sc.context_id = s.context_id
GROUP BY a.statement_id;

-- ── Predicate subsumption ────────────────────────────────────
CREATE TABLE predicate_subsumption (
    child_id    uuid             NOT NULL REFERENCES objects (id),
    parent_id   uuid             NOT NULL REFERENCES objects (id),
    probability double precision NOT NULL DEFAULT 1.0
                    CHECK (probability BETWEEN 0.0 AND 1.0),
    context_id  uuid             REFERENCES objects (id),
    PRIMARY KEY (child_id, parent_id)
);

-- ── Type membership ──────────────────────────────────────────
CREATE TABLE type_membership (
    object_id   uuid             NOT NULL REFERENCES objects (id),
    type_id     uuid             NOT NULL REFERENCES objects (id),
    probability double precision NOT NULL DEFAULT 1.0
                    CHECK (probability BETWEEN 0.0 AND 1.0),
    context_id  uuid             REFERENCES objects (id),
    PRIMARY KEY (object_id, type_id)
);

-- ── Conflicts ────────────────────────────────────────────────
CREATE TABLE conflicts (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    statement_a     uuid        NOT NULL REFERENCES statements (id),
    statement_b     uuid        NOT NULL REFERENCES statements (id),
    conflict_kind   text,
    resolved        boolean     NOT NULL DEFAULT false,
    resolution_note text,
    created_at      timestamptz NOT NULL DEFAULT now()
);

-- ════════════════════════════════════════════════════════════
-- FUNCTIONS
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION update_trust(
    p_source_id  uuid,
    p_context_id uuid,
    p_correct    boolean
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO source_credibility (source_id, context_id, alpha, beta)
    VALUES (p_source_id, p_context_id, 1.0, 1.0)
    ON CONFLICT (source_id, context_id) DO NOTHING;

    IF p_correct THEN
        UPDATE source_credibility
           SET alpha = alpha + 1.0, updated_at = now()
         WHERE source_id = p_source_id AND context_id = p_context_id;
    ELSE
        UPDATE source_credibility
           SET beta  = beta  + 1.0, updated_at = now()
         WHERE source_id = p_source_id AND context_id = p_context_id;
    END IF;
END;
$$;

-- Incorporate one piece of evidence into a statement's Beta belief.
-- p_weight  : source credibility mean (0–1).
-- p_supports: true = evidence for, false = evidence against.
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

CREATE OR REPLACE FUNCTION belief_mean(p_statement_id uuid)
RETURNS double precision LANGUAGE sql STABLE AS $$
    SELECT belief_alpha / (belief_alpha + belief_beta)
      FROM statements WHERE id = p_statement_id;
$$;

-- Returns statements for predicate+args that hold at a given time.
CREATE OR REPLACE FUNCTION holds_at(
    p_predicate_id uuid,
    p_object_args  uuid[],
    p_time         timestamptz,
    p_context_id   uuid DEFAULT '00000000-0000-0000-0000-000000000001'
) RETURNS TABLE (
    statement_id    uuid,
    belief_mean_val double precision,
    evidence_str    double precision
) LANGUAGE sql STABLE AS $$
    SELECT
        s.id,
        s.belief_alpha / (s.belief_alpha + s.belief_beta),
        s.belief_alpha + s.belief_beta
    FROM statements s
    WHERE s.predicate_id = p_predicate_id
      AND s.object_args  @> p_object_args
      AND s.context_id   = p_context_id
      AND s.negated      = false
      AND (
          s.t_kind IN ('eternal', 'always')
          OR (s.t_kind = 'interval'
              AND tstzrange(
                  coalesce(s.t_start_ts, '-infinity'::timestamptz),
                  coalesce(s.t_end_ts,   'infinity'::timestamptz), '[)'
              ) @> p_time)
          OR (s.t_kind = 'default' AND s.t_end_ts IS NULL)
          OR (s.t_kind = 'point'
              AND s.t_start_ts IS NOT NULL
              AND s.t_start_ts <= p_time
              AND p_time < coalesce(s.t_end_ts,
                                    p_time + interval '1 second'))
      )
    ORDER BY (s.belief_alpha / (s.belief_alpha + s.belief_beta)) DESC;
$$;

-- ════════════════════════════════════════════════════════════
-- SEED DATA
-- ════════════════════════════════════════════════════════════

INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES
    ('00000000-0000-0000-0000-000000000001',
     'context',  'reality',       'Reality',
     'The default real-world context'),
    ('00000000-0000-0000-0000-000000000002',
     'source',   'user_parent',   'User (parent)',
     'Primary user — highest trust, analogous to a parent'),
    ('00000000-0000-0000-0000-000000000003',
     'source',   'wikidata',      'Wikidata',
     'Wikidata knowledge graph'),
    ('00000000-0000-0000-0000-000000000004',
     'source',   'llm_generated', 'LLM generated',
     'Fact proposed by language model; lower prior trust'),
    ('00000000-0000-0000-0000-000000000005',
     'source',   'system_kernel', 'System kernel',
     'Axiomatic facts at KB initialisation; near-certain'),
    ('00000000-0000-0000-0000-000000000010',
     'concept',  'true',          'True',  'The Boolean value true'),
    ('00000000-0000-0000-0000-000000000011',
     'concept',  'false',         'False', 'The Boolean value false'),
    ('00000000-0000-0000-0000-000000000012',
     'concept',  'unknown',       'Unknown',
     'Placeholder for unknown or anonymous entities');

INSERT INTO contexts (id, kind, parent_id) VALUES
    ('00000000-0000-0000-0000-000000000001', 'reality', NULL);

INSERT INTO source_credibility (source_id, context_id, alpha, beta) VALUES
    ('00000000-0000-0000-0000-000000000002',
     '00000000-0000-0000-0000-000000000001',   19.0,    1.0),
    ('00000000-0000-0000-0000-000000000003',
     '00000000-0000-0000-0000-000000000001',   13.0,    2.0),
    ('00000000-0000-0000-0000-000000000004',
     '00000000-0000-0000-0000-000000000001',    3.0,    2.0),
    ('00000000-0000-0000-0000-000000000005',
     '00000000-0000-0000-0000-000000000001', 1000.0,    0.001);
