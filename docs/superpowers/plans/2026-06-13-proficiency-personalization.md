# Proficiency Personalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `docs/superpowers/specs/2026-06-13-proficiency-personalization-design.md`: one compact Personalization entry in G inspect, a vertical personalization submenu, combined badge text/colour editing, and separate first-position inscription info boxes.

**Architecture:** Keep domain storage fields unchanged and make surgical UI changes. Add a small text-input utility module for Unicode/newline-safe text state and clipboard paste; keep HEX fields on vanilla `create_text_input`; keep tooltip rendering in `SlabUI` through vanilla `ability_UIBox_table.info`.

**Tech Stack:** Lua 5.1 (LuaJIT), SMODS + Lovely Balatro mod UI tables, Balatro vanilla overlay/info queue integration, headless tests via `dofile`.

---

## Project Conventions

- Repo root: `C:/Users/ChromaPIE/AppData/Roaming/Balatro/Mods/Gradelatro`.
- Test command: `C:/Users/ChromaPIE/AppData/Local/Programs/LuaJIT/bin/luajit.exe tests/run_all.lua`.
- Target tests for this plan: `tests/text_input_test.lua`, `tests/slab_ui_test.lua`, `tests/binder_ui_test.lua`, `tests/proficiency_test.lua`.
- New UI text goes through localization keys in both `localization/en-us.lua` and `localization/zh_CN.lua`.
- Do not hardcode Chinese text in `src/*.lua`.
- Prefer vanilla integration:
  - Tooltip/info boxes use `ability_UIBox_table.info`.
  - HEX fields keep using `create_text_input`.
  - Overlays keep using `create_UIBox_generic_options`.
- Commit after each green task using the message listed in that task.

## File Map

- Create `src/ui/text_input.lua`: text-state utilities for newline normalization, multiline preview, clipboard paste, clear, and a future IME entry point.
- Create `tests/text_input_test.lua`: pure utility coverage for Unicode/newline/paste behavior.
- Modify `tests/run_all.lua`: include `tests/text_input_test.lua`.
- Modify `src/ui/slab_ui.lua`: split inscription from proficiency info, inject inscription as the first info queue entry.
- Modify `tests/slab_ui_test.lua`: assert first-position inscription, no note in proficiency box, no duplicate entries.
- Modify `src/ui/ui_common.lua`: allow disabled/locked outline buttons without click handlers.
- Modify `src/ui/binder_ui.lua`: replace individual proficiency buttons with Personalization, add personalization overlay, add enhanced text editor overlay, add combined badge overlay.
- Modify `tests/binder_ui_test.lua`: cover main inspect button, personalization overlay state, locked rows, eternal colour, text paste/save, combined badge commit.
- Modify `localization/en-us.lua` and `localization/zh_CN.lua`: add new keys and remove unused old keys.
- Modify `tests/proficiency_test.lua` only if a helper is added to validate badge colour before combined commit.

---

### Task 1: Text Input Utility

**Files:**
- Create: `src/ui/text_input.lua`
- Create: `tests/text_input_test.lua`
- Modify: `tests/run_all.lua`

- [ ] **Step 1: Write the failing utility test.** Create `tests/text_input_test.lua`:

```lua
local H = dofile("tests/test_helper.lua")
local TextInput = dofile("src/ui/text_input.lua")

local text = "Alpha\r\n中文第二行\nThird"
local lines = TextInput.split_lines(text)
H.assert_equal(#lines, 3, "split preserves three logical lines")
H.assert_equal(lines[1], "Alpha", "first line normalized")
H.assert_equal(lines[2], "中文第二行", "unicode line preserved")
H.assert_equal(lines[3], "Third", "third line preserved")

local capped = TextInput.split_lines("A\nB\nC\nD", 3)
H.assert_equal(#capped, 3, "line cap applied")
H.assert_equal(capped[3], "C", "cap keeps original order")

local state = { text = "" }
local pasted = TextInput.apply_paste(state, function() return "刻字\n第二行" end)
H.assert_equal(pasted.ok, true, "paste succeeds")
H.assert_equal(state.text, "刻字\n第二行", "paste stores unicode and newline")

local empty = TextInput.apply_paste(state, function() return nil end)
H.assert_equal(empty.ok, false, "nil clipboard rejected")
H.assert_equal(empty.reason, "empty_clipboard", "nil clipboard reason")

TextInput.clear(state)
H.assert_equal(state.text, "", "clear resets text")

TextInput.accept_textinput(state, "未来IME")
H.assert_equal(state.text, "未来IME", "future textinput entry appends text")

print("text input tests ok")
```

