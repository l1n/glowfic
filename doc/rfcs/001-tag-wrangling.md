# RFC 001: Tag Wrangling Interfaces

**Status:** Draft
**Author:** @l1n
**Created:** 2026-08-03

## Summary

Glowfic's tag namespace is globally writable and has no canonicalization. Any
logged-in user creates permanent, site-wide tags as a side effect of tagging
their own post, and nothing merges the duplicates afterwards except an
admin-only model method with no interface attached to it.

This RFC proposes three related pieces of work:

1. **A tag graph** — canonical tags, synonyms, and the wrangler role needed to
   maintain them.
2. **User-suggested tags** — a way for readers to propose tags on posts they
   don't own, with the author retaining control.
3. **Spoiler tags** — taggings that stay hidden until a reader has actually read
   far enough into the post to have hit the thing being tagged.

They are proposed together because they share a data model change: a tagging
(`PostTag`) needs to become a first-class record with state, rather than a bare
join row.

## Background: how tags work today

The tag system is a single-table STI hierarchy on `tags`:

- `Tag` (`app/models/tag.rb`) with `TYPES = %w(Setting Label ContentWarning GalleryGroup)`.
- `tags.name` is `citext`, uniqueness scoped to `type`, so `Bar Fight` and
  `bar fight` are already the same tag within a type.
- Every tag has `user_id NOT NULL` — a creator — plus an `owned` boolean used by
  `Setting`.
- `Setting` alone has hierarchy, via `Tag::SettingTag` (`parent_settings` /
  `child_settings`). `Label`, `ContentWarning`, and `GalleryGroup` are flat.

Worth noting early, because it changes the cost of one proposal below: the table
behind `Tag::SettingTag` is already called `tag_tags`, with generic `tag_id` /
`tagged_id` columns and no type constraint. Only the *model* restricts it to
`Setting`. It also carries an unused `suggested` boolean, referenced nowhere in
the codebase.

Tags reach posts through `Taggable#process_tags` (`app/concerns/taggable.rb`).
The form submits a mix of existing tag IDs and new names prefixed with `_`; the
concern resolves the existing ones, case-insensitively matches the new names
against what already exists, and constructs `klass.new(user: current_user, ...)`
for whatever is left. **Creating a global tag requires no permission beyond
being able to edit the post you are tagging.**

Two facts constrain everything below:

- **Nobody but an admin can currently curate tags.** `Tag#editable_by?` grants
  edit rights to the creator, to `:edit_tags` holders, and — for unowned
  `Setting`s only — to any non-readonly logged-in user. But `:edit_tags` and
  `:delete_tags` are *commented out* of `MOD_PERMS` in
  `app/concerns/permissible.rb:17-18`, so in practice only admins hold them.
- **`Tag#merge_with` already exists** and correctly re-points `UserTag`,
  `PostTag`, `CharacterTag`, `GalleryTag`, and `Tag::SettingTag`, de-duplicating
  as it goes. It is sound; it simply has no UI and no notion of which tag *should*
  survive.

There is also directly relevant precedent for progressive reveal. `post_views`
carries `read_at` and `warnings_hidden`; `Post#show_warnings_for?` gates the
content-warning interstitial per user, `Post#hide_warnings_for` records the
dismissal, and changing a post's warnings resets `warnings_hidden` for every
viewer (`app/models/post.rb:364`). Reading position is derivable today:
`Post#last_seen_reply_for` maps a user's `read_at` onto a concrete reply, and
`replies.reply_order` gives a stable index within a post.

## Prior art: AO3

Relevant pieces of `otwcode/otwarchive`, since it is the largest working
implementation of this problem:

- **Canonical + merger.** `tags.canonical` is a boolean; a non-canonical tag
  points at its canonical form through `merger_id` (`belongs_to :merger`), and
  `mergers` is the reverse. Synonymy is a pointer, not a separate table.
- **Two independent hierarchies.** `MetaTagging` (`meta_tags` / `sub_tags`)
  expresses "this tag implies that broader tag"; `CommonTagging`
  (`parents` / `children`) expresses cross-type containment, e.g. a Character
  belonging to a Fandom. Glowfic's `Tag::SettingTag` is the same shape as the
  latter.
