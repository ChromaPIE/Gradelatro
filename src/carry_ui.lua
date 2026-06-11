local CarryUI = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Carry = load_src("carry.lua")
local Catalog = load_src("catalog.lua")
local Persistence = load_src("persistence.lua")
local UICommon = load_src("ui_common.lua")

local PEEK_VISIBLE_FRACTION = 1 / 3
local GLIDE_DELAY = 0.35

function CarryUI.on_run_start(namespace)
    local runtime = rawget(_G, "G")
    if not namespace or not namespace.collection or not runtime or not runtime.GAME then return end
    local run_id = Carry.run_identity(runtime.GAME)
    Carry.reconcile(namespace.collection, run_id)
    Carry.bind_run(namespace.collection, run_id)
    CarryUI.build_peek(namespace)
end

function CarryUI.can_activate_now(namespace, runtime)
    runtime = runtime or rawget(_G, "G")
    if not namespace or not namespace.collection or not runtime or not runtime.GAME then
        return false, "no_run"
    end
    local collection = namespace.collection
    if not collection.carry then return false, "no_carry" end
    if runtime.GAME.grdl_carry_active then return false, "already_active" end

    local states = runtime.STATES or {}
    if runtime.STATE ~= states.SELECTING_HAND then return false, "not_in_window" end
    local round = runtime.GAME.current_round or {}
    if (round.hands_played or 0) > 0 then return false, "not_in_window" end

    local jokers = runtime.jokers
    if not jokers or #(jokers.cards or {}) >= ((jokers.config or {}).card_limit or 0) then
        return false, "no_joker_slot"
    end

    local gate = Carry.can_activate(collection, {
        run_id = Carry.run_identity(runtime.GAME),
        ante = (runtime.GAME.round_resets or {}).ante or 0
    })
    if not gate.ok then return false, gate.reason end
    return true, gate.ante
end

function CarryUI.activate(namespace, runtime, now)
    runtime = runtime or rawget(_G, "G")
    local ok, ante_or_reason = CarryUI.can_activate_now(namespace, runtime)
    if not ok then return { ok = false, reason = ante_or_reason } end

    local collection = namespace.collection
    local info = Carry.sleeve_info(collection)
    if not info then return { ok = false, reason = "no_carry" } end

    local smods = rawget(_G, "SMODS")
    if not smods or type(smods.add_card) ~= "function" then
        return { ok = false, reason = "spawn_failed" }
    end
    local spawn_args = { key = info.center_key }
    if info.edition ~= "base" then
        spawn_args.edition = "e_" .. info.edition
    else
        spawn_args.no_edition = true
    end
    local spawn_ok, card = pcall(smods.add_card, spawn_args)
    if not spawn_ok or not card then
        return { ok = false, reason = "spawn_failed" }
    end
    card.ability = card.ability or {}
    card.ability.grdl_carry_id = info.card_id

    local used = Carry.apply_use(namespace.config, collection, {
        run_id = info.run_id,
        ante = ante_or_reason,
        now = now or os.time()
    })
    runtime.GAME.grdl_carry_active = info.card_id
    namespace.last_save_ok = Persistence.save(namespace)
    CarryUI.teardown_peek(namespace)

    return { ok = true, card = card, wear = used }
end

function CarryUI.settle_blind(namespace, runtime)
    runtime = runtime or rawget(_G, "G")
    if not namespace or not namespace.collection or not runtime or not runtime.GAME then return end
    local active_id = runtime.GAME.grdl_carry_active
    if not active_id then return end
    runtime.GAME.grdl_carry_active = nil

    local jokers = runtime.jokers
    local found = nil
    for _, card in ipairs((jokers and jokers.cards) or {}) do
        if card.ability and card.ability.grdl_carry_id == active_id then
            found = card
            break
        end
    end

    if found then
        if jokers.remove_card then jokers:remove_card(found) end
        if found.remove then found:remove() end
        CarryUI.build_peek(namespace)
    else
        Carry.mark_lost(namespace.collection, { reason = "run_loss" })
        namespace.last_save_ok = Persistence.save(namespace)
        CarryUI.teardown_peek(namespace)
    end
end

local function remove_from_list(list, item)
    for index, value in ipairs(list or {}) do
        if value == item then
            table.remove(list, index)
            return true
        end
    end
    return false
end

function CarryUI.teardown_peek(namespace)
    local peek = namespace and namespace.carry_peek or nil
    if not peek then return false end
    namespace.carry_peek = nil
    local runtime = rawget(_G, "G")
    if runtime and runtime.I then
        remove_from_list(runtime.I.POPUP, peek.area)
    end
    if peek.card then
        pcall(function() peek.card:remove() end)
    end
    if peek.area then
        pcall(function() peek.area:remove() end)
    end
    return true
