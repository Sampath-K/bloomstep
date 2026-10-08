# Local growth story

The weekly garden story is an optional, read-only recap of the currently open
garden. The signed-in account garden and the device-only guest garden remain
separate SQLite owners; the recap never merges them or requires sign-in. Its
source of truth is the existing local habit, check-in, and reflection data.
Nothing new is collected, inferred from a provider, or sent by viewing or
acknowledging the recap.

The recap covers Monday through the current local calendar date. It counts at
most one effective positive check-in per habit per local date, using the
existing append-only event resolution; `Not today` and undo are not practice.
Each habit retains its existing monotonic growth stage, and a graduated habit
is described as part of the permanent evergreen Grove. The optional next step
is deterministic: it uses this week's effective `Not today` reasons, prioritizes
`too hard`, then `anchor`, `forgot`, and `motivation` for ties, and otherwise
offers a no-change-needed suggestion. It does not alter a recipe or graduation
status.

Acknowledging the recap stores only its local week-start date in a device-local
setting. That key is deliberately excluded from sync payloads and no analytics
event is emitted. The owner export includes a computed `weeklyGardenStory`
snapshot plus the pre-existing raw garden records; the computed summary adds no
account ID, email, provider, token, or record ID.

| Condition | Behavior |
| --- | --- |
| Empty garden | Return a zero-count empty summary; the garden screen keeps its existing empty-state invitation and shows no per-habit recap action. |
| Offline guest or signed-in garden | Read only the current GardenStore owner. No provider calls or network activity are needed to view or acknowledge the story; existing account sync behavior for habit data is unchanged. |
| Read/write failure | Do not show fabricated success. Show a visible recap read/save error and leave the seen-week state unchanged when persistence fails. |
| Reduced motion/accessibility | Recap adds no motion. Growth stage, practice count, Grove membership, date range, and suggestion are ordinary readable text. |
| Duplicate/corrected records | Resolve to the existing effective record for each habit/local date; only positive `did`/`didMore` dates count, so same-day edits cannot inflate the recap. |
| Timezone/week boundary | Convert check-in timestamps to local time before assigning their stored date. Use calendar dates (Monday–Sunday), not elapsed 24-hour windows, so week edges remain meaningful across UTC offsets and daylight-saving changes. |
| Export privacy | Keep the new computed summary free of owner/provider identifiers and secrets. The existing export still contains its established raw account-scoped records and warnings. |
