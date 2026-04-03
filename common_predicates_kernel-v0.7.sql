-- =============================================================
-- Common Knowledge KB — Basis Predicates (v0.7)
-- =============================================================
-- Seeds and enriches the 57 basis predicates across 13 groups.
-- Provides the inverse_predicate_id wiring for automated symmetric
-- assertion (before↔after, part_of↔has_part).
--
-- Run order:
--   1. common_knowledge_schema.sql  (backbone objects, triggers)
--   2. THIS FILE
--   3. common_objects_kernel.sql    (disjointness lattice, role subtypes)
--
-- v0.7 changes:
--
--   arg_type_ids ENFORCEMENT NOW FULLY TRANSITIVE  [Fix #22]
--     The domain check trigger (trg_z_soft_domain_check) now resolves
--     type membership via recursive CTE over subtype_of. Application
--     predicates that constrain args to abstract types (e.g. capable_of
--     → animate) now correctly accept subtype instances (e.g. person
--     → sapient → animate) without requiring manual is_a materialisation.
--     The NULL arg_type_ids on structural predicates (is_a, subtype_of,
--     equivalent_to, disjoint_with) is retained — this is a meta-level
--     bootstrapping circularity, not a transitive closure problem:
--     type-category objects (person, abstract, …) cannot satisfy
--     is_a(X, abstract) without circular reasoning at kernel load time.
--     All remaining NULL comments below reflect this reason only.
--
--   STATEMENT_KIND GUIDANCE  [Fix #17]
--     Descriptions for structural predicates note that statements using
--     them should be inserted with statement_kind = 'ontological'.
--     Descriptions for correlated_with and typical_of note that their
--     statements should use statement_kind = 'statistical' so that they
--     are correctly excluded from logical inference chains.
--
--   no_period SENTINEL FOR LOCATED_IN  [Fix #23]
--     located_in description updated: when no named time period is the
--     semantic argument, use the no_period sentinel (not no_scope) as
--     the third arg. no_scope is restricted to role-scope arguments.
--     causes(x, y, mechanism) retains no_scope for its mechanism arg.
--
--   INVERSE PREDICATE WIRING  [Fix #24]
--     inverse_predicate_id set for:
--       before  ↔  after
--       part_of ↔  has_part
--       contains → part_of (spatial sense)
--     After both predicates in a pair exist, the schema trigger
--     trg_zz_auto_inverse_statement will automatically insert the
--     inverse statement and provenance edge for any new binary assertion.
--     Seeded at the end of this file after all objects exist.
--
--   disjoint_with domain_strictness → 'hard'  [Fix #22]
--     Upgraded from 'soft' to 'hard' to reflect correct long-term intent.
--     arg_type_ids remains NULL (bootstrapping circularity), so the
--     trigger still returns early during kernel load — no false violations.
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
-- CANONICAL TYPE MECHANISM. Inserting an is_a or instance_of statement
-- automatically populates type_membership via trg_sync_type_membership.
-- Do NOT assert type_membership rows directly.
-- [Fix #17] Statements using is_a should carry statement_kind = 'empirical'
-- (default) for individual classifications, or 'ontological' when making
-- structural ontological assertions.
oid := stable_uuid('is_a', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'is_a', 'is a',
    'x is an instance of type y (crisp classification only). '
    'Inserting an is_a statement automatically populates type_membership '
    'via trg_sync_type_membership. Do NOT assert type_membership directly. '
    'Do NOT use for role, state, property, typicality, or identity. '
    'See: has_role (role), has_property (predication), '
    'typical_of (exemplification), same_as (identity). '
    'Use statement_kind = ''ontological'' for structural assertions; '
    '''empirical'' (default) for individual classifications.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates
    (id, arity, arg_type_ids, arg_labels,
     fol_definition, nl_description, source_predicate,
     is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    -- arg_type_ids NULL: meta-level bootstrapping circularity.
    -- Intended constraint: ARRAY[t_entity, t_abstract].
    -- Type-category objects cannot satisfy is_a(X, abstract) without
    -- circular reasoning at kernel load time. This is not the transitive
    -- closure problem (resolved in v0.7); it is a meta-level issue.
    NULL,
    ARRAY['instance', 'type'],
    'primitive',
    'x is an instance of y. Triggers type_membership cache update automatically.',
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
-- [Fix #17] Insert statements with statement_kind = 'ontological'.
-- [Fix #22] Transitive closure is now resolved at enforcement time via
-- recursive CTE in trg_z_soft_domain_check. Manual materialisation of
-- every transitive is_a pair is no longer required.
oid := stable_uuid('subtype_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'subtype_of', 'subtype of',
    'Every instance of x is also an instance of y (transitive, asymmetric). '
    'Transitive closure is resolved at enforcement time via recursive CTE '
    'in trg_z_soft_domain_check (v0.7+). Do not materialise transitive '
    'is_a pairs manually. '
    'Insert statements with statement_kind = ''ontological''.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates
    (id, arity, arg_type_ids, arg_labels,
     fol_definition, nl_description, source_predicate,
     is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    -- arg_type_ids NULL: meta-level bootstrapping circularity.
    -- Intended constraint: ARRAY[t_abstract, t_abstract].
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
    'x and y are distinct entities. Open-world assumption applies: '
    'absence of same_as does not imply different_from.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates
    (id, arity, arg_type_ids, arg_labels,
     fol_definition, nl_description, source_predicate,
     is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_entity],
    ARRAY['entity_a', 'entity_b'],
    'different_from(X,Y) :- not same_as(X,Y); '
    'open-world: absence of same_as is not sufficient evidence for different_from',
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
-- [Fix #24] part_of ↔ has_part inverse wiring seeded at end of file.
-- contains → part_of (spatial sense) also wired there.
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('part_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'part_of', 'part of',
    'x is a component or part of y (transitive, asymmetric). '
    'Inverse: has_part. [Fix #24] inverse_predicate_id wired — '
    'inserting part_of(A, B) automatically inserts has_part(B, A).')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_entity], ARRAY['part', 'whole'],
    'primitive; transitive; asymmetric; inverse: has_part',
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
    'x contains y as a component. '
    'Inverse: part_of. [Fix #24] inverse_predicate_id wired — '
    'inserting has_part(A, B) automatically inserts part_of(B, A).')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_entity], ARRAY['whole', 'part'],
    'has_part(X,Y) :- part_of(Y,X); inverse: part_of',
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
    'x physically or abstractly contains y (spatial sense: part_of(Y,X)). '
    'Inverse: part_of (spatial sense). [Fix #24] inverse_predicate_id '
    'wired at end of file.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_entity], ARRAY['container', 'contained'],
    'contains(X,Y) :- part_of(Y,X) [spatial sense]; inverse: part_of',
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
-- CANONICAL TIME POLICY FOR SPATIAL PREDICATES:
-- located_in(entity, place, time_period) — the THIRD ARG is a named
-- time period object (e.g. "victorian_era", "bronze_age") used only when
-- that period is the genuine semantic argument. Temporal scope (when x
-- was at y) MUST be expressed via the statement's t_start / t_end
-- fuzzy_time fields.
-- [Fix #23] When no named period is the semantic argument, use the
-- no_period sentinel: located_in(X, place, no_period).
-- Do NOT use no_scope here — no_scope is restricted to role-scope args.
-- ════════════════════════════════════════════════════════════

-- located_in(entity, place, time_period)
oid := stable_uuid('located_in', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'located_in', 'located in',
    'x is situated within or at location y. '
    'The third arg (time_period) is a NAMED TIME PERIOD object '
    '(e.g. "victorian_era") — used only when that period is the genuine '
    'semantic argument, not as a temporal encoding mechanism. '
    'ALL temporal scope (when x was at y) goes in the statement''s '
    't_start / t_end fuzzy_time fields. '
    '[Fix #23] When no named period is the semantic argument, use the '
    'no_period sentinel: located_in(entity, place, no_period). '
    'Do NOT use no_scope for this arg — no_scope is for role-scope only. '
    'See schema canonical policy decision #3.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 3,
    ARRAY[t_entity, t_entity, t_entity],
    ARRAY['entity', 'place', 'time_period'],
    'primitive',
    'x is located in y (during named period z if specified, else no_period). '
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
-- These predicates encode ORDERING and OVERLAP relations between events
-- as KB statements, distinct from statement-level fuzzy_time fields.
-- [Fix #24] before ↔ after inverse wiring seeded at end of file.
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('before', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'before', 'before',
    'Event or time x occurs strictly before y (transitive, asymmetric). '
    'Inverse: after. [Fix #24] inverse_predicate_id wired — '
    'inserting before(A, B) automatically inserts after(B, A).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_process], ARRAY['earlier', 'later'],
    'primitive; transitive; asymmetric; inverse: after(Y,X)',
    'x happens strictly before y',
    'allen:before', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('after', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'after', 'after',
    'Event or time x occurs strictly after y. '
    'Inverse: before. [Fix #24] inverse_predicate_id wired — '
    'inserting after(A, B) automatically inserts before(B, A).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_process], ARRAY['later', 'earlier'],
    'after(X,Y) :- before(Y,X); inverse: before(Y,X)',
    'x happens strictly after y',
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
    'primitive (Allen interval relation)',
    'x occurs within the span of y',
    'allen:during', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('simultaneous_with', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'simultaneous_with', 'simultaneous with',
    'Events x and y occur at the same time (symmetric). '
    'Corresponds to Allen ''equals'' relation.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_process], ARRAY['event_a', 'event_b'],
    'primitive; symmetric',
    'x and y happen at the same time',
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
    'primitive',
    'x lasts for duration y',
    'wikidata:P2047', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 5: CAUSAL / FUNCTIONAL  (6)
-- causes(cause, effect, mechanism) — ternary.
-- [Fix #23] Mechanism arg uses no_scope (not no_period) when unknown
-- or irrelevant. no_scope is the correct sentinel for functional/
-- contextual args (mechanism, capacity, scope). no_period is reserved
-- exclusively for time-period args (located_in, etc.).
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('causes', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'causes', 'causes',
    'x brings about y via mechanism z. '
    'When the mechanism is unknown or irrelevant, use no_scope as the '
    'third arg: causes(X, Y, no_scope). '
    'no_scope is correct here (functional arg); no_period is for '
    'time-period args only.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 3, ARRAY[t_entity, t_entity, t_entity],
    ARRAY['cause', 'effect', 'mechanism'],
    'primitive; bitransitive; use no_scope for unknown mechanism',
    'x causes y via mechanism z (no_scope if mechanism unspecified)',
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
    'primitive; weaker than causes',
    'x enables y',
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
    'primitive',
    'x prevents y',
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
    'primitive',
    'x is used for y',
    'conceptnet:UsedFor', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

-- capable_of — first arg constrained to animate.
-- [Fix #22] arg_type_ids ARRAY[t_animate, t_entity] is now reliably
-- enforced via the recursive CTE in trg_z_soft_domain_check. Entities
-- that are subtypes of animate (e.g. person → sapient → animate) pass
-- without requiring a direct is_a(entity, animate).
oid := stable_uuid('capable_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'capable_of', 'capable of',
    'x has the capacity or disposition to do y. '
    'First arg must be animate (satisfied transitively via subtype_of).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_animate, t_entity], ARRAY['agent', 'action'],
    'primitive',
    'x is capable of y',
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
    'primitive',
    'x is motivated by y',
    'conceptnet:MotivatedByGoal', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 6: AGENTIVE / SOCIAL  (6)
-- has_role(entity, role, scope) — ternary.
-- Scope arg policy: use no_scope when role is genuinely unscoped.
-- NULL scope is undocumented behaviour.
-- Role subtypes (mathematician, programmer, etc.) seeded as
-- subtype_of(mathematician, role) in common_objects_kernel.sql.
-- ════════════════════════════════════════════════════════════

-- agent_of — first arg constrained to animate (now transitively enforced).
oid := stable_uuid('agent_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'agent_of', 'agent of',
    'x is the intentional agent who performs action or event y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_animate, t_process], ARRAY['agent', 'action'],
    'primitive',
    'x performs y',
    'wikidata:P664', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('created_by', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'created_by', 'created by',
    'x was made, authored, or produced by agent y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['creation', 'creator'],
    'primitive',
    'x was created by y',
    'wikidata:P170 / conceptnet:CreatedBy', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('has_role', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'has_role', 'has role',
    'x holds role y within scope z (organisation, domain, or context). '
    'Replaces held_office. For genuinely unscoped roles, use no_scope '
    'as the scope arg — do not use NULL or the unknown sentinel. '
    '"X is president" → has_role(X, president, [organisation]).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 3,
    ARRAY[t_entity, t_entity, t_entity],
    ARRAY['entity', 'role', 'scope'],
    'primitive; bitransitive; use no_scope sentinel for unscoped roles',
    'x holds role y within z (use no_scope if unscoped)',
    'wikidata:P39 generalised', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

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
    'primitive; bitransitive',
    'x is affiliated with y in capacity z',
    'wikidata:P108 / P463', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('related_to', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'related_to', 'related to',
    'x and y are related (generic, symmetric). '
    'Use a more specific predicate if one applies.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['entity_a', 'entity_b'],
    'primitive; symmetric',
    'x and y are related',
    'conceptnet:RelatedTo', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('opposite_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'opposite_of', 'opposite of',
    'x is the conceptual opposite or antonym of y (symmetric).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_abstract, t_abstract], ARRAY['concept_a', 'concept_b'],
    'primitive; symmetric',
    'x is the opposite of y',
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
    'primitive',
    'x has quantity y',
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
    'primitive; asymmetric; transitive',
    'x > y',
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
    'primitive; symmetric; fuzzy',
    'x ≈ y',
    NULL, true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 8: EPISTEMIC / MODAL  (5)
-- knows, believes, desires: first arg constrained to sapient.
-- [Fix #22] sapient constraint now transitively enforced — any subtype
-- of sapient (e.g. person) passes without direct is_a(X, sapient).
-- possible, necessary: unary (1 arg).
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('knows', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'knows', 'knows',
    'Agent x has knowledge of fact, concept, or entity y (veridical). '
    'First arg must be sapient (satisfied transitively via subtype_of).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_sapient, t_entity], ARRAY['knower', 'known'],
    'primitive; knows(X,Y) -> true(Y)',
    'x knows y',
    NULL, true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';

oid := stable_uuid('believes', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'believes', 'believes',
    'Agent x believes y to be true (non-veridical; belief may be false). '
    'First arg must be sapient (satisfied transitively via subtype_of).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_sapient, t_entity], ARRAY['believer', 'believed'],
    'primitive; distinct from knows; believes(X,Y) does not entail true(Y)',
    'x believes y',
    NULL, true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';

oid := stable_uuid('desires', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'desires', 'desires',
    'Agent x wants or desires y. '
    'First arg must be sapient (satisfied transitively via subtype_of).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_sapient, t_entity], ARRAY['desirer', 'desired'],
    'primitive',
    'x desires y',
    'conceptnet:Desires', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('possible', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'possible', 'possible',
    'Proposition x is possible (not necessarily actual). Unary (1 arg).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 1, ARRAY[t_entity], ARRAY['proposition'],
    'primitive; modal',
    'x is possible',
    NULL, true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';

oid := stable_uuid('necessary', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'necessary', 'necessary',
    'x is necessarily true — could not be otherwise. Unary (1 arg).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 1, ARRAY[t_entity], ARRAY['proposition'],
    'primitive; modal; necessary(X) -> possible(X)',
    'x is necessarily true',
    NULL, true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 9: LINGUISTIC / REPRESENTATIONAL  (3)
-- arg_type_ids NULL where no backbone type exists yet
-- (language, symbol, name) — tighten in a later migration once
-- language ⊂ symbol and related types are seeded.
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('named', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'named', 'named',
    'Entity x has name y in natural language.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, NULL], ARRAY['entity', 'name'],
    'primitive',
    'x is named y',
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
    'primitive',
    'x is a symbol of y',
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
    'primitive',
    'x is the language of y',
    'wikidata:P407', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 10: EVENT CALCULUS CORE  (4)
-- holds_at_ec avoids name collision with the holds_at() SQL function.
-- NOTE: happens_at and holds_at_ec take formal EC time-point args.
-- This is NOT a violation of canonical policy #3 — EC time-points are
-- named semantic objects in the EC domain model, not temporal encodings
-- of the statement's own scope. The statement's fuzzy_time fields still
-- encode when the assertion holds; the time arg is part of the content.
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('initiates', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'initiates', 'initiates',
    'Event x causes state/fluent y to begin holding.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_entity], ARRAY['event', 'fluent'],
    'primitive; event calculus',
    'event x initiates fluent y',
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
    'primitive; event calculus',
    'event x terminates fluent y',
    'ec:Terminates', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('happens_at', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'happens_at', 'happens at',
    'Event x occurs at time-point y (Event Calculus formal predicate). '
    'The time arg is a named EC time-point entity, not a fuzzy_time encoding. '
    'See Group 10 note.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_entity], ARRAY['event', 'time_point'],
    'primitive; event calculus',
    'event x happens at time-point y',
    'ec:HappensAt', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

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
    'derived from initiates/terminates/happens_at chain',
    'fluent x holds at time-point y',
    'ec:HoldsAt', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 11: PHYSICAL / LIFECYCLE  (4)
-- born_in / died_in absent — use located_in(X, place, no_period)
-- with t_kind='point' and fuzzy_time on the statement. See policy #3.
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('made_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'made_of', 'made of',
    'x is composed of or constructed from material y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_concrete, t_entity], ARRAY['object', 'material'],
    'primitive',
    'x is made of y',
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
    'primitive',
    'x is in state y',
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
    'precondition_of(X,Y) :- necessary(X) ∧ before(X,Y)',
    'x is a precondition of y',
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
    'weaker than causes; affects(X,Y) does not assert direction',
    'x affects y',
    'conceptnet:Causes (weak)', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 12: INFERENTIAL / CORRELATIONAL  (4)
-- [Fix #17] STATEMENT_KIND:
-- correlated_with and typical_of encode statistical/probabilistic
-- patterns, not crisp individual-level facts. Insert all statements
-- using these predicates with statement_kind = 'statistical'.
-- Statistical statements are excluded from logical inference chains
-- (holds_at open_world mode, compute_derived_belief). Full enforcement
-- planned for v0.8.
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
    'primitive; crisp at P=1, probabilistic at P<1',
    'x implies y',
    NULL, true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';

-- correlated_with: insert ALL statements with statement_kind = 'statistical'.
oid := stable_uuid('correlated_with', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'correlated_with', 'correlated with',
    'x and y tend to co-occur or vary together (symmetric; no causal claim). '
    '[Fix #17] Insert all statements using this predicate with '
    'statement_kind = ''statistical''. Statistical statements are excluded '
    'from logical inference chains and must not feed forward_chained derivations.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['entity_a', 'entity_b'],
    'primitive; symmetric; weaker than causes or implies; '
    'all instances require statement_kind = ''statistical''',
    'x and y are correlated; insert with statement_kind = ''statistical''',
    NULL, true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';

-- typical_of: insert ALL statements with statement_kind = 'statistical'.
oid := stable_uuid('typical_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'typical_of', 'typical of',
    'x is a typical or prototypical instance of category y (graded). '
    'belief_mean encodes typicality degree; 1.0 = maximally typical. '
    'Distinct from is_a (crisp membership) and has_property (predication). '
    '[Fix #17] Insert all statements using this predicate with '
    'statement_kind = ''statistical''. Statistical statements are excluded '
    'from logical inference chains.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_abstract], ARRAY['instance', 'category'],
    'primitive; graded; distinct from is_a (crisp) and has_property; '
    'all instances require statement_kind = ''statistical''',
    'x is a typical instance of y; insert with statement_kind = ''statistical''',
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
-- [Fix #17] Insert all statements using equivalent_to and disjoint_with
-- with statement_kind = 'ontological'.
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('equivalent_to', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'equivalent_to', 'equivalent to',
    'x and y are definitionally or intensionally equivalent. '
    'Stronger than same_as (co-reference): same meaning, not just same referent. '
    'Insert statements with statement_kind = ''ontological''.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    -- arg_type_ids NULL: meta-level bootstrapping circularity.
    -- Intended constraint: ARRAY[t_abstract, t_abstract].
    NULL,
    ARRAY['concept_a', 'concept_b'],
    'primitive; symmetric; equivalent_to(X,Y) → same_as(X,Y) but not vice versa',
    'x is definitionally equivalent to y; insert with statement_kind = ''ontological''',
    'owl:equivalentClass / owl:equivalentProperty', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

-- disjoint_with
-- [Fix #22] domain_strictness upgraded to 'hard' (was 'soft' in v0.6).
-- arg_type_ids NULL means trigger returns early during kernel load;
-- no false violations fire. 'hard' reflects correct long-term intent.
-- [Fix #17] Insert all statements with statement_kind = 'ontological'.
oid := stable_uuid('disjoint_with', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'disjoint_with', 'disjoint with',
    'No entity can simultaneously be an instance of both x and y. '
    'Violation drives type_violation conflicts (not direct_negation — '
    'see schema conflict_kind enum). '
    'The full disjointness lattice is seeded in common_objects_kernel.sql. '
    'Insert statements with statement_kind = ''ontological''.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    -- arg_type_ids NULL: meta-level bootstrapping circularity.
    -- Intended constraint: ARRAY[t_abstract, t_abstract].
    -- domain_strictness = 'hard': correct long-term intent. Trigger returns
    -- early with NULL arg_type_ids so no false violations during kernel load.
    NULL,
    ARRAY['type_a', 'type_b'],
    'disjoint_with(X,Y) :- not exists Z s.t. is_a(Z,X) ∧ is_a(Z,Y)',
    'types x and y share no instances; violation is a type_violation conflict; '
    'insert with statement_kind = ''ontological''',
    'owl:disjointWith',
    true, 'hard', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    domain_strictness='hard', is_basis=true, status='confirmed';

-- has_value(entity, attribute, value) — ternary; third arg usually a literal.
oid := stable_uuid('has_value', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'has_value', 'has value',
    'Entity x has attribute y with value z. '
    'Third arg (z) is typically a literal stored in literal_args. '
    'Distinct from has_quantity: has_value names the attribute explicitly.')
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
-- ENRICHMENT: schema-seeded predicates
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('has_capacity', 'predicate');
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['entity', 'capacity'],
    'primitive',
    'x possesses capacity y',
    NULL, true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';

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

END $$;


-- ════════════════════════════════════════════════════════════
-- [Fix #24] INVERSE PREDICATE WIRING
-- Run outside the DO block to guarantee both predicate objects exist.
-- The schema trigger trg_zz_auto_inverse_statement uses these links
-- to automatically maintain inverse consistency on INSERT.
-- ════════════════════════════════════════════════════════════

-- before ↔ after
UPDATE predicates
   SET inverse_predicate_id = stable_uuid('after',  'predicate')
 WHERE id = stable_uuid('before', 'predicate');

UPDATE predicates
   SET inverse_predicate_id = stable_uuid('before', 'predicate')
 WHERE id = stable_uuid('after',  'predicate');

-- part_of ↔ has_part
UPDATE predicates
   SET inverse_predicate_id = stable_uuid('has_part', 'predicate')
 WHERE id = stable_uuid('part_of',  'predicate');

UPDATE predicates
   SET inverse_predicate_id = stable_uuid('part_of',  'predicate')
 WHERE id = stable_uuid('has_part', 'predicate');

-- contains → part_of (spatial sense)
-- contains(A, B) auto-inserts part_of(B, A). part_of's inverse is
-- already wired to has_part above, so the chain is:
--   contains(A,B) → part_of(B,A) → has_part(A,B) [stops: already exists]
UPDATE predicates
   SET inverse_predicate_id = stable_uuid('part_of', 'predicate')
 WHERE id = stable_uuid('contains', 'predicate');


-- ════════════════════════════════════════════════════════════
-- is_a / instance_of EQUIVALENCE LINK
-- Both predicates trigger trg_sync_type_membership by stable_uuid match.
-- Prefer is_a as the canonical name; instance_of is an alias for
-- backward compatibility and external cross-references.
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

COMMIT;


-- ── Verification query ────────────────────────────────────────
SELECT
    o.canonical_name,
    p.arity,
    CASE p.arity
        WHEN 1 THEN 'unary'
        WHEN 2 THEN 'binary'
        WHEN 3 THEN 'ternary'
        ELSE        'higher'
    END                                          AS arg_structure,
    p.arg_labels,
    p.domain_strictness,
    CASE WHEN p.inverse_predicate_id IS NOT NULL
         THEN inv.canonical_name
         ELSE NULL
    END                                          AS inverse,
    p.source_predicate
FROM predicates p
JOIN objects    o   ON o.id   = p.id
LEFT JOIN objects inv ON inv.id = p.inverse_predicate_id
WHERE p.is_basis = true
ORDER BY p.arity, o.canonical_name;