In `tests/run_all.lua`, add this line near the other UI tests:

```lua
dofile("tests/text_input_test.lua")
```

- [ ] **Step 2: Run the new test and confirm it fails because the module does not exist.**

Run:

```powershell
& 'C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe' tests\text_input_test.lua
```

Expected: failure loading `src/ui/text_input.lua`.

- [ ] **Step 3: Implement the utility module.** Create `src/ui/text_input.lua`:

```lua
local TextInput = {}

local function normalize_newlines(text)
    return tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
end

function TextInput.normalize(text)
    return normalize_newlines(text)
end

function TextInput.split_lines(text, max_lines)
    local normalized = normalize_newlines(text)
    local lines = {}
    for line in (normalized .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
        if max_lines and #lines >= max_lines then break end
    end
    if #lines == 0 then lines[1] = "" end
    return lines
end

function TextInput.apply_paste(state, provider)
    if type(state) ~= "table" then return { ok = false, reason = "missing_state" } end
    local text
    if provider then
        text = provider()
    else
        local love_obj = rawget(_G, "love")
        if love_obj and love_obj.system and love_obj.system.getClipboardText then
            local ok, value = pcall(love_obj.system.getClipboardText)
            if ok then text = value end
        end
        local runtime = rawget(_G, "G")
        if (text == nil or text == "") and runtime and runtime.F_LOCAL_CLIPBOARD then
            text = runtime.CLIPBOARD
        end
    end
    if text == nil or text == "" then return { ok = false, reason = "empty_clipboard" } end
    state.text = normalize_newlines(text)
    return { ok = true }
end

function TextInput.clear(state)
    if type(state) == "table" then state.text = "" end
end

function TextInput.accept_textinput(state, text)
    if type(state) ~= "table" then return { ok = false, reason = "missing_state" } end
    if text == nil or text == "" then return { ok = false, reason = "empty_text" } end
    state.text = normalize_newlines((state.text or "") .. tostring(text))
    return { ok = true }
end

return TextInput
```

- [ ] **Step 4: Run the utility test and the full suite.**

Run:

```powershell
& 'C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe' tests\text_input_test.lua
& 'C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe' tests\run_all.lua
```

Expected: both commands exit 0; full suite ends with `all Gradelatro foundation tests ok`.

- [ ] **Step 5: Commit.**

```powershell
git add -- src\ui\text_input.lua tests\text_input_test.lua tests\run_all.lua
git commit -m "feat: add enhanced text input utilities"
```

---

### Task 2: Separate Inscription Tooltip Info

**Files:**
- Modify: `src/ui/slab_ui.lua`
- Modify: `tests/slab_ui_test.lua`

- [ ] **Step 1: Write the failing Slab UI tests.** In `tests/slab_ui_test.lua`, update the proficiency card note fixture to include a newline:

```lua
proficiency = { antes = 13, note = "my note\nsecond line", tooltip_colour = "FF8000" }
```

Replace the current note assertions in the proficiency-info section with:

```lua
H.assert_equal(#prof_card.ability_UIBox_table.info, 2, "inscription and proficiency entries injected")
local inscription_box = prof_card.ability_UIBox_table.info[1]
local info_box = prof_card.ability_UIBox_table.info[2]
H.assert_equal(inscription_box.grdl_inscription, true, "inscription entry inserted first")
H.assert_equal(inscription_box.name, nil, "inscription entry has no title")
H.assert_equal(info_box.grdl_prof, true, "proficiency entry still tagged for dedupe")
H.assert_equal(info_box.name, "grdl_k_prof_title", "proficiency entry keeps title")
prof_env.ui_def.card_h_popup(prof_card)
H.assert_equal(#prof_card.ability_UIBox_table.info, 2, "repeated hover never duplicates entries")

local found_level = false
local found_note_in_prof = false
for _, cells in ipairs(info_box) do
    for _, node in ipairs(cells) do
        if node.config and type(node.config.text) == "string" then
            if node.config.text:find("II", 1, true) then found_level = true end
            if node.config.text:find("my note", 1, true) then found_note_in_prof = true end
        end
    end
end
H.assert_true(found_level, "level label rendered in proficiency box")
H.assert_equal(found_note_in_prof, false, "custom note no longer appears in proficiency box")

local found_note_line = false
local found_second_line = false
for _, cells in ipairs(inscription_box) do
    for _, node in ipairs(cells) do
        if node.config and node.config.text == "my note" then found_note_line = true end
        if node.config and node.config.text == "second line" then found_second_line = true end
    end
end
H.assert_true(found_note_line, "inscription first line rendered")
H.assert_true(found_second_line, "inscription second line rendered")
```