end

function CarryUI.build_peek(namespace)
    local runtime = rawget(_G, "G")
    if not runtime or not rawget(_G, "CardArea") or not rawget(_G, "Card") or not rawget(_G, "UIBox") then return false end
    if not runtime.ROOM or not runtime.P_CENTERS then return false end

    CarryUI.teardown_peek(namespace)

    local info = namespace and namespace.collection and Carry.sleeve_info(namespace.collection) or nil
    if not info then return false end
    if runtime.GAME and runtime.GAME.grdl_carry_active then return false end
    local center = runtime.P_CENTERS[info.center_key]
    if not center then return false end

    local home_x = runtime.ROOM.T.x + runtime.ROOM.T.w * 0.18
    local home_y = runtime.ROOM.T.h - PEEK_VISIBLE_FRACTION * runtime.CARD_H
    local area = CardArea(home_x, home_y, runtime.CARD_W, runtime.CARD_H,
        { card_limit = 1, type = "title", highlight_limit = 0, collection = false })
    if runtime.I then
        remove_from_list(runtime.I.CARDAREA, area)
        table.insert(runtime.I.POPUP, area)
    end

    local card = Card(home_x, home_y, runtime.CARD_W, runtime.CARD_H, (runtime.P_CARDS and runtime.P_CARDS.empty or nil), center)
    local flags = Catalog.edition_flags(info.edition)
    if flags then card:set_edition(flags, true, true) end
    card.click = function(self)
        self.highlighted = not self.highlighted
        if self.juice_up then self:juice_up(0.3, 0.3) end
    end
    area:emplace(card)

    card.children.use_button = UIBox({
        definition = { n = runtime.UIT.ROOT, config = { align = "cm", colour = runtime.C.CLEAR, padding = 0.03 }, nodes = {
            UICommon.outline_button({
                button = "grdl_carry_activate",
                minw = 1.3,
                minh = 0.55,
                lines = { { text = UICommon.localize_text("grdl_b_activate_carry"), scale = 0.3 } }
            })
        } },
        config = { align = "tm", offset = { x = 0, y = -0.08 }, major = card, bond = "Strong", parent = card }
    })

    namespace.carry_peek = { area = area, card = card }
    return true
end

local function glide_and_activate(namespace, runtime)
    local peek = namespace.carry_peek
    if peek and peek.card then
        peek.card.highlighted = false
        if peek.card.states and peek.card.states.drag then peek.card.states.drag.can = false end
        if runtime.jokers and runtime.jokers.T and peek.area then
            peek.area.T.x = runtime.jokers.T.x + runtime.jokers.T.w / 2 - runtime.CARD_W / 2
            peek.area.T.y = runtime.jokers.T.y
        end
    end
    local function finish()
        CarryUI.teardown_peek(namespace)
        CarryUI.activate(namespace)
    end
    if runtime.E_MANAGER and rawget(_G, "Event") then
        runtime.E_MANAGER:add_event(Event({
            trigger = "after",
            delay = GLIDE_DELAY,
            func = function()
                finish()
                return true
            end
        }))
    else
        finish()
    end
end

function CarryUI.install(namespace, env)
    env = env or {}
    if not namespace then return false end
    if namespace.carry_hooks_installed then return true end

    local funcs = env.funcs or (rawget(_G, "G") and G.FUNCS) or nil
    if not funcs then return false end

    funcs.grdl_carry_activate = function(event)
        local runtime = rawget(_G, "G")
        local ok = CarryUI.can_activate_now(namespace, runtime)
        if ok and runtime then
            glide_and_activate(namespace, runtime)
        elseif rawget(_G, "play_sound") then
            pcall(play_sound, "tarot2", 0.76, 0.4)
        end
    end

    local game_class = env.game_class or rawget(_G, "Game")
    if game_class and type(game_class.start_run) == "function" then
        local original_start = game_class.start_run
        game_class.start_run = function(self, args)
            local result = original_start(self, args)
            pcall(CarryUI.on_run_start, namespace)
            return result
        end
    end

    local original_end = env.end_round or rawget(_G, "end_round")
    if type(original_end) == "function" then
        local wrapped = function(...)
            pcall(CarryUI.settle_blind, namespace)
            return original_end(...)
        end
        if env.end_round then
            env.wrapped_end_round = wrapped
        else
            rawset(_G, "end_round", wrapped)
        end
    end

    namespace.carry_hooks_installed = true
    return true
end

return CarryUI
