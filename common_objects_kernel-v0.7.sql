-- =============================================================
-- Common Knowledge KB — Basis Objects & Statements (v0.7)
-- =============================================================
-- Seeds all non-backbone entity objects, domain context objects,
-- type hierarchy statements, disjointness axioms, FOL rules, and
-- typicality prototypes.
--
-- Run order (mandatory):
--   1. common_knowledge_schema.sql
--   2. common_predicates_kernel.sql
--   3. THIS FILE
--
-- All kernel statements use:
--   belief_alpha = 1000.0, belief_beta = 0.001  (near-certain, ~0.9999)
--   t_kind       = 'eternal' (unless stated otherwise)
--   derivation_type = 'axiomatic'
--
-- v0.7 changes:
--
--   statement_kind ON ALL STATEMENTS  [Fix #17]
--     All INSERT INTO statements blocks now include the statement_kind
--     column (added to the schema in v0.7). Values used:
--       'ontological' — subtype_of, is_a, disjoint_with, equivalent_to,
--                       opposite_of, different_from; any structural claim.
--       'statistical' — typical_of; all typicality prototypes (Section 16).
--       'rule'        — implies with literal_args; FOL inference rules
--                       (Section 15). Rule statements are opaque to
--                       holds_at() and tell_about().
--     The interpretation column is now largely superseded by statement_kind
--     for inference chain gating; both are retained for backward compat.
--
--   ROLE SUBTYPE is_a ROWS REMOVED  [Fix #22]
--     Section 12 previously inserted is_a(mathematician, role),
--     is_a(programmer, role), etc. alongside the subtype_of(mathematician,
--     role) rows in Section 13. With the recursive CTE in
--     trg_z_soft_domain_check (v0.7 schema), the subtype_of rows alone
--     are sufficient for domain enforcement; the is_a duplicates created
--     a type/instance punning problem (role subtypes treated simultaneously
--     as types and individuals). Removed from Section 12. The subtype_of
--     statements in Section 13 are the authoritative hierarchy.
--
--   no_period SENTINEL REFERENCED  [Fix #23]
--     The no_period sentinel (seeded by common_knowledge_schema.sql) is
--     referenced in the DECLARE block and verified in the sanity checks.
--     The unknown entity description is updated to distinguish it from
--     both no_scope (role-scope sentinel) and no_period (time-period
--     sentinel). See schema canonical policy decision #3.
--
--   PROCESS HIERARCHY STUB REMOVAL  [Fix #4, carried from v0.6]
--     This file seeds process ⊂ event_type ⊂ abstract ⊂ entity.
--     The schema backbone stub process ⊂ entity is now superseded.
--     After applying this file, remove the stub:
--
--       DELETE FROM statements
--       WHERE predicate_id = stable_uuid('subtype_of','predicate')
--         AND object_args  = ARRAY[stable_uuid('process','entity'),
--                                  stable_uuid('entity','entity')]
--         AND derivation_type = 'axiomatic';
--
--     Verify the chain (process ⊂ event_type ⊂ abstract ⊂ entity) holds
--     in the hierarchy verification query at the end of the file before
--     deleting the stub.
--
-- =============================================================

BEGIN;

DO $$
DECLARE
    -- ── Fixed IDs from schema seed ────────────────────────────
    reality  uuid := stable_uuid('reality',       'context');
    sys      uuid := stable_uuid('system_kernel', 'source');

    -- ── Predicate IDs ─────────────────────────────────────────
    p_is_a           uuid := stable_uuid('is_a',            'predicate');
    p_subtype_of     uuid := stable_uuid('subtype_of',      'predicate');
    p_has_property   uuid := stable_uuid('has_property',    'predicate');
    p_same_as        uuid := stable_uuid('same_as',         'predicate');
    p_different_from uuid := stable_uuid('different_from',  'predicate');
    p_opposite_of    uuid := stable_uuid('opposite_of',     'predicate');
    p_implies        uuid := stable_uuid('implies',         'predicate');
    p_typical_of     uuid := stable_uuid('typical_of',      'predicate');
    p_disjoint_with  uuid := stable_uuid('disjoint_with',   'predicate');
    p_has_value      uuid := stable_uuid('has_value',       'predicate');
    p_equivalent_to  uuid := stable_uuid('equivalent_to',   'predicate');
    p_part_of        uuid := stable_uuid('part_of',         'predicate');
    p_member_of      uuid := stable_uuid('member_of',       'predicate');

    -- ── Kernel belief parameters ──────────────────────────────
    ka  double precision := 1000.0;
    kb  double precision := 0.001;

    -- ── Object IDs — all stable_uuid(name, 'entity') ─────────
    -- Backbone objects (seeded by schema; DO NOTHING on conflict)
    o_entity        uuid := stable_uuid('entity',           'entity');
    o_abstract      uuid := stable_uuid('abstract',         'entity');
    o_concrete      uuid := stable_uuid('concrete',         'entity');
    o_living        uuid := stable_uuid('living',           'entity');
    o_animate       uuid := stable_uuid('animate',          'entity');
    o_sapient       uuid := stable_uuid('sapient',          'entity');
    o_artifact      uuid := stable_uuid('artifact',         'entity');
    o_process       uuid := stable_uuid('process',          'entity');
    o_group         uuid := stable_uuid('group',            'entity');
    o_person        uuid := stable_uuid('person',           'entity');
    o_number        uuid := stable_uuid('number',           'entity');
    o_relation      uuid := stable_uuid('relation',         'entity');
    o_agent         uuid := stable_uuid('agent',            'entity');
    o_institution   uuid := stable_uuid('institution',      'entity');
    o_government    uuid := stable_uuid('government',       'entity');

    -- Sentinels (seeded by schema; referenced here)
    o_no_scope      uuid := stable_uuid('no_scope',         'entity');
    o_no_period     uuid := stable_uuid('no_period',        'entity');  -- [Fix #23]

    -- Animate / social (extensions beyond backbone)
    o_biological_taxon uuid := stable_uuid('biological_taxon','entity');
    o_organism      uuid := stable_uuid('organism',         'entity');
    o_animal        uuid := stable_uuid('animal',           'entity');
    o_mammal        uuid := stable_uuid('mammal',           'entity');

    -- Abstract concept vocabulary
    o_concept_type  uuid := stable_uuid('concept_type',     'entity');
    o_property_c    uuid := stable_uuid('property',         'entity');
    o_attribute     uuid := stable_uuid('attribute',        'entity');
    o_relation_type uuid := stable_uuid('relation_type',    'entity');
    o_proposition   uuid := stable_uuid('proposition',      'entity');
    o_information   uuid := stable_uuid('information',      'entity');
    o_knowledge_st  uuid := stable_uuid('knowledge_state',  'entity');
    o_norm          uuid := stable_uuid('norm',             'entity');
    o_rule          uuid := stable_uuid('rule',             'entity');
    o_goal          uuid := stable_uuid('goal',             'entity');
    o_role_c        uuid := stable_uuid('role',             'entity');
    o_symbol        uuid := stable_uuid('symbol',           'entity');
    o_language      uuid := stable_uuid('language',         'entity');
    o_word          uuid := stable_uuid('word',             'entity');
    o_sentence      uuid := stable_uuid('sentence',         'entity');

    -- Events / processes / states
    o_event         uuid := stable_uuid('event_type',       'entity');
    o_change_event  uuid := stable_uuid('change_event',     'entity');
    o_state_c       uuid := stable_uuid('state',            'entity');
    o_action        uuid := stable_uuid('action',           'entity');

    -- Physical subtypes
    o_phys_obj      uuid := stable_uuid('physical_object',  'entity');
    o_place         uuid := stable_uuid('place',            'entity');
    o_region        uuid := stable_uuid('region',           'entity');
    o_location      uuid := stable_uuid('location',         'entity');
    o_boundary      uuid := stable_uuid('boundary',         'entity');

    -- Quantities and numbers
    o_quantity      uuid := stable_uuid('quantity',         'entity');
    o_real          uuid := stable_uuid('real_number',      'entity');
    o_integer       uuid := stable_uuid('integer',          'entity');
    o_natural       uuid := stable_uuid('natural_number',   'entity');
    o_unit          uuid := stable_uuid('unit_of_measure',  'entity');
    o_measurement   uuid := stable_uuid('measurement',      'entity');
    o_duration      uuid := stable_uuid('duration',         'entity');

    -- Time
    o_time          uuid := stable_uuid('time',             'entity');
    o_interval_t    uuid := stable_uuid('time_interval',    'entity');
    o_point_t       uuid := stable_uuid('time_point',       'entity');

    -- Truth values (seeded by schema as 'entity' kind)
    o_truth_value   uuid := stable_uuid('truth_value',      'entity');
    o_true_val      uuid := stable_uuid('true',             'entity');
    o_false_val     uuid := stable_uuid('false',            'entity');
    o_unknown_val   uuid := stable_uuid('unknown',          'entity');

    -- Role subtypes: functional occupation / role types.
    -- Subtypes of role (abstract entity). Seeded so type reasoning works:
    -- has_role(ada_lovelace, mathematician, no_scope) can be type-checked.
    o_mathematician uuid := stable_uuid('mathematician',     'entity');
    o_programmer    uuid := stable_uuid('programmer',        'entity');
    o_inventor      uuid := stable_uuid('inventor',          'entity');
    o_scientist     uuid := stable_uuid('scientist',         'entity');
    o_engineer      uuid := stable_uuid('engineer',          'entity');
    o_teacher       uuid := stable_uuid('teacher',           'entity');
    o_politician    uuid := stable_uuid('politician',        'entity');
    o_artist        uuid := stable_uuid('artist',            'entity');

    -- Domain contexts
    o_dom_history   uuid := stable_uuid('domain_history',    'context');
    o_dom_science   uuid := stable_uuid('domain_science',    'context');
    o_dom_math      uuid := stable_uuid('domain_mathematics','context');
    o_dom_geography uuid := stable_uuid('domain_geography',  'context');
    o_dom_biology   uuid := stable_uuid('domain_biology',    'context');
    o_dom_physics   uuid := stable_uuid('domain_physics',    'context');
    o_dom_law       uuid := stable_uuid('domain_law',        'context');
    o_dom_language  uuid := stable_uuid('domain_linguistics','context');
    o_dom_social    uuid := stable_uuid('domain_social',     'context');
    o_dom_tech      uuid := stable_uuid('domain_technology', 'context');

BEGIN

-- ═════════════════════════════════════════════════════════════
-- SECTION 1: Sanity checks
-- Verifies that prerequisite files have been applied.
-- ═════════════════════════════════════════════════════════════

IF NOT EXISTS (SELECT 1 FROM objects WHERE id = p_is_a AND kind = 'predicate') THEN
    RAISE EXCEPTION
        'Basis predicates not found (expected is_a at %). '
        'Run common_predicates_kernel.sql before this file.',
        p_is_a;
END IF;

IF NOT EXISTS (SELECT 1 FROM objects WHERE id = o_entity AND kind = 'entity') THEN
    RAISE EXCEPTION
        'Backbone entity objects not found. '
        'Run common_knowledge_schema.sql before this file.';
END IF;

IF NOT EXISTS (SELECT 1 FROM objects WHERE id = o_no_scope AND kind = 'entity') THEN
    RAISE EXCEPTION
        'no_scope sentinel not found (expected at %). '
        'Run common_knowledge_schema.sql before this file.',
        o_no_scope;
END IF;

-- [Fix #23] Verify no_period sentinel exists (seeded by schema v0.7).
IF NOT EXISTS (SELECT 1 FROM objects WHERE id = o_no_period AND kind = 'entity') THEN
    RAISE EXCEPTION
        'no_period sentinel not found (expected at %). '
        'Run common_knowledge_schema.sql (v0.7+) before this file.',
        o_no_period;
END IF;

-- ═════════════════════════════════════════════════════════════
-- SECTION 2: Backbone objects — enrich descriptions
-- Schema seeds these with minimal descriptions; we enrich here.
-- ═════════════════════════════════════════════════════════════

UPDATE objects SET
    display_name = 'Entity',
    description  = 'Anything that exists or can be referred to. '
                   'Absolute top of the object hierarchy.'
WHERE id = o_entity;

UPDATE objects SET
    display_name = 'Abstract',
    description  = 'An entity with no direct physical instantiation: '
                   'concepts, numbers, propositions, rules, relations. '
                   'Disjoint with concrete (see Section 14).'
WHERE id = o_abstract;

UPDATE objects SET
    display_name = 'Concrete',
    description  = 'An entity that occupies or is located in physical space and time. '
                   'Disjoint with abstract (see Section 14).'
WHERE id = o_concrete;

-- Enrich Boolean / epistemic sentinel descriptions.
UPDATE objects SET
    description = 'The Boolean value true; an instance of truth_value.'
WHERE id = o_true_val;

UPDATE objects SET
    description = 'The Boolean value false; an instance of truth_value.'
WHERE id = o_false_val;

-- [Fix #23] unknown is an epistemic state — not a scope or period placeholder.
UPDATE objects SET
    description = 'Epistemic sentinel: the identity or value is not known to the '
                  'asserting agent. NOT a scope placeholder — use no_scope for '
                  'has_role(X, role, no_scope) when a role is genuinely unscoped. '
                  'NOT a time-period placeholder — use no_period for the third arg '
                  'of located_in and similar ternary predicates when no named period '
                  'is the semantic argument. Conflating unknown scope or unknown period '
                  'with absent scope/period is a category error.'
WHERE id = o_unknown_val;

-- Enrich government description (seeded by schema as functional role).
UPDATE objects SET
    display_name = 'Government',
    description  = 'Functional role: governing body of a polity. '
                   'Subtype of institution (hence of agent and group). '
                   'Use has_role(X, government, polity) rather than typing X as government.'
WHERE id = o_government;

-- ═════════════════════════════════════════════════════════════
-- SECTION 3: Animate / social objects (extensions beyond backbone)
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES
    (o_biological_taxon, 'entity', 'biological_taxon', 'Biological taxon',
     'A named group in a biological classification system '
     '(species, genus, family, …). Abstract type, not a physical organism.'),
    (o_organism, 'entity', 'organism', 'Organism',
     'A living entity: plant, animal, fungus, microbe.'),
    (o_animal,   'entity', 'animal',   'Animal',
     'A multicellular organism of the kingdom Animalia.'),
    (o_mammal,   'entity', 'mammal',   'Mammal',
     'A warm-blooded vertebrate of class Mammalia; nurses young with milk.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 4: Abstract concept vocabulary
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES
    (o_concept_type, 'entity', 'concept_type', 'Concept',
     'An abstract idea, category, or mental representation.'),
    (o_property_c,   'entity', 'property',     'Property',
     'An attribute or characteristic that an entity can have; a unary predicate.'),
    (o_attribute,    'entity', 'attribute',    'Attribute',
     'A named feature of an entity that takes a value. '
     'Distinct from property: attributes have values; properties are Boolean.'),
    (o_relation_type,'entity', 'relation_type','Relation type',
     'A type of relation in the predicate vocabulary '
     '(e.g. subtype_of, causes). Subtype of relation.'),
    (o_proposition,  'entity', 'proposition',  'Proposition',
     'A statement that is either true or false in some context.'),
    (o_information,  'entity', 'information',  'Information',
     'Structured content that can be communicated or encoded. '
     'Distinct from knowledge: information does not require a knowing agent.'),
    (o_knowledge_st, 'entity', 'knowledge_state', 'Knowledge state',
     'The set of propositions an agent takes to be true at a time. '
     'Argument type for knows() and believes().'),
    (o_norm,         'entity', 'norm',         'Norm',
     'A standard, obligation, or expectation governing behaviour in a context.'),
    (o_rule,         'entity', 'rule',         'Rule',
     'A formal or informal prescription specifying what should happen '
     'under a condition. Subtype of norm.'),
    (o_goal,         'entity', 'goal',         'Goal',
     'A desired state or outcome that an agent is motivated to bring about.'),
    (o_role_c,       'entity', 'role',         'Role',
     'A position, function, or capacity that an entity occupies within a scope. '
     'Second argument of has_role(entity, role, scope). '
     'Specific role subtypes (mathematician, programmer, etc.) are seeded '
     'in Section 6 of this file as subtypes via subtype_of.'),
    (o_symbol,       'entity', 'symbol',       'Symbol',
     'A sign that represents something else by convention. '
     'Symbols are abstract; the physical inscription is a concrete object.'),
    (o_language,     'entity', 'language',     'Language',
     'A system of communication using symbols according to a grammar.'),
    (o_word,         'entity', 'word',         'Word',
     'A minimal free-standing linguistic unit in a language.'),
    (o_sentence,     'entity', 'sentence',     'Sentence',
     'A grammatical unit expressing a complete thought or proposition.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 5: Event / process / state objects
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES
    (o_event,       'entity', 'event_type',   'Event',
     'A change or occurrence at a time, involving participants. '
     'Abstract type; not a physical object. '
     'Correct chain: process ⊂ event_type ⊂ abstract ⊂ entity. '
     'The schema backbone stub process ⊂ entity is superseded by this file; '
     'see migration note in the file header.'),
    (o_change_event,'entity', 'change_event', 'Change event',
     'An event in which some property or state transitions from one value to another. '
     'Core to Event Calculus: initiates() and terminates() apply to change_events.'),
    (o_state_c,     'entity', 'state',        'State',
     'A condition that persists over a time interval without requiring ongoing action.'),
    (o_action,      'entity', 'action',       'Action',
     'An event intentionally performed by an agent.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 6: Role subtype objects
-- These are entity objects whose type hierarchy is established via
-- subtype_of(X, role) in Section 13. [Fix #22] is_a statements for
-- these objects are NOT inserted in Section 12 — the recursive CTE
-- in trg_z_soft_domain_check resolves subtype_of transitively,
-- so the is_a rows would create type/instance punning without benefit.
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES
    (o_mathematician,'entity', 'mathematician', 'Mathematician',
     'Role: one who practises or studies mathematics. Subtype of role.'),
    (o_programmer,   'entity', 'programmer',   'Programmer',
     'Role: one who writes software. Subtype of role.'),
    (o_inventor,     'entity', 'inventor',     'Inventor',
     'Role: one who creates novel devices, processes, or compositions. '
     'Subtype of role.'),
    (o_scientist,    'entity', 'scientist',    'Scientist',
     'Role: one who conducts systematic empirical inquiry. Subtype of role.'),
    (o_engineer,     'entity', 'engineer',     'Engineer',
     'Role: one who applies scientific knowledge to design and build systems. '
     'Subtype of role.'),
    (o_teacher,      'entity', 'teacher',      'Teacher',
     'Role: one who instructs or facilitates learning. Subtype of role.'),
    (o_politician,   'entity', 'politician',   'Politician',
     'Role: one who participates in organised political activity. Subtype of role.'),
    (o_artist,       'entity', 'artist',       'Artist',
     'Role: one who creates aesthetic works. Subtype of role.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 7: Physical / spatial objects
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES
    (o_phys_obj,  'entity', 'physical_object', 'Physical object',
     'A bounded physical entity: tool, artifact, natural body.'),
    (o_place,     'entity', 'place',           'Place',
     'A location or region in physical space.'),
    (o_region,    'entity', 'region',          'Region',
     'An extended area of space, possibly with administrative or natural boundaries.'),
    (o_location,  'entity', 'location',        'Location',
     'A specific point or area used to describe where something is.'),
    (o_boundary,  'entity', 'boundary',        'Boundary',
     'The interface or limit between two regions or entities. '
     'Part of a region without being a region itself. '
     'Classified as abstract: a boundary has no volume; it is a limit.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 8: Quantities and measurement
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES
    (o_quantity,   'entity', 'quantity',       'Quantity',
     'A measurable or countable amount.'),
    (o_real,       'entity', 'real_number',    'Real number',
     'A number on the continuous number line, including irrationals.'),
    (o_integer,    'entity', 'integer',        'Integer',
     'A whole number: …−2, −1, 0, 1, 2…  Subtype of real_number.'),
    (o_natural,    'entity', 'natural_number', 'Natural number',
     'A non-negative integer: 0, 1, 2, 3…  Convention here includes 0.'),
    (o_unit,       'entity', 'unit_of_measure','Unit of measure',
     'A standard quantity used to express a measurement '
     '(metre, kilogram, second, …).'),
    (o_measurement,'entity', 'measurement',   'Measurement',
     'A quantity expressed in a specific unit; a pairing of number and unit.'),
    (o_duration,   'entity', 'duration',      'Duration',
     'The length of a time interval, expressed as a quantity. '
     'A duration is NOT a time interval — it is a measure of one. '
     'Classified as quantity (abstract); disjoint with time (see Section 14).')
ON CONFLICT (canonical_name, kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 9: Time objects
-- IMPORTANT: These are named TIME PERIOD / TIME ENTITY objects used
-- as semantic arguments of predicates (e.g. the third arg of located_in
-- when a named period is the intended argument, or the time args of EC
-- predicates happens_at / holds_at_ec).
-- They are NOT a mechanism for encoding temporal scope on statements.
-- Temporal scope (when a fact holds) MUST use the statement's t_start /
-- t_end fuzzy_time fields. See schema canonical policy decision #3.
-- [Fix #23] For located_in when no named period is the argument, use
-- the no_period sentinel (seeded by schema). duration measures time
-- and is a quantity, not a subtype of time.
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES
    (o_time,       'entity', 'time',          'Time',
     'The dimension along which events are ordered; '
     'the abstract type for temporal entities. '
     'NOT a mechanism for encoding when a statement holds — use '
     'fuzzy_time fields on statements for that (see schema policy #3).'),
    (o_interval_t, 'entity', 'time_interval', 'Time interval',
     'A bounded span of time with a start and an end. '
     'As a named object, used for named periods (e.g. "the Jurassic"). '
     'As temporal scope on a statement, use t_start/t_end fuzzy_time fields.'),
    (o_point_t,    'entity', 'time_point',    'Time point',
     'An instantaneous moment in time. '
     'Used as the time arg in Event Calculus predicates (happens_at, holds_at_ec). '
     'For birth/death dates etc., encode in statement fuzzy_time fields, not here.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 10: Truth value supertype
-- true / false / unknown already seeded by schema; add truth_value.
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES
    (o_truth_value, 'entity', 'truth_value', 'Truth value',
     'The type whose instances are true, false, and unknown. '
     'Abstract; disjoint with person and physical_object (see Section 14).')
ON CONFLICT (canonical_name, kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 11: Domain context objects
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES
    (o_dom_history,  'context', 'domain_history',    'History',
     'Historical facts, events, persons, dates.'),
    (o_dom_science,  'context', 'domain_science',    'Science (general)',
     'Scientific facts not specific to one discipline.'),
    (o_dom_math,     'context', 'domain_mathematics','Mathematics',
     'Mathematical definitions, theorems, structures.'),
    (o_dom_geography,'context', 'domain_geography',  'Geography',
     'Geographical facts: locations, borders, populations.'),
    (o_dom_biology,  'context', 'domain_biology',    'Biology',
     'Biological facts: taxonomy, anatomy, physiology, ecology.'),
    (o_dom_physics,  'context', 'domain_physics',    'Physics',
     'Physical laws, constants, and phenomena.'),
    (o_dom_law,      'context', 'domain_law',        'Law',
     'Legal facts, statutes, decisions — jurisdiction-sensitive.'),
    (o_dom_language, 'context', 'domain_linguistics','Linguistics',
     'Facts about language, grammar, and meaning.'),
    (o_dom_social,   'context', 'domain_social',     'Social science',
     'Facts about society, culture, economics, politics.'),
    (o_dom_tech,     'context', 'domain_technology', 'Technology',
     'Facts about technology, engineering, computing.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

-- Register domain contexts (orphan-guard requires contexts row)
INSERT INTO contexts (id, kind, parent_id) VALUES
    (o_dom_history,   'domain', reality),
    (o_dom_science,   'domain', reality),
    (o_dom_math,      'domain', reality),
    (o_dom_geography, 'domain', reality),
    (o_dom_biology,   'domain', reality),
    (o_dom_physics,   'domain', reality),
    (o_dom_law,       'domain', reality),
    (o_dom_language,  'domain', reality),
    (o_dom_social,    'domain', reality),
    (o_dom_tech,      'domain', reality)
ON CONFLICT (id) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 12: is_a statements — seed type_membership cache
--
-- These is_a statements fire trg_sync_type_membership and populate
-- the type_membership cache. They cover genuinely cross-hierarchy
-- memberships — cases where an entity belongs to a type that is not
-- reachable by a single-step subtype_of from its primary type chain.
--
-- [Fix #22] Role subtype is_a rows REMOVED. In v0.6, is_a statements
-- for mathematician, programmer, inventor, etc. were inserted here
-- alongside the subtype_of(X, role) rows in Section 13. This created
-- type/instance punning (role subtypes treated as both types and
-- individuals). With the recursive CTE in trg_z_soft_domain_check,
-- the subtype_of rows in Section 13 are sufficient for domain
-- enforcement; the is_a duplicates are not needed and not inserted.
--
-- [Fix #17] All is_a statements below use statement_kind = 'ontological'.
--
-- Do NOT insert directly into type_membership.
-- trg_sync_type_membership is the sole write path.
-- ═════════════════════════════════════════════════════════════

INSERT INTO statements
    (predicate_id, object_args, belief_alpha, belief_beta,
     interpretation, statement_kind, t_kind, context_id, derivation_type, derivation_depth)
VALUES

-- Truth value instances (required early for disjoint axioms in Section 14)
(p_is_a, ARRAY[o_true_val,    o_truth_value], ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_is_a, ARRAY[o_false_val,   o_truth_value], ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_is_a, ARRAY[o_unknown_val, o_truth_value], ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),

-- Cross-hierarchy: person is both a biological organism and a functional agent.
-- person ⊂ sapient is in the backbone; these add the biological and agentive axes.
(p_is_a, ARRAY[o_person,      o_agent],        ka,   kb,   'ontological','ontological','eternal',reality,'axiomatic',0),
(p_is_a, ARRAY[o_person,      o_organism],     ka,   kb,   'ontological','ontological','eternal',reality,'axiomatic',0),

-- Institutions are agents (confirmed) and are usually groups (soft).
(p_is_a, ARRAY[o_institution, o_agent],        ka,   kb,   'ontological','ontological','eternal',reality,'axiomatic',0),
(p_is_a, ARRAY[o_institution, o_group],        70.0, 30.0, 'ontological','ontological','always', reality,'axiomatic',0),

-- Government is an institution (and by chain: agent, group).
(p_is_a, ARRAY[o_government,  o_institution],  ka,   kb,   'ontological','ontological','eternal',reality,'axiomatic',0),

-- Biological hierarchy cross-membership.
(p_is_a, ARRAY[o_mammal,      o_animal],       ka,   kb,   'ontological','ontological','eternal',reality,'axiomatic',0),
(p_is_a, ARRAY[o_animal,      o_organism],     ka,   kb,   'ontological','ontological','eternal',reality,'axiomatic',0),

-- Number subtypes.
(p_is_a, ARRAY[o_integer,     o_real],         ka,   kb,   'ontological','ontological','eternal',reality,'axiomatic',0),
(p_is_a, ARRAY[o_natural,     o_integer],      ka,   kb,   'ontological','ontological','eternal',reality,'axiomatic',0),

-- Event subtypes.
(p_is_a, ARRAY[o_action,      o_event],        ka,   kb,   'ontological','ontological','eternal',reality,'axiomatic',0),
(p_is_a, ARRAY[o_process,     o_event],        ka,   kb,   'ontological','ontological','eternal',reality,'axiomatic',0),
(p_is_a, ARRAY[o_change_event,o_event],        ka,   kb,   'ontological','ontological','eternal',reality,'axiomatic',0),

-- Physical subtypes.
(p_is_a, ARRAY[o_artifact,    o_phys_obj],     ka,   kb,   'ontological','ontological','eternal',reality,'axiomatic',0),

-- Spatial subtypes.
(p_is_a, ARRAY[o_region,      o_place],        ka,   kb,   'ontological','ontological','eternal',reality,'axiomatic',0),
(p_is_a, ARRAY[o_location,    o_place],        ka,   kb,   'ontological','ontological','eternal',reality,'axiomatic',0),

-- Linguistic subtypes.
(p_is_a, ARRAY[o_word,        o_symbol],       ka,   kb,   'ontological','ontological','eternal',reality,'axiomatic',0),
(p_is_a, ARRAY[o_sentence,    o_symbol],       ka,   kb,   'ontological','ontological','eternal',reality,'axiomatic',0),
(p_is_a, ARRAY[o_language,    o_symbol],       ka,   kb,   'ontological','ontological','eternal',reality,'axiomatic',0),

-- Normative subtypes.
(p_is_a, ARRAY[o_rule,        o_norm],         ka,   kb,   'ontological','ontological','eternal',reality,'axiomatic',0)

ON CONFLICT DO NOTHING;


-- ═════════════════════════════════════════════════════════════
-- SECTION 13: Type hierarchy — subtype_of statements
--
-- The backbone already seeds:
--   concrete ⊂ entity, abstract ⊂ entity,
--   living ⊂ concrete, animate ⊂ living, sapient ⊂ animate,
--   person ⊂ sapient, artifact ⊂ concrete,
--   process ⊂ entity (TRANSITIONAL STUB — superseded by this file),
--   group ⊂ entity, number ⊂ abstract, relation ⊂ abstract.
-- We DO NOT repeat those here. We extend downward and sideways.
--
-- [Fix #17] All subtype_of statements use statement_kind = 'ontological'.
-- ═════════════════════════════════════════════════════════════

INSERT INTO statements
    (predicate_id, object_args, belief_alpha, belief_beta,
     interpretation, statement_kind, t_kind, context_id, derivation_type, derivation_depth)
VALUES

-- ── Concrete subtypes (beyond backbone) ──────────────────────
(p_subtype_of, ARRAY[o_organism,    o_concrete],  ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_phys_obj,    o_concrete],  ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
-- artifact ⊂ concrete already in backbone; here we add artifact ⊂ phys_obj (more specific)
(p_subtype_of, ARRAY[o_artifact,    o_phys_obj],  ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_place,       o_concrete],  ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_region,      o_place],     ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_location,    o_place],     ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
-- boundary is abstract: it has no volume; it is a limit, not a region
(p_subtype_of, ARRAY[o_boundary,    o_abstract],  ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),

-- ── Animate hierarchy ─────────────────────────────────────────
(p_subtype_of, ARRAY[o_biological_taxon, o_concept_type], ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_animal,      o_organism],  ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_mammal,      o_animal],    ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
-- person ⊂ mammal (more specific than backbone's person ⊂ sapient)
(p_subtype_of, ARRAY[o_person,      o_mammal],    ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
-- person ⊂ agent (person is both a biological kind and a functional role type)
(p_subtype_of, ARRAY[o_person,      o_agent],     ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
-- agent ⊂ entity (functional layer above the biological hierarchy)
(p_subtype_of, ARRAY[o_agent,       o_entity],    ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_institution, o_agent],     ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_government,  o_institution],ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_group,       o_entity],    ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),

-- ── Abstract subtypes ─────────────────────────────────────────
(p_subtype_of, ARRAY[o_concept_type,  o_abstract], ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_property_c,    o_abstract], ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_attribute,     o_property_c],ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_relation_type, o_relation], ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_proposition,   o_abstract], ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_information,   o_abstract], ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_knowledge_st,  o_information],ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_norm,          o_abstract], ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_rule,          o_norm],     ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_goal,          o_abstract], ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_role_c,        o_abstract], ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_symbol,        o_abstract], ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_language,      o_symbol],   ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_word,          o_symbol],   ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_sentence,      o_symbol],   ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_truth_value,   o_abstract], ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),

-- ── Event / process / state ───────────────────────────────────
-- event_type ⊂ abstract (events are not physical objects)
(p_subtype_of, ARRAY[o_event,         o_abstract], ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_change_event,  o_event],    ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
-- Correct chain: process ⊂ event_type ⊂ abstract ⊂ entity.
-- The schema backbone stub process ⊂ entity is superseded by this row.
(p_subtype_of, ARRAY[o_process,       o_event],    ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_action,        o_event],    ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_state_c,       o_abstract], ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),

-- ── Quantity / number hierarchy ───────────────────────────────
(p_subtype_of, ARRAY[o_quantity,      o_abstract], ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
-- backbone seeds number ⊂ abstract; here we refine: number ⊂ quantity
(p_subtype_of, ARRAY[o_number,        o_quantity], ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_real,          o_number],   ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_integer,       o_real],     ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_natural,       o_integer],  ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_measurement,   o_quantity], ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
-- duration ⊂ quantity: a measurement of time, NOT a subtype of time
(p_subtype_of, ARRAY[o_duration,      o_quantity], ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_unit,          o_abstract], ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),

