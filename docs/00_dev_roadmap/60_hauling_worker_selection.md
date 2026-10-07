# 60 — Hauling worker selection

Implemented 2026-10-06 after the player observed Thoa finish a tree and remain
idle while more distant dwarves collected its lumber.

## Cause

`TaskManager` iterated `_idle_dwarves` in insertion order. Finishing a tree marks
the cutter idle in the same update that creates the timber, but appends them to
the end of that list. The original HAUL probe checked reachability to storage;
it did not compare workers' distances to the pickup. Older idle entries therefore
reserved the available lumber before the newly idle cutter was considered.
There is no post-felling cooldown involved.

A later report showed Duras idle just after felling despite this first fix.
Review found a second bypass: after depositing, an existing hauler called
`_haul_pull_next()` directly on the same lease. That worker could reserve fresh
timber before the scheduler compared the newly idle cutter. A regression with
a real tree completion and an existing delivery reproduced this behavior.

## Result

New HAUL assignments favor available dwarves near actual accepted goods.
Ground zones and containers use the same matching contract. Relocations compare
distance to the rejected source stack, rather than the receiving storage.
Filters, carry capacity, source claims, and remaining storage space participate
in finding the pickup. Sleeping and busy workers are not eligible.

Higher-priority work is considered first. Existing assigned loads are never
stolen when a closer dwarf becomes idle. Equal-distance ties preserve idle queue
order. Distance is a floor-cell Manhattan estimate followed by bounded reachability
checks, not an exhaustive shortest-path comparison or profession optimization.

Each successful delivery now completes its HAUL lease and returns the worker to
the idle pool. The next load goes through the same proximity and priority matching.
This applies to both ground storage and containers. A lone hauler can still make
successive trips; a closer cutter or higher-priority job can win between deliveries.

## Implementation

- `TaskManager` splits wakes with pending hauling into higher-priority, hauling,
  and remaining-work passes. Non-hauling matching retains the existing buckets,
  priorities, retry behavior and cursors.
- HAUL keeps one resumable worker comparison. All eligible idle workers receive
  read-only pickup quotes before one is chosen. Both the pickup and destination
  must pass the existing capped navigation probe; each consumes the shared probe
  allowance. The stages resume correctly even with one probe allowed per wake.
- `StorageComponent.advance_haul_quote` follows normal hauling's loose-first,
  relocation-second choice. `ItemDropManager` and `StockpileManager` own incremental
  candidate scans and keep the scheduler from scanning all goods in one wake.
- Failed pickup cells are excluded per worker, then candidates are compared
  again. This lets a farther reachable worker handle a pile, or lets the same
  worker choose other supplies when the closest pile is inaccessible. The chosen
  executor receives those initial exclusions so its reservation matches the quote.
- Ranking creates no reservations. Normal `reserve_haul` still owns claims,
  bundling, contact-time pickup, interruption and delivery. Each assignment
  changes the available goods, so the next lease is compared afresh.
- `DwarfAgent` clears completed cargo and hauling state, then completes the lease
  after a successful deposit. `StockpileManager` posts replacement intake leases
  through its existing coalesced wake, still capped by `max_haulers`. No per-item
  tasks are created. Failed pulls retain bounded retries; trips already underway
  retain their claims.
- Inventory, filter, claim and capacity changes increment the storage scheduling
  revision. Newly idle dwarves and navigation edits invalidate old comparisons.
  All matching state is transient and cleared on scene reset.

## Verification

`HaulingSelectionTest` reproduces a real mature-oak completion with three dwarves:
the distant idle dwarf is first in the queue and closest to storage, the nearer
helper is second, and the cutter joins last. The cutter and nearer helper take
two logs each; the distant dwarf stays idle. Four goods and four storage claims
remain uniquely owned.

The returning-hauler regression saturates the intake limit with an existing load,
finishes a real tree beside another dwarf, then completes the delivery before the
next scheduler wake. Before the fix, the distant hauler claimed the new timber;
after the fix, the cutter wins. It checks bounded leases, claim cleanup and goods
conservation. Another case introduces higher-priority work during delivery.
`HaulingCapacityTest` verifies a solo worker still completes successive mixed-goods
and crate trips with no duplicate or lost goods.

Additional cases cover sleeping workers, filtered-out nearby goods, higher-priority
work, existing reservations, a blocked closest worker, a blocked closest pile with
reachable alternatives, one-probe wakes, a newly idle worker joining an unfinished
comparison, deadline yields without claims, and container relocation by source
distance. The tests use actual sources and worker executors.

Regression checks include tree felling, mining animation, hauling animation and
capacity, produce crates, storage filters, colony inventory, furniture placement,
and full save/load with scene reset. No new global class or autoload was added.

Playtest in a fresh play session: fell one tree with two other idle dwarves farther
away, keep compatible storage available, and watch which workers reserve its logs.
The cutter should participate when there is no higher-priority work or need
interrupt, unless another eligible dwarf is closer. Already assigned trips continue.
