# ADR-0001: Backup and Restore Model

| Field | Value |
|-------|-------|
| Status | **Accepted** |
| Date | 2026-09-15 |
| Binds | menubar-spacer |
| Decision makers | nlink-jp maintainers |
| Triggered by | Implementing the write layer: the app changes undocumented OS settings on someone else's Mac, so "how do we guarantee a way back" is the product, not a detail |

## Context

menubar-spacer writes two undocumented keys — `NSStatusItemSpacing` and
`NSStatusItemSelectionPadding` — in the CFPreferences current-user /
current-host / any-application scope. On an untouched Mac **both keys are
absent**, and the measurements in [phase1-results](../phase1-results.md) confirm
that absence is not equivalent to any value: the OS behaves like N ≈ 16 but
writing 16 is not the same thing as leaving the key unset, and nothing documents
what the OS will do with these keys in a future release.

The user's real asset is therefore not the spacing they chose; it is **the state
their Mac had before this app ever ran**. Every decision below protects that.

Two further constraints come from the same measurements and from the shape of
the domain. The value is latched per process, so the app cannot observe the
effect of its own write: "did it work?" is answerable only by reading the
preference back. And the keys are ordinary global preferences that anyone can
set with `defaults write` — to any type, not only integers.

## Decision

### 1. Absence is a state, not a default value

`StoredValue` is `.absent | .integer(n) | .other(…)`. Restoring a Mac whose keys
were absent means **deleting** both keys. The "OS default" preset is the same
deletion, taking the same code path as restore.

### 2. The record is captured from observation, never from intention

**Amended 2026-09-21: what happens to the record when a write does not do what
was asked.** The record has to exist before the first mutation, so it is first
saved for the *target* — an intention — and corrected from the read-back when
the write returns. v0.1.0 handled two cases badly.

*A write that threw skipped the correction.* The record went on naming the
target, the Mac stayed on the user's earlier spacing, and Undo refused that
spacing as someone else's change. Now, when macOS reports that the change was
not saved, the record is put back as it was before the click — without reading
anything, because a read made after a failed save can still return the value
that was asked for. With no earlier record the new one stays: it is right if the
write landed after all, and harmless if it did not (Undo finds the Mac already
original and clears it). A restore stores no intention, so its record is simply
left alone.

*A write that changed nothing recorded what it saw.* Over a value someone else
had set, that adopted their value as this app's own, and a later Undo removed it
(against §10). Now: **if the read-back equals what was there before the write,
the record goes back exactly as it was**; otherwise it records what was read.
What remains is the narrow case of a write that lands on one key only, over an
outsider's value: the mix is recorded as observed.

**Known limit: a change macOS accepts and then fails to save.** Measured on
macOS 27.0 (2026-09-21):

- With a throwaway preference file made unwritable, `CFPreferencesSynchronize`
  still returned **true**, and the preferences API — in the writing process and in new
  ones — answered with the unsaved value for between fifteen seconds and a
  minute, then went back to the old value without a word.
- The file cannot be asked instead. For the real domain
  (`~/Library/Preferences/ByHost/.GlobalPreferences.<host uuid>.plist`) macOS
  wrote a *successful* change 4–8 s after `Synchronize` returned. (A throwaway
  domain had shown it at 0 ms; a first draft of this amendment read the file on
  that evidence, and the hardware tests failed every successful write.)

So at the moment of writing, neither source says whether the change was saved,
and the read-back (§13) goes through the API: it sees a change macOS rejects or
ignores, and it cannot see this one. On a Mac in that state the window reports
success and macOS reverts within a minute. What follows depends on the click:

- After an *apply*, the record names a spacing the Mac never got, and Undo may
  refuse the Mac's real value as someone else's.
- After an *Undo* — or an apply whose target is the original — the read-back
  says the Mac is back where it started, so the record is discarded, and the
  Mac then returns to this app's value with no record. The next apply records
  that value as the original: **a hand-set original can be lost.** This is
  v0.1.0's behaviour too; it is stated here because the first text of this
  amendment mentioned only the refusal.

The way home — "macOS default", or the two `defaults` commands in the README —
works once the Mac can save preferences again; until then nothing it is asked to
change is kept, for any app. Closing the limit would mean holding every change
"unconfirmed", and every discard back, until the file and the API agree (seconds
for a success, up to a minute for this failure); that wait on every change was
judged worse than the limit. The probes and their output are in
`evidence/2026-09-21-preference-save/`.

