# 311 — Codes and words

**Status (2026-11-16):** built the same day on the owner's "proceed with your recommendations",
and not yet seen in play. Nothing reads differently in the game; saves from before no longer
load. The rules now live in doc 13 ("Codes and words") and CLAUDE.md ("Text: codes and
words"). This doc stays until the owner has looked: "accepted" retires it, and "What is left"
moves to `00_todo.md` then.

## What the owner asked

Reviewing `scripts/systems/BlueprintLibrary.gd`:

> English error messages in code will make translations harder later. Should error messages be
> ID based and the ID's and text could be in a JSON file. Don't just agree with me, review and
> recommend a solution.

## What the review found, and what was recommended

There was no translation setup at all, and about 4,000 texts: some 1,700 in the data files and
2,500 in 122 scripts. Where a sentence is stored is the cheap part of translating. Three other
things were the costly part, and an id table would have fixed none of them:

- **Logic read the wording** in about 50 places: a deer grazed while `activity == "Grazing"`,
  a dwarf was badly hurt while `word() == "Badly hurt"`, and a status line turned amber when its
  sentence began with "Waiting". Rewording a sentence could silently change behaviour.
- **English grammar was put together in code:** `"%d block%s"`, `"dwarf" if n == 1 else
  "dwarves"`.
- **Saves stored sentences:** an animal's activity, the event log's entries, the journal's
  lines.

The recommendation, which the owner took whole:

1. No id table for every text now.
2. Codes wherever logic, a save or a test tells two messages apart, with BlueprintLibrary as
   the pattern, two lint rules, and saves that keep codes.
3. The words for those codes in each feature's own JSON, not one global file.
4. `push_error`, `push_warning` and `print` text stays English and inline.

A translation itself is not planned. When it is, it uses Godot's own system, joined at
`Wording.fill`.

## What was built

**The helper.** `scripts/components/Wording.gd` (no autoload, no class name; used through
`preload`): `fill(words, fields)` puts named fields into a whole sentence and picks a form by
`fields.count` when the sentence gives forms (`{"one": …, "other": …}`); `of(table, code,
fields)` says a code from a table and reports a code that has no words.

**The pattern: blueprint files.** `BlueprintLibrary.parse()` returns a refusal as a code with
its fields, `{"error": "unknown_material", "material": "marble"}`. There are thirteen codes:
eleven from `parse()` and two from reading the file (`file_too_big`, `not_a_file`). Their
sentences are `"refusals"` in `data/construction/blueprints.json`; `refused()` hands out the
refusals and `refusal_words()` says one. `BlueprintTest` checks every code and that each has
its words.

**Animals.** An animal's `activity` is one of 24 codes (`grazing`, `fleeing`,
`seeking_safe_water` …) and its arrival's `status` one of four (`travelling_inland`,
`flying_inland`, `settled`, `journey_interrupted`). The words are
`data/animals/animal_words.json`, said by `WildlifeManager.words_of()` for the inspector. The
three work sounds that wait for an activity (`data/audio/work_feedback.json`) name the code.

**Dwarves.**
- Health has a `level()`: `healthy`, `hurt` or `badly_hurt`. Its words are `health.words` in
  `data/tasks/task_config.json`, and the panels colour by the level.
- `TaskManager.worker_availability()` gives a code (`trapped`, `self_care` …). Nothing showed
  its words.
- A dwarf with nowhere to go has an empty destination, where "No destination" was set and
  then hidden by comparing against it.
- A room's appeal step has an `id` in `data/rooms/appeal.json` (`horrid`, `plain`,
  `pleasant`, `beautiful`). A dwarf's mood remembers the id, where it remembered the word in
  lower case. The saved values are the same four strings.

**Status lines.** A line's tone (plain, amber, red) is settled in the branch that settles its
words and handed on with them, for building plans, boulders and scree, plants, shrubs,
flowers, trees, furniture and crafting orders (`CraftingManager.status_line()`). None of them
reads a tone back from a sentence any more.

**Smaller places.**
- A task's wait reason is asked "is it still the first one?" by the constant
  `Task.NOT_ASSESSED`.
