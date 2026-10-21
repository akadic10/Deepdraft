# Dining rest and game partners

The later [249 — Solo games and partner search](249_solo_games_and_partner_search.md)
reproduces another wait caused by the local distance limit, broadens companion
search, and adds a smaller solo reward. The cooldown/memory separation below
remains in effect.

2026-10-17. The player reported a standing frame between finishing a seated meal
and sitting again, plus a dwarf waiting at a game with two available companions.

Meal completion reused cancellation, which released the chair and reset every
body part. A successful seated meal now transfers its occupied chair and access
floor to ordinary idle rest. Body and feet retain their seated offsets, empty
hands lower over the existing half-second seat transition, and the table claim
is released. The dwarf remains available for work, later uses the normal gradual
stand-up, and releases the chair on movement, needs, removal or load. Interrupted
meals retain their existing food conservation and cleanup rules.

Game eligibility previously required both the six-hour cooldown and the
twelve-hour happiness memory to expire. This left recent players unavailable
well beyond the advertised cooldown. Only the cooldown now blocks another game;
the existing happiness memory can be refreshed but never stacked. Food, sleep,
cargo, explicit movement, route access and work eligibility retain priority.
No save schema, new global class, art or balancing values are required.

Both reports were reproduced in native source fixtures before the fix. The
expanded dining checks verify body/foot continuity on completion and the next
frame, chair ownership, work availability, gradual standing, table-claim release,
log stools/benches and explicit movement afterward. The recreation fixture seats
one waiting player, then makes two recent players available after cooldown;
exactly one joins and completion refreshes a single happiness bonus.

Five native windowed source fixtures pass: DwarfDiningTest,
RudimentaryRecreationTest, DwarfIdleBehaviorTest, DwarfFoodTest and JobLifecycleTest.
They also cover existing needs, food conservation, claims, interruption, pause,
work leases and current save/restore behavior. Each requires its success marker,
exit code zero and no script/runtime errors. Fixtures use isolated user profiles.

Evidence: [results and compressed logs](concepts/dining_recreation_20261017/summary.json).
Restart Play. No Windows playtest was created or updated.