- **Wrangling is assigned, not ambient.** `WranglingAssignment` is a
  `user_id` × `fandom_id` join: wranglers own bins of work rather than the whole
  namespace. `WranglingGuideline` puts written policy in the app itself, and
  `LastWranglingActivity` tracks staleness.
- **`unwrangleable`** marks tags deliberately left alone, so the queue can
  distinguish "not yet done" from "will not be done".
- **Denormalized filters.** `FilterTagging` / `FilterCount` maintain a
  materialized index so that searching a canonical tag also finds works tagged
  with its synonyms and sub-tags, without a recursive query per search.

Worth being explicit about what AO3 does *not* have, since it is often assumed:
there is no general "suggest a tag on someone else's work" flow. Users add
freeform tags to their own works and wranglers canonicalize afterwards. The
`*_nomination` models (`TagNomination`, `FandomNomination`, …) belong to tag
sets and challenges, not to open works. The user-suggestion design below is
therefore glowfic-specific and has no upstream implementation to copy.

## Problem statement

1. **Duplicate proliferation.** Nothing prevents `Bar Fight`, `Barfight`, and
   `bar-fight` from coexisting as three `Label`s. Citext collapses case only.
2. **No curation path.** The one tool that exists (`merge_with`) is unreachable
   without a Rails console.
3. **Readers cannot contribute.** A reader who notices a post needs a content
   warning has no in-app way to say so.
4. **Tags spoil posts.** A tag is metadata about the whole post, displayed up
   front. `Character Death` or a late-arriving setting is a spoiler for a reader
   on reply 3 of 400. Authors currently choose between tagging accurately and
   not spoiling, and accuracy loses.

## Proposal

### 1. Tag graph and the wrangler role

Add to `tags`:

| column | type | notes |
| --- | --- | --- |
| `canonical` | `boolean`, default `false`, not null | curated, preferred form |
| `merger_id` | `integer`, FK → `tags.id`, nullable | synonym pointer |
| `unwrangleable` | `boolean`, default `false`, not null | deliberately skipped |

Constraints worth enforcing in the model rather than discovering later:

- A tag with `merger_id` set must not be `canonical`.
- `merger_id` must point at a tag of the same `type`.
- Synonym chains resolve one level only — a merger must itself be canonical.
  This is the rule AO3 relies on, and it keeps resolution a single join.

`Tag#merge_with` stays as the mechanism, but synonyming becomes the default
outcome: merging sets `merger_id` on the loser rather than destroying it, so
existing links and bookmarks to the old tag still resolve. Because this is a
behavioural change to `merge_with`'s current contract (it calls
`other_tag.destroy`), it lands as a *new* method rather than a mutation of the
existing one, and both remain available — the wrangling UI offers "merge as
synonym" as the primary action and "merge and delete" as an admin-only
secondary. Deletion stays the rare case, for tags that should never have existed
rather than tags that are duplicates.

**Hierarchy generalizes beyond `Setting`.** `Label` gains the parent/child
structure `Setting` has, which is what makes implication ("tagging X implies Y")
possible and is a prerequisite for most of the wrangling wins. This costs no
migration: `Tag::SettingTag` becomes `Tag::MetaTag` over the same `tag_tags`
table, with the `Setting`-typed associations replaced by polymorphic-by-type
ones and a validation that both sides share a `type`. `Setting`'s
`parent_settings` / `child_settings` associations stay as named wrappers so
existing callers don't change.

Cross-type implication (a `Setting` implying a `ContentWarning`, say) is
deliberately *not* proposed here. AO3 has it via `CommonTagging` and it is
useful, but it raises questions about who owns the implied tag that same-type
implication does not. Deferred.

**`tag_tags.suggested` gets a meaning.** The unused column becomes the
proposed-but-unconfirmed state for an implication edge. An edge with
`suggested = true` is recorded but not yet in force: it does not imply anything
at query time, and it appears in a confirmation queue.

