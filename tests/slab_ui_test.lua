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

H.assert_near(SlabUI.line_scale("SHORT", 0.2, 20), 0.2, 0.0001, "short line keeps base scale")
H.assert_near(SlabUI.line_scale("2026 LUCKY JIMBOS: JOKER PACK", 0.2, 20), 0.2 * 20 / 29, 0.0001, "long line shrinks")

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

local definition = SlabUI.slab_definition(record, catalog_entry)
H.assert_equal(definition.n, "ROOT", "slab definition is a root node")
H.assert_equal(definition.config.colour, _G.G.C.RED, "slab frame is red")
H.assert_equal(#definition.nodes[1].nodes, 4, "slab has four label lines")
local first_text = definition.nodes[1].nodes[1].nodes[1].nodes[1]
H.assert_equal(first_text.config.font, _G.G.FONTS[3], "label text forced to noto sans")

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

local hover_count = 0
local stop_count = 0
local card_class = {}
function card_class.hover(self)
    hover_count = hover_count + 1
end
function card_class.stop_hover(self)
    stop_count = stop_count + 1
end
function card_class.align_h_popup(self)
    return { type = "tm", offset = { x = 0, y = -0.1 } }
end

local env = {
    ui_def = {
        card_h_popup = function()
            return fake_popup()
        end
    },
    card_class = card_class
}

H.assert_equal(SlabUI.install(namespace, env), true, "install wraps environment")
local wrapped_popup = env.ui_def.card_h_popup
H.assert_equal(SlabUI.install(namespace, env), true, "second install is a no-op")
H.assert_equal(env.ui_def.card_h_popup, wrapped_popup, "wrapper not double wrapped")

local graded_card = { grdl_record = record, children = {} }
local popup = env.ui_def.card_h_popup(graded_card)
local inner_rows = popup.nodes[1].nodes[1].nodes[1].nodes
H.assert_equal(#inner_rows, 2, "badge row appended to popup")
H.assert_equal(badge_calls[1].text, "PSA 10", "graded badge text")

local raw_card = { grdl_record = { status = "raw" }, children = {} }
env.ui_def.card_h_popup(raw_card)
H.assert_equal(badge_calls[2].text, "grdl_k_badge_ungraded", "ungraded badge uses localization key")

local plain_popup = env.ui_def.card_h_popup({ children = {} })
H.assert_equal(#plain_popup.nodes[1].nodes[1].nodes[1].nodes, 1, "non binder card untouched")

local lifted = card_class.align_h_popup(graded_card)
H.assert_true(lifted.offset.y < -0.5, "tooltip lifted above slab for graded card")
H.assert_equal(card_class.align_h_popup(raw_card).offset.y, -0.1, "raw card tooltip not lifted")

card_class.hover(graded_card)
H.assert_equal(hover_count, 1, "original hover still runs")
H.assert_true(graded_card.children.grdl_slab == nil, "slab attach skipped without UIBox global")

local removed = 0
graded_card.children.grdl_slab = {
    remove = function()
        removed = removed + 1
    end
}
card_class.stop_hover(graded_card)
H.assert_equal(stop_count, 1, "original stop hover still runs")
H.assert_equal(removed, 1, "slab removed on stop hover")
H.assert_equal(graded_card.children.grdl_slab, nil, "slab reference cleared")

_G.create_badge = nil
_G.G = previous_g

print("slab ui tests ok")
