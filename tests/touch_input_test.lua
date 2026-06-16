local H = dofile("tests/test_helper.lua")

local TouchInput = dofile("src/ui/touch_input.lua")

local previous_g = rawget(_G, "G")
local previous_love = rawget(_G, "love")

local now = 10
_G.love = {
    system = { getOS = function() return "Android" end },
    timer = { getTime = function() return now end }
}

local record_card = { grdl_record = { id = "grdl_touch_1" } }
local inspected_record = nil
local namespace = {
    BinderUI = {
        inspect_from_card = function(_, card)
            inspected_record = card
            return { ok = true }
        end
    }
}

_G.G = {
    CONTROLLER = {
        HID = { touch = true },
        is_cursor_down = true,
        hovering = { target = record_card },
        cursor_down = { target = record_card }
    }
}

local first = TouchInput.touchpressed(namespace, "finger2", 100, 100)
H.assert_equal(first, false, "first external tap only arms the gesture")
H.assert_equal(inspected_record, nil, "first tap does not inspect")

now = now + 0.12
local second = TouchInput.touchpressed(namespace, "finger2", 104, 104)
H.assert_equal(second, true, "second external tap opens inspect")
H.assert_equal(inspected_record, record_card, "record target opens through BinderUI")

now = now + 1
inspected_record = nil
_G.love.system.getOS = function() return "Windows" end
local ignored_desktop = TouchInput.touchpressed(namespace, "finger2", 100, 100)
H.assert_equal(ignored_desktop, false, "desktop touch hook is ignored")
H.assert_equal(inspected_record, nil, "desktop does not inspect")

now = now + 1
_G.love.system.getOS = function() return "Android" end
_G.G.CONTROLLER.is_cursor_down = false
local ignored_unheld = TouchInput.touchpressed(namespace, "finger2", 100, 100)
H.assert_equal(ignored_unheld, false, "unheld touch target is ignored")

now = now + 1
local loadout_card = { ability = { grdl_loadout_id = "grdl_loadout_touch" } }
local loadout_id = nil
local overlay_definition = nil
namespace.BinderUI.inspect_loadout = function(_, card_id, opts)
    loadout_id = card_id
    return { close_func = opts and opts.close_func }
end
namespace.BinderUI.create_inspect_definition = function()
    return { n = "inspect" }
end
_G.G = {
    SETTINGS = {},
    FUNCS = {
        overlay_menu = function(args)
            overlay_definition = args.definition
        end
    },
    CONTROLLER = {
        HID = { touch = true },
        is_cursor_down = true,
        hovering = { target = loadout_card },
        cursor_down = { target = loadout_card }
    }
}

TouchInput.touchpressed(namespace, "finger2", 100, 100)
now = now + 0.1
local opened_loadout = TouchInput.touchpressed(namespace, "finger2", 100, 100)
H.assert_equal(opened_loadout, true, "loadout target opens on double tap")
H.assert_equal(loadout_id, "grdl_loadout_touch", "loadout id is routed")
H.assert_equal(_G.G.SETTINGS.paused, true, "loadout inspect pauses before overlay")
H.assert_equal(overlay_definition.n, "inspect", "loadout inspect overlay is shown")

_G.G = previous_g
_G.love = previous_love

print("touch input tests ok")
