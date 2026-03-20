-- =============================================================
-- Common Knowledge KB — Kernel Objects & Statements
-- =============================================================
-- This file populates the foundational layer of the KB:
--
--   1. Abstract concept objects — the types, categories, and
--      abstract entities that basis predicates reference as
--      argument kinds (person, number, place, time, etc.)
--
--   2. Type hierarchy — subtype_of / is_a relations that form
--      the skeleton of the ontology. All eternal, confidence ~1.
--
--   3. Logical / mathematical eternal truths — opposite_of,
--      same_as, implies for the Boolean / logical primitives.
--
--   4. Domain context objects — the named domains in which
--      source credibility is tracked (history, science, etc.)
--
-- What is NOT here:
--   • Named individuals (John Tyler, France, the Sun) —
--     those belong in domain-specific population files.
--   • Contingent or time-bounded facts.
--   • Anything requiring a source other than system_kernel.
--
-- All statements in this file use:
--   belief_alpha = 1000.0, belief_beta = 0.001  (near-certain)
--   t_kind       = 'eternal'
--   derivation_type = 'axiomatic'
--   source       = system_kernel
-- =============================================================

BEGIN;

DO $$
DECLARE
    -- Fixed UUIDs for sources and contexts already in seed data
    reality     uuid := '00000000-0000-0000-0000-000000000001';
    sys         uuid := '00000000-0000-0000-0000-000000000005'; -- system_kernel

    -- Belief parameters for kernel axioms
    ka_alpha    double precision := 1000.0;
    ka_beta     double precision := 0.001;

    -- We collect predicate IDs by name at the start
    p_is_a          uuid;
    p_subtype_of    uuid;
    p_has_property  uuid;
    p_same_as       uuid;
    p_different_from uuid;
    p_part_of       uuid;
    p_member_of     uuid;
    p_opposite_of   uuid;
    p_implies       uuid;
    p_typical_of    uuid;
    p_correlated_with uuid;
    p_necessary     uuid;
    p_possible      uuid;
    p_named         uuid;

    -- We'll collect object IDs as we create them
    -- Top-level abstract types
    o_entity        uuid;
    o_abstract      uuid;
    o_physical      uuid;

    -- Entity subtypes
    o_person        uuid;
    o_organism      uuid;
    o_animal        uuid;
    o_mammal        uuid;
    o_agent         uuid;
    o_institution   uuid;
    o_group         uuid;

    -- Abstract subtypes
    o_concept       uuid;
    o_property      uuid;
    o_relation      uuid;
    o_proposition   uuid;
    o_event         uuid;
    o_process       uuid;
    o_state         uuid;
    o_action        uuid;

    -- Physical subtypes
    o_object        uuid;   -- physical object (avoid name clash with SQL)
    o_place         uuid;
    o_region        uuid;
    o_location      uuid;

    -- Quantity and measurement
    o_quantity      uuid;
    o_number        uuid;
    o_integer       uuid;
    o_real          uuid;
    o_natural       uuid;
    o_unit          uuid;
    o_measurement   uuid;

    -- Time
    o_time          uuid;
    o_interval_t    uuid;
    o_point_t       uuid;
    o_duration      uuid;

    -- Language and representation
    o_language      uuid;
    o_symbol        uuid;
    o_word          uuid;
    o_sentence      uuid;

    -- Truth values
    o_truth_value   uuid;
    o_true_val      uuid := '00000000-0000-0000-0000-000000000010';
    o_false_val     uuid := '00000000-0000-0000-0000-000000000011';
    o_unknown_val   uuid := '00000000-0000-0000-0000-000000000012';

    -- Domain contexts
    o_dom_history   uuid;
    o_dom_science   uuid;
    o_dom_math      uuid;
    o_dom_geography uuid;
    o_dom_biology   uuid;
    o_dom_physics   uuid;
    o_dom_law       uuid;
    o_dom_language  uuid;
    o_dom_social    uuid;
    o_dom_tech      uuid;

    stmt_id         uuid;

    -- ── Helper: insert one concept object ─────────────────────
    -- Returns the new id via RETURNING into a variable.
    -- (PL/pgSQL doesn't support inline functions easily, so we
    --  use the pattern: INSERT ... RETURNING id INTO var)

