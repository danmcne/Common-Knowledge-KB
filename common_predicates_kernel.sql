-- =============================================================
-- Common Knowledge KB — Basis Predicate Seed Data  (v2)
-- =============================================================
-- 55 predicates across 12 groups.
-- Changes from v1:
--   • predicates INSERT includes domains[] column (new in schema v2).
--   • Four new predicates added: implies, correlated_with,
--     typical_of, occurs_in.
--   • held_office moved to "common knowledge" tier comment —
--     kept in basis but flagged as borderline.
--   • All is_basis = true entries are 'confirmed'.
-- =============================================================

BEGIN;

DO $$
DECLARE
    sys uuid := '00000000-0000-0000-0000-000000000005'; -- system_kernel
    oid uuid;
BEGIN

-- ════════════════════════════════════════════════════════════
-- GROUP 1: TAXONOMIC / TYPE  (5)
-- ════════════════════════════════════════════════════════════

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','is_a','is a',
'x is an instance of type y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,
ARRAY['concept','concept']::object_kind[],ARRAY['instance','type'],
'primitive','x is an instance of y','rdf:type / wikidata:P31',
true,ARRAY['taxonomic'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','subtype_of','subtype of',
'Every instance of x is also an instance of y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,
ARRAY['concept','concept']::object_kind[],ARRAY['subtype','supertype'],
'subtype_of(X,Y) :- forall Z, is_a(Z,X) -> is_a(Z,Y)',
'x is a subtype of y','rdfs:subClassOf',
true,ARRAY['taxonomic'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','has_property','has property',
'x has property or attribute y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['entity','concept'],
'primitive','x has property y','conceptnet:HasProperty',
true,ARRAY['taxonomic'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','same_as','same as',
'x and y refer to the same real-world entity.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['entity','entity'],
'primitive','x and y are the same entity','owl:sameAs',
true,ARRAY['taxonomic'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','different_from','different from',
'x and y are distinct entities.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['entity','entity'],
'different_from(X,Y) :- not same_as(X,Y)',
'x and y are not the same entity','owl:differentFrom',
true,ARRAY['taxonomic'],
'confirmed',sys,now());

-- ════════════════════════════════════════════════════════════
-- GROUP 2: MEREOLOGY  (4)
-- ════════════════════════════════════════════════════════════

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','part_of','part of',
'x is a component or part of y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['part','whole'],
'primitive','x is a part of y','conceptnet:PartOf / wikidata:P361',
true,ARRAY['mereology','spatial'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','has_part','has part',
'x contains y as a component.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['whole','part'],
'has_part(X,Y) :- part_of(Y,X)',
'x has y as a part','conceptnet:HasA / wikidata:P527',
true,ARRAY['mereology','spatial'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','member_of','member of',
'x is a member of group or set y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['member','group'],
'primitive','x is a member of y','wikidata:P463',
true,ARRAY['mereology','social'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','contains','contains',
'x physically or abstractly contains y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['container','contained'],
'contains(X,Y) :- part_of(Y,X) [spatial sense]',
'x contains y',NULL,
true,ARRAY['mereology','spatial'],
'confirmed',sys,now());

-- ════════════════════════════════════════════════════════════
-- GROUP 3: SPATIAL  (3)
-- ════════════════════════════════════════════════════════════

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','located_in','located in',
'x is situated within or at location y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['entity','concept'],
'primitive','x is located within y',
'conceptnet:AtLocation / wikidata:P131',
true,ARRAY['spatial'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','adjacent_to','adjacent to',
'x is spatially next to or bordering y (symmetric).') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['entity','entity'],
'primitive; symmetric','x is next to or borders y',NULL,
true,ARRAY['spatial'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','origin_of','origin of',
'x is the place or source from which y originates.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['concept','entity'],
'primitive','x is the origin of y','wikidata:P19 generalised',
true,ARRAY['spatial','causal'],
'confirmed',sys,now());

-- ════════════════════════════════════════════════════════════
-- GROUP 4: TEMPORAL  (5)
-- ════════════════════════════════════════════════════════════

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','before','before',
'Event or time x occurs strictly before y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,
ARRAY['event','event']::object_kind[],ARRAY['earlier','later'],
'primitive; transitive; asymmetric','x happens strictly before y',
'allen:before',
true,ARRAY['temporal'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','after','after',
'Event or time x occurs strictly after y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,
ARRAY['event','event']::object_kind[],ARRAY['later','earlier'],
'after(X,Y) :- before(Y,X)','x happens strictly after y',
'allen:after',
true,ARRAY['temporal'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','during','during',
'Event x occurs entirely within the time span of event y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,
ARRAY['event','event']::object_kind[],
ARRAY['contained_event','containing_event'],
'primitive (Allen interval relation)','x occurs within the span of y',
'allen:during',
true,ARRAY['temporal'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','simultaneous_with','simultaneous with',
'Events x and y occur at the same time (symmetric).') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,
ARRAY['event','event']::object_kind[],ARRAY['event_a','event_b'],
'primitive; symmetric','x and y happen at the same time',
'allen:equals',
true,ARRAY['temporal'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','has_duration','has duration',
'Event or state x lasts for duration y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['event_or_state','quantity'],
'primitive','x lasts for duration y','wikidata:P2047',
true,ARRAY['temporal','quantitative'],
'confirmed',sys,now());

-- ════════════════════════════════════════════════════════════
-- GROUP 5: CAUSAL / FUNCTIONAL  (6)
-- ════════════════════════════════════════════════════════════

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','causes','causes',
'x brings about or produces y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['cause','effect'],
'primitive','x causes y','conceptnet:Causes',
true,ARRAY['causal'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','enables','enables',
'x makes y possible without necessarily causing it.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['enabler','enabled'],
'primitive','x enables y','conceptnet:Enables',
true,ARRAY['causal'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','prevents','prevents',
'x inhibits or blocks y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['preventer','prevented'],
'primitive','x prevents y','conceptnet:Obstructs',
true,ARRAY['causal'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','used_for','used for',
'x is typically used to accomplish y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['tool','purpose'],
'primitive','x is used for y','conceptnet:UsedFor',
true,ARRAY['causal','functional'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','capable_of','capable of',
'x has the capacity to do y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['agent','action'],
'primitive','x is capable of y','conceptnet:CapableOf',
true,ARRAY['causal','social'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','motivated_by','motivated by',
'Action x is done because of reason or goal y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['action','concept'],
'primitive','x is motivated by y','conceptnet:MotivatedByGoal',
true,ARRAY['causal','social'],
'confirmed',sys,now());

-- ════════════════════════════════════════════════════════════
-- GROUP 6: AGENTIVE / SOCIAL  (6)
-- ════════════════════════════════════════════════════════════

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','agent_of','agent of',
'x is the intentional agent who performs action or event y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,
ARRAY['person','event']::object_kind[],ARRAY['agent','action'],
'primitive','x performs y','wikidata:P664',
true,ARRAY['social'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','created_by','created by',
'x was made, authored, or produced by agent y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['creation','creator'],
'primitive','x was created by y',
'wikidata:P170 / conceptnet:CreatedBy',
true,ARRAY['social','causal'],
'confirmed',sys,now());

-- held_office: arity=4, three object args + one integer literal arg.
-- Borderline for basis set (very common but specific to political domain).
-- Kept here; arg_types = ["object","object","object","integer"].
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','held_office','held office',
'Person x held role y within organisation z (at ordinal n).') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,4,
ARRAY['person','concept','concept','concept']::object_kind[],
ARRAY['person','role','organisation','ordinal'],
'primitive','x held office y in z at position n',
'wikidata:P39',
true,ARRAY['social'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','affiliated_with','affiliated with',
'x is associated with, employed by, or a member of y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['entity','institution'],
'primitive','x is affiliated with y','wikidata:P108 / P463',
true,ARRAY['social'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','related_to','related to',
'x and y are related (generic, symmetric, weakest basis predicate).') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['entity','entity'],
'primitive; symmetric','x and y are related','conceptnet:RelatedTo',
true,ARRAY['taxonomic'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','opposite_of','opposite of',
'x is the conceptual opposite or antonym of y (symmetric).') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['concept','concept'],
'primitive; symmetric','x is the opposite of y','conceptnet:Antonym',
true,ARRAY['taxonomic','linguistic'],
'confirmed',sys,now());

-- ════════════════════════════════════════════════════════════
-- GROUP 7: QUANTITATIVE  (3)
-- ════════════════════════════════════════════════════════════

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','has_quantity','has quantity',
'x has measurable quantity y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['entity','quantity'],
'primitive','x has quantity y','wikidata:P1082 etc.',
true,ARRAY['quantitative'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','greater_than','greater than',
'Quantity x is greater than quantity y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,
ARRAY['quantity','quantity']::object_kind[],ARRAY['larger','smaller'],
'primitive; asymmetric; transitive','x > y',NULL,
true,ARRAY['quantitative'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','approximately_equal','approximately equal',
'x and y are approximately equal in magnitude (symmetric, fuzzy).') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['entity','entity'],
'primitive; symmetric; fuzzy','x ≈ y',NULL,
true,ARRAY['quantitative'],
'confirmed',sys,now());

-- ════════════════════════════════════════════════════════════
-- GROUP 8: EPISTEMIC / MODAL  (5)
-- ════════════════════════════════════════════════════════════

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','knows','knows',
'Agent x has knowledge of fact, concept, or entity y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,
ARRAY['person','concept']::object_kind[],ARRAY['knower','known'],
'primitive','x knows y',NULL,
true,ARRAY['epistemic'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','believes','believes',
'Agent x believes y to be true (belief may be false).') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,
ARRAY['person','concept']::object_kind[],ARRAY['believer','believed'],
'primitive; distinct from knows','x believes y',NULL,
true,ARRAY['epistemic'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','desires','desires',
'Agent x wants or desires y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,
ARRAY['person','concept']::object_kind[],ARRAY['desirer','desired'],
'primitive','x desires y','conceptnet:Desires',
true,ARRAY['epistemic','social'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','possible','possible',
'Event or state x is possible (not necessarily actual).') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,1,NULL,ARRAY['proposition'],
'primitive; modal','x is possible',NULL,
true,ARRAY['epistemic','modal'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','necessary','necessary',
'x is necessarily true — could not be otherwise.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,1,NULL,ARRAY['proposition'],
'primitive; modal; necessary(X) -> possible(X)','x is necessarily true',NULL,
true,ARRAY['epistemic','modal'],
'confirmed',sys,now());

-- ════════════════════════════════════════════════════════════
-- GROUP 9: LINGUISTIC / REPRESENTATIONAL  (3)
-- ════════════════════════════════════════════════════════════

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','named','named',
'Entity x has name y in natural language.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['entity','concept'],
'primitive','x is named y','rdfs:label / wikidata:P2561',
true,ARRAY['linguistic'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','symbol_for','symbol for',
'x is a symbol or representation of y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['concept','concept'],
'primitive','x is a symbol of y','conceptnet:SymbolOf',
true,ARRAY['linguistic'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','language_of','language of',
'Language x is spoken, written, or used by y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['concept','entity'],
'primitive','x is the language of y','wikidata:P407',
true,ARRAY['linguistic','social'],
'confirmed',sys,now());

-- ════════════════════════════════════════════════════════════
-- GROUP 10: EVENT CALCULUS CORE  (4)
-- Meta-predicates over events and fluents.
-- Required for temporal reasoning over state changes.
-- ════════════════════════════════════════════════════════════

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','initiates','initiates',
'Event x causes state/fluent y to begin holding.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,
ARRAY['event','concept']::object_kind[],ARRAY['event','fluent'],
'primitive; event calculus','event x initiates fluent y','ec:Initiates',
true,ARRAY['temporal','causal'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','terminates','terminates',
'Event x causes state/fluent y to stop holding.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,
ARRAY['event','concept']::object_kind[],ARRAY['event','fluent'],
'primitive; event calculus','event x terminates fluent y','ec:Terminates',
true,ARRAY['temporal','causal'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','happens_at','happens at',
'Event x occurs at time y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,
ARRAY['event','concept']::object_kind[],ARRAY['event','time'],
'primitive; event calculus','event x happens at time y','ec:HappensAt',
true,ARRAY['temporal'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','holds_at','holds at',
'State or fluent x is true at time y. Primary temporal query predicate.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,
ARRAY['concept','concept']::object_kind[],ARRAY['fluent','time'],
'derived from initiates/terminates/happens_at chain',
'fluent x holds at time y','ec:HoldsAt',
true,ARRAY['temporal'],
'confirmed',sys,now());

-- ════════════════════════════════════════════════════════════
-- GROUP 11: PHYSICAL / LIFECYCLE  (5)
-- ════════════════════════════════════════════════════════════

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','made_of','made of',
'x is composed of or constructed from material y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['object','material'],
'primitive','x is made of y','conceptnet:MadeOf',
true,ARRAY['physical'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','has_state','has state',
'Entity x is in physical or abstract state y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['entity','concept'],
'primitive','x is in state y',NULL,
true,ARRAY['physical'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','precondition_of','precondition of',
'x must hold before y can occur.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['concept','event'],
'precondition_of(X,Y) :- necessary(X), before(X,Y)',
'x is a precondition of y','conceptnet:HasPrerequisite',
true,ARRAY['causal','temporal'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','affects','affects',
'x has some effect on y (weaker than causes).') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['entity','entity'],
'weaker than causes; partial effects','x affects y',
'conceptnet:Causes (weak)',
true,ARRAY['causal'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','born_in','born in',
'Person or organism x was born in place or time y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,
ARRAY['person','concept']::object_kind[],ARRAY['organism','place_or_time'],
'primitive; shorthand for holds_at(located_in(x,y), birth_time(x))',
'x was born in y','wikidata:P19 / P569',
true,ARRAY['social','temporal'],
'confirmed',sys,now());

INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','died_in','died in',
'Person or organism x died in place or at time y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,
ARRAY['person','concept']::object_kind[],ARRAY['organism','place_or_time'],
'primitive; shorthand for terminates(death_event(x), alive(x))',
'x died in y','wikidata:P20 / P570',
true,ARRAY['social','temporal'],
'confirmed',sys,now());

-- ════════════════════════════════════════════════════════════
-- GROUP 12: NEW — INFERENTIAL / CORRELATIONAL  (4)
-- These four were absent from v1; complete the basis set.
-- ════════════════════════════════════════════════════════════

-- implies
-- P(x,y): proposition x logically or probabilistically entails y.
-- Probabilistic: P(y|x) is high. Crisp: P(y|x)=1.
-- Distinct from causes (no time order required).
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','implies','implies',
'Proposition or state x logically or probabilistically entails y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['proposition','proposition'],
'primitive; crisp at P=1, probabilistic at P<1',
'x implies y (logical or probabilistic)',NULL,
true,ARRAY['epistemic','causal','modal'],
'confirmed',sys,now());

-- correlated_with
-- P(x,y): x and y tend to co-occur or vary together (symmetric).
-- Weaker than causes or implies; covers statistical association.
-- Critical for Bayesian KB where causal direction is unknown.
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','correlated_with','correlated with',
'x and y tend to co-occur or vary together (symmetric, no causal claim).') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['entity','entity'],
'primitive; symmetric; weaker than causes; covers statistical association',
'x and y are correlated',NULL,
true,ARRAY['causal','quantitative'],
'confirmed',sys,now());

-- typical_of
-- P(x,y): x is a typical or characteristic instance of type y.
-- Different from is_a (which is definite membership).
-- Handles prototype effects: "a robin is more typical_of bird than a penguin".
-- Essential for the fuzzy / probabilistic type system.
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','typical_of','typical of',
'x is a typical or prototypical instance of category y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,NULL,ARRAY['entity','concept'],
'primitive; graded; distinct from is_a (crisp membership)',
'x is a typical instance of y','conceptnet:IsA (prototype sense)',
true,ARRAY['taxonomic'],
'confirmed',sys,now());

-- occurs_in
-- P(event,context_or_location): event x takes place within
-- situation, context, or location y.
-- Complements located_in (for objects) and during (for time).
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (gen_random_uuid(),'predicate','occurs_in','occurs in',
'Event x takes place within situation, context, or location y.') RETURNING id INTO oid;
INSERT INTO predicates VALUES (oid,2,
ARRAY['event','concept']::object_kind[],ARRAY['event','situation'],
'primitive; complements located_in and during',
'event x occurs in situation or location y',NULL,
true,ARRAY['temporal','spatial'],
'confirmed',sys,now());

END $$;

COMMIT;

-- ── Verification query ────────────────────────────────────────
SELECT
    o.canonical_name,
    p.arity,
    p.arg_labels,
    p.domains,
    p.source_predicate
FROM predicates p
JOIN objects o ON o.id = p.id
WHERE p.is_basis = true
ORDER BY p.domains[1], p.arity, o.canonical_name;
