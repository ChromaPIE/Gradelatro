local LoadoutUI = {}

local function load_src(path)
    return assert(SMODS.load_file("src/" .. path))()
end

local Catalog = load_src("domain/catalog.lua")
local Condition = load_src("domain/condition.lua")
local Loadout = load_src("domain/loadout.lua")
local Persistence = load_src("core/persistence.lua")
local Proficiency = load_src("domain/proficiency.lua")
local StakeEconomy = load_src("domain/stake_economy.lua")
local Storage = load_src("core/storage.lua")
local UICommon = load_src("ui/ui_common.lua")

local safe_localize = UICommon.localize_text
local ui_text = UICommon.text_node
local row = UICommon.row
local col = UICommon.col

local TRANSPORT_ORDER = { "blue", "green", "red", "purple", "gold" }
local TIER_KEYS = { "grdl_k_tier_1", "grdl_k_tier_2", "grdl_k_tier_3", "grdl_k_tier_4" }
local ENTRY_FEE_INNER_W = 5.65
local ENTRY_FEE_TIME_SCALE = 2.5
local ENTRY_FEE_ROLL_DURATION = 1.5
local ENTRY_FEE_FINAL_HOLD = 0.35 * ENTRY_FEE_TIME_SCALE
local ENTRY_FEE_GLHF_HOLD = 0.65 * ENTRY_FEE_TIME_SCALE
local ENTRY_FEE_AMOUNT_SCALE = 0.74
local ENTRY_FEE_GLHF_SCALE = 0.58

function LoadoutUI.license_label(level)
    if not level or level <= 0 then return safe_localize("grdl_k_license_none") end
    -- composed instead of a #1# variable key: the localize fallback returns
    -- bare keys, which would swallow the tier name in headless contexts
    return safe_localize(TIER_KEYS[Loadout.tier(level)]) .. " X" .. tostring(Loadout.within(level))
end