This falls out of the scoped/global split. A `WRANGLER` scoped to one Setting
will routinely notice implications that reach outside it — most usefully "this
Setting implies this `ContentWarning`" — and has no authority to assert them.
Rather than blocking on an admin or letting the scope be bypassed, they record a
suggested edge and an admin holding `:wrangle_tags_global` confirms or discards
it. Same-scope edges are created already-confirmed and never enter the queue.

**The canonical invariant.** Nothing user-facing may depend on `canonical`.
Search, filtering, autocomplete, and display all behave identically for a
canonical and a non-canonical tag; `canonical` is an annotation *for wranglers*,
recording that a human has looked at this tag and blessed its form. What
actually changes behaviour is `merger_id`, and that is only ever set by an
explicit merge.

This invariant is what makes the rollout below survivable. There is no
`canonical = true` backfill — every tag starts non-canonical and is promoted by
hand — so on day one the wrangling queue *is* the entire corpus. That is
tolerable precisely because an uncanonical tag is not a degraded tag. If
canonicalization ever gates behaviour, this decision has to be revisited first.

**Roles.** Rather than uncommenting `:edit_tags` / `:delete_tags` into
`MOD_PERMS` — which hands the whole namespace to every mod — add *two* roles to
`Permissible`, mirroring the split AO3 runs between wranglers and wrangling
supervisors (`:tag_wrangler` plus a supervisor tier):

- **`WRANGLER`** — a new role holding `:wrangle_tags`, scoped by
  `WranglingAssignment`. May canonicalize, synonym, and edit tags within their
  assigned Settings and those Settings' descendants.
- **Global wrangling is an admin capability, not a role.** `:wrangle_tags_global`
  and unscoped `:edit_tags` go to admins. This covers the tags that belong to no
  Setting — `Label`s spanning settings, and all `ContentWarning`s — and is the
  escalation path when a merge spans two wranglers' assignments.

`:delete_tags` stays admin-only in both cases. Deletion is destructive and
rarely the right answer once synonyms exist.

Two things are being decided here and they are worth separating. The global tier
is *distinct* from the scoped one — it is not an "unassigned" bucket inside
`WRANGLER` — because the global tags have the widest blast radius, content
warnings above all, and should not be editable by everyone handed a single
Setting to look after. But distinct does not require a third role: a separate
role only pays for itself when its membership is larger than the admin group,
and there is no reason to expect that here. If global wrangling ever becomes a
bottleneck on admin availability, promoting the capability to its own role is a
small change, because the permission is already named separately from the role
that holds it.

**Scope.** AO3 scopes wranglers by fandom. The closest glowfic analogue is not
the continuity but the **`Setting`** — a Setting *is* the world a post takes
place in, which is what a fandom is on AO3, whereas a `Board` is closer to a
posting venue. So: `WranglingAssignment(user_id, setting_id)`, with `setting_id`
referencing a `Setting`-typed tag.

Two consequences fall out of scoping this way, both of them arguments in favour:

- `Setting` already has hierarchy, and **an assignment cascades to descendant
  settings automatically**. A wrangler responsible for a broad world inherits
  its sub-worlds without a second assignment, which is exactly the containment
  AO3 gets from `meta_tags` and has to maintain by hand.
- The scope is itself a wrangled object. **Merging two duplicate Settings merges
  the bin of work** — both wranglers end up assigned to the survivor, and both
  are notified that their scope changed. Scopes collapsing into one is the
  accepted cost of keeping assignments consistent with the tag graph rather than
  drifting from it; the notification is what keeps it from happening behind the
  backs of the people it affects. Notification rather than an approval step,
  because an approval gate would let one wrangler block another's legitimate
  merge. Reuse the existing `Notification` model rather than inventing a
  channel.

Automatic inheritance has two prerequisites that do not exist today, and both
should be treated as blocking rather than as follow-ups:

**The Setting graph has no cycle guard.** `Tag::SettingTag` validates only
uniqueness of child within parent; nothing prevents A → B → A. With inheritance,
resolving a wrangler's scope becomes a graph traversal, and a cycle makes it
non-terminating. **The hierarchy editor rejects cycle-closing edges outright**,
with a validation on `Tag::MetaTag` rather than a check in the controller, so
the constraint holds for imports and console work too. Scope resolution should
*still* use a cycle-detecting recursive CTE as a belt-and-braces measure against
rows that predate the validation.

Rejecting rather than recording-and-ignoring does change the behaviour of an
editor ordinary users touch today: a save that previously succeeded can now fail
with a validation error. That is the right trade — a silently-ignored edge is a
lie about the state of the graph — but it needs a comprehensible error message,
not a bare "is invalid". This is worth fixing regardless, since a cycle is
already a latent hazard for anything walking `parent_settings`; inheritance is
what makes it acute.

**Editing the hierarchy becomes a privilege escalation.** Once an assignment
cascades, attaching Setting X as a child of Setting Y hands Y's wrangler
authority over X. Today `Tag#editable_by?` lets *any* non-readonly logged-in
user edit an unowned `Setting`, and `tags_controller#update:57` sets
`parent_settings` straight from `process_tags`. So under automatic inheritance,
an ordinary user could restructure the graph to expand or contract a wrangler's
scope. Editing `parent_settings` has to become wrangler-gated before inheritance
ships; the general "anyone may edit an unowned Setting" affordance can stay for
name and description.

The awkward case is a tag that appears across many unrelated Settings — most
`Label`s, and every `ContentWarning`. Those need a global wrangler tier that is
not assignment-scoped; assignment governs Settings and the tags that cluster
within them, not the whole namespace.

**Queue interface.** `/tags/wrangling`, wrangler-only:

- Non-canonical, non-synonym tags, ordered by usage count descending, filterable
  by type and by board.
- Inline actions per row: mark canonical, merge into an existing canonical tag
  (autocomplete), mark unwrangleable.
- Bulk select for the common case of many near-identical spellings.
- A "recently created" view, since the cheapest moment to catch a duplicate is
  when it is first used.

**Deferred:** the `FilterTagging` equivalent. Until glowfic has enough tags for
synonym-aware search to be slow, resolving `merger_id` at query time with a join
is sufficient, and a denormalized index is a large amount of invalidation
machinery to maintain. Revisit if tag search becomes a hotspot.

### 2. User-suggested tags

New model `TagSuggestion`:

| column | type | notes |
| --- | --- | --- |
| `post_id` | integer, not null | |
| `user_id` | integer, not null | suggester |
| `tag_id` | integer, nullable | existing tag, if any |
| `tag_type` | string, nullable | with `tag_name`, for a proposed new tag |
| `tag_name` | citext, nullable | |
| `status` | integer, not null | `pending` / `accepted` / `rejected` |
| `resolved_by_id` | integer, nullable | |
| `resolved_at` | datetime, nullable | |
| `note` | text, nullable | optional short rationale |

Exactly one of `tag_id` or (`tag_type`, `tag_name`) must be present.

**Flow.** A logged-in, non-readonly user opens "Suggest a tag" on a post they do
not own, picks an existing tag or proposes a name, optionally adds a note. The
post author sees a badge on their own post and a list under their user menu;
accepting creates the `PostTag` (and the `Tag`, if new, attributed to the
*suggester* as creator, consistent with `process_tags` today).

**Rejection blocks globally**, not per suggester. Once an author rejects a tag
on a post, nobody may suggest that tag on that post again. The alternative —
blocking only the original suggester — means an author can be asked the same
question by a stream of different readers, which is the failure mode that makes
authors switch suggestions off entirely.

Two details this implies:

- The block is keyed on `(post_id, tag_id)`, or on `(post_id, tag_type,
  lower(tag_name))` for a proposed new tag, so re-proposing the same name as a
  "new" tag does not slip past a rejection. `tags.name` being `citext` handles
  the casing for existing tags; proposed names need the comparison done
  explicitly since no `Tag` row exists yet.