-- ── Time hierarchy ────────────────────────────────────────────
(p_subtype_of, ARRAY[o_time,          o_abstract], ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_interval_t,    o_time],     ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_point_t,       o_time],     ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),

-- ── Role subtypes ─────────────────────────────────────────────
-- Occupation / functional role types as subtypes of role.
-- [Fix #22] These subtype_of statements are sufficient for domain
-- enforcement via the recursive CTE in trg_z_soft_domain_check.
-- The corresponding is_a rows are NOT needed and NOT in Section 12.
(p_subtype_of, ARRAY[o_mathematician, o_role_c],   ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_programmer,    o_role_c],   ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_inventor,      o_role_c],   ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_scientist,     o_role_c],   ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_engineer,      o_role_c],   ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_teacher,       o_role_c],   ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_politician,    o_role_c],   ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_artist,        o_role_c],   ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0)

ON CONFLICT DO NOTHING;


-- ═════════════════════════════════════════════════════════════
-- SECTION 14: Disjointness axioms
-- Full principled lattice covering the abstract ⊥ concrete split
-- and the cross-domain disjointness of their immediate children.
--
-- CONFLICT SEMANTICS: disjoint_with violations produce type_violation
-- conflicts (via trg_z_soft_domain_check in the schema), NOT
-- direct_negation conflicts. See conflict_kind enum comment in
-- common_knowledge_schema.sql.
--
-- Belief values:
--   ka/kb (≈1.0)   : logically certain disjointness
--   900/100 (0.9)  : strong but acknowledged edge cases
--   700/300 (0.7)  : soft conventional disjointness
--
-- [Fix #17] All disjoint_with statements use statement_kind = 'ontological'.
-- ═════════════════════════════════════════════════════════════

INSERT INTO statements
    (predicate_id, object_args, belief_alpha, belief_beta,
     interpretation, statement_kind, t_kind, context_id, derivation_type, derivation_depth)
VALUES

-- ── LEVEL 1: The foundational split ──────────────────────────
-- Nothing can be both abstract and concrete.
(p_disjoint_with, ARRAY[o_abstract,    o_concrete],    ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),

-- ── LEVEL 2a: Abstract children ⊥ concrete ───────────────────
-- Seeded explicitly so the domain trigger fires without a reasoner.
(p_disjoint_with, ARRAY[o_event,       o_concrete],    ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),
(p_disjoint_with, ARRAY[o_proposition, o_concrete],    ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),
(p_disjoint_with, ARRAY[o_number,      o_concrete],    ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),
(p_disjoint_with, ARRAY[o_time,        o_concrete],    ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),
(p_disjoint_with, ARRAY[o_norm,        o_concrete],    ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),
(p_disjoint_with, ARRAY[o_role_c,      o_concrete],    ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),
(p_disjoint_with, ARRAY[o_truth_value, o_concrete],    ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),
-- symbol ⊥ concrete: symbols are abstract; physical inscriptions are separate
(p_disjoint_with, ARRAY[o_symbol,      o_concrete],    ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),
(p_disjoint_with, ARRAY[o_goal,        o_concrete],    ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),
(p_disjoint_with, ARRAY[o_quantity,    o_concrete],    ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),

-- ── LEVEL 2b: Concrete children ⊥ abstract ───────────────────
(p_disjoint_with, ARRAY[o_organism,    o_abstract],    ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),
(p_disjoint_with, ARRAY[o_phys_obj,    o_abstract],    ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),
(p_disjoint_with, ARRAY[o_place,       o_abstract],    ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),

-- ── LEVEL 2c: Cross-domain within-abstract disjointness ───────
-- Time is not a number, proposition, or symbol (commonly confused).
(p_disjoint_with, ARRAY[o_time,        o_number],      ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),
(p_disjoint_with, ARRAY[o_time,        o_proposition], ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),
(p_disjoint_with, ARRAY[o_time,        o_symbol],      ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),
-- Numbers are not events or propositions.
(p_disjoint_with, ARRAY[o_number,      o_event],       ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),
(p_disjoint_with, ARRAY[o_number,      o_proposition], ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),
-- Events are not propositions (events happen; propositions are stated about them).
(p_disjoint_with, ARRAY[o_event,       o_proposition], ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),
-- duration ⊥ time: duration measures time; it is not a temporal entity
(p_disjoint_with, ARRAY[o_duration,    o_time],        ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),

-- ── LEVEL 2d: Within-concrete disjointness ────────────────────
-- Places are not organisms (places are stable loci; organisms move).
(p_disjoint_with, ARRAY[o_place,       o_organism],    ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),
-- Persons are not institutions (soft: sole-trader edge case in law).
(p_disjoint_with, ARRAY[o_person,      o_institution], 900.0, 100.0, 'ontological','ontological','eternal',reality,'axiomatic',0),
-- Organisms are not artifacts (soft: GMO / synthetic biology edge case).
(p_disjoint_with, ARRAY[o_organism,    o_artifact],    900.0, 100.0, 'ontological','ontological','eternal',reality,'axiomatic',0),

-- ── Specific cross-kind pairs ─────────────────────────────────
-- physical_object ⊥ time: a rock is not an interval
(p_disjoint_with, ARRAY[o_time,        o_phys_obj],    ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),
-- number ⊥ organism: no number is alive
(p_disjoint_with, ARRAY[o_number,      o_organism],    ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),
-- truth_value ⊥ person: true and false are not persons
(p_disjoint_with, ARRAY[o_truth_value, o_person],      ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),
-- truth_value ⊥ number: soft — in Boolean arithmetic true=1, false=0
(p_disjoint_with, ARRAY[o_truth_value, o_number],      700.0, 300.0, 'ontological','ontological','eternal',reality,'axiomatic',0),
-- place ⊥ number: Paris is not a number
(p_disjoint_with, ARRAY[o_place,       o_number],      ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0),
-- proposition ⊥ physical_object: propositions are not physical
(p_disjoint_with, ARRAY[o_proposition, o_phys_obj],    ka,    kb,    'ontological','ontological','eternal',reality,'axiomatic',0)

ON CONFLICT DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 15: Logical / modal eternal statements
-- [Fix #17] opposite_of and different_from use statement_kind =
-- 'ontological'. FOL rule statements use statement_kind = 'rule'.
-- Rule statements are opaque to holds_at() and tell_about().
-- ═════════════════════════════════════════════════════════════

INSERT INTO statements
    (predicate_id, object_args, belief_alpha, belief_beta,
     interpretation, statement_kind, t_kind, context_id, derivation_type, derivation_depth)
VALUES
(p_opposite_of,   ARRAY[o_true_val,  o_false_val],  ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_different_from,ARRAY[o_true_val,  o_false_val],  ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_different_from,ARRAY[o_true_val,  o_unknown_val],ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0),
(p_different_from,ARRAY[o_false_val, o_unknown_val],ka,kb,'ontological','ontological','eternal',reality,'axiomatic',0)
ON CONFLICT DO NOTHING;

-- ── FOL rule statements ───────────────────────────────────────
-- Inference rules encoded as implies(antecedent, consequent) with
-- both args as string literals. object_args = '{}' satisfies the
-- args_nonempty check via literal_args.
-- [Fix #17] statement_kind = 'rule'. Rule statements are excluded from
-- holds_at() and tell_about() and are consumed by the reasoning layer
-- (ProbLog compiler or equivalent). They are queryable by kind.
-- derivation_type = 'axiomatic'; no statement_dependencies needed
-- (provenance enforcement applies only to forward_chained / abduced).

-- Modal axiom T: necessary(P) → possible(P)
INSERT INTO statements
    (predicate_id, object_args, literal_args, belief_alpha, belief_beta,
     interpretation, statement_kind, t_kind, context_id, derivation_type, derivation_depth)
VALUES (p_implies, '{}'::uuid[],
    '[{"pos":0,"type":"string","value":"necessary(P)"},
      {"pos":1,"type":"string","value":"possible(P)"}]'::jsonb,
    ka,kb,'ontological','rule','eternal',reality,'axiomatic',0);

-- Type rule: is_a(X, integer) → is_a(X, real_number)
INSERT INTO statements
    (predicate_id, object_args, literal_args, belief_alpha, belief_beta,
     interpretation, statement_kind, t_kind, context_id, derivation_type, derivation_depth)
VALUES (p_implies, '{}'::uuid[],
    '[{"pos":0,"type":"string","value":"is_a(X, integer)"},
      {"pos":1,"type":"string","value":"is_a(X, real_number)"}]'::jsonb,
    ka,kb,'ontological','rule','eternal',reality,'axiomatic',0);

-- Type rule: is_a(X, mammal) → is_a(X, animal)
INSERT INTO statements
    (predicate_id, object_args, literal_args, belief_alpha, belief_beta,
     interpretation, statement_kind, t_kind, context_id, derivation_type, derivation_depth)
VALUES (p_implies, '{}'::uuid[],
    '[{"pos":0,"type":"string","value":"is_a(X, mammal)"},
      {"pos":1,"type":"string","value":"is_a(X, animal)"}]'::jsonb,
    ka,kb,'ontological','rule','eternal',reality,'axiomatic',0);

