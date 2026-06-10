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

H.assert_near(SlabUI.line_scale("SHORT", 0.27, 24), 0.27, 0.0001, "short line keeps base scale")
H.assert_near(SlabUI.line_scale("2026 LUCKY JIMBOS: JOKER PACK", 0.27, 24), 0.27 * 24 / 29, 0.0001, "long line shrinks")

local previous_g = rawget(_G, "G")
_G.G = {
    UIT = { R = "R", C = "C", T = "T", O = "O", ROOT = "ROOT" },
    C = {
        RED = { 1, 0, 0, 1 },
        WHITE = { 1, 1, 1, 1 },
        CLEAR = { 0, 0, 0, 0 },
        JOKER_GREY = { 0.5, 0.5, 0.5, 1 },
        UI = { TEXT_DARK = { 0, 0, 0, 1 }, TEXT_LIGHT = { 1, 1, 1, 1 } }
    },
    FONTS = {
        { file = "resources/fonts/m6x11plus.ttf" },
        { file = "resources/fonts/NotoSansSC-Bold.ttf" },
        { file = "resources/fonts/NotoSans-Bold.ttf" }
    }
}

H.assert_equal(SlabUI.label_font(), _G.G.FONTS[3], "noto sans bold font found")

local box = SlabUI.slab_box(record, catalog_entry)
H.assert_equal(box.n, "R", "slab box is a framed row node")
H.assert_equal(box.config.colour, _G.G.C.RED, "slab frame is red")
local inner = box.nodes[1]
H.assert_equal(#inner.nodes, 3, "label has left column, spacer, right column")
local left_col, spacer, right_col = inner.nodes[1], inner.nodes[2], inner.nodes[3]
H.assert_equal(#left_col.nodes, 4, "left column has four lines")
H.assert_equal(#right_col.nodes, 4, "right column has four lines")
H.assert_equal(left_col.nodes[1].config.align, "cl", "left lines flush left")
H.assert_equal(right_col.nodes[1].config.align, "cr", "right lines flush right")
H.assert_true((spacer.config.minw or 0) > 0, "spacer keeps a fixed gap")
H.assert_equal(left_col.nodes[1].nodes[1].config.font, _G.G.FONTS[3], "label text forced to noto sans")
H.assert_equal(left_col.nodes[1].nodes[1].config.text, "2026 MONARCHY", "left text content")
H.assert_equal(right_col.nodes[1].nodes[1].config.text, "#001", "right text content")

local namespace = {
    binder_hover_index = { kino_air_freshener = catalog_entry }
}

local function fake_popup()
    return { nodes = { { nodes = { { nodes = { { nodes = { { name = "name_box" } } } } } } } } }
end

local badge_calls = {}
_G.create_badge = function(text, badge_col, text_col)
    badge_calls[#badge_calls + 1] = { text = text, badge_col = badge_col, text_col = text_col }
    return { name = "badge", text = text }
end

local funcs = {}
local env = {
    ui_def = {
        card_h_popup = function()
            return fake_popup()
        end
    },
    funcs = funcs
}

H.assert_equal(SlabUI.install(namespace, env), true, "install wraps environment")
local wrapped_popup = env.ui_def.card_h_popup
H.assert_equal(SlabUI.install(namespace, env), true, "second install is a no-op")
H.assert_equal(env.ui_def.card_h_popup, wrapped_popup, "wrapper not double wrapped")
H.assert_true(type(funcs.grdl_show_slab) == "function", "slab anchor func registered")

local graded_card = { grdl_record = record, children = {} }
local popup = env.ui_def.card_h_popup(graded_card)
local column = popup.nodes[1].nodes
local anchor = column[1]
H.assert_equal(anchor.config.func, "grdl_show_slab", "slab anchor inserted at column top")
H.assert_true(anchor.config.ref_table ~= nil, "anchor carries slab nodes")
H.assert_equal(#column, 2, "anchor sits above the original frame")
local frame_rows = column[2].nodes[1].nodes
H.assert_equal(frame_rows[1].name, "name_box", "original box preserved below anchor")
H.assert_equal(badge_calls[1].text, "PSA 10", "graded badge text")
H.assert_equal(frame_rows[2].nodes[1].text, "PSA 10", "badge row appended inside frame")

local raw_card = { grdl_record = { status = "raw" }, children = {} }
local raw_popup = env.ui_def.card_h_popup(raw_card)
H.assert_equal(#raw_popup.nodes[1].nodes, 1, "raw card gets no slab anchor")
H.assert_equal(badge_calls[2].text, "grdl_k_badge_ungraded", "ungraded badge uses localization key")

local plain_popup = env.ui_def.card_h_popup({ children = {} })
H.assert_equal(#plain_popup.nodes[1].nodes, 1, "non binder card untouched")
H.assert_equal(#badge_calls, 2, "non binder card gets no badge")

local uibox_args = nil
_G.UIBox = function(args)
    uibox_args = args
    return {
        align_to_major = function() end
    }
end

local anchor_element = { config = anchor.config, children = {} }
funcs.grdl_show_slab(anchor_element)
H.assert_true(anchor_element.children.info ~= nil, "slab uibox attached to anchor")
H.assert_equal(anchor_element.config.ref_table, nil, "anchor ref table consumed")
H.assert_equal(uibox_args.config.align, "tm", "slab floats above the tooltip")
H.assert_equal(uibox_args.config.parent, anchor_element, "slab parented to anchor element")
H.assert_equal(uibox_args.definition.n, "ROOT", "slab definition wrapped in clear root")
H.assert_equal(uibox_args.definition.nodes[1].config.colour, _G.G.C.RED, "wrapped root carries the red slab box")

funcs.grdl_show_slab(anchor_element)
H.assert_true(anchor_element.children.info ~= nil, "second call is a no-op")

_G.UIBox = nil
_G.create_badge = nil
_G.G = previous_g

print("slab ui tests ok")