local function build_state_fields(namespace)
    local collection = namespace.collection
    Loadout.reconcile(collection)
    local entries = {}
    for _, card_id in ipairs(collection.loadout.card_ids) do
        local card = Storage.find_card(collection, card_id)
        if card then entries[#entries + 1] = card end
    end
    return {
        license = collection.loadout.license,
        capacity = Loadout.capacity(collection.loadout.license),
        entries = entries,
        transports = collection.loadout.transports,
        active_transport = collection.loadout.active_transport
    }
end

function LoadoutUI.open(namespace)
    if not namespace or not namespace.collection then return nil end
    local state = build_state_fields(namespace)
    state.feedback = ""
    namespace.loadout_ui_state = state
    return state
end

-- in-place update preserving table identity so ref-bound nodes in the
-- live overlay keep pointing at the current state
function LoadoutUI.refresh(namespace)
    local state = namespace and namespace.loadout_ui_state or nil
    if not state then return LoadoutUI.open(namespace) end
    for key, value in pairs(build_state_fields(namespace)) do
        state[key] = value
    end
    return state
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

local function now_seconds(runtime)
    local timers = runtime and runtime.TIMERS or nil
    if timers and type(timers.REAL) == "number" then return timers.REAL end
    return os.clock()
end

local function set_entry_fee_line(line, text, scale, colour, effect)
    if not line then return end
    local next_text = (text ~= nil and text ~= "") and tostring(text) or " "
    local next_effect = effect == true
    if line.scale ~= scale or line.colour ~= colour or line.effect ~= next_effect then
        line.object_dirty = true
    end
    line.text = next_text
    line.scale = scale
    line.colour = colour
    line.effect = next_effect
end

local function entry_fee_text_object_args(line)
    return {
        string = { { ref_table = line, ref_value = "text" } },
        colours = { line.colour },
        scale = line.scale,
        maxw = ENTRY_FEE_INNER_W - 0.3,
        shadow = true,
        silent = true,
        float = line.effect and true or nil,
        pop_in = line.effect and 0 or nil,
        pop_in_rate = line.effect and 6 or nil
    }
end

local function sync_entry_fee_text_object(line, element)
    local object = line and line.object or nil
    local node_t = element and (element.T or element.VT) or nil
    if not object or not node_t then return end
    if object.T then
        object.T.x, object.T.y, object.T.w, object.T.h = node_t.x, node_t.y, node_t.w, node_t.h
    end
    if object.VT then
        object.VT.x, object.VT.y, object.VT.w, object.VT.h = node_t.x, node_t.y, node_t.w, node_t.h
    end
    if object.move_with_major then pcall(object.move_with_major, object, 0) end
    if object.align_to_major then pcall(object.align_to_major, object) end
end

local function rebuild_entry_fee_text_object(line, element)
    if not line or not line.object_config or not rawget(_G, "DynaText") then return false end
    if line.object and line.object.remove then pcall(line.object.remove, line.object) end
    local ok, object = pcall(DynaText, entry_fee_text_object_args(line))
    if not ok or not object then return false end
    line.object = object
    line.object_config.object = object
    line.object_dirty = false
    sync_entry_fee_text_object(line, element)
    return true
end

function LoadoutUI.entry_fee_balance_text(value)
    return "Ⓖ " .. tostring(math.max(0, math.floor(tonumber(value) or 0)))
end

function LoadoutUI.entry_fee_final_balance(state)
    state = state or {}
    local balance = math.max(0, math.floor(tonumber(state.balance) or 0))
    local fee = math.max(0, math.floor(tonumber(state.fee) or 0))
    if state.paid and state.charged == false then return balance end
    return math.max(0, balance - fee)
end

function LoadoutUI.set_entry_fee_warning_view(ui, state)
    if not ui then return end
    state = state or {}
    local title_key = state.enabled and "grdl_k_entry_fee_title" or "grdl_k_entry_fee_insufficient_title"
    set_entry_fee_line(ui.lines[1], safe_localize(title_key), 0.5, G.C.WHITE)
    set_entry_fee_line(ui.lines[2], safe_localize("grdl_k_entry_fee_balance", { state.balance or 0 }), 0.34, G.C.UI.TEXT_LIGHT)
    set_entry_fee_line(ui.lines[3], safe_localize("grdl_k_entry_fee_required", { state.fee or 0 }), 0.34, G.C.UI.TEXT_LIGHT)
    set_entry_fee_line(ui.lines[4], state.enabled and " " or safe_localize("grdl_k_entry_fee_blocked"), 0.3, G.C.UI.TEXT_INACTIVE)
end

function LoadoutUI.set_entry_fee_balance_view(ui, value)
    if not ui then return end
    set_entry_fee_line(ui.lines[1], " ", 0.44, G.C.WHITE)
    set_entry_fee_line(ui.lines[2], LoadoutUI.entry_fee_balance_text(value), ENTRY_FEE_AMOUNT_SCALE, G.C.GOLD)
    set_entry_fee_line(ui.lines[3], " ", 0.34, G.C.WHITE)
    set_entry_fee_line(ui.lines[4], " ", 0.3, G.C.WHITE)
end

function LoadoutUI.set_entry_fee_glhf_view(ui)
    if not ui then return end
    local text = safe_localize("grdl_k_entry_fee_glhf")
    set_entry_fee_line(ui.lines[1], " ", 0.44, G.C.WHITE)
    set_entry_fee_line(ui.lines[2], text, ENTRY_FEE_GLHF_SCALE, G.C.ORANGE, true)
    set_entry_fee_line(ui.lines[3], " ", 0.34, G.C.WHITE)
    set_entry_fee_line(ui.lines[4], " ", 0.3, G.C.WHITE)
end

function LoadoutUI.entry_fee_ui_state(namespace)
    namespace = namespace or {}
    local runtime = rawget(_G, "G")
    local state = namespace.entry_fee_warning or (runtime and runtime.GAME and runtime.GAME.grdl_entry) or {}
    local ui = namespace.entry_fee_warning_ui
    if not ui or ui.source_state ~= state then
        ui = {
            source_state = state,
            lines = { {}, {}, {}, {} },
            buttons_disabled = false
        }
        namespace.entry_fee_warning_ui = ui
    end
    if not ui.animating then
        ui.buttons_disabled = false
        LoadoutUI.set_entry_fee_warning_view(ui, state)
    end
    return ui
end

function LoadoutUI.begin_entry_fee_continue(namespace, runtime)
    namespace = namespace or {}
    runtime = runtime or rawget(_G, "G")
    local state = namespace.entry_fee_warning or (runtime and runtime.GAME and runtime.GAME.grdl_entry) or nil
    if not state then return false end
    if not state.enabled then
        namespace.entry_fee_warning = nil
        namespace.entry_fee_warning_ui = nil
        if runtime and runtime.FUNCS and runtime.FUNCS.exit_overlay_menu then
            runtime.FUNCS.exit_overlay_menu()
        end
        return true
    end
    local ui = LoadoutUI.entry_fee_ui_state(namespace)
    if ui.animating then return false end
    ui.animating = true
    ui.buttons_disabled = true
    ui.started_at = now_seconds(runtime)
    ui.start_balance = math.max(0, math.floor(tonumber(state.balance) or 0))
    ui.final_balance = LoadoutUI.entry_fee_final_balance(state)
    ui.roll_duration = ENTRY_FEE_ROLL_DURATION
    ui.final_hold = ENTRY_FEE_FINAL_HOLD
    ui.greeting_hold = ENTRY_FEE_GLHF_HOLD
    ui.completed = false
    LoadoutUI.set_entry_fee_balance_view(ui, ui.start_balance)
    if rawget(_G, "play_sound") then pcall(play_sound, "chips1", 0.8, 0.45) end
    return true
end

function LoadoutUI.update_entry_fee_continue(namespace, runtime)
    namespace = namespace or {}
    local ui = namespace.entry_fee_warning_ui
    if not ui or not ui.animating or ui.completed then return false end
    runtime = runtime or rawget(_G, "G")
    local elapsed = math.max(0, now_seconds(runtime) - (ui.started_at or 0))
    local roll_duration = math.max(0.01, ui.roll_duration or ENTRY_FEE_ROLL_DURATION)
    local final_hold = math.max(0, ui.final_hold or ENTRY_FEE_FINAL_HOLD)
    local greeting_hold = math.max(0, ui.greeting_hold or ENTRY_FEE_GLHF_HOLD)
    if elapsed < roll_duration then
        local progress = math.max(0, math.min(1, elapsed / roll_duration))
        local value = math.floor((ui.start_balance or 0) + ((ui.final_balance or 0) - (ui.start_balance or 0)) * progress + 0.5)
        LoadoutUI.set_entry_fee_balance_view(ui, value)
        return true
    end
    if elapsed < roll_duration + final_hold then
        LoadoutUI.set_entry_fee_balance_view(ui, ui.final_balance or 0)
        return true
    end
    if elapsed < roll_duration + final_hold + greeting_hold then
        LoadoutUI.set_entry_fee_glhf_view(ui)
        return true
    end
    ui.completed = true
    namespace.entry_fee_warning = nil
    namespace.entry_fee_warning_ui = nil
    if runtime and runtime.FUNCS and runtime.FUNCS.exit_overlay_menu then
        runtime.FUNCS.exit_overlay_menu()
    end
    return true
end

-- ===== overlay definitions =====

local function loadout_cards_row(namespace, state)
    if #state.entries == 0 or not (rawget(_G, "CardArea") and rawget(_G, "Card") and rawget(_G, "G") and G.P_CENTERS) then
        return row({ ui_text(safe_localize("grdl_k_loadout_empty"), 0.35, G.C.UI.TEXT_INACTIVE) }, { padding = 0.3 })
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
            card.grdl_inspect_close_func = "grdl_open_loadout"
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
        row({ ui_text(safe_localize("grdl_k_loadout_hint"), 0.31, G.C.UI.TEXT_INACTIVE) }),
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
            solid = true,
            minw = 1.7,
            minh = 0.8,
            lines = {
                { text = label, scale = 0.3 },
                { text = safe_localize("grdl_k_grading_fee", { price }), scale = 0.27, colour = G.C.GOLD }
            }
        }) }, { align = "cm", minw = 1.85 })
    end
    local colour = owned and G.C.GREEN or G.C.UI.TEXT_INACTIVE
    local status = owned and safe_localize("grdl_k_owned") or safe_localize("grdl_k_locked")
    return col({
        row({ ui_text(label, 0.3, colour) }, { padding = 0.01 }),
        row({ ui_text(status, 0.26, colour) }, { padding = 0.01 })
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
            solid = true,
            minw = 1.5,
            minh = 0.9,
            lines = {
                { text = name, scale = 0.28 },
                { text = safe_localize("grdl_k_transport_antes", { antes }), scale = 0.24 },
                { text = safe_localize("grdl_k_grading_fee", { transport.price }), scale = 0.26, colour = G.C.GOLD }
            }
        }) }, { align = "cm", minw = 1.5 })
    end
    if state.active_transport == key then
        return col({
            row({ ui_text(name, 0.28, G.C.GREEN) }, { padding = 0.01 }),
            row({ ui_text(safe_localize("grdl_k_transport_antes", { antes }), 0.24, G.C.GREEN) }, { padding = 0.01 }),
            row({ ui_text(safe_localize("grdl_k_enabled"), 0.26, G.C.GREEN) }, { padding = 0.01 })
        }, { align = "cm", minw = 1.5 })
    end
    return col({ UICommon.outline_button({
        button = "grdl_transport_activate",
        ref = { key = key },
        solid = true,
        colour = G.C.BLUE,
        minw = 1.5,
        minh = 0.9,
        lines = {
            { text = name, scale = 0.28 },
            { text = safe_localize("grdl_k_transport_antes", { antes }), scale = 0.24 },
            { text = safe_localize("grdl_b_enable"), scale = 0.26 }
        }
    }) }, { align = "cm", minw = 1.5 })
