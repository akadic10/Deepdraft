# Gradual season transition evidence

See [194](../../194_gradual_season_transition.md) for behavior, measurements and
limitations. `CollectSeasonEvidence.py` copies logs and source snapshots here;
runtime user profiles and player save contents are excluded.

- `season_before_clean_30`, `season_before_5` and `season_before_20` are clean
  native baselines using the four frozen prior production files.
- `season_after_5`, `season_after_20` and `season_after_30` are the first trial:
  trees stay alive, but admitting terrain tiles individually repeats too much
  snapshot/statistics work. They remain diagnostic evidence, not final results.
- `season_final_5`, `season_final_20` and `season_final_30` use normal terrain
  worker batches distributed across the night, plus the gradual plant updates.
- `season_before_30` is an earlier diagnostic with screenshot readbacks during
  sampling. Its frame statistics are excluded from comparisons.

Each native run retains its command/input-hash metadata, full flat frame stream,
subsystem statistics and spike detail. The calendar is deliberately accelerated
to five real seconds per game hour, with actor speed x1 and arrival/autosave
scheduling disabled. It is a focused transition test, not a long-session result.
All runs use isolated copies of the same settlement and are launched sequentially.

`sources/before` stores the previous production files. `sources/first_trial`
stores the implementation before terrain batching. `sources/final` and the
manifest identify the delivered implementation and fixtures. The new queue
script could exist in baseline workspaces but is not referenced by baseline code.

`fixture_v1`, `fixture_v2` and `regressions` include failed intermediate attempts.
`fixture_v3` is the earlier 239-check pass; `regressions_final` contains the final
243-check fixture and all 14 clean regression results. The initial baseline-five
wrapper mistakenly treated an unset PowerShell exit variable as failure after a
clean game run; source restoration still completed. The runner now returns an
explicit success code. The retained game's `run.json`, log and data are valid.

`package` and `package_audit.json` retain the final native packaged transition,
save/reload, screenshot and release/archive checks. Original
player storage is never modified by these tools.