BEGIN

-- ════════════════════════════════════════════════════════════
-- SECTION 0: Resolve predicate IDs from basis_predicates.sql
-- ════════════════════════════════════════════════════════════
-- We look up by canonical_name; these must already exist.

SELECT id INTO p_is_a           FROM objects WHERE canonical_name='is_a'            AND kind='predicate';
SELECT id INTO p_subtype_of     FROM objects WHERE canonical_name='subtype_of'      AND kind='predicate';
SELECT id INTO p_has_property   FROM objects WHERE canonical_name='has_property'    AND kind='predicate';
SELECT id INTO p_same_as        FROM objects WHERE canonical_name='same_as'         AND kind='predicate';
SELECT id INTO p_different_from FROM objects WHERE canonical_name='different_from'  AND kind='predicate';
SELECT id INTO p_part_of        FROM objects WHERE canonical_name='part_of'         AND kind='predicate';
SELECT id INTO p_member_of      FROM objects WHERE canonical_name='member_of'       AND kind='predicate';
SELECT id INTO p_opposite_of    FROM objects WHERE canonical_name='opposite_of'     AND kind='predicate';
SELECT id INTO p_implies        FROM objects WHERE canonical_name='implies'         AND kind='predicate';
SELECT id INTO p_typical_of     FROM objects WHERE canonical_name='typical_of'      AND kind='predicate';
SELECT id INTO p_necessary      FROM objects WHERE canonical_name='necessary'       AND kind='predicate';
SELECT id INTO p_possible       FROM objects WHERE canonical_name='possible'        AND kind='predicate';
SELECT id INTO p_named          FROM objects WHERE canonical_name='named'           AND kind='predicate';

-- Sanity check: abort if basis predicates not loaded
IF p_is_a IS NULL THEN
    RAISE EXCEPTION 'Basis predicates not found. Run basis_predicates.sql first.';
END IF;

-- ════════════════════════════════════════════════════════════
-- SECTION 1: Top-level ontological concepts
-- ════════════════════════════════════════════════════════════

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','entity','Entity',
 'Anything that exists or can be referred to. Top of the object hierarchy.')
RETURNING id INTO o_entity;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','abstract_thing','Abstract thing',
 'An entity with no physical instantiation: concepts, numbers, propositions.')
RETURNING id INTO o_abstract;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','physical_thing','Physical thing',
 'An entity that occupies space and time.')
RETURNING id INTO o_physical;

-- ════════════════════════════════════════════════════════════
-- SECTION 2: Entity subtypes — animate / social
-- ════════════════════════════════════════════════════════════

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','organism','Organism',
 'A living entity: plant, animal, fungus, microbe.')
RETURNING id INTO o_organism;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','animal','Animal',
 'A multicellular organism of the kingdom Animalia.')
RETURNING id INTO o_animal;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','mammal','Mammal',
 'A warm-blooded vertebrate animal of the class Mammalia.')
RETURNING id INTO o_mammal;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','person','Person',
 'A human individual. Subtype of mammal and agent.')
RETURNING id INTO o_person;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','agent','Agent',
 'An entity capable of intentional action.')
RETURNING id INTO o_agent;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','institution','Institution',
 'An organisation, government, company, or structured social entity.')
RETURNING id INTO o_institution;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','group','Group',
 'A collection of agents or entities treated as a unit.')
RETURNING id INTO o_group;

-- ════════════════════════════════════════════════════════════
-- SECTION 3: Abstract subtypes
-- ════════════════════════════════════════════════════════════

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','concept_type','Concept',
 'An abstract idea, category, or mental representation.')
RETURNING id INTO o_concept;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','property','Property',
 'An attribute or characteristic that entities can have.')
RETURNING id INTO o_property;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','relation','Relation',
 'A predicate taking two or more arguments.')
RETURNING id INTO o_relation;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','proposition','Proposition',
 'A statement that is either true or false (in some context).')
RETURNING id INTO o_proposition;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','event_type','Event',
 'A change or occurrence at a time, involving participants.')
