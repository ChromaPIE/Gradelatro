# G View Proficiency Personalization Design

## Goal

Improve the graded-card inspect flow in the G view by moving all proficiency-unlocked customization actions behind a single compact Personalization entry. The redesign should follow the existing Gradelatro/Balatro overlay style, prefer vanilla UI integration where it fits, and avoid wide or browser-like layouts.

## Scope

This change covers:

- The G view inspect action layout for proficiency perks.
- A secondary Personalization overlay.
- A combined custom badge overlay for badge text and badge colour.
- A practical enhanced text input path for custom text fields.
- Tooltip/info rendering for custom inscription text.
- Localization cleanup for added, renamed, or removed UI strings.

This change does not implement full IME composition support. The input layer must leave one clear integration point so a later pass can connect direct IME handling without rewriting the Binder UI flow.

## Main Inspect View

The main card inspect overlay should no longer show separate proficiency buttons such as Custom Note, Eternal, Custom Badge, Badge Colour, or Tooltip Colour.

For graded cards, it should show one `Personalization` action button. This button opens the secondary Personalization overlay. The button remains available even when no individual personalization perk is unlocked, so the user can inspect unlock requirements.

Raw cards and offer inspect views should not gain this personalization entry.

## Personalization Overlay

The Personalization overlay uses a compact vertical list, not long browser-style rows. Each row should match the mod's existing compact button proportions and remain readable at normal overlay scale.

Rows appear in this order:

1. Inscription
2. Eternal
3. Badge
4. Tooltip Colour

Unlocked rows use the normal white outline treatment. Locked rows use grey outline and grey text. Locked rows include a second smaller line:

`Unlocks at proficiency level #1#`

The locked second line must not make unrelated rows visually unbalanced. The vertical-list layout is chosen specifically so a locked row can be taller without changing the height of a neighbouring unlocked row.

Eternal keeps its existing state-based appearance:

- Off: white outline with transparent fill.
- On: white outline with green fill.

Clicking a locked row should not mutate card state. It may surface the localized locked reason and should avoid opening the destination editor.

## Badge Overlay

The Badge row opens a single badge customization overlay. That overlay combines:

- Badge text.
- Badge colour HEX input.
- A live colour preview swatch.

Badge text and badge colour save together through the existing proficiency storage fields:

- `proficiency.badge_text`
- `proficiency.badge_colour`

HEX parsing and preview should continue using the existing strict six-digit RGB behavior, accepting an optional leading `#` and storing uppercase hex without `#`.

## Inscription Display

Custom inscription text replaces the old behavior where note text was appended to the Proficiency info box.

The Proficiency info box should only show proficiency level and progress/mastered state.

If inscription text exists and the card has unlocked the note/inscription perk, inject a separate vanilla info queue entry for the inscription. This entry:

- Has no title/name.
- Uses a white bordered info-box style.
- Renders the inscription text as one or more lines.
- Is inserted at the first position of `ability_UIBox_table.info`, so it appears before other info boxes and is the front-most custom note-like entry.
- Deduplicates on repeated hover just like the existing proficiency entry.

The implementation should continue to use Balatro's vanilla `ability_UIBox_table.info` path rather than attaching a custom floating box.

## Enhanced Text Input

Vanilla `create_text_input` remains appropriate for short ASCII-like fields such as HEX colour because it is already integrated with Balatro's keyboard/controller UI and is sufficient for six-character RGB input.

For inscription and other custom text fields, Gradelatro should introduce a small enhanced text input adapter. This adapter must support:

- Unicode text stored without byte-by-byte truncation.
- Preserved newlines.
- Pasting text into the backing value.
- A multiline preview in the editor overlay.

The first implementation can rely on paste/edit affordances rather than full IME composition. It must expose a concentrated entry point for future direct `love.textinput` or composition-event integration, so IME support does not become scattered through Binder UI callbacks.

Badge text should use the enhanced path as well, so custom text fields behave consistently. Badge colour and tooltip colour remain HEX fields.

## Localization

Add or update localization for:

- Personalization
- Inscription
- Badge text
- Badge colour
- Tooltip colour
- Unlocks at proficiency level `#1#`
- Paste text / clear text / save labels if introduced by the enhanced input overlay

Remove old localization keys only after confirming no code or tests reference them.

## Testing

Tests should cover:

- The main inspect definition shows a single Personalization button for graded cards instead of the old individual proficiency buttons.
- The Personalization overlay renders all four rows in order.
- Locked rows are grey, include the unlock-level line, and do not call the editor/toggle action.
- Eternal still toggles state in place and green fill reflects the enabled state.
- Badge customization opens one overlay containing both text and colour fields, and commits both values.
- Inscription text is no longer appended to the Proficiency info box.
- Inscription text is inserted as a separate first info queue entry with no title/name.
- Repeated hover does not duplicate inscription or proficiency info entries.
- Unicode and newline text can be stored by the enhanced input path and rendered as multiple inscription lines.
- Removed localization keys have no remaining references.

## Implementation Notes

Prefer narrow helpers over a broad UI rewrite:

- Keep domain storage fields unchanged where possible.
- Add small Binder UI helpers for personalization rows and locked-state rows.
- Add or isolate enhanced text input behavior in a module/helper that Binder UI can call for inscription and badge text.
- Keep HEX input on the current vanilla-backed path.
- Keep tooltip and info-box rendering in `SlabUI`, where the existing vanilla tooltip integration already lives.
