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

local SLEEVE_SCALE = 0.55
local SLEEVE_OFFSET = { x = 0.08, y = 1.6 }

function CarryUI.on_run_start(namespace)
    local runtime = rawget(_G, "G")
    if not namespace or not namespace.collection or not runtime or not runtime.GAME then return end
    local run_id = Carry.run_identity(runtime.GAME)
    Carry.reconcile(namespace.collection, run_id)
    Carry.bind_run(namespace.collection, run_id)
    CarryUI.build_sleeve(namespace)
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
    CarryUI.build_sleeve(namespace)

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
    else
        Carry.mark_lost(namespace.collection, { reason = "run_loss" })
        namespace.last_save_ok = Persistence.save(namespace)
    end
    CarryUI.build_sleeve(namespace)
end

function CarryUI.build_sleeve(namespace)
    local runtime = rawget(_G, "G")
    if not runtime or not runtime.HUD or not rawget(_G, "UIBox") then return false end

    if runtime.HUD.children.grdl_sleeve then
        runtime.HUD.children.grdl_sleeve:remove()
        runtime.HUD.children.grdl_sleeve = nil
    end

    local info = namespace and namespace.collection and Carry.sleeve_info(namespace.collection) or nil
    if not info then return false end
    local active = runtime.GAME and runtime.GAME.grdl_carry_active or nil

    local nodes = {}
    if not active and rawget(_G, "CardArea") and rawget(_G, "Card")
        and runtime.P_CENTERS and runtime.P_CENTERS[info.center_key] then
        local width = SLEEVE_SCALE * runtime.CARD_W
        local height = SLEEVE_SCALE * runtime.CARD_H
        local area = CardArea(0, 0, width, height, { card_limit = 1, type = "title", highlight_limit = 0, collection = true })
        local card = Card(0, 0, width, height, (runtime.P_CARDS and runtime.P_CARDS.empty or nil), runtime.P_CENTERS[info.center_key])
        local flags = Catalog.edition_flags(info.edition)
        if flags then card:set_edition(flags, true, true) end
        if card.states and card.states.collide then card.states.collide.can = false end
        area:emplace(card)
        nodes[#nodes + 1] = { n = runtime.UIT.R, config = { align = "cm", padding = 0.03 }, nodes = {
            { n = runtime.UIT.O, config = { object = area } }
        } }
    end

    nodes[#nodes + 1] = { n = runtime.UIT.R, config = { align = "cm", padding = 0.03 }, nodes = {
        UIBox_button({
            button = "grdl_carry_activate",
            label = { UICommon.localize_text(active and "grdl_k_carry_active" or "grdl_b_activate_carry") },
            minw = 1.2,
            maxw = 1.2,
            minh = 0.45,
            scale = 0.26,
            colour = active and runtime.C.GREY or runtime.C.GOLD,
            focus_args = { nav = "wide" }
        })
    } }

    runtime.HUD.children.grdl_sleeve = UIBox({
        definition = { n = runtime.UIT.ROOT, config = { align = "cm", colour = runtime.C.CLEAR, padding = 0.04, r = 0.08 }, nodes = nodes },
        config = {
            align = "cr",
            offset = { x = SLEEVE_OFFSET.x, y = SLEEVE_OFFSET.y },
            major = runtime.HUD,
            bond = "Strong",
            parent = runtime.HUD
        }
    })
    return true
end

function CarryUI.install(namespace, env)
    env = env or {}
    if not namespace then return false end
    if namespace.carry_hooks_installed then return true end

    local funcs = env.funcs or (rawget(_G, "G") and G.FUNCS) or nil
    if not funcs then return false end

    funcs.grdl_carry_activate = function(event)
        local result = CarryUI.activate(namespace)
        if not result.ok and rawget(_G, "play_sound") then
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