-- Type rule: is_a(X, animal) → is_a(X, organism)
INSERT INTO statements
    (predicate_id, object_args, literal_args, belief_alpha, belief_beta,
     interpretation, statement_kind, t_kind, context_id, derivation_type, derivation_depth)
VALUES (p_implies, '{}'::uuid[],
    '[{"pos":0,"type":"string","value":"is_a(X, animal)"},
      {"pos":1,"type":"string","value":"is_a(X, organism)"}]'::jsonb,
    ka,kb,'ontological','rule','eternal',reality,'axiomatic',0);

-- Mortal rule: is_a(X, person) → mortal(X)
-- NOT eternal: strong empirical generalisation, revisable.
-- alpha=95, beta=5 (mean 0.95). Philosophical edge cases prevent
-- treating this as a logical truth.
INSERT INTO statements
    (predicate_id, object_args, literal_args, belief_alpha, belief_beta,
     interpretation, statement_kind, t_kind, context_id, derivation_type, derivation_depth)
VALUES (p_implies, '{}'::uuid[],
    '[{"pos":0,"type":"string","value":"is_a(X, person)"},
      {"pos":1,"type":"string","value":"mortal(X)"}]'::jsonb,
    95.0,5.0,'ontological','rule','always',reality,'axiomatic',0);

