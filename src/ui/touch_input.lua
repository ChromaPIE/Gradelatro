local TouchInput = {}

local DOUBLE_TAP_SECONDS = 0.35
local COOLDOWN_SECONDS = 0.6

local function now_seconds()
    local love_obj = rawget(_G, "love")
    if love_obj and love_obj.timer and type(love_obj.timer.getTime) == "function" then
        local ok, value = pcall(love_obj.timer.getTime)
        if ok and type(value) == "number" then return value end
    end
    return os.clock()
end

function TouchInput.is_mobile(runtime, love_obj)
    runtime = runtime or rawget(_G, "G")
    if runtime and runtime.F_MOBILE_UI then return true end
    love_obj = love_obj or rawget(_G, "love")
    local get_os = love_obj and love_obj.system and love_obj.system.getOS or nil
    if type(get_os) ~= "function" then return false end
    local ok, os_name = pcall(get_os)
    return ok and (os_name == "Android" or os_name == "iOS")
end

local function inspectable_target(target)
    if type(target) ~= "table" then return nil end
    if target.grdl_record or target.grdl_offer then return target end
    if target.ability and target.ability.grdl_loadout_id then return target end
    return nil
end

function TouchInput.held_target(runtime)
    runtime = runtime or rawget(_G, "G")
    local controller = runtime and runtime.CONTROLLER or nil
    if not controller or not controller.HID or not controller.HID.touch then return nil end
    if not controller.is_cursor_down then return nil end
    return inspectable_target(
        controller.hovering and controller.hovering.target
        or controller.cursor_down and controller.cursor_down.target
        or nil
    )
end

function TouchInput.open_target(namespace, target)
    if not namespace or not target then return false end
    local binder_ui = namespace.BinderUI
    if not binder_ui then return false end

    if target.grdl_record and binder_ui.inspect_from_card then
        return binder_ui.inspect_from_card(namespace, target) ~= nil
    end
    if target.grdl_offer and binder_ui.inspect_offer then
        return binder_ui.inspect_offer(namespace, target.grdl_offer) ~= nil
    end
    if target.ability and target.ability.grdl_loadout_id and binder_ui.inspect_loadout then
        local runtime = rawget(_G, "G")
        local state = binder_ui.inspect_loadout(namespace, target.ability.grdl_loadout_id, {
            close_func = "exit_overlay_menu"
        })
        if state and runtime and runtime.FUNCS and runtime.FUNCS.overlay_menu
            and binder_ui.create_inspect_definition then
            if runtime.SETTINGS then runtime.SETTINGS.paused = true end
            runtime.FUNCS.overlay_menu({
                definition = binder_ui.create_inspect_definition(namespace)
            })
        end
        return state ~= nil
    end
    return false
end

function TouchInput.touchpressed(namespace, id, x, y)
    local runtime = rawget(_G, "G")
    if not TouchInput.is_mobile(runtime) then return false end

    local target = TouchInput.held_target(runtime)
    if not target then return false end

    local state = namespace.touch_input_state or {}
    namespace.touch_input_state = state

    local now = now_seconds()
    if state.cooldown_until and now < state.cooldown_until then return false end

    if state.target ~= target or not state.last_tap_at or now - state.last_tap_at > DOUBLE_TAP_SECONDS then
        state.target = target
        state.last_tap_at = now
        state.tap_count = 1
        return false
    end

    state.last_tap_at = now
    state.tap_count = (state.tap_count or 1) + 1
    if state.tap_count < 2 then return false end

    state.tap_count = 0
    state.cooldown_until = now + COOLDOWN_SECONDS
    return TouchInput.open_target(namespace, target)
end

return TouchInput