RETURNING id INTO o_event;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','process','Process',
 'An extended event with internal temporal structure.')
RETURNING id INTO o_process;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','state','State',
 'A condition that persists over a time interval.')
RETURNING id INTO o_state;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','action','Action',
 'An event intentionally performed by an agent.')
RETURNING id INTO o_action;

-- ════════════════════════════════════════════════════════════
-- SECTION 4: Physical / spatial subtypes
-- ════════════════════════════════════════════════════════════

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','physical_object','Physical object',
 'A bounded physical entity: tool, artifact, natural body.')
RETURNING id INTO o_object;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','place','Place',
 'A location or region in physical space.')
RETURNING id INTO o_place;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','region','Region',
 'An extended area of space, possibly administrative.')
RETURNING id INTO o_region;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','location','Location',
 'A point or area used to describe where something is.')
RETURNING id INTO o_location;

-- ════════════════════════════════════════════════════════════
-- SECTION 5: Quantity and measurement
-- ════════════════════════════════════════════════════════════

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','quantity','Quantity',
 'A measurable amount: number, mass, length, temperature, etc.')
RETURNING id INTO o_quantity;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','number','Number',
 'An abstract mathematical quantity.')
RETURNING id INTO o_number;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','integer','Integer',
 'A whole number: …−2, −1, 0, 1, 2…')
RETURNING id INTO o_integer;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','natural_number','Natural number',
 'A non-negative integer: 0, 1, 2, 3…')
RETURNING id INTO o_natural;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','real_number','Real number',
 'A number on the continuous number line, including irrationals.')
RETURNING id INTO o_real;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','unit_of_measure','Unit of measure',
 'A standard quantity used to express a measurement.')
RETURNING id INTO o_unit;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','measurement','Measurement',
 'A quantity expressed in a specific unit.')
RETURNING id INTO o_measurement;

-- ════════════════════════════════════════════════════════════
-- SECTION 6: Time concepts
-- ════════════════════════════════════════════════════════════

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','time','Time',
 'The dimension along which events are ordered.')
RETURNING id INTO o_time;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','time_interval','Time interval',
 'A bounded span of time with a start and an end.')
RETURNING id INTO o_interval_t;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','time_point','Time point',
 'An instantaneous moment in time.')
RETURNING id INTO o_point_t;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','duration','Duration',
 'The length of a time interval.')
RETURNING id INTO o_duration;

-- ════════════════════════════════════════════════════════════
-- SECTION 7: Language and representation
-- ════════════════════════════════════════════════════════════

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','language','Language',
 'A system of communication using symbols.')
RETURNING id INTO o_language;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','symbol','Symbol',
 'A sign that represents something else by convention.')
RETURNING id INTO o_symbol;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','word','Word',
 'A minimal free-standing linguistic unit.')
RETURNING id INTO o_word;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','sentence','Sentence',
 'A grammatical unit expressing a complete thought.')
RETURNING id INTO o_sentence;

-- ════════════════════════════════════════════════════════════
-- SECTION 8: Truth values (extend existing seed objects)
-- ════════════════════════════════════════════════════════════

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('concept','truth_value','Truth value',
 'One of: true, false, or unknown.')
RETURNING id INTO o_truth_value;

-- o_true_val, o_false_val, o_unknown_val already exist from schema seed.

-- ════════════════════════════════════════════════════════════
-- SECTION 9: Domain context objects
-- These are contexts (kind='context') used for source credibility
-- scoping — "this source is credible in history but not in physics".
-- ════════════════════════════════════════════════════════════

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('context','domain_history','History',
 'Historical facts, events, persons, dates.')
RETURNING id INTO o_dom_history;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('context','domain_science','Science (general)',
 'Scientific facts not specific to one discipline.')
RETURNING id INTO o_dom_science;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('context','domain_mathematics','Mathematics',
 'Mathematical definitions, theorems, structures.')
RETURNING id INTO o_dom_math;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('context','domain_geography','Geography',
 'Geographical facts: locations, borders, populations.')
RETURNING id INTO o_dom_geography;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('context','domain_biology','Biology',
 'Biological facts: taxonomy, anatomy, physiology.')
