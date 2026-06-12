local LoadoutUI = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Catalog = load_src("catalog.lua")
local Condition = load_src("condition.lua")
local Loadout = load_src("loadout.lua")
local Persistence = load_src("persistence.lua")
local Proficiency = load_src("proficiency.lua")
local Storage = load_src("storage.lua")
local UICommon = load_src("ui_common.lua")

local safe_localize = UICommon.localize_text
local ui_text = UICommon.text_node
local row = UICommon.row
local col = UICommon.col

local TRANSPORT_ORDER = { "blue", "green", "red", "purple", "gold" }
local TIER_KEYS = { "grdl_k_tier_1", "grdl_k_tier_2", "grdl_k_tier_3", "grdl_k_tier_4" }

function LoadoutUI.license_label(level)
    if not level or level <= 0 then return safe_localize("grdl_k_license_none") end
    -- composed instead of a #1# variable key: the localize fallback returns
    -- bare keys, which would swallow the tier name in headless contexts
    return safe_localize(TIER_KEYS[Loadout.tier(level)]) .. " X" .. tostring(Loadout.within(level))
end

function LoadoutUI.open(namespace)
    if not namespace or not namespace.collection then return nil end
    local collection = namespace.collection
    Loadout.reconcile(collection)
    local entries = {}
    for _, card_id in ipairs(collection.loadout.card_ids) do
        local card = Storage.find_card(collection, card_id)
        if card then entries[#entries + 1] = card end
    end
    namespace.loadout_ui_state = {
        license = collection.loadout.license,
        capacity = Loadout.capacity(collection.loadout.license),
        entries = entries,
        transports = collection.loadout.transports,
        active_transport = collection.loadout.active_transport,
        feedback = ""
    }
    return namespace.loadout_ui_state
end

local function feedback(namespace, result, ok_key)
    local state = namespace.loadout_ui_state
    if not state then return end
    if result.ok then
        state.feedback = safe_localize(ok_key)
    else
        state.feedback = safe_localize("grdl_k_reason_" .. tostring(result.reason))
    end
end

-- ===== overlay definitions =====

local function loadout_cards_row(namespace, state)
    if #state.entries == 0 or not (rawget(_G, "CardArea") and rawget(_G, "Card") and rawget(_G, "G") and G.P_CENTERS) then
        return row({ ui_text(safe_localize("grdl_k_loadout_empty"), 0.32, G.C.UI.TEXT_INACTIVE) }, { padding = 0.3 })
    end
    local area = CardArea(
        G.ROOM.T.x + 0.2 * G.ROOM.T.w / 2, G.ROOM.T.h,
        3.25 * G.CARD_W, 0.95 * G.CARD_H,
        { card_limit = 3, type = "title", highlight_limit = 0, collection = true })
    for _, entry in ipairs(state.entries) do
        local center = G.P_CENTERS[entry.center_key]
        if center then
            local card = Card(area.T.x + area.T.w / 2, area.T.y, G.CARD_W, G.CARD_H,
                (G.P_CARDS and G.P_CARDS.empty or nil), center)
            UICommon.suppress_selection(card)
            local flags = Catalog.edition_flags(entry.edition)
            if flags then card:set_edition(flags, true, true) end
            card.grdl_record = entry
            area:emplace(card)
        end
    end
    return row({ { n = G.UIT.O, config = { object = area } } }, { padding = 0.05, no_fill = true })
end

function LoadoutUI.create_overlay_definition(namespace)
    namespace = namespace or rawget(_G, "Gradelatro") or {}
    local state = namespace.loadout_ui_state or LoadoutUI.open(namespace)
    if not state then
        return create_UIBox_generic_options({ back_func = "grdl_open_binder", contents = {} })
    end
    local transport_name = state.active_transport
        and safe_localize("grdl_k_transport_" .. state.active_transport)
        or safe_localize("grdl_k_transport_none")
    local rows = {
        row({ ui_text(safe_localize("grdl_k_loadout_title"), 0.55, G.C.WHITE) }),
        row({
            UICommon.stat_chip(LoadoutUI.license_label(state.license)),
            UICommon.stat_chip(safe_localize("grdl_k_capacity", { state.capacity })),
            UICommon.stat_chip(safe_localize("grdl_k_active_transport", { transport_name }))
        }, { padding = 0.09 }),
        loadout_cards_row(namespace, state),
        row({ ui_text(safe_localize("grdl_k_loadout_hint"), 0.27, G.C.UI.TEXT_INACTIVE) }),
        row({
            UIBox_button({
                button = "grdl_open_license",
                label = { safe_localize("grdl_b_license") },
                minw = 2.8,
                maxw = 2.8,
                minh = 0.7,
                scale = 0.34,
                colour = G.C.PURPLE,
                focus_args = { nav = "wide" }
            })
        }, { padding = 0.08 }),
        row({ { n = G.UIT.T, config = { ref_table = state, ref_value = "feedback", scale = 0.3, colour = G.C.GOLD } } })
    }
    return create_UIBox_generic_options({
        back_func = "grdl_open_binder",
        minw = 7.2,
        padding = 0.12,
        colour = G.C.L_BLACK,
        outline_colour = G.C.RED,
        contents = rows
    })
end

local function license_cell(config_table, state, level)
    local owned = state.license >= level
    local next_level = state.license + 1 == level
    local label = LoadoutUI.license_label(level)
    local price = config_table.loadout.license_prices[level]
    if next_level then
        return col({ UICommon.outline_button({
            button = "grdl_license_buy",
            minw = 1.55,
            minh = 0.75,
            lines = {
                { text = label, scale = 0.26 },
                { text = safe_localize("grdl_k_grading_fee", { price }), scale = 0.24, colour = G.C.GOLD }
            }
        }) }, { align = "cm", minw = 1.7 })
    end
    local colour = owned and G.C.GREEN or G.C.UI.TEXT_INACTIVE
    local status = owned and safe_localize("grdl_k_owned") or safe_localize("grdl_k_locked")
    return col({
        row({ ui_text(label, 0.26, colour) }, { padding = 0.01 }),
        row({ ui_text(status, 0.22, colour) }, { padding = 0.01 })
    }, { align = "cm", minw = 1.7 })
end

local function transport_cell(config_table, state, key)
    local transport = config_table.loadout.transports[key]
    local name = safe_localize("grdl_k_transport_" .. key)
    local antes = table.concat(transport.antes, "/")
    if not state.transports[key] then
        return col({ UICommon.outline_button({
            button = "grdl_transport_buy",
            ref = { key = key },
            minw = 1.35,
            minh = 0.85,
            lines = {
                { text = name, scale = 0.25 },
                { text = safe_localize("grdl_k_transport_antes", { antes }), scale = 0.21 },
                { text = safe_localize("grdl_k_grading_fee", { transport.price }), scale = 0.23, colour = G.C.GOLD }
            }
        }) }, { align = "cm", minw = 1.5 })
    end
    if state.active_transport == key then
        return col({
            row({ ui_text(name, 0.25, G.C.GREEN) }, { padding = 0.01 }),
            row({ ui_text(safe_localize("grdl_k_transport_antes", { antes }), 0.21, G.C.GREEN) }, { padding = 0.01 }),
            row({ ui_text(safe_localize("grdl_k_enabled"), 0.22, G.C.GREEN) }, { padding = 0.01 })
        }, { align = "cm", minw = 1.5 })
    end
    return col({ UICommon.outline_button({
        button = "grdl_transport_activate",
        ref = { key = key },
        minw = 1.35,
        minh = 0.85,
        lines = {
            { text = name, scale = 0.25 },
            { text = safe_localize("grdl_k_transport_antes", { antes }), scale = 0.21 },
            { text = safe_localize("grdl_b_enable"), scale = 0.23 }
        }
    }) }, { align = "cm", minw = 1.5 })
end

function LoadoutUI.create_license_definition(namespace)
    namespace = namespace or rawget(_G, "Gradelatro") or {}
    local state = namespace.loadout_ui_state or LoadoutUI.open(namespace)
    if not state then
        return create_UIBox_generic_options({ back_func = "grdl_open_loadout", contents = {} })
    end
    local config_table = namespace.config
    local ladder = {}
    for tier = 1, 4 do
        local cells = { row({ ui_text(safe_localize(TIER_KEYS[tier]), 0.3, G.C.WHITE) }, { padding = 0.02 }) }
        for within = 1, 3 do
            cells[#cells + 1] = row({ license_cell(config_table, state, (tier - 1) * 3 + within) }, { padding = 0.02 })
        end
        ladder[#ladder + 1] = col(cells, { align = "tm", minw = 1.8, padding = 0.03 })
    end
    local transports = {}
    for _, key in ipairs(TRANSPORT_ORDER) do
        transports[#transports + 1] = transport_cell(config_table, state, key)
    end
    local rows = {
        row({ ui_text(safe_localize("grdl_k_license_title"), 0.5, G.C.WHITE) }),
        row(ladder, { padding = 0.04 }),
        row({ ui_text(safe_localize("grdl_k_transport_title"), 0.38, G.C.WHITE) }, { padding = 0.04 }),
        row(transports, { padding = 0.04 }),
        row({ { n = G.UIT.T, config = { ref_table = state, ref_value = "feedback", scale = 0.3, colour = G.C.GOLD } } })
    }
    return create_UIBox_generic_options({
        back_func = "grdl_open_loadout",
        minw = 8.0,
        padding = 0.12,
        colour = G.C.L_BLACK,
        outline_colour = G.C.RED,
        contents = rows
    })
end

-- ===== runtime install =====

local function default_adapter(runtime)
    runtime = runtime or rawget(_G, "G")
    local function show(definition)
        if not runtime or not runtime.FUNCS or not runtime.FUNCS.overlay_menu then return end
        if runtime.SETTINGS then runtime.SETTINGS.paused = true end
        runtime.FUNCS.overlay_menu({ definition = definition })
    end
    return {
        open_loadout = function(namespace) show(LoadoutUI.create_overlay_definition(namespace)) end,
        open_license = function(namespace) show(LoadoutUI.create_license_definition(namespace)) end
    }
end

local function event_key(event)
    return event and event.config and event.config.ref_table and event.config.ref_table.key or nil
end

function LoadoutUI.install_runtime(namespace, runtime, adapter)
    namespace = namespace or rawget(_G, "Gradelatro")
    runtime = runtime or rawget(_G, "G")
    if not namespace or not runtime or not runtime.FUNCS then return false end
    adapter = adapter or default_adapter(runtime)

    runtime.FUNCS.grdl_open_loadout = function(event)
        local state = LoadoutUI.open(namespace)
        if state and adapter.open_loadout then adapter.open_loadout(namespace, state, event) end
    end

    runtime.FUNCS.grdl_open_license = function(event)
        if not namespace.loadout_ui_state then LoadoutUI.open(namespace) end
        if adapter.open_license then adapter.open_license(namespace, namespace.loadout_ui_state, event) end
    end

    local function refresh_license(event)
        if adapter.open_license then adapter.open_license(namespace, namespace.loadout_ui_state, event) end
    end

    local function purchase_handler(action, ok_key)
        return function(event)
            if not namespace.loadout_ui_state then LoadoutUI.open(namespace) end
            local result = action(event)
            if result.ok then
                namespace.last_save_ok = Persistence.save(namespace)
                LoadoutUI.open(namespace)
                feedback(namespace, result, ok_key)
                refresh_license(event)
            else
                feedback(namespace, result, ok_key)
                if rawget(_G, "play_sound") then pcall(play_sound, "tarot2", 0.76, 0.4) end
            end
        end
    end

    runtime.FUNCS.grdl_license_buy = purchase_handler(function()
        return Loadout.purchase_license(namespace.config, namespace.collection)
    end, "grdl_k_license_bought")

    runtime.FUNCS.grdl_transport_buy = purchase_handler(function(event)
        return Loadout.purchase_transport(namespace.config, namespace.collection, event_key(event))
    end, "grdl_k_transport_bought")

    runtime.FUNCS.grdl_transport_activate = purchase_handler(function(event)
        return Loadout.set_active_transport(namespace.collection, event_key(event))
    end, "grdl_k_transport_enabled")

    runtime.FUNCS.grdl_entry_confirm = function(event)
        local area = namespace.loadout_entry_area
        local picked = {}
        for _, card in ipairs((area and area.cards) or {}) do
            if card.highlighted and card.grdl_record then picked[#picked + 1] = card.grdl_record.id end
        end
        if #picked > 0 then
            LoadoutUI.spawn_entries(namespace, picked, os.time())
        end
        namespace.loadout_entry_window = nil
        namespace.loadout_entry_area = nil
        if runtime.FUNCS.exit_overlay_menu then runtime.FUNCS.exit_overlay_menu() end
    end

    runtime.FUNCS.grdl_entry_skip = function(event)
        namespace.loadout_entry_window = nil
        namespace.loadout_entry_area = nil
        if runtime.FUNCS.exit_overlay_menu then runtime.FUNCS.exit_overlay_menu() end
    end

    return true
end

-- ===== run integration =====

function LoadoutUI.on_run_start(namespace)
    local runtime = rawget(_G, "G")
    if not namespace or not namespace.collection or not runtime or not runtime.GAME then return end
    local run_id = Loadout.run_identity(runtime.GAME)
    local existing = runtime.GAME.grdl_loadout
    if not existing or existing.run_id ~= run_id then
        runtime.GAME.grdl_loadout = Loadout.begin_run(namespace.collection, run_id)
    end
end

function LoadoutUI.count_proficiency(namespace, runtime, run_state)
    local changed = false
    for _, card_id in ipairs(run_state.entered or {}) do
        local present = false
        for _, joker in ipairs((runtime.jokers and runtime.jokers.cards) or {}) do
            if joker.ability and joker.ability.grdl_loadout_id == card_id then
                present = true
                break
            end
        end
        if present then
            local card = Storage.find_card(namespace.collection, card_id)
            if card and Proficiency.record_ante(card) then changed = true end
        end
    end
    if changed then namespace.last_save_ok = Persistence.save(namespace) end
end

function LoadoutUI.on_boss_cash_out(namespace)
    local runtime = rawget(_G, "G")
    if not namespace or not namespace.collection or not runtime or not runtime.GAME then return end
    local resets = runtime.GAME.round_resets or {}
    if not resets.blind_states or resets.blind_states.Boss ~= "Defeated" then return end
    local run_state = runtime.GAME.grdl_loadout
    if not run_state then return end
    -- ease_ante has already run by cash-out time, so the beaten ante is one back
    local defeated_ante = (resets.ante or 1) - 1
    if run_state.counted_ante == defeated_ante then return end
    run_state.counted_ante = defeated_ante

    LoadoutUI.count_proficiency(namespace, runtime, run_state)

    local window = Loadout.window(namespace.config, namespace.collection, run_state, defeated_ante)
    if not window then return end
    namespace.loadout_entry_window = window
    if runtime.E_MANAGER and rawget(_G, "Event") then
        runtime.E_MANAGER:add_event(Event({
            trigger = "after",
            delay = 0.7,
            blockable = false,
            func = function()
                pcall(LoadoutUI.open_entry, namespace)
                return true
            end
        }))
    end
end

function LoadoutUI.spawn_entries(namespace, card_ids, now)
    local runtime = rawget(_G, "G")
    local smods = rawget(_G, "SMODS")
    if not runtime or not runtime.GAME or not runtime.GAME.grdl_loadout then
        return { ok = false, reason = "no_run" }
    end
    if not smods or type(smods.add_card) ~= "function" then
        return { ok = false, reason = "spawn_failed" }
    end
    local run_state = runtime.GAME.grdl_loadout
    local collection = namespace.collection
    now = now or os.time()
    local spawned = 0
    for index, card_id in ipairs(card_ids or {}) do
        local card = Storage.find_card(collection, card_id)
        if card and (card.status == "raw" or card.status == "graded") then
            local spawn_args = { key = card.center_key }
            if card.status == "graded" and Proficiency.allows_edition(card) and card.edition ~= "base" then
                spawn_args.edition = "e_" .. card.edition
            else
                spawn_args.no_edition = true
            end
            local ok, joker = pcall(smods.add_card, spawn_args)
            if ok and joker then
                joker.ability = joker.ability or {}
                joker.ability.grdl_loadout_id = card.id
                if card.status == "graded" and Proficiency.can_eternal(card)
                    and card.proficiency and card.proficiency.eternal then
                    if joker.set_eternal then
                        pcall(joker.set_eternal, joker, true)
                    else
                        joker.ability.eternal = true
                    end
                end
                if card.status == "raw" then
                    local _, intensity = Loadout.roll_wear(namespace.config, now + index * 7919)
                    card.condition = Condition.apply_wear(card.condition, card.edition, intensity)
                    card.wear_count = (card.wear_count or 0) + 1
                end
                Loadout.mark_entered(run_state, card.id)
                spawned = spawned + 1
            end
        end
    end
    namespace.last_save_ok = Persistence.save(namespace)
    return { ok = spawned > 0, spawned = spawned, reason = spawned == 0 and "spawn_failed" or nil }
end

-- ===== entry popup =====

function LoadoutUI.create_entry_definition(namespace)
    local window = namespace.loadout_entry_window
    if not window then
        return create_UIBox_generic_options({ back_func = "grdl_entry_skip", contents = {} })
    end
    local collection = namespace.collection
    local nodes = {
        row({ ui_text(safe_localize("grdl_k_entry_title"), 0.5, G.C.WHITE) }),
        row({ ui_text(safe_localize("grdl_k_entry_pick", { window.picks }), 0.32, G.C.UI.TEXT_LIGHT) }, { padding = 0.04 })
    }
    if rawget(_G, "CardArea") and rawget(_G, "Card") and rawget(_G, "G") and G.P_CENTERS then
        local area = CardArea(
            G.ROOM.T.x + 0.2 * G.ROOM.T.w / 2, G.ROOM.T.h,
            3.25 * G.CARD_W, 0.95 * G.CARD_H,
            { card_limit = 3, type = "title", highlight_limit = window.picks, collection = true })
        namespace.loadout_entry_area = area
        for _, card_id in ipairs(window.card_ids) do
            local record = Storage.find_card(collection, card_id)
            local center = record and G.P_CENTERS[record.center_key] or nil
            if center then
                local card = Card(area.T.x + area.T.w / 2, area.T.y, G.CARD_W, G.CARD_H,
                    (G.P_CARDS and G.P_CARDS.empty or nil), center)
                local flags = Catalog.edition_flags(record.edition)
                if flags then card:set_edition(flags, true, true) end
                card.grdl_record = record
                card.click = function(self)
                    if self.highlighted then
                        self.highlighted = false
                    else
                        local count = 0
                        for _, other in ipairs(area.cards) do
                            if other.highlighted then count = count + 1 end
                        end
                        if count >= window.picks then
                            if rawget(_G, "play_sound") then pcall(play_sound, "cancel") end
                            return
                        end
                        self.highlighted = true
                    end
                    if self.juice_up then self:juice_up(0.3, 0.3) end
                end
                area:emplace(card)
            end
        end
        nodes[#nodes + 1] = row({ { n = G.UIT.O, config = { object = area } } }, { padding = 0.05, no_fill = true })
    end
    nodes[#nodes + 1] = row({
        col({ UICommon.outline_button({
            button = "grdl_entry_confirm",
            solid = true,
            minw = 1.8,
            minh = 0.65,
            lines = { { text = safe_localize("grdl_b_entry_confirm"), scale = 0.32 } }
        }) }, { align = "cm", minw = 2.2 }),
        col({ UICommon.outline_button({
            button = "grdl_entry_skip",
            minw = 1.5,
            minh = 0.65,
            lines = { { text = safe_localize("grdl_b_entry_skip"), scale = 0.3 } }
        }) }, { align = "cm", minw = 1.9 })
    }, { padding = 0.08 })
    return create_UIBox_generic_options({
        back_func = "grdl_entry_skip",
        minw = 6.6,
        padding = 0.12,
        colour = G.C.L_BLACK,
        outline_colour = G.C.RED,
        contents = nodes
    })
end

function LoadoutUI.open_entry(namespace)
    local runtime = rawget(_G, "G")
    if not namespace or not namespace.loadout_entry_window then return end
    if not runtime or not runtime.FUNCS or not runtime.FUNCS.overlay_menu then return end
    if runtime.SETTINGS then runtime.SETTINGS.paused = true end
    runtime.FUNCS.overlay_menu({ definition = LoadoutUI.create_entry_definition(namespace) })
end

-- ===== hooks =====

function LoadoutUI.install(namespace, env)
    env = env or {}
    if not namespace then return false end
    if namespace.loadout_hooks_installed then return true end

    local funcs = env.funcs or (rawget(_G, "G") and G.FUNCS) or nil
    if not funcs then return false end

    local game_class = env.game_class or rawget(_G, "Game")
    if game_class and type(game_class.start_run) == "function" then
        local original_start = game_class.start_run
        game_class.start_run = function(self, args)
            local result = original_start(self, args)
            pcall(LoadoutUI.on_run_start, namespace)
            return result
        end
    end

    if type(funcs.cash_out) == "function" then
        local original_cash_out = funcs.cash_out
        funcs.cash_out = function(e)
            local result = original_cash_out(e)
            pcall(LoadoutUI.on_boss_cash_out, namespace)
            return result
        end
    end

    namespace.loadout_hooks_installed = true
    return true
end

return LoadoutUI