- Rejection must be reversible by the author. A rejected suggestion is a
  standing decision, not a permanent one — authors change their minds, and a
  post's content changes under it. The author's own view of rejected
  suggestions needs an "allow again" action.

**Spoiler taggings are suggestible**, and this is where suggestions and spoilers
interact badly if built naively. A reader past a reveal threshold is exactly the
person positioned to notice a missing spoiler tag, so the suggestion form
carries the same `spoiler` and `reveal_after_reply_order` fields the author's
own tagging form does.

The leak is not in the suggestion itself — pending suggestions are visible only
to the author, so nothing is exposed to other readers by construction. The leak
is in **deduplication feedback**. If a reader who has not reached the threshold
suggests a tag that is *already applied as a hidden spoiler tagging*, the
obvious response — "that tag is already on this post" — reveals the spoiler. The
same applies to the global rejection block: "that tag was already suggested and
rejected" tells the reader the tag was contemplated.

So the dedup check must be **read-state aware**, and must fail open rather than
informatively. Where a collision exists that the suggester is not entitled to
know about, accept the suggestion normally and show the ordinary confirmation.
The suggester learns nothing.

**The author sees it as an endorsement, not a redundant suggestion.** A reader
independently arriving at a tag the author already applied is useful signal —
it says the tag is legible, that a real reader reached for the same words — so
the author's view should record it as corroboration of the existing tagging
rather than as a pending item needing a decision. Endorsements need no accept or
reject action; they accumulate against the tagging.

This is also the better answer to a worry the redundant-suggestion framing
created. Showing an author "someone suggested a tag you already have, hidden as
a spoiler" tells them their spoiler tagging is discoverable by inference.
Showing them "a reader endorsed this tag" says the same thing about legibility
without inviting them to conclude their spoiler leaked — because it did not. The
reader guessed; that is what the endorsement records.

This constraint is the reason pending suggestions should stay author-visible
only. If a future change surfaces them more widely — a public "suggested tags"
list, say — every one of these rules has to be re-derived, and the reveal rule
must apply to the suggestion list too.

**Author control.** Per-post `allow_tag_suggestions` (default on) and a per-user
default in settings. Authors who do not want the interaction should be able to
turn it off entirely rather than field the notifications.

**Abuse handling.** This is the feature most likely to be misused, so:

- Readonly and suspended users cannot suggest, reusing `readonly_forbidden`.
- Per-user rate limit on pending suggestions, plus a cap per post.
- Existing user ignore lists suppress suggestions from ignored users.
- Repeated rejected suggestions to the same author are a mod-visible signal.

**Content warnings, and the limit of this feature.** The strongest motivation
for suggestions is a reader hitting untagged material that should have carried a
warning. It is tempting to let mods apply a `ContentWarning` over an author's
rejection, and this RFC explicitly does **not** propose that: authors retain
creative control over their own posts, including over tags they decline.

The consequence should be stated plainly rather than left implicit. A reader who
believes a post needs a warning the author refuses has no recourse *within the
tag system*; their recourse is the existing out-of-band mod report, which is a
site-rules matter and deliberately a heavier instrument. `ContentWarning`
suggestions are therefore ordinary suggestions with no special powers attached —
the only accommodation is that a rejected `ContentWarning` suggestion is worth
surfacing to mods as a signal, without granting them the ability to act on it
unilaterally.

### 3. Spoiler tags

Make the tagging, not the tag, carry the spoiler state. `Character Death` is
not inherently a spoiler; it is a spoiler *on this post, until reply 200*.

Add to `post_tags`:

| column | type | notes |
| --- | --- | --- |
| `spoiler` | boolean, default `false`, not null | |
| `reveal_after_reply_order` | integer, nullable | reveal once the reader has read past this reply |

`spoiler` with a null `reveal_after_reply_order` means "reveal only when the
reader has reached the end of the post as it currently stands".

**Resolution.** A tagging is revealed to a user when any of:

- the user is the post's author or a mod;
- `spoiler` is false;
- the user's furthest-read reply order ≥ `reveal_after_reply_order`.