- [ ] **Step 2: Run the Slab UI test and confirm it fails.**

Run:

```powershell
& 'C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe' tests\slab_ui_test.lua
```

Expected: it still finds only one info entry or finds the note in the proficiency box.

- [ ] **Step 3: Implement first-position inscription injection.** In `src/ui/slab_ui.lua`, load the utility near the existing `Proficiency` load:

```lua
local TextInput = load_src("ui/text_input.lua")
```

Remove the note append block from `proficiency_rows`.

Add these helpers near `inject_proficiency_info`:

```lua
local function remove_tagged_info(aut, tag)
    for index = #(aut.info or {}), 1, -1 do
        if aut.info[index] and aut.info[index][tag] then
            table.remove(aut.info, index)
        end
    end
end

local function inscription_rows(record)
    local note = record.proficiency and record.proficiency.note or nil
    if not note or note == "" or Proficiency.level(record) < 2 then return nil end
    local rows = {}
    for _, line in ipairs(TextInput.split_lines(note, 4)) do
        rows[#rows + 1] = { { n = G.UIT.T, config = {
            text = line,
            scale = 0.3,
            colour = G.C.UI.TEXT_DARK
        } } }
    end
    rows.grdl_inscription = true
    rows.background_colour = G.C.WHITE
    return rows
end

local function inject_inscription_info(card, record)
    local aut = card.ability_UIBox_table
    if type(aut) ~= "table" then return end
    local entry = inscription_rows(record)
    if not entry then return end
    aut.info = aut.info or {}
    remove_tagged_info(aut, "grdl_inscription")
    table.insert(aut.info, 1, entry)
end
```

In `inject_proficiency_info`, replace the early dedupe return with tag removal so proficiency can be re-appended after inscription:

```lua
    aut.info = aut.info or {}
    remove_tagged_info(aut, "grdl_prof")
    local entry = proficiency_rows(record)
    entry.name = UICommon.localize_text("grdl_k_prof_title")
    entry.grdl_prof = true
    aut.info[#aut.info + 1] = entry
```

In the hover wrapper, call `inject_inscription_info(card, record)` before `inject_proficiency_info(card, record)`.

- [ ] **Step 4: Run Slab UI and full suite.**

Run:

```powershell
& 'C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe' tests\slab_ui_test.lua
& 'C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe' tests\run_all.lua
```

Expected: both commands exit 0.

- [ ] **Step 5: Commit.**

```powershell
git add -- src\ui\slab_ui.lua tests\slab_ui_test.lua
git commit -m "feat: show inscriptions as first tooltip info"
```

---

### Task 3: Personalization Entry And Vertical Overlay

**Files:**
- Modify: `src/ui/ui_common.lua`
- Modify: `src/ui/binder_ui.lua`
- Modify: `tests/binder_ui_test.lua`

- [ ] **Step 1: Write failing Binder UI tests for the new entry and overlay.** In `tests/binder_ui_test.lua`, after the existing eternal button setup, replace the direct old-button assertions with:

```lua
local inspect_definition = BinderUI.create_inspect_definition(namespace)
local personalize_button = find_button(inspect_definition, "grdl_prof_personalize")
H.assert_true(personalize_button ~= nil, "graded inspect renders one personalization button")
H.assert_equal(find_button(inspect_definition, "grdl_prof_note"), nil, "note button removed from main inspect")
H.assert_equal(find_button(inspect_definition, "grdl_prof_badge"), nil, "badge button removed from main inspect")
H.assert_equal(find_button(inspect_definition, "grdl_prof_badge_colour"), nil, "badge colour button removed from main inspect")
H.assert_equal(find_button(inspect_definition, "grdl_prof_tint"), nil, "tint button removed from main inspect")
```

Add helper assertions for the submenu:

```lua
local low_personal_card = member_card
low_personal_card.proficiency = { antes = 5 }
BinderUI.open_personalization(namespace, low_personal_card.id)
local personal_definition = BinderUI.create_personalization_definition(namespace)
local inscription_locked = find_button(personal_definition, "grdl_prof_inscription")
local eternal_locked = find_button(personal_definition, "grdl_prof_eternal")
H.assert_true(inscription_locked ~= nil, "inscription row rendered")
H.assert_true(eternal_locked ~= nil, "eternal row rendered")
H.assert_equal(inscription_locked.config.button, nil, "locked inscription has no click action")
H.assert_equal(eternal_locked.config.button, nil, "locked eternal has no click action")
H.assert_equal(inscription_locked.config.outline_colour, _G.G.C.UI.TEXT_INACTIVE, "locked row grey outline")

low_personal_card.proficiency.antes = 100
BinderUI.open_personalization(namespace, low_personal_card.id)
local unlocked_personal_definition = BinderUI.create_personalization_definition(namespace)
local unlocked_inscription = find_button(unlocked_personal_definition, "grdl_prof_inscription")
local unlocked_eternal = find_button(unlocked_personal_definition, "grdl_prof_eternal")
local unlocked_badge = find_button(unlocked_personal_definition, "grdl_prof_badge")
local unlocked_tint = find_button(unlocked_personal_definition, "grdl_prof_tint")
H.assert_true(unlocked_inscription ~= nil, "unlocked inscription row rendered")
H.assert_true(unlocked_eternal ~= nil, "unlocked eternal row rendered")
H.assert_true(unlocked_badge ~= nil, "unlocked badge row rendered")
H.assert_true(unlocked_tint ~= nil, "unlocked tint row rendered")
H.assert_equal(unlocked_inscription.config.button, "grdl_prof_inscription", "unlocked inscription clickable")
```

- [ ] **Step 2: Run Binder UI test and confirm it fails.**

Run:

```powershell
& 'C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe' tests\binder_ui_test.lua
```

Expected: `grdl_prof_personalize` and personalization functions do not exist.

- [ ] **Step 3: Extend `UICommon.outline_button` for locked rows.** In `src/ui/ui_common.lua`, update the returned config in `outline_button`:

```lua
        hover = args.disabled and false or true,
        shadow = solid and true or false,
        button = args.disabled and nil or args.button,
        ref_table = args.disabled and nil or args.ref,
        focus_args = args.disabled and nil or { nav = "wide" }
```

The existing callers do not pass `disabled`, so this is backwards-compatible.

- [ ] **Step 4: Add Binder UI personalization helpers.** In `src/ui/binder_ui.lua`, add a local level map near the action helpers:

```lua
local PROF_PERSONALIZATION = {
    { key = "inscription", button = "grdl_prof_inscription", label = "grdl_b_prof_inscription", level = 2, gate = Proficiency.can_note },
    { key = "eternal", button = "grdl_prof_eternal", label = "grdl_b_prof_eternal", level = 3, gate = Proficiency.can_eternal },
    { key = "badge", button = "grdl_prof_badge", label = "grdl_b_prof_badge", level = 4, gate = Proficiency.can_badge },
    { key = "tint", button = "grdl_prof_tint", label = "grdl_b_prof_tint", level = 5, gate = Proficiency.can_tint }
}
```

Add `BinderUI.open_personalization`:

```lua
function BinderUI.open_personalization(namespace, card_id)
    if not namespace or not namespace.collection then return nil end
    local card = Storage.find_card(namespace.collection, card_id)
    if not card or card.status ~= "graded" then return nil end
    namespace.personalization_ui_state = { card_id = card_id, feedback = "" }
    return namespace.personalization_ui_state
end
```

In `inspect_action_row`, replace the old individual proficiency action block with one action:

```lua
    if entry.status == "graded" then
        actions[#actions + 1] = inspect_action_button("grdl_prof_personalize", entry.id, {
            { text = safe_localize("grdl_b_prof_personalize") }
        }, regular_font)
    end
```

Add a compact row builder:

```lua
local function personalization_row(card, state, item, regular_font)
    local unlocked = item.gate(card)
    local fill = G.C.CLEAR
    if item.key == "eternal" then
        state.eternal_button_colour = state.eternal_button_colour or { 0, 0, 0, 0 }
        set_state_colour(state.eternal_button_colour, (card.proficiency and card.proficiency.eternal) and G.C.GREEN or G.C.CLEAR)
        fill = state.eternal_button_colour
    end
    local lines = { { text = safe_localize(item.label), colour = unlocked and G.C.WHITE or G.C.UI.TEXT_INACTIVE } }
    if not unlocked then
        lines[#lines + 1] = {
            text = safe_localize("grdl_k_prof_unlocks_at", { Proficiency.level_label(item.level) }),
            scale = 0.26,
            colour = G.C.UI.TEXT_INACTIVE
        }
    end
    return UICommon.outline_button({
        button = item.button,
        ref = { id = card.id },
        lines = lines,
        font = regular_font,
        minw = 2.6,
        minh = unlocked and 0.62 or 0.82,
        colour = fill,
        outline_colour = unlocked and G.C.WHITE or G.C.UI.TEXT_INACTIVE,
        disabled = not unlocked
    })
end
```