-- Agent rule: is_a(X, person) → capable_of(X, intentional_action)
INSERT INTO statements
    (predicate_id, object_args, literal_args, belief_alpha, belief_beta,
     interpretation, statement_kind, t_kind, context_id, derivation_type, derivation_depth)
VALUES (p_implies, '{}'::uuid[],
    '[{"pos":0,"type":"string","value":"is_a(X, person)"},
      {"pos":1,"type":"string","value":"capable_of(X, intentional_action)"}]'::jsonb,
    90.0,10.0,'ontological','rule','always',reality,'axiomatic',0);

-- Disjoint rule: disjoint_with(A,B) ∧ is_a(X,A) → ¬is_a(X,B)
-- Produces a type_violation conflict at inference time, NOT direct_negation.
-- type_violation = structural constraint failure.
-- direct_negation = evidential opposition between belief-bearing statements.
INSERT INTO statements
    (predicate_id, object_args, literal_args, belief_alpha, belief_beta,
     interpretation, statement_kind, t_kind, context_id, derivation_type, derivation_depth)
VALUES (p_implies, '{}'::uuid[],
    '[{"pos":0,"type":"string","value":"disjoint_with(A,B) ∧ is_a(X,A)"},
      {"pos":1,"type":"string","value":"¬is_a(X,B) [type_violation conflict, not direct_negation]"}]'::jsonb,
    ka,kb,'ontological','rule','eternal',reality,'axiomatic',0);