Both fields of `BackupRecord` hold what was actually read:

- `original` is read immediately before the first apply.
- `applied` is re-saved from the state read back **after** each write, not from
  the target that was requested.

A write that half lands therefore leaves the record describing the Mac as it
really is. The earlier design stored the target, which made the app diagnose its
own half-finished write as someone else's change and refuse to clean it up.

### 3. No value is "implausible"

There is no range check on a value read from the Mac. Whatever someone's Mac
holds — a hand-set 100, a string — is what a restore has to put back. An earlier
plausibility gate (0…64) recorded such a value faithfully and then rejected the
same record on every restore, leaving no in-app way back at all. Validation
belongs to *decoding a file*, not to *observing a Mac*.

### 4. A value the app cannot interpret is preserved verbatim

`defaults write -g NSStatusItemSpacing 8` (without `-int`) stores a **string**.
Coercing what is read to an integer would record `absent` for that key, and
Restore would then delete a key the user had set. `.other` keeps the value as a
binary property list and writes it back unchanged; `isRestorable` reports the
case where even that is impossible, instead of writing something else.

### 5. The way back is stored before the first write

`apply` saves the record and only then calls the writer. A write that fails — or
an app that dies between the two — never loses the original. (On a second or
later apply, a crash in that window leaves a record that names the new target
while the Mac holds the earlier value, so Undo refuses it until any spacing is
applied again; two fields cannot cover this window and the one in §9 both.) The guarantee is
against a crash or a failed write, not against power loss: the file is written
atomically (temp file plus rename) but not fsynced.

### 6. `original` is captured once and survives every later apply

The record keeps the state from before this app's *first* write. Applying a
second preset updates `applied`, never `original`. Restore means "before
menubar-spacer", not "before the last click".

### 7. A record exists only while something of ours is in effect

When an apply or restore leaves the Mac at `original`, the record is deleted. So
"there is a backup" and "this app is currently changing something" are the same
statement. Deleting the record is best-effort: a write that already succeeded is
never reported as a failure because the bookkeeping file would not delete.

### 8. Every mutating path runs under an exclusive lock, and reads inside it

`apply` and `restore` take an exclusive `flock` on a file beside the record, and
read the live preferences **inside** it. The sequence read-current → load record
→ save → write is a read-modify-write over state shared with every other copy of
this app on the Mac; without the lock a second instance can record a state this
app itself produced as the user's original. `state()` stays lock-free: it only
displays, and blocking the UI to render a status would be worse than rendering
one a moment out of date.

### 9. A state that is partly ours is ours to clean up

`RestorePlanner.isExplainedByOurWrite` accepts any state in which each key holds
either its original value or the last value we observed. That covers the state we
left behind, a write the OS honoured for one key only, and a crash between the
write and the record correction. Anything else is `changedExternally`. A third
party that happens to set a key to precisely the value we wrote is
indistinguishable from us and is treated as us; restoring is the right move
either way.

### 10. Restore refuses an external change; apply reports it

Undo must not discard someone else's change, so `restore` refuses and hands the
decision back. `apply` is the opposite situation — the user is asking for a new
value right now — so it proceeds, and returns
`appliedOverExternalChange` naming what it replaced. The asymmetry is
deliberate: refusing an explicit request would be obstruction, while performing
an undo over an unexplained state would be destruction.

### 11. An unreadable backup blocks every value preset — except the way home

If the record file exists but cannot be decoded, `load()` throws rather than
reporting "no backup", which would tell the user nothing was changed while their
Mac still is. Applying a *value* preset then refuses, because writing a fresh
record would overwrite the damaged one with a state this app itself produced.
Applying **OS default** is still allowed: it needs no record and cannot make
recovery worse.