RETURNING id INTO o_dom_biology;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('context','domain_physics','Physics',
 'Physical laws, constants, and phenomena.')
RETURNING id INTO o_dom_physics;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('context','domain_law','Law',
 'Legal facts, statutes, decisions — jurisdiction-sensitive.')
RETURNING id INTO o_dom_law;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('context','domain_linguistics','Linguistics',
 'Facts about language, grammar, and meaning.')
RETURNING id INTO o_dom_language;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('context','domain_social','Social science',
 'Facts about society, culture, economics, politics.')
RETURNING id INTO o_dom_social;

INSERT INTO objects (kind,canonical_name,display_name,description) VALUES
('context','domain_technology','Technology',
 'Facts about technology, engineering, computing.')
RETURNING id INTO o_dom_tech;

-- Register domain contexts in the contexts table
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
    (o_dom_tech,      'domain', reality);

-- ════════════════════════════════════════════════════════════
-- SECTION 10: Type hierarchy — subtype_of statements
-- All are eternal axioms with near-certain belief.
-- ════════════════════════════════════════════════════════════
-- Helper macro pattern:
-- INSERT INTO statements (predicate_id, object_args, arg_types,
--     belief_alpha, belief_beta, t_kind, context_id,
--     derivation_type, derivation_depth)
-- VALUES (p_subtype_of, ARRAY[child, parent], ARRAY['object','object'],
--         ka_alpha, ka_beta, 'eternal', reality, 'axiomatic', 0);

-- Top-level splits
INSERT INTO statements (predicate_id,object_args,arg_types,belief_alpha,belief_beta,t_kind,context_id,derivation_type,derivation_depth) VALUES
(p_subtype_of,ARRAY[o_abstract, o_entity],   ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_physical, o_entity],   ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_quantity, o_abstract], ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_time,     o_abstract], ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0);

-- Physical subtypes
INSERT INTO statements (predicate_id,object_args,arg_types,belief_alpha,belief_beta,t_kind,context_id,derivation_type,derivation_depth) VALUES
(p_subtype_of,ARRAY[o_organism, o_physical],       ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_object,   o_physical],       ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_place,    o_physical],       ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_region,   o_place],          ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_location, o_place],          ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0);

-- Animate hierarchy
INSERT INTO statements (predicate_id,object_args,arg_types,belief_alpha,belief_beta,t_kind,context_id,derivation_type,derivation_depth) VALUES
(p_subtype_of,ARRAY[o_animal,   o_organism],       ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_mammal,   o_animal],         ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_person,   o_mammal],         ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_person,   o_agent],          ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_agent,    o_entity],         ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_institution, o_agent],       ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_group,    o_entity],         ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0);

-- Abstract hierarchy
INSERT INTO statements (predicate_id,object_args,arg_types,belief_alpha,belief_beta,t_kind,context_id,derivation_type,derivation_depth) VALUES
(p_subtype_of,ARRAY[o_concept,     o_abstract],    ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_property,    o_abstract],    ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_relation,    o_abstract],    ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_proposition, o_abstract],    ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_event,       o_abstract],    ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_process,     o_event],       ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_state,       o_abstract],    ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_action,      o_event],       ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0);

-- Number hierarchy
INSERT INTO statements (predicate_id,object_args,arg_types,belief_alpha,belief_beta,t_kind,context_id,derivation_type,derivation_depth) VALUES
(p_subtype_of,ARRAY[o_number,   o_quantity],       ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_real,     o_number],         ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_integer,  o_real],           ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_natural,  o_integer],        ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_measurement, o_quantity],    ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_duration, o_quantity],       ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0);

-- Time hierarchy
INSERT INTO statements (predicate_id,object_args,arg_types,belief_alpha,belief_beta,t_kind,context_id,derivation_type,derivation_depth) VALUES
(p_subtype_of,ARRAY[o_interval_t, o_time],         ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_point_t,    o_time],         ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_duration,   o_time],         ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0);

