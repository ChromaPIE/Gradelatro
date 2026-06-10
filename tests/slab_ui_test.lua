local H = dofile("tests/test_helper.lua")
local SlabUI = dofile("src/slab_ui.lua")

local record = {
    id = "grdl_9",
    center_key = "kino_air_freshener",
    local_key = "air_freshener",
    edition = "negative",
    status = "graded",
    grade = 10,
    cert_number = "000129",
    acquired_year = 2026
}
local catalog_entry = {
    center_key = "kino_air_freshener",
    mod_name = "Monarchy",
    series_index = 1
}

local args = SlabUI.label_args(record, catalog_entry)
H.assert_equal(args.year, 2026, "label year")
H.assert_equal(args.mod_name, "Monarchy", "label mod name")
H.assert_equal(args.series_index, 1, "label series index")
H.assert_equal(args.local_key, "air_freshener", "label local key")
H.assert_equal(args.grade, 10, "label grade")
H.assert_equal(args.edition, "negative", "label edition")
H.assert_equal(args.cert_number, "000129", "label cert number")

local Label = dofile("src/label.lua")
local lines = Label.slab_lines(args)
H.assert_equal(lines[1].left, "2026 MONARCHY", "slab line one left")
H.assert_equal(lines[1].right, "#001", "slab line one right")
H.assert_equal(lines[2].left, "AIR FRESHENER", "slab line two left")
H.assert_equal(lines[2].right, "GEM MT", "slab line two right")
H.assert_equal(lines[3].left, "NEGATIVE", "slab line three left")
H.assert_equal(lines[3].right, "10", "slab line three right")
H.assert_equal(lines[4].right, "000129", "slab line four right")

local fallback_args = SlabUI.label_args({ center_key = "j_x", mod_id = "SomeMod" }, nil)
H.assert_equal(fallback_args.mod_name, "SomeMod", "mod id fallback when catalog missing")
H.assert_equal(fallback_args.local_key, "j_x", "center key fallback for local key")

local function fake_popup()
    return { nodes = { { nodes = { { name = "original_box" } } } } }
end

local popup = fake_popup()
local node = { name = "slab" }
H.assert_equal(SlabUI.inject(popup, node), true, "inject succeeds on popup shape")
H.assert_equal(popup.nodes[1].nodes[1].name, "slab", "slab injected at top")
H.assert_equal(popup.nodes[1].nodes[2].name, "original_box", "original box preserved")
H.assert_equal(SlabUI.inject(nil, node), false, "nil popup rejected")
H.assert_equal(SlabUI.inject({ nodes = {} }, node), false, "malformed popup rejected")

local previous_g = rawget(_G, "G")
_G.G = {
    UIT = { R = "R", C = "C", T = "T", O = "O" },
    C = { RED = { 1, 0, 0, 1 }, WHITE = { 1, 1, 1, 1 }, UI = { TEXT_DARK = { 0, 0, 0, 1 } } }
}

local box = SlabUI.label_box(record, catalog_entry)
H.assert_equal(box.n, "R", "label box is a row node")
H.assert_true(box.nodes ~= nil and #box.nodes >= 1, "label box has inner frame")

local namespace = {
    binder_hover_index = { kino_air_freshener = catalog_entry }
}
local ui_def = {
    card_h_popup = function()
        return fake_popup()
    end
}
H.assert_equal(SlabUI.install(namespace, ui_def), true, "install wraps popup builder")
local wrapped = ui_def.card_h_popup
H.assert_equal(SlabUI.install(namespace, ui_def), true, "second install is a no-op")
H.assert_equal(ui_def.card_h_popup, wrapped, "wrapper not double wrapped")

local graded_popup = ui_def.card_h_popup({ grdl_record = record })
H.assert_true(graded_popup.nodes[1].nodes[1].n == "R", "graded card popup gains slab row")
H.assert_equal(graded_popup.nodes[1].nodes[2].name, "original_box", "graded popup keeps original box")

local raw_popup = ui_def.card_h_popup({ grdl_record = { status = "raw" } })
H.assert_equal(raw_popup.nodes[1].nodes[1].name, "original_box", "raw card popup untouched")

local plain_popup = ui_def.card_h_popup({})
H.assert_equal(plain_popup.nodes[1].nodes[1].name, "original_box", "non binder card untouched")

_G.G = previous_g

print("slab ui tests ok")