Reading position comes from the existing `post_views.read_at` via
`Post#last_seen_reply_for`, which already resolves a timestamp to a reply.
Logged-out users have no `post_view` and therefore see no spoiler taggings.

A caveat that should be designed for rather than discovered: `read_at` is a
*timestamp*, so a reader who opened a thread while it was short and returned
after 200 new replies has a `read_at` that maps to a high `reply_order` without
having read the intervening replies. This is acceptable for spoiler-hiding —
the failure mode is revealing slightly early to someone who skipped ahead, which
is what skipping ahead means — but it should not be described to users as a
guarantee.

**Leakage is the hard part.** Hiding the tag on the post page is easy and
insufficient. If a spoiler tagging still participates in tag → post listings,
then the tag page for `Character Death` lists the post and the spoiler is out.
Options:

- **(a) Exclude spoiler taggings from reverse lookup entirely.** Simple,
  leak-free, and it costs the tag its discoverability — the post genuinely does
  not appear under a tag it genuinely has.
- **(b) Filter per viewer.** Correct, but it makes every tag listing depend on
  the current user's read state across every post in the result set. Expensive
  and hard to cache.
- **(c) Include, but behind an explicit opt-in.** A user preference —
  "show posts under spoiler tags" — defaulting to off, plus an interstitial on
  the tag page.

**Recommendation: (a) for the first implementation, with (c) as a follow-up.**
(b) should be rejected outright; the caching cost is not worth it. Authors
should be told plainly in the UI that marking a tagging as a spoiler removes the
post from that tag's listings, because the alternative is authors believing they
get both discoverability and secrecy.

**Reuse the content-warning interstitial.** The reveal UI should follow the
existing pattern rather than inventing a second one: where spoiler taggings
exist but are not yet revealed, show a neutral count ("3 spoiler tags") that
expands on click, and record the choice the way `hide_warnings_for` does. Note
that per `app/models/post.rb:364`, changing a post's warnings resets
`warnings_hidden` for all viewers; the equivalent reset for spoiler taggings is
*not* wanted, since re-hiding a tag a reader has already seen achieves nothing.

**API behaviour: hide, do not omit.** `apipie` exposes post tags, so the reveal
rule has to apply there or the API is simply the leak by another route. But the
right treatment differs from the HTML view: an unrevealed tagging is *redacted*,
not dropped. The serialized entry stays in the array with its identity withheld:

```json
{ "id": null, "type": "Label", "spoiler": true, "revealed": false }
```

The reasoning is that the API's consumer is a program, not a reader. Omitting
entries makes the array length lie, so a client cannot distinguish "no tags" from
"tags it may not see", and any client computing counts silently gets them wrong.
Redaction keeps the shape honest while withholding the content. Authenticated
requests resolve `revealed` against the requesting user's read position exactly
as the web view does; anonymous requests have no read state and so see every
spoiler tagging redacted.

## Schema summary

```
tags            + canonical:boolean, merger_id:integer, unwrangleable:boolean
post_tags       + spoiler:boolean, reveal_after_reply_order:integer
posts           + allow_tag_suggestions:boolean
users           + allow_tag_suggestions:boolean (default for new posts)
tag_suggestions        new table (see above)
wrangling_assignments  new table (user_id, setting_id)
tag_tags        unchanged — generalizing Tag::SettingTag to Tag::MetaTag is a
                model-only change, and the existing `suggested` column is
                adopted as the unconfirmed-implication state
```

`post_tags` gaining columns is the change with the widest blast radius: it is
currently a bare join table and several queries treat it as one. Those need
auditing before the migration, not after.

The `tag_tags.suggested` column already exists, is unused, and is adopted here
as the unconfirmed state for an implication edge (see above). Since it currently
defaults to `false` and no rows set it, existing edges are correctly interpreted
as confirmed with no data migration.

## Rollout

1. Tag graph columns + model constraints, no UI. **No backfill** — every tag
   starts non-canonical and is promoted by hand. This is only viable because of
   the canonical invariant above: an uncanonical tag behaves exactly like a
   canonical one, so "unwrangled" is a backlog, not a defect.
