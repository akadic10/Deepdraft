# 219 — Retain X-ray geometry across slice toggles

Slice Off moves the renderer's cutoff to 127; Slice On restores the previous
height. The X-ray listener previously called `_invalidate_all()` for either
change, hiding every inspection chunk and rebuilding them across multiple
frames. The prior performance correction in 218 removed redundant physical
terrain rebuilds but did not remove this inspection rebuild path.

`XrayController` now retains up to three recent height variants per interior
chunk, including its active variant. Fully hidden and fully exposed chunks
share variants across distant slice heights. Changing the cutoff selects a
valid cached variant immediately and queues only missing variants. Returning
to a recently visited height restores the exact meshes, without waiting for
another frame. Unaffected chunks remain present on the first uncached toggle.

Full and Flat geometry share each variant. Least-recently-used inactive
variants are freed to bound memory. A one-level distinction above each chunk
preserves water clipping at its top boundary. Water changes mark cached
variants stale and refresh only their water when activated, including changes
made while X-ray is Off. Interior edits retire affected chunks at every cached
height; season changes retire all variants. Re-entering X-ray consumes pending
world changes instead of rebuilding unchanged geometry.

Same-height notifications do no work. Pinned reference geometry is translated
to the new slice plane immediately while its outline refreshes. Picking uses
the selected variant's actual face sets; undiscovered terrain remains hidden.
The cache is transient and does not change the saved world or slice contract.

## Validation

`XrayViewTest` now covers repeated Slice Off/On with zero queued builds on cache
hits, mesh identity and visibility before the next frame, immediate retention
of unaffected chunks on the first toggle, same-height notifications, X-ray
Off/On reuse, bounded eviction over several heights, and dormant/off-state
water and terrain changes. Existing Full/Flat geometry, discovery, lighting,
selection, working tools, live edits and aspect checks remain.

Native time/slice HUD, terrain explorer and construction input tests cover the
surrounding controls and targeting. A separate isolated copy of the player's
quicksave exercises the real colony at 7680×2160; its toggle records, capture,
original-save hashes and native logs are retained with the evidence.

All four native regressions pass. In the copied save at slice 53, the first
toggle to 127 retains 42 of 56 chunks and queues the other 14. Four subsequent
Off/On cycles and an X-ray Off/On cycle queue zero inspection builds, retain
the exact mesh identities, and expose all 56 selected chunks before the next
frame. The cache holds 70 variants in that scenario. All four original save
hashes remain unchanged.

This avoids rebuilding the entire X-ray view for a display toggle. The first
visit to an uncached height can still build affected chunks, and real terrain,
water or seasonal changes still update their geometry. The normal world's
slice meshes also have their own actual-cutoff update work; this cache does
not claim to eliminate that cost.

Evidence: [checks and save hashes](concepts/xray_slice_cache_20261017/summary.json).
Restart Play and reload. Original saves are untouched; no Windows export.