A damaged file is **moved aside** (`backup.json.damaged-<date>`), never deleted,
and only after a write that took the Mac home. The read may have failed for a
transient reason, and its bytes may still be readable by a person. (v0.1.0 moved
it after any write, including one the OS ignored or applied to one key only —
leaving this app's value in effect with the file that might undo it set aside.)

**Amended 2026-09-21: two kinds of "cannot be read", and one exception.** The
store reported both as `unreadable`. They are not the same fact. A file that
could not be *read* may read next time, and the rule above is for it. A file
that was read and does not *decode* (`undecodable`) holds the same bytes on
every later read. For that one, the rule produced a dead end: with both keys
already unset, choosing OS default writes nothing, so nothing ever moved the
file aside; every value preset went on refusing, Undo could not use the file
either, and the message said this very choice "clears it". So an undecodable
file is moved aside when the user takes the way home even if nothing is
written. The unreadable case is unchanged, and its message no longer promises
a clearing that a transient failure does not get.

"The same bytes on every later read" is true of this version. A file written by a
*newer* version in a format this one cannot decode is undecodable here and
readable there; after a downgrade, the way home sets it aside too. Nothing is
lost — the bytes keep the `.damaged-` name and the newer version's file can be
put back by hand — and the alternative is the dead end above, for a case this
app has no way to tell apart. Names get a numbered suffix when two files are set
aside within one second.

### 12. A failure to write the record down is not a failure to change the spacing

Once the preferences have been written, the Mac has changed. If the record
cannot be *corrected* afterwards, the change stands and only the bookkeeping is
stale, so it is reported as `SpacingRecordError.notUpdated` — the sentence says
what the Mac now holds and that applying any spacing again rewrites the note.
v0.1.0 and v0.1.1 reported "The spacing could not be changed", which was false.

Where the record already on disk says what the correction would write — the
write did what was asked, so the record stored before it is true — the rewrite
is best effort and no failure is reported at all. Failing to store the record
*before* the write is a real failure: nothing has been written yet.

### 13. Every write is verified by reading it back, and only differing keys are written

`SystemSpacingPreferences.apply` re-reads the scope and returns what it found;
the coordinator compares it with the target and reports `noEffect` when they
differ. (What this cannot see is recorded in §2, amended.) `SpacingPlan.operations` emits the minimal set/delete list, so a no-op
apply touches nothing. The single-key write is covered by the hardware tests,
which the measurement probe never exercised.

## Rejected alternatives

**Guard against an unsaved write with more state.** Three drafts of the
2026-09-21 amendment did: a record naming both the target and the value being
replaced, a process that refused every action after a failed flush, a next
process that settled the record. Each was blocked in review and none shipped.
All three assumed `CFPreferencesSynchronize` returns false when a write is not
saved. It returns true, so none of that machinery would ever have run.

**Verify a write against the settings file.** The file is truthful, but for this
domain it is written seconds after the change (§2, amended), so an immediate
check fails every success — found by the hardware tests, before release.

**Store the OS default as a number and restore that.** Requires believing 16 is
"the" default, which the measurements do not support. Rejected as an assumption
the product would silently impose on the user's Mac.

**Range-check values read from the Mac.** Sounds defensive; in practice it
refuses to restore exactly the users whose Macs are furthest from default.

**Coerce every value to an integer.** Simpler types, but it turns a string into
"absent" and makes Restore delete a key the user set.

**Keep a history of every change.** A stack of states invites "how far back?"
and multiplies the ways a restore can be wrong. One record answers the only
question the user has.

**Let restore win over an external change.** Always succeeds, and silently
destroys a change the user may have made deliberately.

**Refuse to apply over an external change too.** Symmetrical, but it blocks an
explicit request to fix the very state the user is looking at.

**Treat an unreadable backup as no backup.** Trivial code, invisible failure:
the app would report "nothing to restore" to a user whose menu bar is visibly
changed.

**Block everything when the backup is unreadable.** Safe for the record, but
leaves no in-app route back to the OS default — the one action needing no record.

**Rely on a single-instance guard instead of a lock.** The guard is still worth
having (see below), but it is a property of app launch; the invariant belongs to
the data.

## Consequences

- The UI must render five apply outcomes and seven restore outcomes, including
  the refusals. Silent no-ops are not available.
- The lock closes the race between two running copies. A **single-instance
  guard** is still required before the UI can apply anything — two windows both
  offering to change the same setting is a UX defect even when it is safe. This
  is recorded as a blocking Phase 2 gate in `AGENTS.md`.
- The backup is a single JSON file under Application Support. Deleting it by
  hand loses the way back, which is why the READMEs document the `defaults`
  command that returns the Mac to the OS default without it.
- Durability is crash-safe, not power-safe. If that becomes a requirement, the
  save needs an fsync of both the file and its directory.

## Related

- [phase1-results](../phase1-results.md) — the measurements these rules rest on
- [RFP](../menubar-spacer-rfp.md) — scope and the decisions that preceded these
- [日本語版](../../ja/adr/0001-backup-and-restore-model.ja.md)