Add `BinderUI.create_personalization_definition(namespace)` that resolves `namespace.personalization_ui_state.card_id`, builds one compact vertical row per `PROF_PERSONALIZATION` entry, and wraps them with `create_UIBox_generic_options({ back_func = "grdl_reopen_inspect", minw = 4.4, ... })`.

- [ ] **Step 5: Register callbacks.** In `BinderUI.install_runtime`, add:

```lua
    runtime.FUNCS.grdl_prof_personalize = function(event)
        local card_id = event_card_id(event)
        local state = BinderUI.open_personalization(namespace, card_id)
        if state and runtime.FUNCS.overlay_menu then
            if runtime.SETTINGS then runtime.SETTINGS.paused = true end
            runtime.FUNCS.overlay_menu({ definition = BinderUI.create_personalization_definition(namespace) })
        end
    end

    runtime.FUNCS.grdl_reopen_inspect = function()
        local personal = namespace.personalization_ui_state
        if personal and personal.card_id then reopen_inspect(personal.card_id) end
    end
```

Rename the old note callback to route through the new row:

```lua
    runtime.FUNCS.grdl_prof_inscription = function(event)
        BinderUI.open_prof_input(namespace, event_card_id(event), "note")
    end
```

Keep `grdl_prof_eternal`, `grdl_prof_badge`, and `grdl_prof_tint` as destination callbacks for the submenu.

- [ ] **Step 6: Run Binder UI and full suite.**

Run:

```powershell
& 'C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe' tests\binder_ui_test.lua
& 'C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe' tests\run_all.lua
```

Expected: both commands exit 0.

- [ ] **Step 7: Commit.**

```powershell
git add -- src\ui\ui_common.lua src\ui\binder_ui.lua tests\binder_ui_test.lua
git commit -m "feat: group proficiency actions under personalization"
```

---

### Task 4: Enhanced Inscription Editor And Combined Badge Editor

**Files:**
- Modify: `src/ui/binder_ui.lua`
- Modify: `tests/binder_ui_test.lua`

- [ ] **Step 1: Write failing editor tests.** Extend the `open_prof_input` test block in `tests/binder_ui_test.lua`:

```lua
local previous_love = rawget(_G, "love")
_G.love = { system = { getClipboardText = function() return "刻字\n第二行" end } }

captured_overlay = nil
BinderUI.open_prof_input(namespace, member_card.id, "note")
H.assert_true(captured_overlay ~= nil, "inscription editor opens")
H.assert_equal(namespace.prof_text_input.kind, "note", "inscription editor uses text input state")
runtime.FUNCS.grdl_prof_text_paste()
H.assert_equal(namespace.prof_text_input.text, "刻字\n第二行", "inscription paste preserves unicode newline")
runtime.FUNCS.grdl_prof_text_commit()
H.assert_equal(member_card.proficiency.note, "刻字\n第二行", "inscription commit stores pasted text")

_G.love = { system = { getClipboardText = function() return "徽标中文" end } }
captured_overlay = nil
captured_text_input = nil
BinderUI.open_badge_input(namespace, member_card.id)
H.assert_true(captured_overlay ~= nil, "combined badge editor opens")
H.assert_true(captured_text_input ~= nil, "badge colour still uses vanilla text input")
H.assert_equal(captured_text_input.ref_value, "badge_colour", "badge colour field bound")
H.assert_equal(captured_text_input.extended_corpus, true, "badge colour keeps extended corpus")
runtime.FUNCS.grdl_prof_badge_paste()
H.assert_equal(namespace.prof_badge_input.badge_text, "徽标中文", "badge text paste stores unicode")
namespace.prof_badge_input.badge_colour = "00FF80"
runtime.FUNCS.grdl_prof_badge_commit()
H.assert_equal(member_card.proficiency.badge_text, "徽标中文", "badge text committed")
H.assert_equal(member_card.proficiency.badge_colour, "00FF80", "badge colour committed")

_G.love = previous_love
```