-- Language hierarchy
INSERT INTO statements (predicate_id,object_args,arg_types,belief_alpha,belief_beta,t_kind,context_id,derivation_type,derivation_depth) VALUES
(p_subtype_of,ARRAY[o_language, o_symbol],         ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_symbol,   o_abstract],       ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_word,     o_symbol],         ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_subtype_of,ARRAY[o_sentence, o_symbol],         ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0);

-- Truth value hierarchy
INSERT INTO statements (predicate_id,object_args,arg_types,belief_alpha,belief_beta,t_kind,context_id,derivation_type,derivation_depth) VALUES
(p_subtype_of,   ARRAY[o_truth_value, o_abstract],  ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_is_a,         ARRAY[o_true_val,    o_truth_value],ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_is_a,         ARRAY[o_false_val,   o_truth_value],ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0),
(p_is_a,         ARRAY[o_unknown_val, o_truth_value],ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0);

-- ════════════════════════════════════════════════════════════
-- SECTION 11: Logical / definitional eternal statements
-- ════════════════════════════════════════════════════════════

-- true and false are opposite
INSERT INTO statements (predicate_id,object_args,arg_types,belief_alpha,belief_beta,t_kind,context_id,derivation_type,derivation_depth) VALUES
(p_opposite_of,  ARRAY[o_true_val, o_false_val],    ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0);

-- true and false are different
INSERT INTO statements (predicate_id,object_args,arg_types,belief_alpha,belief_beta,t_kind,context_id,derivation_type,derivation_depth) VALUES
(p_different_from, ARRAY[o_true_val, o_false_val],  ARRAY['object','object'],ka_alpha,ka_beta,'eternal',reality,'axiomatic',0);

-- necessary implies possible (modal axiom T)
-- necessary(P) -> possible(P) for any P; encode as:
-- subtype_of(necessary_fact, possible_fact) at the meta level
-- We encode this as an implies statement using the concept objects.
-- This is a schema-level logical law.
INSERT INTO statements (predicate_id,object_args,arg_types,belief_alpha,belief_beta,t_kind,context_id,derivation_type,derivation_depth,literal_args) VALUES
(p_implies, ARRAY[]::uuid[], ARRAY['string','string'],
 ka_alpha,ka_beta,'eternal',reality,'axiomatic',0,
 '[{"pos":0,"type":"string","value":"necessary(P)"},
   {"pos":1,"type":"string","value":"possible(P)"}]'::jsonb);

-- integers are a subtype of real numbers (mathematical axiom)
-- (already covered by subtype_of hierarchy above)

-- Every integer is a real number — stated as an always-true rule
-- via implies: is_a(X, integer) -> is_a(X, real_number)
INSERT INTO statements (predicate_id,object_args,arg_types,belief_alpha,belief_beta,t_kind,context_id,derivation_type,derivation_depth,literal_args) VALUES
(p_implies, ARRAY[]::uuid[], ARRAY['string','string'],
 ka_alpha,ka_beta,'eternal',reality,'axiomatic',0,
 '[{"pos":0,"type":"string","value":"is_a(X, integer)"},
   {"pos":1,"type":"string","value":"is_a(X, real_number)"}]'::jsonb);

-- Every mammal is an animal
INSERT INTO statements (predicate_id,object_args,arg_types,belief_alpha,belief_beta,t_kind,context_id,derivation_type,derivation_depth,literal_args) VALUES
(p_implies, ARRAY[]::uuid[], ARRAY['string','string'],
 ka_alpha,ka_beta,'eternal',reality,'axiomatic',0,
 '[{"pos":0,"type":"string","value":"is_a(X, mammal)"},
   {"pos":1,"type":"string","value":"is_a(X, animal)"}]'::jsonb);

