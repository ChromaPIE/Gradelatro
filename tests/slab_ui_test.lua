local H = dofile("tests/test_helper.lua")
local SlabUI = dofile("src/ui/slab_ui.lua")

local record = {
    id = "grdl_9",
    center_key = "kino_air_freshener",
    local_key = "air_freshener",
    edition = "negative",
    status = "graded",
    grade = 10,
    cert_number = "000129",
    acquired_year = 2026,
    proficiency = { badge_text = "OG", badge_colour = "00FF80" }
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

local Label = dofile("src/domain/label.lua")
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

local UICommon = dofile("src/ui/ui_common.lua")
_G.G.FONTS[4] = { file = "resources/fonts/GoNotoCJKCore.ttf" }
H.assert_equal(UICommon.noto_regular(), _G.G.FONTS[4], "regular cjk noto found")
_G.G.LANG = { font = _G.G.FONTS[2] }
H.assert_equal(UICommon.noto_bold(), _G.G.FONTS[2], "noto language font preferred for bold")
H.assert_equal(SlabUI.label_font(), _G.G.FONTS[3], "slab label font ignores language font")
_G.G.LANG = { font = _G.G.FONTS[1] }
H.assert_equal(UICommon.noto_bold(), _G.G.FONTS[3], "pixel language font falls back to noto sans bold")
_G.G.FONTS[5] = { file = "resources/fonts/GoNotoCurrent-Bold.ttf" }
H.assert_equal(UICommon.noto_bold(), _G.G.FONTS[5], "universal bold preferred over latin-only bold")
_G.G.FONTS[5] = nil
_G.G.LANG = nil

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

local scaled = SlabUI.slab_box(record, catalog_entry, { scale = 2 })
local scaled_inner = scaled.nodes[1]
H.assert_near(scaled_inner.nodes[1].nodes[1].nodes[1].config.scale, SlabUI.line_scale("2026 MONARCHY") * 2, 0.000001, "scaled label text")
H.assert_near(scaled_inner.nodes[2].config.minw, 0.7, 0.000001, "scaled column gap")
H.assert_near(scaled_inner.nodes[1].nodes[1].config.minh, 0.64, 0.000001, "scaled line height")

local attach_card = { children = {} }
H.assert_equal(SlabUI.attach_above(attach_card, record, catalog_entry), false, "attach without UIBox global is a safe no-op")
H.assert_equal(attach_card.children.grdl_slab, nil, "no slab child without UIBox global")

local attach_args = nil
_G.UIBox = function(args)
    attach_args = args
    return {
        states = { collide = { can = true } },
        remove = function() end
    }
end
H.assert_equal(SlabUI.attach_above(attach_card, record, catalog_entry, { scale = 1.2 }), true, "attach succeeds with UIBox")
H.assert_true(attach_card.children.grdl_slab ~= nil, "slab child stored on card")
H.assert_equal(attach_args.config.align, "tm", "slab mounts above the card")
H.assert_equal(attach_args.config.major, attach_card, "slab follows the card")
H.assert_equal(attach_args.config.instance_type, "POPUP", "slab draws on the popup layer")
H.assert_equal(attach_args.definition.n, "ROOT", "slab wrapped in clear root")
H.assert_equal(attach_args.definition.nodes[1].config.colour, _G.G.C.RED, "wrapped root carries the red slab box")
H.assert_equal(attach_card.children.grdl_slab.states.collide.can, false, "slab does not catch the cursor")
H.assert_equal(SlabUI.attach_above(attach_card, record, catalog_entry), false, "second attach is a no-op")

local previous_room = _G.G.ROOM
_G.G.ROOM = { T = { x = 0, y = 0, w = 10, h = 10 } }
local overflow_attach_args = nil
_G.UIBox = function(args)
    overflow_attach_args = args
    local box = {
        config = args.config,
        states = { collide = { can = true } },
        T = { x = 8, y = -0.4, w = 2.4, h = 1.1 },
        remove = function() end
    }
    function box:set_alignment(args2)
        self.last_alignment = args2
        self.config.align = args2.type
        self.config.offset = args2.offset
    end
    function box:align_to_major()
        self.aligned_to_major = (self.aligned_to_major or 0) + 1
    end
    return box
end
local right_edge_card = { children = {}, T = { x = 8.2, y = 0.1, w = 1.0, h = 1.4 } }
H.assert_equal(SlabUI.attach_above(right_edge_card, record, catalog_entry), true, "overflowing slab still attaches")
H.assert_equal(right_edge_card.children.grdl_slab.last_alignment.type, "cl", "top overflow near right edge moves slab to the left side")
H.assert_equal(right_edge_card.children.grdl_slab.last_alignment.offset.x, -0.03, "left side slab uses vanilla infotip offset")
H.assert_true((right_edge_card.children.grdl_slab.aligned_to_major or 0) > 0, "adaptive slab realigns through UIBox")
H.assert_equal(overflow_attach_args.config.align, "cl", "stored slab config follows adaptive alignment")
_G.G.ROOM = previous_room
_G.UIBox = nil

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
H.assert_equal(badge_calls[2].text, "OG", "custom badge text")
H.assert_near(badge_calls[2].badge_col[1], 0, 0.001, "custom badge red channel")
H.assert_near(badge_calls[2].badge_col[2], 1, 0.001, "custom badge green channel")
H.assert_near(badge_calls[2].badge_col[3], 0.502, 0.001, "custom badge blue channel")
H.assert_equal(frame_rows[2].nodes[1].text, "PSA 10", "badge row appended inside frame")
H.assert_equal(frame_rows[2].nodes[2].text, "OG", "custom badge appended inside tooltip badge row")

local raw_card = { grdl_record = { status = "raw" }, children = {} }
local raw_popup = env.ui_def.card_h_popup(raw_card)
H.assert_equal(#raw_popup.nodes[1].nodes, 1, "raw card gets no slab anchor")
H.assert_equal(badge_calls[3].text, "grdl_k_badge_ungraded", "ungraded badge uses localization key")

local plain_popup = env.ui_def.card_h_popup({ children = {} })
H.assert_equal(#plain_popup.nodes[1].nodes, 1, "non binder card untouched")
H.assert_equal(#badge_calls, 3, "non binder card gets no badge")

local whole_tooltip_namespace = {
    binder_hover_index = { kino_air_freshener = catalog_entry }
}
local whole_tooltip_funcs = {}
local hover_card_class = {}
function hover_card_class:align_h_popup()
    local direction = self.base_popup_direction or "tm"
    return {
        type = direction,
        align = direction,
        offset = {
            x = (direction == "cl" and -0.05) or (direction == "cr" and 0.05) or 0,
            y = direction == "tm" and -0.13 or direction == "bm" and 0.1 or 0
        },
        parent = self,
        major = self
    }
end
local hover_node = {}
local hover_node_calls = 0
local whole_tooltip_badge_text_node = nil
local whole_tooltip_badge_text_object = nil
function hover_node.hover(card)
    hover_node_calls = hover_node_calls + 1
    local column = card.config.h_popup.nodes[1].nodes
    local popup_box
    local anchor = {
        config = column[1].config,
        children = {},
        T = { x = 8.1, y = -0.2, w = 1.0, h = 0.4 },
        VT = { x = 8.1, y = -0.2, w = 1.0, h = 0.4 }
    }
    whole_tooltip_badge_text_object = {
        config = {},
        states = { hover = { is = false } },
        T = { x = 7.9, y = -0.1, w = 0.5, h = 0.2 },
        VT = { x = 7.9, y = -0.1, w = 0.5, h = 0.2 }
    }
    function whole_tooltip_badge_text_object:hard_set_T(x, y, w, h)
        self.T.x, self.T.y, self.T.w, self.T.h = x, y, w, h
        self.VT.x, self.VT.y, self.VT.w, self.VT.h = x, y, w, h
    end
    function whole_tooltip_badge_text_object:move_with_major() self.moved_with_major = true end
    function whole_tooltip_badge_text_object:align_to_major() self.aligned_to_major = true end
    whole_tooltip_badge_text_node = {
        config = { object = whole_tooltip_badge_text_object },
        children = {},
        T = { x = 7.9, y = -0.1, w = 0.5, h = 0.2 },
        VT = { x = 7.9, y = -0.1, w = 0.5, h = 0.2 }
    }
    popup_box = {
        config = card.config.h_popup_config,
        states = { collide = { can = true }, drag = { can = false } },
        T = { x = 7.4, y = -0.25, w = 2.5, h = 1.3 },
        VT = { x = 7.4, y = -0.25, w = 2.5, h = 1.3 },
        UIRoot = { children = { anchor, whole_tooltip_badge_text_node } }
    }
    function popup_box:set_alignment(args2)
        self.last_alignment = args2
        self.config.type = args2.type
        self.config.align = args2.type
        self.config.offset = args2.offset
    end
    function popup_box:align_to_major()
        self.aligned_to_major = (self.aligned_to_major or 0) + 1
        if self.last_alignment and self.last_alignment.type == "cl" then
            self.T.x = self.last_alignment.major.T.x - self.T.w + self.last_alignment.offset.x
            self.T.y = self.last_alignment.major.T.y + 0.2
        end
    end
    function anchor:move_with_major()
        self.T.x = popup_box.T.x + 0.7
        self.T.y = popup_box.T.y + 0.05
        self.VT.x = self.T.x
        self.VT.y = self.T.y
    end
    function whole_tooltip_badge_text_node:move_with_major()
        self.T.x = popup_box.T.x + 1.2
        self.T.y = popup_box.T.y + 0.4
    end
    anchor.UIBox = popup_box
    card.children.h_popup = popup_box
end
local whole_tooltip_env = {
    ui_def = {
        card_h_popup = function()
            return fake_popup()
        end
    },
    funcs = whole_tooltip_funcs,
    node = hover_node,
    card = hover_card_class
}
H.assert_equal(SlabUI.install(whole_tooltip_namespace, whole_tooltip_env), true, "install wraps hover for whole tooltip positioning")
local previous_whole_tooltip_room = _G.G.ROOM
_G.G.ROOM = { T = { x = 0, y = 0, w = 10, h = 10 } }
local whole_tooltip_uibox_calls = 0
local whole_tooltip_slab = nil
local whole_tooltip_slab_child = nil
local whole_tooltip_next_slab_y = -0.35
_G.UIBox = function(args)
    whole_tooltip_uibox_calls = whole_tooltip_uibox_calls + 1
    whole_tooltip_slab_child = {
        T = { x = 8.1, y = whole_tooltip_next_slab_y, w = 2.2, h = 1.0 },
        VT = { x = 8.1, y = whole_tooltip_next_slab_y, w = 2.2, h = 1.0 },
        children = {}
    }
    whole_tooltip_slab = {
        config = args.config,
        children = {},
        T = { x = 8.1, y = whole_tooltip_next_slab_y, w = 2.2, h = 1.0 },
        VT = { x = 8.1, y = whole_tooltip_next_slab_y, w = 2.2, h = 1.0 },
        UIRoot = { children = { whole_tooltip_slab_child } },
        align_to_major = function(self)
            self.aligned_to_major = (self.aligned_to_major or 0) + 1
            self.last_parent_x = self.config.parent.T.x
            self.last_parent_y = self.config.parent.T.y
        end,
        move_with_major = function(self)
            self.moved_with_major = (self.moved_with_major or 0) + 1
            self.T.x = self.config.parent.T.x
            self.T.y = self.config.parent.T.y - 0.04
        end
    }
    function whole_tooltip_slab_child:move_with_major()
        self.T.x = whole_tooltip_slab.T.x
        self.T.y = whole_tooltip_slab.T.y
    end
    function whole_tooltip_slab_child:align_to_major()
        self.aligned_to_major = (self.aligned_to_major or 0) + 1
    end
    function whole_tooltip_slab:initialize_VT()
        if self.UIRoot and self.UIRoot.initialize_VT then
            self.UIRoot:initialize_VT()
        end
    end
    return whole_tooltip_slab
end
local hover_card = {
    grdl_record = record,
    children = {},
    config = {},
    T = { x = 8.2, y = 1.2, w = 1.0, h = 1.4 }
}
setmetatable(hover_card, { __index = hover_card_class })
hover_card.config.h_popup = whole_tooltip_env.ui_def.card_h_popup(hover_card)
hover_card.config.h_popup_config = hover_card:align_h_popup()
whole_tooltip_env.node.hover(hover_card)
H.assert_equal(hover_node_calls, 1, "original node hover still runs once")
H.assert_equal(whole_tooltip_uibox_calls, 1, "slab anchor is resolved during hover")
H.assert_true(hover_card.children.h_popup.last_alignment ~= nil, "hover popup realigns before the first update tick")
H.assert_equal(hover_card.children.h_popup.last_alignment.type, "cl", "top overflowing slab moves the whole tooltip to the side")
H.assert_equal(hover_card.children.h_popup.last_alignment.offset.x, -0.03, "whole tooltip uses the slab side offset")
H.assert_near(hover_card.children.h_popup.VT.x, hover_card.children.h_popup.T.x, 0.000001, "whole tooltip visual position snaps to the side")
H.assert_true(whole_tooltip_slab.last_parent_x < 7, "slab realigns against the moved tooltip anchor")
H.assert_near(whole_tooltip_slab_child.VT.x, whole_tooltip_slab.T.x, 0.000001, "slab label contents snap with the moved slab")
H.assert_near(whole_tooltip_badge_text_object.VT.x, whole_tooltip_badge_text_node.T.x, 0.000001, "badge text object snaps with the moved tooltip node")
hover_card.children.h_popup:set_alignment(hover_card:align_h_popup())
H.assert_equal(hover_card.children.h_popup.last_alignment.type, "cl", "next card move keeps the slab overflow side alignment")

local side_hover_card = {
    grdl_record = record,
    children = {},
    config = {},
    base_popup_direction = "cl",
    T = { x = 8.2, y = 1.2, w = 1.0, h = 1.4 }
}
setmetatable(side_hover_card, { __index = hover_card_class })
side_hover_card.config.h_popup = whole_tooltip_env.ui_def.card_h_popup(side_hover_card)
side_hover_card.config.h_popup_config = side_hover_card:align_h_popup()
whole_tooltip_env.node.hover(side_hover_card)
H.assert_equal(side_hover_card.children.h_popup.last_alignment, nil, "pre-side vanilla tooltip alignment is not changed")
H.assert_equal(whole_tooltip_slab.config.align, "cl", "left-side tooltip keeps the slab on the left side")
H.assert_equal(whole_tooltip_slab.config.parent, side_hover_card.children.h_popup, "left-side slab follows the tooltip box")

local right_side_hover_card = {
    grdl_record = record,
    children = {},
    config = {},
    base_popup_direction = "cr",
    T = { x = 1.0, y = 1.2, w = 1.0, h = 1.4 }
}
setmetatable(right_side_hover_card, { __index = hover_card_class })
right_side_hover_card.config.h_popup = whole_tooltip_env.ui_def.card_h_popup(right_side_hover_card)
right_side_hover_card.config.h_popup_config = right_side_hover_card:align_h_popup()
whole_tooltip_env.node.hover(right_side_hover_card)
H.assert_equal(right_side_hover_card.children.h_popup.last_alignment, nil, "right-side vanilla tooltip alignment is not changed")
H.assert_equal(whole_tooltip_slab.config.align, "cr", "right-side tooltip keeps the slab on the right side")
H.assert_equal(whole_tooltip_slab.config.parent, right_side_hover_card.children.h_popup, "right-side slab follows the tooltip box")

whole_tooltip_next_slab_y = 2.15
local below_hover_card = {
    grdl_record = record,
    children = {},
    config = {},
    base_popup_direction = "bm",
    T = { x = 8.2, y = 1.2, w = 1.0, h = 1.4 }
}
setmetatable(below_hover_card, { __index = hover_card_class })
below_hover_card.config.h_popup = whole_tooltip_env.ui_def.card_h_popup(below_hover_card)
below_hover_card.config.h_popup_config = below_hover_card:align_h_popup()
whole_tooltip_env.node.hover(below_hover_card)
H.assert_true(below_hover_card.children.h_popup.last_alignment ~= nil, "below-card slab overlap realigns the whole tooltip")
H.assert_equal(below_hover_card.children.h_popup.last_alignment.type, "cl", "below-card slab overlap moves the tooltip to a side")
below_hover_card.children.h_popup:set_alignment(below_hover_card:align_h_popup())
H.assert_equal(below_hover_card.children.h_popup.last_alignment.type, "cl", "below-card slab overlap keeps the side alignment on later movement")

whole_tooltip_next_slab_y = 0.1
local popup_only_overflow_card = {
    grdl_record = record,
    children = {},
    config = {},
    T = { x = 8.2, y = 1.2, w = 1.0, h = 1.4 }
}
setmetatable(popup_only_overflow_card, { __index = hover_card_class })
popup_only_overflow_card.config.h_popup = whole_tooltip_env.ui_def.card_h_popup(popup_only_overflow_card)
popup_only_overflow_card.config.h_popup_config = popup_only_overflow_card:align_h_popup()
whole_tooltip_env.node.hover(popup_only_overflow_card)
H.assert_equal(popup_only_overflow_card.children.h_popup.last_alignment, nil, "popup top overflow alone does not side-align the tooltip")
_G.G.ROOM = previous_whole_tooltip_room
_G.UIBox = nil

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

local previous_tooltip_room = _G.G.ROOM
_G.G.ROOM = { T = { x = 0, y = 0, w = 10, h = 10 } }
local overflow_anchor = {
    config = { ref_table = { SlabUI.slab_box(record, catalog_entry) } },
    children = {},
    T = { x = 8.1, y = 0.05, w = 0.8, h = 0.5 }
}
_G.UIBox = function(args)
    local box = {
        config = args.config,
        T = { x = 8.1, y = -0.35, w = 2.2, h = 1.0 }
    }
    function box:set_alignment(args2)
        self.last_alignment = args2
        self.config.align = args2.type
        self.config.offset = args2.offset
    end
    function box:align_to_major()
        self.aligned_to_major = (self.aligned_to_major or 0) + 1
    end
    return box
end
funcs.grdl_show_slab(overflow_anchor)
H.assert_equal(overflow_anchor.children.info.last_alignment.type, "cl", "overflowing tooltip slab moves to a side")
H.assert_equal(overflow_anchor.children.info.last_alignment.offset.x, -0.03, "tooltip slab side offset follows vanilla infotip")
_G.G.ROOM = previous_tooltip_room
_G.UIBox = nil

-- ===== proficiency info box and tooltip tint =====
local tooltip_border_colour = { 0, 0, 0, 1 }
local tooltip_background_colour = { 0.1, 0.1, 0.1, 1 }
local function tinted_popup()
    return { nodes = { { nodes = { {
        config = { colour = { tooltip_border_colour[1], tooltip_border_colour[2], tooltip_border_colour[3], tooltip_border_colour[4] } },
        nodes = { {
            config = { colour = { tooltip_background_colour[1], tooltip_background_colour[2], tooltip_background_colour[3], tooltip_background_colour[4] } },
            nodes = { { name = "name_box" } }
        } }
    } } } } }
end

local prof_funcs = {}
local prof_namespace = { binder_hover_index = {} }
local prof_env = {
    ui_def = { card_h_popup = function() return tinted_popup() end },
    funcs = prof_funcs
}
H.assert_equal(SlabUI.install(prof_namespace, prof_env), true, "fresh namespace installs its own wrap")

local prof_card = {
    children = {},
    ability_UIBox_table = { info = {} },
    grdl_record = {
        id = "grdl_p1",
        status = "graded",
        grade = 9,
        center_key = "kino_air_freshener",
        proficiency = { antes = 13, note = "my note\nsecond line", tooltip_colour = "FF8000" }
    }
}
local prof_popup = prof_env.ui_def.card_h_popup(prof_card)
local prof_column = prof_popup.nodes[1].nodes
H.assert_equal(#prof_column, 2, "anchor and frame only, no custom box appended")
local main_frame = prof_column[2]
local main_background = main_frame.nodes[1]
H.assert_near(main_frame.config.colour[1], tooltip_border_colour[1], 0.001, "tooltip tint preserves border red")
H.assert_near(main_frame.config.colour[2], tooltip_border_colour[2], 0.001, "tooltip tint preserves border green")
H.assert_near(main_frame.config.colour[3], tooltip_border_colour[3], 0.001, "tooltip tint preserves border blue")
H.assert_near(main_background.config.colour[1], 1, 0.001, "tooltip tint changes background red")
H.assert_near(main_background.config.colour[2], 0.502, 0.001, "tooltip tint changes background green")
H.assert_near(main_background.config.colour[3], 0, 0.001, "tooltip tint changes background blue")
H.assert_equal(#prof_card.ability_UIBox_table.info, 2, "inscription and proficiency entries injected")
local inscription_box = prof_card.ability_UIBox_table.info[1]
local info_box = prof_card.ability_UIBox_table.info[2]
H.assert_equal(inscription_box.grdl_inscription, true, "inscription entry inserted first")
H.assert_equal(inscription_box.name, nil, "inscription entry has no title name")
H.assert_equal(inscription_box.grdl_hide_title, true, "inscription entry asks vanilla to skip the title row")
H.assert_equal(info_box.grdl_prof, true, "proficiency entry still tagged for dedupe")
H.assert_equal(info_box.name, "grdl_k_prof_title", "entry named for the vanilla info box title")
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

local tinted = false
local function find_tint(node)
    if type(node) ~= "table" then return end
    if node.config and type(node.config.colour) == "table"
        and node.config.colour[1] == 1 and math.abs((node.config.colour[2] or 0) - 0.502) < 0.01 then
        tinted = true
    end
    for _, child in ipairs(node.nodes or {}) do find_tint(child) end
end
find_tint(prof_popup)
H.assert_true(tinted, "tooltip tinted with the custom colour")

-- in-run loadout joker resolves its record through the namespace
prof_namespace.collection = {
    cards = {
        { id = "grdl_lj1", status = "graded", grade = 8, center_key = "kino_air_freshener", proficiency = { antes = 100, badge_text = "LOAD", badge_colour = "00FF80" } }
    }
}
local loadout_joker = { children = {}, ability_UIBox_table = { info = {} }, ability = { grdl_loadout_id = "grdl_lj1" } }
local joker_popup = prof_env.ui_def.card_h_popup(loadout_joker)
H.assert_equal(#joker_popup.nodes[1].nodes, 1, "loadout joker popup column untouched")
H.assert_equal(#loadout_joker.ability_UIBox_table.info, 1, "loadout joker gets the proficiency entry")
local joker_frame_rows = joker_popup.nodes[1].nodes[1].nodes[1].nodes
H.assert_equal(joker_frame_rows[2].nodes[1].text, "PSA 8", "loadout joker gets PSA badge in tooltip")
H.assert_equal(joker_frame_rows[2].nodes[2].text, "LOAD", "loadout joker gets custom badge in tooltip")
local found_maxed = false
for _, cells in ipairs(loadout_joker.ability_UIBox_table.info[1]) do
    for _, node in ipairs(cells) do
        if node.config and node.config.text == "grdl_k_prof_maxed" then found_maxed = true end
    end
end
H.assert_true(found_maxed, "maxed proficiency shows the mastered key")

-- raw collection card gets neither box nor tint
local raw_prof_card = { children = {}, ability_UIBox_table = { info = {} }, grdl_record = { id = "grdl_p2", status = "raw" } }
prof_env.ui_def.card_h_popup(raw_prof_card)
H.assert_equal(#raw_prof_card.ability_UIBox_table.info, 0, "raw card gets no proficiency entry")

_G.UIBox = nil
_G.create_badge = nil
_G.G = previous_g

print("slab ui tests ok")