- A room's temperature has `RoomManager.comfort()` (`cold`, `chilly`, `comfortable`, `hot`),
  with its words in `data/world_gen/temperature.json`.
- A room type has a `noun` ("a bedroom") in `data/rooms/room_kinds.json`, where the window cut
  it out of "What makes it a bedroom".
- A fishing zone says `fished_out` as a fact.
- The career map colours "Needs tool" by the fact.
- The storage window's group state is `all`, `some` or `none`, worded by the grid.
- The load notice goes by the slot (`auto`, `quick`), not by its label.

**The event log.** An entry holds a `line` code and `fields`, never a sentence:
`cavern_found`, `flood`, `season_came`, `food_short`, `promoted`, `arrived`, `founded`,
`founded_with`, `food_rotted`, `food_going_bad`, `crop_late`. Their sentences, detail lines
and past wording are `"lines"` in `data/events/event_log.json`.
- A field is a number, a proper name or an id (an item, a crop, a profession, an arrival, a
  place). `EventLog` words the ids when an entry is read, so Events and the toasts get the
  same sentences as before.
- A resolved warning reads in its past words because it is resolved. No sentence is swapped
  and stored.
- The six callers pass a code and fields: a promotion, rotting and spoiling food, an arrival,
  the founding, a crop not ripe in time.

**The journal.** A line holds its `topic`, `tone`, the dwarves, the speaker's name and
`fields`. The thought's text and the dwarf's own line are built when the journal is read; the
choice of line was already fixed by the speaker, the day and the topic.

**Saves.** The validator knows the new shapes. It refuses an animal activity that is not a
code, an event entry that names an unknown line, item, crop or profession, and a journal topic
with no lines. Saves from before this change are refused. The schema number was left at 2, as
the earlier save-ending changes left it.

**The lint.** Two rules in `tools/lint_project.py`:
- `wording-compare`: a sentence or a capitalised word compared with `==` or `!=`, looked for
  in a list, or tested with `begins_with`, `contains` and the like. Node names are not
  checked. It finds nothing today.
- `glued-plural`: a word or an ending chosen in code by whether a count is one. It finds 40
  lines in 24 files, recorded as known in `tools/lint_baseline.json`.

## Decisions of mine

These were mine, not the owner's. Each can be changed.

1. **The 40 plural lines are recorded, not fixed.** The owner agreed to record the existing
   ones; the count I gave was 33. The rule also catches a whole word chosen by a count ("day"
   or "days"), which my earlier count did not. One of the 40 is not a plural
   (`CatchLog.gd:52` leaves the year out in year 1).
2. **Status captions stay in code.** Only the tone moved. "Waiting for builder" and its like
   are plain captions that nothing compares any more.
3. **A task's wait reasons stay sentences.** They are passed through and shown in the job
   inspector and a plan's details. Only the one comparison became a constant.
4. **A season and a map edge are their ids in the event sentences** ("autumn", "north"). The
   game has no table of season names yet.
5. **The thoughts' words stay in code,** gathered in one table (`DwarfMood.THOUGHT_WORDS`).
   The journal stores the thought's id and fields.
6. **Arrival refusals** ("population cap", "scarce prey") stay as they are in the world
   events' history. They are saved, but only the DEV status shows them.
7. **`WordingTest` is in the `ui` area, not the gate,** so the gate stays at 55 tests.
8. **The new rule's 40 lines were added to the baseline by a one-off script,** since the
   lint's own `--update-baseline` only lowers counts and `--reset-baseline` is the owner's
   call. No other rule's entries changed.

## What is left

- The 40 plural lines, each to become a sentence with forms when its file is next changed.
- Wording seen and not converted: "Found a taste: " in the journal; the room thought's
  "… in a … room" and its " · " join; "the …" in the tastes; the freshness words and "about N
  days" for food; the thoughts' help and effect lines.
- The tests: at least 63 quote the game's wording. Those touched here check codes now; the
  rest change as they are touched.
- A translation: captions, the data files' names and descriptions, and a language to test
  with. Not planned.

## Checked

- Focused tests while building, then every test in the project and the lint once at the end
  (the result is in the changelog entry).
- Not seen in play. The owner's colony from 2026-11-15 (Balstad) is from before this change.