-- Every person is mortal — this is NOT eternal (it's a strong default).
-- Belief high but not kernel-level; t_kind = 'always'.
INSERT INTO statements (predicate_id,object_args,arg_types,belief_alpha,belief_beta,t_kind,context_id,derivation_type,derivation_depth,literal_args) VALUES
(p_implies, ARRAY[]::uuid[], ARRAY['string','string'],
 95.0, 5.0,         -- mean 0.95 — strong but not certain (philosophical edge cases)
 'always',reality,'axiomatic',0,
 '[{"pos":0,"type":"string","value":"is_a(X, person)"},
   {"pos":1,"type":"string","value":"mortal(X)"}]'::jsonb);

-- ════════════════════════════════════════════════════════════
-- SECTION 12: Typical_of statements (prototype knowledge)
-- These represent central tendency, not crisp membership.
-- Belief < 1.0 by design: typicality is inherently graded.
-- ════════════════════════════════════════════════════════════

INSERT INTO statements (predicate_id,object_args,arg_types,belief_alpha,belief_beta,t_kind,context_id,derivation_type,derivation_depth) VALUES
-- A person is a typical agent
(p_typical_of, ARRAY[o_person,    o_agent],    ARRAY['object','object'], 90.0, 10.0,'always',reality,'axiomatic',0),
-- An institution is a typical agent (less typical than person)
(p_typical_of, ARRAY[o_institution, o_agent],  ARRAY['object','object'], 60.0, 40.0,'always',reality,'axiomatic',0),
-- An action is a typical event
(p_typical_of, ARRAY[o_action,    o_event],    ARRAY['object','object'], 80.0, 20.0,'always',reality,'axiomatic',0),
-- A process is a typical event (longer, less bounded)
(p_typical_of, ARRAY[o_process,   o_event],    ARRAY['object','object'], 65.0, 35.0,'always',reality,'axiomatic',0),
-- A region is a typical place
(p_typical_of, ARRAY[o_region,    o_place],    ARRAY['object','object'], 75.0, 25.0,'always',reality,'axiomatic',0);

-- ════════════════════════════════════════════════════════════
-- SECTION 13: Attestations for all kernel statements
-- Source = system_kernel for all the above.
-- ════════════════════════════════════════════════════════════

INSERT INTO attestations (statement_id, source_id)
SELECT id, sys
FROM statements
WHERE derivation_type = 'axiomatic'
  AND NOT EXISTS (
      SELECT 1 FROM attestations a WHERE a.statement_id = statements.id
  );

-- ════════════════════════════════════════════════════════════
-- SECTION 14: Type membership — fuzzy class membership
-- Encode the ontological kinds as type_membership entries.
-- P=1.0 for the crisp IS-A relationships.
-- ════════════════════════════════════════════════════════════

INSERT INTO type_membership (object_id, type_id, probability, context_id) VALUES
(o_person,      o_agent,    1.0,  reality),
(o_person,      o_organism, 1.0,  reality),
(o_institution, o_agent,    1.0,  reality),
(o_institution, o_group,    0.7,  reality),  -- most but not all institutions are groups
(o_mammal,      o_animal,   1.0,  reality),
(o_integer,     o_real,     1.0,  reality),
(o_natural,     o_integer,  1.0,  reality),
(o_action,      o_event,    1.0,  reality),
(o_process,     o_event,    1.0,  reality),
(o_region,      o_place,    1.0,  reality),
(o_word,        o_symbol,   1.0,  reality),
(o_sentence,    o_symbol,   1.0,  reality);

RAISE NOTICE 'Kernel objects and statements loaded successfully.';
RAISE NOTICE 'Objects inserted: %',   (SELECT count(*) FROM objects   WHERE kind != 'source' AND kind != 'context' AND created_at > now() - interval '1 minute');
RAISE NOTICE 'Statements inserted: %',(SELECT count(*) FROM statements WHERE derivation_type = 'axiomatic');

END $$;

COMMIT;

-- ── Verification queries ──────────────────────────────────────

-- Show the type hierarchy as loaded
SELECT
    child.canonical_name  AS child,
    parent.canonical_name AS parent,
    sb.mean               AS belief
FROM statement_belief sb
JOIN statements s ON s.id = sb.id
JOIN objects child  ON child.id  = s.object_args[1]
JOIN objects parent ON parent.id = s.object_args[2]
WHERE s.predicate_id = (
    SELECT id FROM objects WHERE canonical_name='subtype_of' AND kind='predicate'
)
ORDER BY parent.canonical_name, child.canonical_name;

-- Show domain contexts
SELECT canonical_name, display_name
FROM objects
WHERE kind = 'context'
ORDER BY canonical_name;