2. Wrangler roles and queue interface. Run it manually for a while; the queue's
   shape will be wrong in ways that are only visible in use.

Because the queue starts as the whole corpus, it has to be ordered by value
rather than presented as a list to be finished:

- Default ordering by usage count descending, so the tags on the most posts get
  a decision first.
- Duplicate-suspect clustering — group tags whose names are near-matches under a
  normalization (case, whitespace, punctuation, simple pluralization), since
  those are both the highest-value merges and the easiest calls. Computed and
  cached rather than stored as a column, so the normalization can be tuned
  without a migration; invalidated on tag create, rename, and merge.
- Surface progress as *coverage weighted by usage* — "canonical tags account for
  N% of taggings" — not as a count of tags remaining. The raw remaining count
  will look unmoving for a long time and is a discouraging number to show a
  volunteer.
3. Spoiler taggings. Self-contained, and the most immediately valuable to
   authors.
4. User suggestions last, once there is a wrangler group able to absorb the
   moderation load it generates.

## Resolved

Decisions taken on the questions this draft opened with:

- **`Label` gains hierarchy.** Generalize `Tag::SettingTag` to `Tag::MetaTag`;
  no migration required. Cross-type implication deferred.
- **Wrangler assignments scope by `Setting`**, not by `Board` — a Setting is the
  structural analogue of an AO3 fandom. Global tags (`Label`s that span
  settings, all `ContentWarning`s) need an unscoped wrangler tier alongside it.
- **Mods cannot override an author's rejection of a `ContentWarning`.** Authors
  keep creative control; the escalation path stays the existing out-of-band mod
  report.
- **Merging synonyms by default, deletion retained.** Both behaviours stay
  available, with synonyming as the primary action and delete as admin-only.
- **The API redacts spoiler taggings rather than omitting them**, so array
  shapes and counts stay truthful for programmatic consumers.
- **No canonical backfill; canonicalization is entirely manual.** Viable only
  under the canonical invariant — nothing user-facing may depend on `canonical`.
- **One new role plus an admin capability.** `WRANGLER` is Setting-scoped;
  global wrangling (`:wrangle_tags_global`, covering cross-setting `Label`s and
  all `ContentWarning`s) is an admin capability rather than a third role. The
  tiers stay distinct — global is not an unassigned bucket inside `WRANGLER` —
  but the permission is named separately from the role holding it, so promoting
  it later is cheap.
- **`tag_tags.suggested` is adopted** as the unconfirmed-implication state,
  which is how a scoped wrangler proposes an edge reaching outside their scope.
- **A rejected suggestion blocks that tag on that post for everyone**, reversible
  by the author.
- **Assignments inherit down the Setting hierarchy automatically**, gated on
  adding a cycle guard and on making hierarchy edits wrangler-only.
- **Assignments follow a merged Setting**, collapsing both wranglers onto the
  survivor.
- **Duplicate clustering is computed and cached**, not a stored column.
- **Spoiler taggings are suggestible**, with a read-state-aware dedup check that
  fails open rather than revealing a collision.
- **Cycle-closing hierarchy edges are rejected** by model validation, not
  recorded and ignored.
- **A merge that collapses two wranglers' scopes notifies both**, via the
  existing `Notification` model; no approval gate.
- **A suggestion colliding with an unseen tagging is recorded as an
  endorsement** of the existing tagging, needing no author action.

## Next steps

Every question this draft opened with has been answered; what remains is
sequencing rather than design. The rollout section above is the intended order,
and the two prerequisites for automatic inheritance — the cycle validation and
wrangler-gating of `parent_settings` — should be broken out as their own tickets
ahead of step 2, since both are small, independently useful, and block the role
work.

One thing to settle at implementation time rather than here: endorsements need a
home in the schema. They are close enough to `TagSuggestion` to reuse it with a
fourth `status` (`endorsed`), and different enough — no decision pending, no
rejection possible, aggregate rather than individual interest — that a separate
counter on `post_tags` may read better. Decide it against the queries the
author's view actually needs.
