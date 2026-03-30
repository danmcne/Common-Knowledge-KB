-- =============================================================
-- Common Knowledge KB — Basis Predicates (v0.6)
-- =============================================================
-- Compatibility notes vs. v0.5 predicate file:
--
--   All changes from v0.5 are preserved. v0.6 changes:
--
--   [Fix #1]  is_a / instance_of → type_membership sync
--     Both is_a and instance_of now trigger trg_sync_type_membership
--     in the schema (common_knowledge_schema.sql). Inserting either
--     predicate automatically populates or updates the type_membership
--     cache. Do not assert type_membership directly. The object_equivalence
--     link between is_a and instance_of is retained; both predicates are
--     canonical triggers. Comments updated throughout.
--
--   [Fix #3]  located_in third arg policy
--     The third arg of located_in was documented as a "time/temporal
--     object". This was a category error (see schema policy decision #3).
--     The third arg is now documented as a NAMED TIME PERIOD (e.g.
--     "victorian_era", "bronze_age") — used only when the period is the
--     genuine semantic argument. Temporal scope (when x was at y) is
--     expressed via the statement's t_start / t_end fuzzy_time fields.
--     arg_label renamed from 'time' to 'time_period'. Description updated.
--
--   [Fix #5]  has_role scope arg: no_scope sentinel
--     "scope may be NULL" removed from has_role documentation.
--     The correct pattern for a genuinely unscoped role is
--     has_role(X, role, no_scope) using the seeded no_scope sentinel.
--     NULL scope is now undocumented behavior. Description and
--     fol_definition updated.
--
--   [Fix #8]  disjoint_with semantic clarification
--     Comment added: disjoint_with drives type_violation conflicts
--     (hard domain enforcement), not direct_negation. Conflict semantics
--     are distinct — see schema conflict_kind enum comment.
--
--   [Fix #12]  disjoint_with: lattice seeded in objects kernel
--     Comment added: the full abstract ⊥ concrete disjointness lattice
--     is seeded in common_objects_kernel.sql, not here. This file
--     defines the predicate only.
--
--   [Fix #13]  role subtypes (mathematician, programmer, inventor)
--     These are seeded in common_objects_kernel.sql as
--     subtype_of(mathematician, role) etc. They are NOT bare entities.
--     No code change here; documented as a cross-file dependency.
--
-- Compatibility notes vs. v0.5 (unchanged):
--
--   • object_kind enum is coarse (entity/predicate/context/source).
--     arg_kinds object_kind[] dropped; arg constraints via arg_type_ids.
--
--   • arg_types text[] (old) → arg_type_ids uuid[] (v0.5+).
--     Where a type object exists in the backbone seed, we reference it
--     via stable_uuid(name,'entity'). Where no backbone object exists
--     yet (e.g. 'language', 'material', 'symbol'), arg_type_ids is NULL
--     and can be tightened in later migrations.
--
--   • domains text[] dropped. Domain info lives in nl_description and
--     fol_definition.
--
--   • domain_strictness: basis predicates default to 'soft' unless a
--     hard logical constraint is warranted. disjoint_with is 'hard'.
--
--   • Predicates already seeded by common_knowledge_schema.sql
--     (subtype_of, instance_of, has_role, has_capacity, models_as)
--     are re-inserted with ON CONFLICT DO UPDATE to fill richer metadata.
--
--   • 57 basis predicates across 13 groups (count unchanged).
--     held_office absent; has_role covers it.
--     born_in / died_in absent; use located_in + fuzzy_time scope.
--
-- Cross-file dependencies:
--   Run common_knowledge_schema.sql FIRST (seeds backbone objects and
--   the trg_sync_type_membership trigger).
--   Run this file SECOND.
--   Run common_objects_kernel.sql THIRD (seeds disjointness lattice,
--   role subtype hierarchy, domain contexts, etc.).
--
-- KNOWN LIMITATION — arg_type_ids ENFORCEMENT (v0.6):
--   The domain check trigger (trg_z_soft_domain_check) verifies arg
--   types via a direct type_membership lookup. This does NOT perform
--   transitive closure over subtype_of. As a result, arg_type_ids
--   enforcement is unreliable for:
--   a) Structural/ontological predicates (disjoint_with, subtype_of,
--      is_a, equivalent_to) whose args are type-category objects that
--      cannot satisfy is_a(X,X) without circularity.
--   b) Any predicate used before type_membership is populated (kernel
--      bootstrap phase) or whose arg's type is only implied transitively
--      (e.g. ada_lovelace → person → sapient → animate).
--
--   For structural predicates, arg_type_ids is set to NULL in this file.
--   The constraint is documented in nl_description and fol_definition.
--   Hard enforcement will be re-enabled in v0.7 when the domain check
--   uses a recursive subtype_of CTE instead of a direct lookup.
--
--   For application predicates (agent_of, capable_of, etc.), arg_type_ids
--   is retained as documentation metadata. Soft violations will correctly
--   fire for clearly mis-typed args where type_membership IS directly
--   populated (e.g. after full bootstrap with named individuals).
--
-- =============================================================

BEGIN;

DO $$
DECLARE
    sys  uuid := stable_uuid('system_kernel', 'source');
    ctx  uuid := stable_uuid('reality',       'context');
    oid  uuid;

    -- Backbone type UUIDs (seeded by common_knowledge_schema.sql)
    t_entity    uuid := stable_uuid('entity',   'entity');
    t_abstract  uuid := stable_uuid('abstract', 'entity');
    t_concrete  uuid := stable_uuid('concrete', 'entity');
    t_animate   uuid := stable_uuid('animate',  'entity');
    t_sapient   uuid := stable_uuid('sapient',  'entity');
    t_person    uuid := stable_uuid('person',   'entity');
    t_process   uuid := stable_uuid('process',  'entity');
    t_group     uuid := stable_uuid('group',    'entity');
    t_number    uuid := stable_uuid('number',   'entity');
    t_relation  uuid := stable_uuid('relation', 'entity');

BEGIN

-- ════════════════════════════════════════════════════════════
-- GROUP 1: TAXONOMIC / TYPE  (5)
-- ════════════════════════════════════════════════════════════

-- is_a(instance, type)
-- [Fix #1] CANONICAL TYPE MECHANISM.
-- Inserting a statement with predicate is_a or instance_of automatically
-- populates or updates type_membership via trg_sync_type_membership
-- (defined in common_knowledge_schema.sql). Do NOT assert type_membership
-- rows directly; they will be overwritten on the next trigger fire.
-- The schema seeds 'instance_of' for this concept. 'is_a' is the canonical
-- basis predicate name; an object_equivalence link to instance_of is
-- recorded at the end of this file so both names trigger the sync.
oid := stable_uuid('is_a', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'is_a', 'is a',
    'x is an instance of type y (crisp classification only). '
    'Inserting an is_a statement automatically populates type_membership '
    'via trg_sync_type_membership. Do NOT assert type_membership directly. '
    'Do NOT use for role, state, property, typicality, or identity. '
    'See: has_role (role), has_property (predication), '
    'typical_of (exemplification), same_as (identity).')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates
    (id, arity, arg_type_ids, arg_labels,
     fol_definition, nl_description, source_predicate,
     is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    -- [Bootstrapping limitation] arg_type_ids set to NULL.
    -- Intended constraint: ARRAY[t_entity, t_abstract].
    -- Cannot be enforced via direct type_membership lookup because
    -- (a) type-category objects cannot satisfy is_a(X, abstract) without
    --     circular reasoning, and (b) the check has no transitive closure.
    -- Re-enable in v0.7 with recursive subtype_of traversal.
    NULL,
    ARRAY['instance', 'type'],
    'primitive',
    'x is an instance of y. '
    'Triggers type_membership cache update automatically.',
    'rdf:type / wikidata:P31',
    true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids     = EXCLUDED.arg_type_ids,
    arg_labels       = EXCLUDED.arg_labels,
    fol_definition   = EXCLUDED.fol_definition,
    nl_description   = EXCLUDED.nl_description,
    source_predicate = EXCLUDED.source_predicate,
    is_basis         = true,
    status           = 'confirmed',
    introduced_by    = EXCLUDED.introduced_by;

-- subtype_of(subtype, supertype) — already seeded by schema; enrich metadata.
oid := stable_uuid('subtype_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'subtype_of', 'subtype of',
    'Every instance of x is also an instance of y (transitive, asymmetric). '
    'Transitive closure over subtype_of is the reasoner''s responsibility; '
    'type_membership does not reflect it directly.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates
    (id, arity, arg_type_ids, arg_labels,
     fol_definition, nl_description, source_predicate,
     is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    -- [Bootstrapping limitation] arg_type_ids set to NULL.
    -- Intended constraint: ARRAY[t_abstract, t_abstract].
    -- Type-category objects (abstract, concrete, organism, …) cannot be
    -- registered as members of abstract without circular is_a reasoning.
    -- Re-enable in v0.7 with recursive subtype_of traversal.
    NULL,
    ARRAY['subtype', 'supertype'],
    'subtype_of(X,Y) :- forall Z, is_a(Z,X) -> is_a(Z,Y)',
    'x is a subtype of y',
    'rdfs:subClassOf',
    true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids     = EXCLUDED.arg_type_ids,
    arg_labels       = EXCLUDED.arg_labels,
    fol_definition   = EXCLUDED.fol_definition,
    nl_description   = EXCLUDED.nl_description,
    source_predicate = EXCLUDED.source_predicate,
    is_basis         = true,
    status           = 'confirmed',
    introduced_by    = EXCLUDED.introduced_by;

-- has_property(entity, property)
oid := stable_uuid('has_property', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'has_property', 'has property',
    'x has property or attribute y (predication sense of copula). '
    '"The sky is blue" → has_property(sky, blue).')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates
    (id, arity, arg_type_ids, arg_labels,
     fol_definition, nl_description, source_predicate,
     is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_entity],
    ARRAY['entity', 'property'],
    'primitive',
    'x has property y',
    'conceptnet:HasProperty',
    true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids     = EXCLUDED.arg_type_ids,
    arg_labels       = EXCLUDED.arg_labels,
    fol_definition   = EXCLUDED.fol_definition,
    nl_description   = EXCLUDED.nl_description,
    source_predicate = EXCLUDED.source_predicate,
    is_basis         = true,
    status           = 'confirmed';

-- same_as(x, y) — identity
oid := stable_uuid('same_as', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'same_as', 'same as',
    'x and y refer to the same real-world entity (identity, not classification).')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates
    (id, arity, arg_type_ids, arg_labels,
     fol_definition, nl_description, source_predicate,
     is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_entity],
    ARRAY['entity_a', 'entity_b'],
    'primitive; symmetric; same_as(X,Y) -> same_as(Y,X)',
    'x and y are the same entity',
    'owl:sameAs',
    true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids     = EXCLUDED.arg_type_ids,
    arg_labels       = EXCLUDED.arg_labels,
    fol_definition   = EXCLUDED.fol_definition,
    nl_description   = EXCLUDED.nl_description,
    source_predicate = EXCLUDED.source_predicate,
    is_basis         = true,
    status           = 'confirmed';

-- different_from(x, y)
oid := stable_uuid('different_from', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'different_from', 'different from',
    'x and y are distinct entities.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates
    (id, arity, arg_type_ids, arg_labels,
     fol_definition, nl_description, source_predicate,
     is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_entity],
    ARRAY['entity_a', 'entity_b'],
    'different_from(X,Y) :- not same_as(X,Y)',
    'x and y are not the same entity',
    'owl:differentFrom',
    true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids     = EXCLUDED.arg_type_ids,
    arg_labels       = EXCLUDED.arg_labels,
    fol_definition   = EXCLUDED.fol_definition,
    nl_description   = EXCLUDED.nl_description,
    source_predicate = EXCLUDED.source_predicate,
    is_basis         = true,
    status           = 'confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 2: MEREOLOGY  (4)
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('part_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'part_of', 'part of',
    'x is a component or part of y (transitive, asymmetric).')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_entity], ARRAY['part', 'whole'],
    'primitive; transitive; asymmetric',
    'x is a part of y',
    'conceptnet:PartOf / wikidata:P361',
    true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids=EXCLUDED.arg_type_ids, arg_labels=EXCLUDED.arg_labels,
    fol_definition=EXCLUDED.fol_definition, nl_description=EXCLUDED.nl_description,
    source_predicate=EXCLUDED.source_predicate, is_basis=true, status='confirmed';

oid := stable_uuid('has_part', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'has_part', 'has part',
    'x contains y as a component.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_entity], ARRAY['whole', 'part'],
    'has_part(X,Y) :- part_of(Y,X)',
    'x has y as a part',
    'conceptnet:HasA / wikidata:P527',
    true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids=EXCLUDED.arg_type_ids, arg_labels=EXCLUDED.arg_labels,
    fol_definition=EXCLUDED.fol_definition, nl_description=EXCLUDED.nl_description,
    source_predicate=EXCLUDED.source_predicate, is_basis=true, status='confirmed';

oid := stable_uuid('member_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'member_of', 'member of',
    'x is a member of group or set y (not part-whole; no transitivity assumed).')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_group], ARRAY['member', 'group'],
    'primitive',
    'x is a member of y',
    'wikidata:P463',
    true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids=EXCLUDED.arg_type_ids, arg_labels=EXCLUDED.arg_labels,
    fol_definition=EXCLUDED.fol_definition, nl_description=EXCLUDED.nl_description,
    source_predicate=EXCLUDED.source_predicate, is_basis=true, status='confirmed';

oid := stable_uuid('contains', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'contains', 'contains',
    'x physically or abstractly contains y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_entity], ARRAY['container', 'contained'],
    'contains(X,Y) :- part_of(Y,X) [spatial sense]',
    'x contains y',
    NULL,
    true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids=EXCLUDED.arg_type_ids, arg_labels=EXCLUDED.arg_labels,
    fol_definition=EXCLUDED.fol_definition, nl_description=EXCLUDED.nl_description,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 3: SPATIAL  (4)
--
-- [Fix #3] CANONICAL TIME POLICY FOR SPATIAL PREDICATES:
-- located_in(entity, place, time_period) — the THIRD ARG is a named
-- time period object (e.g. "victorian_era", "bronze_age") used only when
-- that period is the genuine semantic argument of the predicate
-- (e.g. "Paris in the Middle Ages"). It is NOT a mechanism for encoding
-- temporal scope. Temporal scope (when x was at y) MUST be expressed
-- via the statement's t_start / t_end fuzzy_time fields. A bare year-
-- object as the time arg (e.g. "1815_birth_time") is a category error.
--
-- For timeless geographic containment (France contains Paris):
--   Use t_kind='always' or 'eternal' on the statement; leave the
--   third arg absent (store a sentinel or reduce arity via a binary
--   specialisation if your reasoner supports it) or use no_scope.
-- ════════════════════════════════════════════════════════════

-- located_in(entity, place, time_period)
-- [Fix #3] Third arg renamed from 'time' to 'time_period'.
-- Temporal scope encoded in statement fuzzy_time fields; see policy above.
oid := stable_uuid('located_in', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'located_in', 'located in',
    'x is situated within or at location y. '
    'The optional third arg (time_period) is a NAMED TIME PERIOD object '
    '(e.g. "victorian_era") — used only when that period is the genuine '
    'semantic argument, not as a temporal encoding mechanism. '
    'ALL temporal scope (when x was at y) goes in the statement''s '
    't_start / t_end fuzzy_time fields. '
    'See schema canonical policy decision #3.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 3,
    ARRAY[t_entity, t_entity, t_entity],
    -- [Fix #3] Renamed from 'time' to 'time_period' to prevent misuse
    ARRAY['entity', 'place', 'time_period'],
    'primitive',
    'x is located in y (during named period z if specified). '
    'Temporal scope expressed in statement fuzzy_time fields.',
    'conceptnet:AtLocation / wikidata:P131',
    true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids=EXCLUDED.arg_type_ids, arg_labels=EXCLUDED.arg_labels,
    fol_definition=EXCLUDED.fol_definition, nl_description=EXCLUDED.nl_description,
    source_predicate=EXCLUDED.source_predicate, is_basis=true, status='confirmed';

oid := stable_uuid('adjacent_to', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'adjacent_to', 'adjacent to',
    'x is spatially next to or bordering y (symmetric).')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_entity], ARRAY['entity_a', 'entity_b'],
    'primitive; symmetric',
    'x is next to or borders y',
    NULL,
    true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids=EXCLUDED.arg_type_ids, arg_labels=EXCLUDED.arg_labels,
    fol_definition=EXCLUDED.fol_definition, nl_description=EXCLUDED.nl_description,
    is_basis=true, status='confirmed';

oid := stable_uuid('origin_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'origin_of', 'origin of',
    'x is the place, source, or cause from which y originates.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_entity], ARRAY['origin', 'thing'],
    'primitive',
    'x is the origin of y',
    'wikidata:P19 generalised',
    true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids=EXCLUDED.arg_type_ids, arg_labels=EXCLUDED.arg_labels,
    fol_definition=EXCLUDED.fol_definition, nl_description=EXCLUDED.nl_description,
    source_predicate=EXCLUDED.source_predicate, is_basis=true, status='confirmed';

oid := stable_uuid('transferred_to', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'transferred_to', 'transferred to',
    'x moved or was transferred from source y to destination z. '
    'Covers physical movement, ownership transfer, transmission of information.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 3,
    ARRAY[t_entity, t_entity, t_entity],
    ARRAY['thing', 'source', 'destination'],
    'primitive; bitransitive',
    'x is transferred from y to z',
    'wikidata:P185 generalised',
    true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids=EXCLUDED.arg_type_ids, arg_labels=EXCLUDED.arg_labels,
    fol_definition=EXCLUDED.fol_definition, nl_description=EXCLUDED.nl_description,
    source_predicate=EXCLUDED.source_predicate, is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 4: TEMPORAL  (5)
-- Allen interval algebra + has_duration.
-- These predicates take process/event-typed args and encode ORDERING
-- and OVERLAP relations between events as KB statements.
-- They are distinct from the statement-level fuzzy_time fields, which
-- encode the temporal scope of the fact itself. A holds_at() query
-- uses fuzzy_time; a before(battle_of_hastings, magna_carta) statement
-- uses these predicates to encode the ordering relation as a KB fact.
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('before', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'before', 'before',
    'Event or time x occurs strictly before y (transitive, asymmetric).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_process], ARRAY['earlier', 'later'],
    'primitive; transitive; asymmetric', 'x happens strictly before y',
    'allen:before', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('after', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'after', 'after',
    'Event or time x occurs strictly after y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_process], ARRAY['later', 'earlier'],
    'after(X,Y) :- before(Y,X)', 'x happens strictly after y',
    'allen:after', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('during', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'during', 'during',
    'Event x occurs entirely within the time span of event y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_process], ARRAY['contained_event', 'containing_event'],
    'primitive (Allen interval relation)', 'x occurs within the span of y',
    'allen:during', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('simultaneous_with', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'simultaneous_with', 'simultaneous with',
    'Events x and y occur at the same time (symmetric).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_process], ARRAY['event_a', 'event_b'],
    'primitive; symmetric', 'x and y happen at the same time',
    'allen:equals', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('has_duration', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'has_duration', 'has duration',
    'Event or state x lasts for duration y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_number], ARRAY['event_or_state', 'quantity'],
    'primitive', 'x lasts for duration y',
    'wikidata:P2047', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 5: CAUSAL / FUNCTIONAL  (6)
-- causes(cause, effect, mechanism) — ternary
-- mechanism arg is often unknown; stored as NULL literal or no_scope.
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('causes', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'causes', 'causes',
    'x brings about y via mechanism z. '
    'Mechanism (z) may be the no_scope sentinel when unknown or irrelevant.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 3, ARRAY[t_entity, t_entity, t_entity],
    ARRAY['cause', 'effect', 'mechanism'],
    'primitive; bitransitive', 'x causes y via mechanism z',
    'conceptnet:Causes', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('enables', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'enables', 'enables',
    'x makes y possible without necessarily causing it.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['enabler', 'enabled'],
    'primitive; weaker than causes', 'x enables y',
    'conceptnet:Enables', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('prevents', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'prevents', 'prevents',
    'x inhibits or blocks y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['preventer', 'prevented'],
    'primitive', 'x prevents y',
    'conceptnet:Obstructs', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('used_for', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'used_for', 'used for',
    'x is typically used to accomplish y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['tool', 'purpose'],
    'primitive', 'x is used for y',
    'conceptnet:UsedFor', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('capable_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'capable_of', 'capable of',
    'x has the capacity or disposition to do y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_animate, t_entity], ARRAY['agent', 'action'],
    'primitive', 'x is capable of y',
    'conceptnet:CapableOf', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('motivated_by', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'motivated_by', 'motivated by',
    'Action x is done because of reason or goal y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_entity], ARRAY['action', 'goal'],
    'primitive', 'x is motivated by y',
    'conceptnet:MotivatedByGoal', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 6: AGENTIVE / SOCIAL  (6)
-- has_role(entity, role, scope) — ternary.
-- [Fix #5] SCOPE ARG POLICY:
--   Use has_role(X, role, no_scope) when the role is genuinely
--   unscoped (e.g. an itinerant or informal role with no institutional
--   home). The no_scope sentinel is seeded in common_knowledge_schema.sql.
--   A NULL scope arg is undocumented behavior and should not be relied on.
--   If the scope is unknown (exists but identity not known), that
--   uncertainty should be expressed in a separate epistemic statement
--   rather than via NULL.
-- [Fix #13] ROLE SUBTYPES:
--   Specific role types (mathematician, programmer, inventor, etc.) are
--   seeded as subtype_of(mathematician, role) in common_objects_kernel.sql.
--   Do not insert them as bare entities or via has_property.
-- ════════════════════════════════════════════════════════════

-- agent_of(agent, event)
oid := stable_uuid('agent_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'agent_of', 'agent of',
    'x is the intentional agent who performs action or event y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_animate, t_process], ARRAY['agent', 'action'],
    'primitive', 'x performs y',
    'wikidata:P664', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

-- created_by(creation, creator)
oid := stable_uuid('created_by', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'created_by', 'created by',
    'x was made, authored, or produced by agent y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['creation', 'creator'],
    'primitive', 'x was created by y',
    'wikidata:P170 / conceptnet:CreatedBy', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

-- has_role(entity, role, scope) — enrich the schema-seeded predicate.
-- [Fix #5] Updated: NULL scope removed from documentation. Use no_scope.
oid := stable_uuid('has_role', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'has_role', 'has role',
    'x holds role y within scope z (organisation, domain, or context). '
    'Replaces held_office. For genuinely unscoped roles, use no_scope '
    'as the scope arg — do not use NULL or the unknown sentinel. '
    'This is the role/state sense of the copula: '
    '"X is president" → has_role(X, president, [organisation]).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 3,
    ARRAY[t_entity, t_entity, t_entity],
    ARRAY['entity', 'role', 'scope'],
    -- [Fix #5] Removed "scope may be NULL"; use no_scope sentinel instead
    'primitive; bitransitive; use no_scope sentinel for unscoped roles',
    'x holds role y within z (use no_scope if unscoped)',
    'wikidata:P39 generalised', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

-- affiliated_with(entity, organisation, capacity)
oid := stable_uuid('affiliated_with', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'affiliated_with', 'affiliated with',
    'x is associated with organisation y in capacity z. '
    'Use no_scope as capacity when affiliation has no specific capacity.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 3,
    ARRAY[t_entity, t_entity, t_entity],
    ARRAY['entity', 'organisation', 'capacity'],
    'primitive; bitransitive', 'x is affiliated with y in capacity z',
    'wikidata:P108 / P463', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

-- related_to — generic fallback; symmetric.
oid := stable_uuid('related_to', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'related_to', 'related to',
    'x and y are related (generic, symmetric). '
    'Use a more specific predicate if one applies.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['entity_a', 'entity_b'],
    'primitive; symmetric', 'x and y are related',
    'conceptnet:RelatedTo', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

-- opposite_of — symmetric, conceptual antonymy.
oid := stable_uuid('opposite_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'opposite_of', 'opposite of',
    'x is the conceptual opposite or antonym of y (symmetric).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_abstract, t_abstract], ARRAY['concept_a', 'concept_b'],
    'primitive; symmetric', 'x is the opposite of y',
    'conceptnet:Antonym', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 7: QUANTITATIVE  (3)
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('has_quantity', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'has_quantity', 'has quantity',
    'x has measurable quantity y (population, mass, length, …).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_number], ARRAY['entity', 'quantity'],
    'primitive', 'x has quantity y',
    'wikidata:P1082 etc.', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('greater_than', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'greater_than', 'greater than',
    'Quantity x is greater than quantity y (asymmetric, transitive).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_number, t_number], ARRAY['larger', 'smaller'],
    'primitive; asymmetric; transitive', 'x > y',
    NULL, true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description,
    is_basis=true, status='confirmed';

oid := stable_uuid('approximately_equal', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'approximately_equal', 'approximately equal',
    'x and y are approximately equal in magnitude (symmetric, fuzzy).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_number, t_number], ARRAY['quantity_a', 'quantity_b'],
    'primitive; symmetric; fuzzy', 'x ≈ y',
    NULL, true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 8: EPISTEMIC / MODAL  (5)
-- knows, believes, desires: agent arg constrained to sapient.
-- possible, necessary: unary (1 arg).
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('knows', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'knows', 'knows',
    'Agent x has knowledge of fact, concept, or entity y (veridical).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_sapient, t_entity], ARRAY['knower', 'known'],
    'primitive; knows(X,Y) -> true(Y)', 'x knows y',
    NULL, true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';

oid := stable_uuid('believes', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'believes', 'believes',
    'Agent x believes y to be true (non-veridical; belief may be false).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_sapient, t_entity], ARRAY['believer', 'believed'],
    'primitive; distinct from knows; believes(X,Y) does not entail true(Y)',
    'x believes y', NULL, true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';

oid := stable_uuid('desires', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'desires', 'desires',
    'Agent x wants or desires y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_sapient, t_entity], ARRAY['desirer', 'desired'],
    'primitive', 'x desires y',
    'conceptnet:Desires', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('possible', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'possible', 'possible',
    'Proposition x is possible (not necessarily actual). Intransitive (1 arg).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 1, ARRAY[t_entity], ARRAY['proposition'],
    'primitive; modal', 'x is possible',
    NULL, true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';

oid := stable_uuid('necessary', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'necessary', 'necessary',
    'x is necessarily true — could not be otherwise. Intransitive (1 arg).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 1, ARRAY[t_entity], ARRAY['proposition'],
    'primitive; modal; necessary(X) -> possible(X)', 'x is necessarily true',
    NULL, true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 9: LINGUISTIC / REPRESENTATIONAL  (3)
-- arg_type_ids left NULL where no backbone type exists yet
-- (language, symbol, name) — tighten in a later migration.
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('named', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'named', 'named',
    'Entity x has name y in natural language.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, NULL], ARRAY['entity', 'name'],
    'primitive', 'x is named y',
    'rdfs:label / wikidata:P2561', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('symbol_for', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'symbol_for', 'symbol for',
    'x is a symbol or representation of y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['symbol', 'concept'],
    'primitive', 'x is a symbol of y',
    'conceptnet:SymbolOf', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('language_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'language_of', 'language of',
    'Language x is spoken, written, or used by y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['language', 'entity'],
    'primitive', 'x is the language of y',
    'wikidata:P407', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 10: EVENT CALCULUS CORE  (4)
-- holds_at_ec avoids name collision with the holds_at() SQL function.
--
-- NOTE ON TIME ARGS IN EVENT CALCULUS PREDICATES:
-- happens_at(event, time) and holds_at_ec(fluent, time) take a formal
-- time-point argument as part of the EC formalism — this is not a
-- violation of schema canonical policy #3. In EC, HappensAt(e, t) and
-- HoldsAt(f, t) are formal meta-predicates where t is a named time-point
-- in the EC domain, not a temporal encoding of a statement's own scope.
-- The statement's fuzzy_time fields still encode when the assertion
-- itself holds; the time arg is part of the predicate's content.
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('initiates', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'initiates', 'initiates',
    'Event x causes state/fluent y to begin holding.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_entity], ARRAY['event', 'fluent'],
    'primitive; event calculus', 'event x initiates fluent y',
    'ec:Initiates', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('terminates', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'terminates', 'terminates',
    'Event x causes state/fluent y to stop holding.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_entity], ARRAY['event', 'fluent'],
    'primitive; event calculus', 'event x terminates fluent y',
    'ec:Terminates', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

-- happens_at(event, time)
-- EC formal predicate: time arg is a named time-point entity in the EC
-- domain model, not a fuzzy_time encoding. See group note above.
oid := stable_uuid('happens_at', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'happens_at', 'happens at',
    'Event x occurs at time-point y (Event Calculus formal predicate). '
    'The time arg is a named EC time-point entity, not a fuzzy_time encoding. '
    'See schema canonical policy #3 and Group 10 note.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_entity], ARRAY['event', 'time_point'],
    'primitive; event calculus', 'event x happens at time-point y',
    'ec:HappensAt', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

-- holds_at_ec(fluent, time_point)
-- EC formal predicate: named holds_at_ec to avoid collision with the
-- holds_at() SQL function in common_knowledge_schema.sql.
oid := stable_uuid('holds_at_ec', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'holds_at_ec', 'holds at (EC)',
    'State or fluent x is true at time-point y (Event Calculus meta-predicate). '
    'Named holds_at_ec to avoid collision with the holds_at() SQL query function. '
    'The time arg is a named EC time-point entity; see Group 10 note.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['fluent', 'time_point'],
    'derived from initiates/terminates/happens_at chain', 'fluent x holds at time-point y',
    'ec:HoldsAt', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 11: PHYSICAL / LIFECYCLE  (4)
-- born_in / died_in absent — use located_in + fuzzy_time scope on
-- the statement (t_start/t_end, t_kind='point'). See policy #3.
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('made_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'made_of', 'made of',
    'x is composed of or constructed from material y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_concrete, t_entity], ARRAY['object', 'material'],
    'primitive', 'x is made of y',
    'conceptnet:MadeOf', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('has_state', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'has_state', 'has state',
    'Entity x is in physical or abstract state y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['entity', 'state'],
    'primitive', 'x is in state y',
    NULL, true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';

oid := stable_uuid('precondition_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'precondition_of', 'precondition of',
    'x must hold before y can occur.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_process], ARRAY['condition', 'event'],
    'precondition_of(X,Y) :- necessary(X) ∧ before(X,Y)', 'x is a precondition of y',
    'conceptnet:HasPrerequisite', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('affects', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'affects', 'affects',
    'x has some effect on y (weaker than causes; no mechanism implied).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['influencer', 'influenced'],
    'weaker than causes; affects(X,Y) does not assert direction', 'x affects y',
    'conceptnet:Causes (weak)', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 12: INFERENTIAL / CORRELATIONAL  (4)
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('implies', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'implies', 'implies',
    'x logically or probabilistically entails y. '
    'Distinct from causes: no temporal order or mechanism required.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['antecedent', 'consequent'],
    'primitive; crisp at P=1, probabilistic at P<1', 'x implies y',
    NULL, true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';

oid := stable_uuid('correlated_with', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'correlated_with', 'correlated with',
    'x and y tend to co-occur or vary together (symmetric; no causal claim).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['entity_a', 'entity_b'],
    'primitive; symmetric; weaker than causes or implies', 'x and y are correlated',
    NULL, true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';

oid := stable_uuid('typical_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'typical_of', 'typical of',
    'x is a typical or prototypical instance of category y (graded). '
    'Encodes the exemplification sense of the copula. '
    'Belief value encodes typicality degree; belief_mean = 1 → maximally typical. '
    'Distinct from is_a (crisp membership) and has_property (predication).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_abstract], ARRAY['instance', 'category'],
    'primitive; graded; distinct from is_a (crisp) and has_property',
    'x is a typical instance of y',
    'conceptnet:IsA (prototype sense)', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('occurs_in', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'occurs_in', 'occurs in',
    'Event x takes place within situation, context, or location y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_entity], ARRAY['event', 'situation'],
    'primitive; complements located_in (objects) and during (time)',
    'event x occurs in situation or location y',
    NULL, true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 13: STRUCTURAL / LOGICAL  (3)
-- ════════════════════════════════════════════════════════════

-- equivalent_to — intensional equivalence; stronger than same_as.
oid := stable_uuid('equivalent_to', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'equivalent_to', 'equivalent to',
    'x and y are definitionally or intensionally equivalent. '
    'Stronger than same_as (co-reference): equivalent_to requires '
    'the same meaning, not just the same referent.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    -- [Bootstrapping limitation] arg_type_ids set to NULL.
    -- Intended constraint: ARRAY[t_abstract, t_abstract].
    NULL,
    ARRAY['concept_a', 'concept_b'],
    'primitive; symmetric; equivalent_to(X,Y) → same_as(X,Y) but not vice versa',
    'x is definitionally equivalent to y',
    'owl:equivalentClass / owl:equivalentProperty', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

-- disjoint_with — no instance can belong to both types simultaneously.
--
-- [Fix #8] CONFLICT SEMANTICS:
--   disjoint_with drives type_violation conflicts (domain_strictness='hard'),
--   not direct_negation conflicts. A statement asserting is_a(Z, X) where
--   disjoint_with(X, Y) exists and Z is already is_a(Z, Y) triggers
--   a type_violation, not a direct_negation. These are conceptually
--   distinct: direct_negation is about evidential opposition between
--   two statements about the same fact; type_violation is about an
--   argument failing a structural constraint on who can hold a type.
--
-- [Fix #12] DISJOINTNESS LATTICE:
--   This predicate definition enables the full disjointness lattice to
--   be seeded. The actual disjoint_with STATEMENTS (abstract ⊥ concrete
--   and their descendants) are seeded in common_objects_kernel.sql after
--   the full type hierarchy is in place. This file defines the predicate
--   only; no disjoint_with statements are inserted here.
oid := stable_uuid('disjoint_with', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'disjoint_with', 'disjoint with',
    'No entity can simultaneously be an instance of both x and y. '
    'Violation of this constraint drives type_violation conflicts '
    '(not direct_negation — see schema conflict_kind enum comment). '
    'The full disjointness lattice is seeded in common_objects_kernel.sql.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    -- [Bootstrapping limitation] arg_type_ids set to NULL.
    -- Intended constraint: ARRAY[t_abstract, t_abstract].
    -- domain_strictness lowered to 'soft' for the same reason:
    -- with NULL arg_type_ids the trigger returns early regardless, but
    -- 'soft' is retained as belt-and-suspenders until v0.7 re-enables
    -- enforcement via recursive subtype_of traversal.
    -- The hard constraint is the right long-term design; it is correctly
    -- documented in fol_definition and nl_description.
    NULL,
    ARRAY['type_a', 'type_b'],
    'disjoint_with(X,Y) :- not exists Z s.t. is_a(Z,X) ∧ is_a(Z,Y)',
    'types x and y share no instances; violation is a type_violation conflict',
    'owl:disjointWith',
    true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

-- has_value(entity, attribute, value) — ternary; third arg usually a literal.
oid := stable_uuid('has_value', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'has_value', 'has value',
    'Entity x has attribute y with value z. '
    'Third arg (z) is typically a literal (integer, float, string) stored '
    'in literal_args. Distinct from has_quantity: has_value names the '
    'attribute explicitly.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 3, ARRAY[t_entity, t_abstract, NULL],
    ARRAY['entity', 'attribute', 'value'],
    'primitive; bitransitive; value arg is typically in literal_args',
    'x has attribute y with value z',
    'wikidata:P1 generalised', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- ENRICHMENT: schema-seeded predicates not already covered
-- ════════════════════════════════════════════════════════════

-- has_capacity — seeded by schema; enrich with arg_type_ids and is_basis.
oid := stable_uuid('has_capacity', 'predicate');
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['entity', 'capacity'],
    'primitive', 'x possesses capacity y',
    NULL, true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';

-- models_as — seeded by schema; enrich with arg_type_ids.
-- Not is_basis (it is a modeling convenience, not a primitive relation).
oid := stable_uuid('models_as', 'predicate');
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 3, ARRAY[t_entity, t_abstract, t_entity],
    ARRAY['subject', 'type', 'context'],
    'primitive; non-ontological modeling convenience',
    'subject is modeled as type within context',
    NULL, false, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- is_a / instance_of EQUIVALENCE LINK
-- [Fix #1] Both is_a and instance_of trigger trg_sync_type_membership.
-- The schema's trg_sync_type_membership fires on both predicates by
-- stable_uuid match, so both are fully functional canonical type
-- mechanism triggers. This object_equivalence records the semantic
-- identity for callers querying predicate metadata. Callers should
-- prefer is_a as the canonical name; instance_of remains as an alias
-- for backward compatibility and external-schema cross-references.
-- ════════════════════════════════════════════════════════════

INSERT INTO object_equivalence (object_a, object_b, alpha, beta, context_id)
VALUES (
    LEAST(   stable_uuid('is_a',        'predicate'),
             stable_uuid('instance_of', 'predicate') ),
    GREATEST(stable_uuid('is_a',        'predicate'),
             stable_uuid('instance_of', 'predicate') ),
    19.0, 1.0,
    stable_uuid('reality', 'context')
)
ON CONFLICT (object_a, object_b) DO NOTHING;

END $$;

COMMIT;


-- ── Verification query ────────────────────────────────────────
SELECT
    o.canonical_name,
    p.arity,
    CASE p.arity
        WHEN 1 THEN 'intransitive'
        WHEN 2 THEN 'binary'
        WHEN 3 THEN 'ternary'
        ELSE        'higher'
    END                AS arg_structure,
    p.arg_labels,
    p.domain_strictness,
    p.source_predicate
FROM predicates p
JOIN objects    o ON o.id = p.id
WHERE p.is_basis = true
ORDER BY p.arity, o.canonical_name;
