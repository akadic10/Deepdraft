# 00 — Open Issues (playtest findings awaiting investigation)

> Lightweight log for playtest-reported defects that don't yet belong to an active
> milestone doc. Convention: log the *observable* facts and ranked hypotheses at report
> time; when an issue is root-caused and fixed, move the full write-up into the relevant
> system/milestone doc (the doc 22 addenda pattern) and mark the entry here CLOSED with a
> pointer. Newest issues at the top.

---

## Issue 001 — Dwarf idles beside available work; unstuck by an unrelated zone completion · **OPEN** · reported 2026-08-14 (Alen, playtest, two screenshots)

**2026-10-06 follow-up:** [60 — Hauling worker selection](60_hauling_worker_selection.md)
fixes idle-queue ordering after tree felling and a returning hauler bypassing
matching after deposit. Those defects have targeted reproductions and passing
regressions. They do not establish the cause of this older mining-face stall;
Issue 001 remains open with the original diagnostic plan below.

**Observed.** Slice at Y = 47, mountain dig-in face. Multiple mining zones designated
(yellow); a ground stockpile zone (cyan) on the settlement plain with plenty of empty
tiles; a dozen-plus packed-furniture crates loose *outside* the zone; more loose drops
piled at the face. One dwarf stood idle at the face for an extended period, then **got
moving at exactly the moment the first mining zone fully completed** — despite having
had access to the remaining work the whole time through a partially-mined opening, and
despite haulable loose items being available.

**What the unstick timing establishes.** A wake event (the completion cascade —
`task_completed` → requeues, source unregistration, lease re-arms) successfully matched
him, so he **was in `_idle_dwarves`** — the idle-pool-dropout hypothesis from the first
report is effectively disproven. The defect is therefore in *why matching produced
nothing for him* during the stall, not in whether matching could see him. Two candidates
fit, plus the sleep caveat:

1. <span style="color:#d29922;">**Probe-cap starvation (now the lead).**</span> The
   scheduler's reachability probe is a capped A* (`scheduler.probe_node_cap`, 1200 —
   doc 32). A real path existed via the partial mine, but a long, convoluted route
   through a tunnel + down the face can exhaust 1200 nodes and probe as *unreachable*
   even though the player can see it's open — the task goes BLOCKED with backoff and
   keeps re-failing on every retry, indefinitely, because the *route* stays long. "Fully
   completing" the first zone is also the moment the terrain is maximally opened —
   plausibly shortening the route under the probe horizon so probes started succeeding.
   This is the **same failure class as the 2026-06-10 incident** that raised the cap
   from 200 to 1200 ("reachable zones across the settlement plain were probing as
   unreachable" — doc 32); vertical dig-face terrain may have found the new ceiling.
   **30-second experiment:** raise `scheduler.probe_node_cap` in
   `data/tasks/task_config.json` (e.g. 1200 → 4000, data-only, no code) and reproduce.
   If the stall disappears, this is confirmed — then decide between a permanently
   higher cap (it's a latency/cost dial, never frame-time — doc 32) or a smarter fix
   (e.g. hierarchical/cached reachability, or re-probe from the dwarf's current cell
   after partial mining progress).
2. **Wake-gap: no matching ran during the stall.** The scheduler is event-driven; the
   0.5 s heartbeat "survives as the safety net that catches `retry_at` expiries"
   (doc 31). If the heartbeat only re-arms expired BLOCKED tasks *without running the
   idle-dwarf matching loop* (or the re-arm doesn't wake matching), an idle dwarf plus
   re-armed pending tasks can coexist quietly until the next real event — exactly a
   stall ended by someone else's completion. Distinguishable from hypothesis 1 in the
   logs: if probes were *failing*, `blocked_count`s climb during the stall; if matching
   *never ran*, they don't move at all. `TaskManager.get_scheduler_stats()` (debug
   overlay row) shows both.
3. <span style="color:#d29922;">**Sleep overlap (caveat, not a bug).**</span> If a 💤
   was showing, part of the stall is sleep-lite working as designed and only the
   remainder needs explaining. Note for next repro: confirm 💤 state at stall start.

**Also unexplained by 1 alone:** the loose crates sit on the *plain*, likely within easy
probe range of the plain-side stockpile zone stand cells — but HAUL leases target the
*item pickup* first from the dwarf's position at the face; the probe from the dig face
down to the plain may share the same long-route failure. If a raised cap fixes mining
pulls but hauling stays dead, look separately at the HAUL lease wake plumbing
(`StockpileManager`, doc 18) and whether those specific crates are in the loose index
(pick one up / DEV-spawn a fresh drop beside an idle dwarf and compare reactions).

**Repro context.** 2026-08-14 session save; settlement plain + mountain face;
DEV-spawned furniture mix on the plain; multiple mining zones at the face, one partially
mined.

**Next step.** Reproduce with the scheduler stats row visible; watch `blocked_count`
movement to split hypotheses 1 vs 2; A/B the probe cap via `task_config.json`. Fix lands
as an addendum in doc 16 §2 / doc 32 (probe) or doc 31 (heartbeat), and this entry
closes with a pointer.

---