- [ ] **Step 2: Run Binder UI test and confirm it fails.**

Run:

```powershell
& 'C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe' tests\binder_ui_test.lua
```

Expected: `open_badge_input`, `prof_text_input`, and paste callbacks are missing.

- [ ] **Step 3: Load text utility and split editor paths.** In `src/ui/binder_ui.lua`, add:

```lua
local TextInput = load_src("ui/text_input.lua")
```

Change `open_prof_input` so `kind == "note"` routes to an enhanced text editor, while `kind == "tint"` keeps the existing HEX editor. Do not use vanilla `create_text_input` for note text.

Add `BinderUI.open_text_input(namespace, card_id, kind)`:

```lua
function BinderUI.open_text_input(namespace, card_id, kind)
    local runtime = rawget(_G, "G")
    if not runtime or not runtime.FUNCS or not runtime.FUNCS.overlay_menu then return end
    local card = Storage.find_card(namespace.collection or {}, card_id)
    if not card then return end
    local meta = card.proficiency or {}
    local current = kind == "note" and meta.note or ""
    namespace.prof_text_input = { card_id = card_id, kind = kind, text = current or "", feedback = "" }
    local preview_rows = {}
    for _, line in ipairs(TextInput.split_lines(namespace.prof_text_input.text, 4)) do
        preview_rows[#preview_rows + 1] = row({ ui_text(line, 0.32, G.C.UI.TEXT_DARK) }, { padding = 0.02 })
    end
    local nodes = {
        row({ ui_text(safe_localize("grdl_b_prof_inscription"), 0.4, G.C.WHITE) }),
        row({ { n = G.UIT.C, config = { minw = 4.2, minh = 0.9, r = 0.08, colour = G.C.WHITE, emboss = 0.04 }, nodes = preview_rows } }, { padding = 0.06 }),
        row({
            UICommon.outline_button({ button = "grdl_prof_text_paste", solid = true, minw = 1.35, minh = 0.55, lines = { { text = safe_localize("grdl_b_paste"), scale = 0.3 } } }),
            UICommon.outline_button({ button = "grdl_prof_text_clear", minw = 1.35, minh = 0.55, lines = { { text = safe_localize("grdl_b_clear"), scale = 0.3 } } }),
            UICommon.outline_button({ button = "grdl_prof_text_commit", solid = true, minw = 1.35, minh = 0.55, lines = { { text = safe_localize("grdl_b_confirm"), scale = 0.3 } } })
        }, { padding = 0.05 }),
        row({ { n = G.UIT.T, config = { ref_table = namespace.prof_text_input, ref_value = "feedback", scale = 0.32, colour = G.C.GOLD } } })
    }
    if runtime.SETTINGS then runtime.SETTINGS.paused = true end
    runtime.FUNCS.overlay_menu({ definition = create_UIBox_generic_options({
        back_func = "grdl_prof_personalize",
        minw = 5.0,
        padding = 0.12,
        colour = G.C.L_BLACK,
        outline_colour = G.C.RED,
        contents = nodes
    }) })
end
```

Make `BinderUI.open_prof_input(namespace, card_id, "note")` call `BinderUI.open_text_input(namespace, card_id, "note")`.

- [ ] **Step 4: Add combined badge editor.** Add `BinderUI.open_badge_input(namespace, card_id)`:

```lua
function BinderUI.open_badge_input(namespace, card_id)
    local runtime = rawget(_G, "G")
    if not runtime or not runtime.FUNCS or not runtime.FUNCS.overlay_menu then return end
    if not rawget(_G, "create_text_input") then return end
    local card = Storage.find_card(namespace.collection or {}, card_id)
    if not card then return end
    local meta = card.proficiency or {}
    namespace.prof_badge_input = {
        card_id = card_id,
        badge_text = meta.badge_text or "",
        badge_colour = meta.badge_colour or "",
        feedback = ""
    }
    local preview_rows = {}
    for _, line in ipairs(TextInput.split_lines(namespace.prof_badge_input.badge_text, 2)) do
        preview_rows[#preview_rows + 1] = row({ ui_text(line, 0.32, G.C.UI.TEXT_DARK) }, { padding = 0.02 })
    end
    local nodes = {
        row({ ui_text(safe_localize("grdl_b_prof_badge"), 0.4, G.C.WHITE) }),
        row({ { n = G.UIT.C, config = { minw = 4.2, minh = 0.65, r = 0.08, colour = G.C.WHITE, emboss = 0.04 }, nodes = preview_rows } }, { padding = 0.05 }),
        row({
            UICommon.outline_button({ button = "grdl_prof_badge_paste", solid = true, minw = 1.35, minh = 0.55, lines = { { text = safe_localize("grdl_b_paste"), scale = 0.3 } } }),
            UICommon.outline_button({ button = "grdl_prof_badge_clear", minw = 1.35, minh = 0.55, lines = { { text = safe_localize("grdl_b_clear"), scale = 0.3 } } })
        }, { padding = 0.04 }),
        row({ ui_text(safe_localize("grdl_b_prof_badge_colour"), 0.34, G.C.WHITE) }),
        row({ create_text_input({
            ref_table = namespace.prof_badge_input,
            ref_value = "badge_colour",
            max_length = 6,
            all_caps = false,
            extended_corpus = true,
            prompt_text = safe_localize("grdl_k_hex_prompt"),
            w = 3.0
        }) }, { padding = 0.04 }),
        row({ { n = G.UIT.C, config = {
            minw = 1.2,
            minh = 0.4,
            r = 0.1,
            emboss = 0.05,
            colour = Proficiency.parse_hex(namespace.prof_badge_input.badge_colour) or { 0.2, 0.2, 0.2, 1 },
            func = "grdl_badge_hex_preview"
        }, nodes = {} } }, { padding = 0.04 }),
        row({ UICommon.outline_button({ button = "grdl_prof_badge_commit", solid = true, minw = 1.6, minh = 0.6, lines = { { text = safe_localize("grdl_b_confirm"), scale = 0.34 } } }) }, { padding = 0.05 }),
        row({ { n = G.UIT.T, config = { ref_table = namespace.prof_badge_input, ref_value = "feedback", scale = 0.32, colour = G.C.GOLD } } })
    }
    if runtime.SETTINGS then runtime.SETTINGS.paused = true end
    runtime.FUNCS.overlay_menu({ definition = create_UIBox_generic_options({
        back_func = "grdl_prof_personalize",
        minw = 5.2,
        padding = 0.12,
        colour = G.C.L_BLACK,
        outline_colour = G.C.RED,
        contents = nodes
    }) })
end
```

Update `runtime.FUNCS.grdl_prof_badge` to call `BinderUI.open_badge_input(...)` instead of the old single-field badge editor.

- [ ] **Step 5: Add paste, clear, preview, and commit callbacks.** In `BinderUI.install_runtime`, add:

```lua
    runtime.FUNCS.grdl_prof_text_paste = function()
        local input = namespace.prof_text_input
        local result = TextInput.apply_paste(input)
        if result.ok then
            BinderUI.open_text_input(namespace, input.card_id, input.kind)
        elseif input then
            input.feedback = safe_localize(reason_key(result.reason))
        end
    end

    runtime.FUNCS.grdl_prof_text_clear = function()
        local input = namespace.prof_text_input
        if input then
            TextInput.clear(input)
            BinderUI.open_text_input(namespace, input.card_id, input.kind)
        end
    end

    runtime.FUNCS.grdl_prof_text_commit = function()
        local input = namespace.prof_text_input
        if not input then return end
        local result = BinderUI.commit_prof_text(namespace, input.card_id, input.kind, input.text)
        if result.ok then reopen_inspect(input.card_id) else input.feedback = safe_localize(reason_key(result.reason)) end
    end

    runtime.FUNCS.grdl_prof_badge_paste = function()
        local input = namespace.prof_badge_input
        if not input then return end
        local temp = { text = input.badge_text }
        local result = TextInput.apply_paste(temp)
        if result.ok then
            input.badge_text = temp.text
            BinderUI.open_badge_input(namespace, input.card_id)
        else
            input.feedback = safe_localize(reason_key(result.reason))
        end
    end
```

Add badge clear, badge commit, and badge hex preview:

```lua
    runtime.FUNCS.grdl_prof_badge_clear = function()
        local input = namespace.prof_badge_input
        if input then
            input.badge_text = ""
            BinderUI.open_badge_input(namespace, input.card_id)
        end
    end

    runtime.FUNCS.grdl_prof_badge_commit = function()
        local input = namespace.prof_badge_input
        if not input then return end
        if input.badge_colour ~= "" and not Proficiency.parse_hex(input.badge_colour) then
            input.feedback = safe_localize("grdl_k_reason_invalid_hex")
            return
        end
        local text_result = BinderUI.commit_prof_text(namespace, input.card_id, "badge", input.badge_text)
        local colour_result = text_result.ok and BinderUI.commit_prof_text(namespace, input.card_id, "badge_colour", input.badge_colour) or text_result
        if colour_result.ok then reopen_inspect(input.card_id) else input.feedback = safe_localize(reason_key(colour_result.reason)) end
    end

    runtime.FUNCS.grdl_badge_hex_preview = function(element)
        local input = namespace.prof_badge_input
        if not input or not element or not element.config then return end
        local parsed = Proficiency.parse_hex(input.badge_colour)
        local target = element.config.colour
        if parsed and type(target) == "table" then
            target[1], target[2], target[3], target[4] = parsed[1], parsed[2], parsed[3], 1
        end
    end
```

- [ ] **Step 6: Run target tests and full suite.**

Run:

```powershell
& 'C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe' tests\binder_ui_test.lua
& 'C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe' tests\run_all.lua
```

Expected: both commands exit 0.

- [ ] **Step 7: Commit.**

```powershell
git add -- src\ui\binder_ui.lua tests\binder_ui_test.lua
git commit -m "feat: add enhanced inscription and badge editors"
```

---

### Task 5: Localization Cleanup And Final Verification

**Files:**
- Modify: `localization/en-us.lua`
- Modify: `localization/zh_CN.lua`
- Modify: `tests/binder_ui_test.lua` if localization-key assertions need updating

- [ ] **Step 1: Update localization keys.** In both locale files, add or rename keys in the existing dictionary block:

English:

```lua
grdl_b_prof_personalize = "Personalization",
grdl_b_prof_inscription = "Inscription",
grdl_b_prof_badge_text = "Badge Text",
grdl_b_paste = "Paste",
grdl_b_clear = "Clear",
grdl_k_prof_unlocks_at = "Unlocks at proficiency level #1#",
grdl_k_reason_empty_clipboard = "Clipboard is empty.",
grdl_k_reason_invalid_hex = "Use a 6 digit HEX colour.",
```

Chinese:

```lua
grdl_b_prof_personalize = "个性化",
grdl_b_prof_inscription = "刻字",
grdl_b_prof_badge_text = "徽标文本",
grdl_b_paste = "粘贴",
grdl_b_clear = "清空",
grdl_k_prof_unlocks_at = "解锁于 #1# 级熟练度",
grdl_k_reason_empty_clipboard = "剪贴板为空。",
grdl_k_reason_invalid_hex = "请输入 6 位 HEX 颜色。",
```

Keep these keys if code still uses them:

```lua
grdl_b_prof_badge = "Custom Badge",
grdl_b_prof_badge_colour = "Badge Colour",
grdl_b_prof_tint = "Tooltip Colour",
grdl_b_prof_eternal = "Eternal",
```

Remove `grdl_b_prof_note` after `rg` confirms it has no code/test references.

- [ ] **Step 2: Scan for removed or stale keys.**

Run:

```powershell
rg -n "grdl_b_prof_note|grdl_prof_badge_colour" src tests localization
```

Expected: no `grdl_b_prof_note` matches. `grdl_prof_badge_colour` callback/button should have no matches if the old separate badge-colour action was fully removed.

- [ ] **Step 3: Run formatting and full verification.**

Run:

```powershell
git diff --check
& 'C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe' tests\text_input_test.lua
& 'C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe' tests\slab_ui_test.lua
& 'C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe' tests\binder_ui_test.lua
& 'C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe' tests\proficiency_test.lua
& 'C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe' tests\run_all.lua
```

Expected:

- `git diff --check` exits 0.
- Target tests exit 0.
- Full suite exits 0 and ends with `all Gradelatro foundation tests ok`.

- [ ] **Step 4: Commit final localization cleanup.**

```powershell
git add -- localization\en-us.lua localization\zh_CN.lua tests\binder_ui_test.lua
git commit -m "chore: localize proficiency personalization flow"
```

---

## Self-Review Checklist

- Spec main inspect requirement maps to Task 3.
- Spec compact vertical list and locked-state behavior maps to Task 3.
- Spec eternal green-fill preservation maps to Task 3.
- Spec combined badge editor maps to Task 4.
- Spec inscription first info queue entry maps to Task 2.
- Spec enhanced text input with Unicode/newline/paste and future IME entry point maps to Task 1 and Task 4.
- Spec localization cleanup maps to Task 5.
- Verification commands are explicit for every task.