-- ═════════════════════════════════════════════════════════════
-- SECTION 16: Typicality statements (prototype knowledge)
-- belief < 1.0 by design; typicality is inherently graded.
-- t_kind = 'always' (not eternal: prototypes are revisable).
-- [Fix #17] All typical_of statements use statement_kind = 'statistical'.
-- Statistical statements are excluded from logical inference chains
-- (holds_at open_world mode, compute_derived_belief). They are
-- queryable directly by statement_kind = 'statistical'.
-- ═════════════════════════════════════════════════════════════

INSERT INTO statements
    (predicate_id, object_args, belief_alpha, belief_beta,
     interpretation, statement_kind, t_kind, context_id, derivation_type, derivation_depth)
VALUES
(p_typical_of, ARRAY[o_person,       o_agent],    90.0,10.0,'ontological','statistical','always',reality,'axiomatic',0),
(p_typical_of, ARRAY[o_institution,  o_agent],    60.0,40.0,'ontological','statistical','always',reality,'axiomatic',0),
(p_typical_of, ARRAY[o_action,       o_event],    85.0,15.0,'ontological','statistical','always',reality,'axiomatic',0),
(p_typical_of, ARRAY[o_process,      o_event],    65.0,35.0,'ontological','statistical','always',reality,'axiomatic',0),
(p_typical_of, ARRAY[o_change_event, o_event],    75.0,25.0,'ontological','statistical','always',reality,'axiomatic',0),
(p_typical_of, ARRAY[o_region,       o_place],    75.0,25.0,'ontological','statistical','always',reality,'axiomatic',0),
(p_typical_of, ARRAY[o_location,     o_place],    70.0,30.0,'ontological','statistical','always',reality,'axiomatic',0),
(p_typical_of, ARRAY[o_artifact,     o_phys_obj], 70.0,30.0,'ontological','statistical','always',reality,'axiomatic',0),
(p_typical_of, ARRAY[o_rule,         o_norm],     80.0,20.0,'ontological','statistical','always',reality,'axiomatic',0),
(p_typical_of, ARRAY[o_word,         o_symbol],   80.0,20.0,'ontological','statistical','always',reality,'axiomatic',0)
ON CONFLICT DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 17: Bulk attestation
-- Link all axiomatic statements to system_kernel.
-- axiomatic statements do not require statement_dependencies rows —
-- provenance enforcement applies only to forward_chained and abduced
-- derivation types.
-- ═════════════════════════════════════════════════════════════

INSERT INTO attestations (statement_id, source_id)
SELECT s.id, sys
FROM statements s
WHERE s.derivation_type = 'axiomatic'
  AND NOT EXISTS (
      SELECT 1 FROM attestations a WHERE a.statement_id = s.id
  );

-- ═════════════════════════════════════════════════════════════
-- SECTION 18: Diagnostic counts
-- ═════════════════════════════════════════════════════════════

RAISE NOTICE 'Basis objects & statements load complete (v0.7).';
RAISE NOTICE '  entity objects     : %',
    (SELECT count(*) FROM objects WHERE kind = 'entity');
RAISE NOTICE '  context objects    : %',
    (SELECT count(*) FROM objects WHERE kind = 'context');
RAISE NOTICE '  axiomatic stmts    : %',
    (SELECT count(*) FROM statements WHERE derivation_type = 'axiomatic');
RAISE NOTICE '  ontological stmts  : %',
    (SELECT count(*) FROM statements WHERE statement_kind = 'ontological');
RAISE NOTICE '  statistical stmts  : %',
    (SELECT count(*) FROM statements WHERE statement_kind = 'statistical');
RAISE NOTICE '  rule stmts         : %',
    (SELECT count(*) FROM statements WHERE statement_kind = 'rule');
RAISE NOTICE '  subtype_of stmts   : %',
    (SELECT count(*) FROM statements s
     WHERE s.predicate_id = stable_uuid('subtype_of','predicate'));
RAISE NOTICE '  is_a stmts         : %',
    (SELECT count(*) FROM statements s
     WHERE s.predicate_id = stable_uuid('is_a','predicate'));
RAISE NOTICE '  disjoint axioms    : %',
    (SELECT count(*) FROM statements s
     WHERE s.predicate_id = stable_uuid('disjoint_with','predicate'));
RAISE NOTICE '  type_membership    : % (derived from is_a via trigger)',
    (SELECT count(*) FROM type_membership);
RAISE NOTICE '  attestations       : %',
    (SELECT count(*) FROM attestations);

END $$;

COMMIT;


-- ── Verification queries ──────────────────────────────────────

-- Full type hierarchy ordered by parent then child
SELECT
    child.canonical_name  AS child,
    parent.canonical_name AS parent,
    round(s.belief_mean::numeric, 4) AS belief
FROM statements s
JOIN objects child  ON child.id  = s.object_args[1]
JOIN objects parent ON parent.id = s.object_args[2]
WHERE s.predicate_id = stable_uuid('subtype_of', 'predicate')
ORDER BY parent.canonical_name, child.canonical_name;

-- Disjointness pairs with effective belief
SELECT
    a.canonical_name  AS type_a,
    b.canonical_name  AS type_b,
    round(seb.effective_mean::numeric, 4) AS effective_belief
FROM statement_effective_belief seb
JOIN statements s ON s.id = seb.id
JOIN objects a ON a.id = s.object_args[1]
JOIN objects b ON b.id = s.object_args[2]
WHERE s.predicate_id = stable_uuid('disjoint_with', 'predicate')
ORDER BY type_a, type_b;

-- type_membership cache (derived from is_a statements via trigger)
SELECT
    obj.canonical_name  AS object,
    typ.canonical_name  AS type,
    round((tm.alpha / (tm.alpha + tm.beta))::numeric, 4) AS belief
FROM type_membership tm
JOIN objects obj ON obj.id = tm.object_id
JOIN objects typ ON typ.id = tm.type_id
ORDER BY obj.canonical_name, typ.canonical_name;

-- Role subtypes via subtype_of
SELECT
    child.canonical_name  AS role_subtype,
    parent.canonical_name AS parent_type,
    round(s.belief_mean::numeric, 4) AS belief
FROM statements s
JOIN objects child  ON child.id = s.object_args[1]
JOIN objects parent ON parent.id = s.object_args[2]
WHERE s.predicate_id = stable_uuid('subtype_of', 'predicate')
  AND s.object_args[2] = stable_uuid('role', 'entity')
ORDER BY child.canonical_name;

-- Statements by kind
SELECT statement_kind, count(*) AS count
FROM statements
GROUP BY statement_kind
ORDER BY statement_kind;

-- Domain contexts
SELECT canonical_name, display_name
FROM objects
WHERE kind = 'context'
ORDER BY canonical_name;