end

local function license_tab_root(nodes, opts)
    opts = opts or {}
    return { n = G.UIT.ROOT, config = {
        align = opts.align or "tm",
        colour = G.C.CLEAR,
        minw = opts.minw or 7.4,
        minh = opts.minh or 4.6,
        padding = 0.05
    }, nodes = nodes }
end

local function license_tab_definition(namespace)
    return function()
        local state = namespace.loadout_ui_state or LoadoutUI.open(namespace)
        state.license_tab = "license"
        local config_table = namespace.config
        local ladder = {}
        for tier = 1, 4 do
            local cells = { row({ ui_text(safe_localize(TIER_KEYS[tier]), 0.34, G.C.WHITE) }, { padding = 0.02 }) }
            for within = 1, 3 do
                cells[#cells + 1] = row({ license_cell(config_table, state, (tier - 1) * 3 + within) }, { padding = 0.02 })
            end
            ladder[#ladder + 1] = col(cells, { align = "tm", minw = 1.8, padding = 0.03 })
        end
        return license_tab_root({ row(ladder, { padding = 0.04 }) })
    end
end

local function transport_tab_definition(namespace)
    return function()
        local state = namespace.loadout_ui_state or LoadoutUI.open(namespace)
        state.license_tab = "transport"
        local transports = {}
        for _, key in ipairs(TRANSPORT_ORDER) do
            transports[#transports + 1] = transport_cell(namespace.config, state, key)
        end
        -- a single row of cells: a tight, centred root avoids dead space
        return license_tab_root({ row(transports, { padding = 0.04 }) }, { align = "cm", minh = 2.2 })
    end
end

function LoadoutUI.create_license_definition(namespace)
    namespace = namespace or rawget(_G, "Gradelatro") or {}
    local state = namespace.loadout_ui_state or LoadoutUI.open(namespace)
    if not state then
        return create_UIBox_generic_options({ back_func = "grdl_open_loadout", contents = {} })
    end
    local rows = {
        row({ ui_text(safe_localize("grdl_k_license_title"), 0.5, G.C.WHITE) }),
        row({
            create_tabs({
                tabs = {
                    {
                        label = safe_localize("grdl_b_license"),
                        chosen = state.license_tab ~= "transport",
                        tab_definition_function = license_tab_definition(namespace)
                    },
                    {
                        label = safe_localize("grdl_k_transport_title"),
                        chosen = state.license_tab == "transport",
                        tab_definition_function = transport_tab_definition(namespace)
                    }
                },
                text_scale = 0.4
            })
        }, { padding = 0.05 }),
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

    local function purchase_handler(action, ok_key, tab_def_factory)
        return function(event)
            if not namespace.loadout_ui_state then LoadoutUI.open(namespace) end
            local result = action(event)
            if result.ok then
                namespace.last_save_ok = Persistence.save(namespace)
                LoadoutUI.refresh(namespace)
                feedback(namespace, result, ok_key)
                -- swap the live tab contents in place: reopening the overlay
                -- replays the enter and exit animations
                if not UICommon.swap_tab_contents(tab_def_factory(namespace)) then
                    if adapter.open_license then adapter.open_license(namespace, namespace.loadout_ui_state, event) end
                end
            else
                feedback(namespace, result, ok_key)
                if rawget(_G, "play_sound") then pcall(play_sound, "tarot2", 0.76, 0.4) end
            end
        end
    end

    runtime.FUNCS.grdl_license_buy = purchase_handler(function()
        return Loadout.purchase_license(namespace.config, namespace.collection)
    end, "grdl_k_license_bought", license_tab_definition)

    runtime.FUNCS.grdl_transport_buy = purchase_handler(function(event)
        return Loadout.purchase_transport(namespace.config, namespace.collection, event_key(event))
    end, "grdl_k_transport_bought", transport_tab_definition)

    runtime.FUNCS.grdl_transport_activate = purchase_handler(function(event)
        return Loadout.set_active_transport(namespace.collection, event_key(event))
    end, "grdl_k_transport_enabled", transport_tab_definition)

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

    runtime.FUNCS.grdl_open_entry_fee_warning = function(event)
        LoadoutUI.open_entry_fee(namespace)
    end

    runtime.FUNCS.grdl_entry_fee_continue = function(event)
        LoadoutUI.begin_entry_fee_continue(namespace, runtime)
    end

    runtime.FUNCS.grdl_entry_fee_reselect = function(event)
        local ui = namespace.entry_fee_warning_ui
        if ui and ui.buttons_disabled then return end
        namespace.entry_fee_warning = nil
        namespace.entry_fee_reselect_pending = true
        if runtime.FUNCS.exit_overlay_menu then runtime.FUNCS.exit_overlay_menu() end
        if not namespace.entry_fee_warning_event_active then
            LoadoutUI.perform_entry_fee_reselect(namespace, runtime, event)
        end
    end

    runtime.FUNCS.grdl_entry_fee_text_tick = function(element)
        LoadoutUI.update_entry_fee_continue(namespace, runtime)
        local line = element and element.config and element.config.ref_table or nil
        if not line or not element.config then return end
        if element.config.object then
            line.object_config = element.config
            if line.object_dirty then
                rebuild_entry_fee_text_object(line, element)
            end
            return
        end
        element.config.text = line.text
        element.config.scale = line.scale
        element.config.colour = line.colour
    end

    runtime.FUNCS.grdl_entry_fee_button_tick = function(element)
        local ref = element and element.config and element.config.ref_table or nil
        local ui = ref and ref.ui or nil
        if not ref or not element.config then return end
        local disabled = ui and ui.buttons_disabled
        element.config.button = disabled and nil or ref.button
        element.config.hover = not disabled
        element.config.colour = disabled
            and G.C.GREY
            or ref.colour
    end

    return true
end

-- ===== run integration =====

function LoadoutUI.perform_entry_fee_reselect(namespace, runtime, event)
    if not namespace or not namespace.entry_fee_reselect_pending then return false end
    runtime = runtime or rawget(_G, "G")
    if not runtime or not runtime.FUNCS then return false end
    namespace.entry_fee_reselect_pending = nil
    local setup_event = { config = {} }
    if runtime.FUNCS.setup_run then
        runtime.FUNCS.setup_run(setup_event)
        return true
    end
    if runtime.FUNCS.notify_then_setup_run and runtime.OVERLAY_MENU then
        runtime.FUNCS.notify_then_setup_run(event or setup_event)
        return true
    end
    return false
end

function LoadoutUI.open_entry_fee(namespace)
    local runtime = rawget(_G, "G")
    if not namespace or not namespace.entry_fee_warning then return end
    if not runtime or not runtime.FUNCS or not runtime.FUNCS.overlay_menu then return end
    if runtime.SETTINGS then runtime.SETTINGS.paused = true end
    runtime.FUNCS.overlay_menu({
        definition = LoadoutUI.create_entry_fee_definition(namespace),
        config = { no_esc = true }
    })
end

function LoadoutUI.queue_entry_fee_warning(namespace, state, queue_index)
    if not namespace or not state then return false end
    if math.max(0, math.floor(tonumber(state.fee) or 0)) <= 0 then return false end
    local warning_key = state.run_key or (tostring(state.run_id or "unknown") .. ":" .. tostring(state.run_started_at or "unknown"))
    if namespace.entry_fee_warning_run_key == warning_key then return false end
    namespace.entry_fee_warning = state
    local runtime = rawget(_G, "G")
    if runtime and runtime.E_MANAGER and rawget(_G, "Event") then
        local opened = false
        local event = Event({
            grdl_entry_fee_warning = true,
            blocking = true,
            func = function()
                namespace.entry_fee_warning_event_active = true
                if not opened then
                    opened = true
                    if runtime.FUNCS and runtime.FUNCS.grdl_open_entry_fee_warning then
                        runtime.FUNCS.grdl_open_entry_fee_warning()
                    else
                        pcall(LoadoutUI.open_entry_fee, namespace)
                    end
                end
                if namespace.entry_fee_warning == nil then
                    LoadoutUI.perform_entry_fee_reselect(namespace, runtime)
                    namespace.entry_fee_warning_event_active = nil
                    return true
                end
                return namespace.entry_fee_warning == nil
            end
        })
        local base_queue = runtime.E_MANAGER.queues and runtime.E_MANAGER.queues.base or nil
        if type(base_queue) == "table" then
            local index = tonumber(queue_index) or (#base_queue + 1)
            index = math.max(1, math.min(index, #base_queue + 1))
            table.insert(base_queue, index, event)
        else
            runtime.E_MANAGER:add_event(event)
        end
    else
        pcall(LoadoutUI.open_entry_fee, namespace)
    end
    namespace.entry_fee_warning_run_key = warning_key
    return true
end

function LoadoutUI.on_run_start(namespace, warning_queue_index)
    local runtime = rawget(_G, "G")
    if not namespace or not namespace.collection or not runtime or not runtime.GAME then return end
    local entry_state = StakeEconomy.ensure_entry_state(namespace.config, namespace.collection, runtime, os.time())
    if entry_state and entry_state.charged then namespace.last_save_ok = Persistence.save(namespace) end
    if entry_state and not entry_state.enabled then
        runtime.GAME.grdl_loadout = nil
        LoadoutUI.queue_entry_fee_warning(namespace, entry_state, warning_queue_index)
        return
    end
    local run_id = Loadout.run_identity(runtime.GAME)
    local existing = runtime.GAME.grdl_loadout
    if not existing or existing.run_id ~= run_id then
        runtime.GAME.grdl_loadout = Loadout.begin_run(namespace.collection, run_id)
    end
    if entry_state then
        LoadoutUI.queue_entry_fee_warning(namespace, entry_state, warning_queue_index)
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

function LoadoutUI.on_boss_cash_out(namespace, defeated_ante)
    local runtime = rawget(_G, "G")
    if not namespace or not namespace.collection or not runtime or not runtime.GAME then return end
    if not StakeEconomy.run_enabled(runtime) then return end
    local run_state = runtime.GAME.grdl_loadout
    if not run_state then return end
    if not defeated_ante then return end
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
    if not StakeEconomy.run_enabled(runtime) then
        return { ok = false, reason = "entry_fee_unpaid" }
    end
    if not runtime or not runtime.GAME or not runtime.GAME.grdl_loadout then
        return { ok = false, reason = "no_run" }
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
                local edition_flags = Catalog.edition_flags(card.edition)
                if edition_flags then
                    spawn_args.edition = edition_flags
                else
                    spawn_args.no_edition = true
                end
            else
                spawn_args.no_edition = true
            end
            local ok, joker = pcall(SMODS.add_card, spawn_args)
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

function LoadoutUI.create_entry_fee_definition(namespace)
    namespace = namespace or rawget(_G, "Gradelatro") or {}
    local ui = LoadoutUI.entry_fee_ui_state(namespace)
    local function live_line_object_node(line)
        local object_config = {
            align = "cm",
            ref_table = line,
            func = "grdl_entry_fee_text_tick"
        }
        local node = { n = G.UIT.O, config = object_config }
        line.object_config = object_config
        rebuild_entry_fee_text_object(line)
        return node
    end
    local function live_line_node(line)
        return { n = G.UIT.T, config = {
            align = "cm",
            text = line.text,
            ref_table = line,
            ref_value = "text",
            scale = line.scale,
            colour = line.colour,
            func = "grdl_entry_fee_text_tick"
        } }
    end
    local function line_row(line, config)
        config = config or {}
        local object_text = config.object_text
        config.object_text = nil
        config.align = config.align or "cm"
        config.minw = config.minw or ENTRY_FEE_INNER_W
        local node = object_text and live_line_object_node(line) or live_line_node(line)
        return { n = G.UIT.R, config = config, nodes = { node } }
    end
    local line_rows = {
        line_row(ui.lines[1], { minh = 0.42 }),
        line_row(ui.lines[2], { padding = 0.04, minh = 0.62, object_text = true }),
        line_row(ui.lines[3], { minh = 0.38 })
    }
    if not (ui.source_state and ui.source_state.enabled == true) then
        line_rows[#line_rows + 1] = line_row(ui.lines[4], { minh = 0.32 })
    end
    local reselect_ref = { ui = ui, button = "grdl_entry_fee_reselect", colour = G.C.GREEN }
    local continue_ref = { ui = ui, button = "grdl_entry_fee_continue", colour = G.C.RED }
    return create_UIBox_generic_options({ no_back = true, contents = {
        { n = G.UIT.R, config = { align = "cm", minw = 2.5, padding = 0.15, r = 0.1, colour = G.C.L_BLACK }, nodes = {
            { n = G.UIT.C, config = { align = "tm", minw = ENTRY_FEE_INNER_W, minh = 1, r = 0.1, colour = G.C.BLACK, padding = 0.15, emboss = 0.05 }, nodes = line_rows }
        } },
        { n = G.UIT.R, config = { align = "cm", padding = 0 }, nodes = {
            { n = G.UIT.C, config = { minw = 2.72, minh = 0.8, r = 0.1, hover = true, button = "grdl_entry_fee_reselect", colour = G.C.GREEN, align = "cm", emboss = 0.1, func = "grdl_entry_fee_button_tick", ref_table = reselect_ref }, nodes = {
                { n = G.UIT.R, config = { align = "cm" }, nodes = {
                    ui_text(safe_localize("grdl_b_entry_fee_reselect"), 0.5, G.C.WHITE)
                } }
            } },
            { n = G.UIT.C, config = { align = "cm", minw = 0.2 }, nodes = {} },
            { n = G.UIT.C, config = { minw = 2.72, minh = 0.8, r = 0.1, hover = true, button = "grdl_entry_fee_continue", colour = G.C.RED, align = "cm", emboss = 0.1, func = "grdl_entry_fee_button_tick", ref_table = continue_ref }, nodes = {
                { n = G.UIT.R, config = { align = "cm" }, nodes = {
                    ui_text(safe_localize("grdl_b_entry_fee_continue"), 0.5, G.C.WHITE)
                } }
            } }
        } }
    } })
end

function LoadoutUI.create_entry_definition(namespace)
    local window = namespace.loadout_entry_window
    if not window then
        return create_UIBox_generic_options({ back_func = "grdl_entry_skip", contents = {} })
    end
    local collection = namespace.collection
    local nodes = {
        row({ ui_text(safe_localize("grdl_k_entry_title"), 0.5, G.C.WHITE) }),
        row({ ui_text(safe_localize("grdl_k_entry_pick", { window.picks }), 0.35, G.C.UI.TEXT_LIGHT) }, { padding = 0.04 })
    }
    if rawget(_G, "CardArea") and rawget(_G, "Card") and rawget(_G, "G") and G.P_CENTERS then
        local area = CardArea(
            G.ROOM.T.x + 0.2 * G.ROOM.T.w / 2, G.ROOM.T.h,
            3.25 * G.CARD_W, 1.02 * G.CARD_H,
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
        nodes[#nodes + 1] = row({ { n = G.UIT.O, config = { object = area } } }, { padding = 0.07, no_fill = true })
    end
    nodes[#nodes + 1] = row({
        col({ UICommon.outline_button({
            button = "grdl_entry_confirm",
            solid = true,
            colour = G.C.GREEN,
            minw = 1.8,
            minh = 0.65,
            lines = { { text = safe_localize("grdl_b_entry_confirm"), scale = 0.34 } }
        }) }, { align = "cm", minw = 2.2 }),
        col({ UICommon.outline_button({
            button = "grdl_entry_skip",
            solid = true,
            minw = 1.5,
            minh = 0.65,
            lines = { { text = safe_localize("grdl_b_entry_skip"), scale = 0.32 } }
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
            local game = rawget(_G, "G")
            local base_queue = game and game.E_MANAGER and game.E_MANAGER.queues and game.E_MANAGER.queues.base
            local warning_queue_index = type(base_queue) == "table" and (#base_queue + 1) or 1
            local result = original_start(self, args)
            pcall(LoadoutUI.on_run_start, namespace, warning_queue_index)
            return result
        end
    end

    if type(funcs.cash_out) == "function" then
        local original_cash_out = funcs.cash_out
        funcs.cash_out = function(e)
            -- vanilla cash_out calls reset_blinds() before returning, wiping
            -- the Defeated flag - the boss state and the already-eased ante
            -- must be captured before the original runs
            local defeated_ante = nil
            local game = rawget(_G, "G")
            local resets = game and game.GAME and game.GAME.round_resets or nil
            if resets and resets.blind_states and resets.blind_states.Boss == "Defeated" then
                defeated_ante = (resets.ante or 1) - 1
            end
            local result = original_cash_out(e)
            if defeated_ante then
                pcall(LoadoutUI.on_boss_cash_out, namespace, defeated_ante)
            end
            return result
        end
    end

    namespace.loadout_hooks_installed = true
    return true
end

return LoadoutUI
