local DebugTools = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Catalog = load_src("domain/catalog.lua")
local BlackMarket = load_src("domain/black_market.lua")
local Economy = load_src("domain/economy.lua")
local Persistence = load_src("core/persistence.lua")
local Proficiency = load_src("domain/proficiency.lua")
local Rng = load_src("core/rng.lua")
local Storage = load_src("core/storage.lua")

local GRADE_CONDITION = {
    [10] = 9.8,
    [9] = 9.2,
    [8] = 8.2,
    [7] = 7.2,
    [6] = 6.2,
    [5] = 5.4
}

local SEED_GRADES = { 10, 9, 8, 7, 6 }
local SEED_EDITIONS = { "base", "foil", "holographic", "polychrome", "negative" }

function DebugTools.condition_for_grade(grade)
    local value = GRADE_CONDITION[grade] or GRADE_CONDITION[9]
    return {
        centering = value,
        print_quality = value,
        corners = value,
        edges = value,
        surface = value
    }
end

function DebugTools.adjust_currency(state, op, amount)
    if not state then return { ok = false, reason = "missing_collection" } end
    amount = tonumber(amount)
    if not amount then return { ok = false, reason = "invalid_amount" } end
    amount = math.floor(amount)

    if op == "set" then
        state.currency_g = math.max(0, amount)
    elseif op == "add" then
        Storage.add_currency(state, amount)
    elseif op == "sub" then
        Storage.add_currency(state, -amount)
    else
        return { ok = false, reason = "unknown_op" }
    end

    return { ok = true, currency_g = state.currency_g }
end

function DebugTools.parse_seed_args(args)
    args = args or {}
    local graded = true
    local count_arg = args[1]
    if args[1] == "g" or args[1] == "ug" then
        graded = args[1] == "g"
        count_arg = args[2]
    elseif args[1] ~= nil and not tonumber(args[1]) then
        return { ok = false, reason = "unknown_mode" }
    end
    return { ok = true, graded = graded, count = tonumber(count_arg) or 10 }
end

function DebugTools.seed_cards(state, catalog, args)
    if not state then return { ok = false, reason = "missing_collection" } end
    args = args or {}
    local graded = args.graded ~= false
    local count = math.max(1, math.floor(args.count or 10))
    local now = args.now or os.time()
    local rand = Rng.lcg(args.rng_seed or (now + #(state.cards or {}) * 7919))

    local by_mod = {}
    local mod_order = {}
    for _, entry in ipairs(catalog or {}) do
        if not by_mod[entry.mod_id] then
            by_mod[entry.mod_id] = {}
            mod_order[#mod_order + 1] = entry.mod_id
        end
        local bucket = by_mod[entry.mod_id]
        bucket[#bucket + 1] = entry
    end
    if #mod_order == 0 then return { ok = false, reason = "empty_catalog" } end

    Rng.shuffle(mod_order, rand)
    for _, bucket in pairs(by_mod) do
        Rng.shuffle(bucket, rand)
    end
    local grade_phase = math.floor(rand() * #SEED_GRADES)
    local edition_phase = math.floor(rand() * #SEED_EDITIONS)

    local created = {}
    local cursor = {}
    local mod_index = 0
    local acquired_date = os.date("*t", now)
    while #created < count and #mod_order > 0 do
        mod_index = mod_index % #mod_order + 1
        local mod_id = mod_order[mod_index]
        cursor[mod_id] = (cursor[mod_id] or 0) + 1
        local entry = by_mod[mod_id][cursor[mod_id]]
        if entry then
            local n = #created + 1
            local grade = SEED_GRADES[(n - 1 + grade_phase) % #SEED_GRADES + 1]
            local edition_index = ((n - 1 + edition_phase) + math.floor((n - 1) / #SEED_EDITIONS)) % #SEED_EDITIONS + 1
            local edition = SEED_EDITIONS[edition_index]
            local price = 0
            if args.config then
                price = math.floor(Economy.raw_anchor_value(args.config, {
                    rarity = entry.rarity,
                    edition = edition
                }))
            end
            local card = Storage.add_raw_card(state, {
                center_key = entry.center_key,
                local_key = entry.local_key,
                series_key = entry.series_key,
                mod_id = entry.mod_id,
                rarity = entry.rarity,
                edition = edition,
                condition = DebugTools.condition_for_grade(grade),
                acquired_at = now,
                acquired_year = acquired_date.year,
                acquired_month = acquired_date.month,
                acquired_day = acquired_date.day,
                acquired_price = price,
                source = "debug_seed"
            })
            if graded then
                card.status = "graded"
                card.grade = grade
                card.graded_at = now
                card.grade_service = "standard"
                card.cert_number = Storage.allocate_cert_number(state)
            end
            created[#created + 1] = card
        else
            table.remove(mod_order, mod_index)
            mod_index = mod_index - 1
        end
    end

    return { ok = true, cards = created }
end

function DebugTools.clear_collection(state)
    if not state then return { ok = false, reason = "missing_collection" } end
    local cards_removed = #(state.cards or {})
    local queue_removed = #(state.grading_queue or {})
    state.cards = {}
    state.grading_queue = {}
    return { ok = true, cards_removed = cards_removed, queue_removed = queue_removed }
end

function DebugTools.set_license(state, level)
    if not state then return { ok = false, reason = "missing_collection" } end
    level = tonumber(level)
    if not level then return { ok = false, reason = "invalid_level" } end
    level = math.max(0, math.min(12, math.floor(level)))
    state.loadout = type(state.loadout) == "table" and state.loadout or {}
    state.loadout.license = level
    return { ok = true, level = level }
end

function DebugTools.grant_transports(config, state, key)
    if not state then return { ok = false, reason = "missing_collection" } end
    local transports = config and config.loadout and config.loadout.transports or {}
    state.loadout = type(state.loadout) == "table" and state.loadout or {}
    state.loadout.transports = type(state.loadout.transports) == "table" and state.loadout.transports or {}
    local granted = {}
    if key == "all" or key == nil then
        for name in pairs(transports) do
            state.loadout.transports[name] = true
            granted[#granted + 1] = name
        end
    else
        if not transports[key] then return { ok = false, reason = "unknown_transport" } end
        state.loadout.transports[key] = true
        granted[#granted + 1] = key
    end
    if not state.loadout.active_transport and granted[1] then
        state.loadout.active_transport = granted[1]
    end
    return { ok = true, granted = granted }
end

function DebugTools.reset_transports(state)
    if not state then return { ok = false, reason = "missing_collection" } end
    state.loadout = type(state.loadout) == "table" and state.loadout or {}
    local removed = 0
    for _ in pairs(state.loadout.transports or {}) do
        removed = removed + 1
    end
    state.loadout.transports = {}
    state.loadout.active_transport = nil
    return { ok = true, removed = removed }
end

function DebugTools.set_proficiency(state, antes)
    if not state then return { ok = false, reason = "missing_collection" } end
    antes = tonumber(antes)
    if not antes then return { ok = false, reason = "invalid_antes" } end
    antes = math.max(0, math.floor(antes))
    local updated = 0
    for _, card in ipairs(state.cards or {}) do
        if card.status == "graded" then
            Proficiency.ensure(card).antes = antes
            updated = updated + 1
        end
    end
    return { ok = true, updated = updated, antes = antes }
end

function DebugTools.finish_queue(state, now)
    if not state then return { ok = false, reason = "missing_collection" } end
    now = now or os.time()
    local finished = 0
    for _, entry in ipairs(state.grading_queue or {}) do
        if (entry.due_at or 0) > now then
            entry.due_at = now - 1
            finished = finished + 1
        end
    end
    return { ok = true, finished = finished }
end

function DebugTools.regen_black_market(namespace, now)
    local runtime = rawget(_G, "G")
    if not namespace or not namespace.collection or not namespace.config then
        return { ok = false, reason = "missing_collection" }
    end
    if not runtime or not runtime.P_CENTERS then
        return { ok = false, reason = "no_runtime" }
    end
    now = now or os.time()
    local smods = rawget(_G, "SMODS")
    local catalog = Catalog.discover(namespace.config, runtime.P_CENTERS, smods and smods.Mods or nil)
    local bosses = {}
    for key, blind in pairs(runtime.P_BLINDS or {}) do
        if blind.boss then bosses[#bosses + 1] = key end
    end
    table.sort(bosses)
    local boss_key = bosses[1] and bosses[(now % #bosses) + 1] or nil
    return BlackMarket.generate(namespace.config, namespace.collection, {
        catalog = catalog,
        run_id = "debug_" .. tostring(now),
        boss_key = boss_key,
        now = now
    })
end

local HELP_TEXT = table.concat({
    "grdl <subcommand> - Gradelatro debug toolkit",
    "grdl g [set|add|sub <n>] - show or adjust the G balance",
    "grdl seed [g|ug] [count] - seed graded/raw test cards",
    "grdl clear - wipe cards and grading queue",
    "grdl license <0-12> - set the loadout license level",
    "grdl transport all|blue|green|red|purple|gold|reset - grant or reset shipping services",
    "grdl prof <antes> - set proficiency antes on every graded card",
    "grdl queue - finish all pending gradings now",
    "grdl bm - regenerate the black market offers"
}, "\n")

function DebugTools.dispatch(namespace, args)
    args = args or {}
    local collection = namespace and namespace.collection or nil
    local config = namespace and namespace.config or nil
    if not collection or not config then return "Gradelatro state unavailable.", "ERROR" end
    local sub = args[1]

    if sub == nil or sub == "help" then
        return HELP_TEXT
    end

    if sub == "g" then
        if not args[2] then
            return "G balance: " .. tostring(collection.currency_g or 0)
        end
        local result = DebugTools.adjust_currency(collection, args[2], args[3])
        if not result.ok then
            return "Usage: grdl g set|add|sub <amount> (" .. tostring(result.reason) .. ")", "ERROR"
        end
        Persistence.save(namespace)
        return "G balance: " .. tostring(result.currency_g)
    end

    if sub == "seed" then
        local runtime = rawget(_G, "G")
        if not runtime or not runtime.P_CENTERS then return "Game centers not loaded yet.", "ERROR" end
        local parsed = DebugTools.parse_seed_args({ args[2], args[3] })
        if not parsed.ok then
            return "Usage: grdl seed [g|ug] [count]", "ERROR"
        end
        local smods = rawget(_G, "SMODS")
        local catalog = Catalog.discover(config, runtime.P_CENTERS, smods and smods.Mods or nil)
        local result = DebugTools.seed_cards(collection, catalog, { count = parsed.count, graded = parsed.graded, config = config })
        if not result.ok then
            return "Seeding failed: " .. tostring(result.reason), "ERROR"
        end
        Persistence.save(namespace)
        return "Seeded " .. tostring(#result.cards) .. (parsed.graded and " graded" or " ungraded") .. " cards into the binder."
    end

    if sub == "clear" then
        local result = DebugTools.clear_collection(collection)
        if not result.ok then return "Clear failed: " .. tostring(result.reason), "ERROR" end
        Persistence.save(namespace)
        return "Cleared " .. tostring(result.cards_removed) .. " cards and " .. tostring(result.queue_removed) .. " queue entries."
    end

    if sub == "license" then
        local result = DebugTools.set_license(collection, args[2])
        if not result.ok then return "Usage: grdl license <0-12> (" .. tostring(result.reason) .. ")", "ERROR" end
        Persistence.save(namespace)
        return "Loadout license level: " .. tostring(result.level)
    end

    if sub == "transport" then
        if args[2] == "reset" then
            local result = DebugTools.reset_transports(collection)
            if not result.ok then return "Transport reset failed: " .. tostring(result.reason), "ERROR" end
            Persistence.save(namespace)
            return "Reset transports; removed " .. tostring(result.removed) .. " purchases."
        end
        local result = DebugTools.grant_transports(config, collection, args[2] or "all")
        if not result.ok then return "Usage: grdl transport all|blue|green|red|purple|gold|reset (" .. tostring(result.reason) .. ")", "ERROR" end
        Persistence.save(namespace)
        return "Granted transports: " .. table.concat(result.granted, ", ")
    end

    if sub == "prof" then
        local result = DebugTools.set_proficiency(collection, args[2])
        if not result.ok then return "Usage: grdl prof <antes> (" .. tostring(result.reason) .. ")", "ERROR" end
        Persistence.save(namespace)
        return "Set " .. tostring(result.antes) .. " antes on " .. tostring(result.updated) .. " graded cards."
    end

    if sub == "queue" then
        local result = DebugTools.finish_queue(collection)
        Persistence.save(namespace)
        return "Fast-forwarded " .. tostring(result.finished) .. " grading entries; open the binder to reveal."
    end

    if sub == "bm" then
        local result = DebugTools.regen_black_market(namespace)
        if not result.ok then return "Black market regen failed: " .. tostring(result.reason), "ERROR" end
        Persistence.save(namespace)
        return "Black market regenerated (" .. tostring(#(result.black_market.offers or {})) .. " offers)."
    end

    return "Unknown subcommand. " .. HELP_TEXT, "ERROR"
end

function DebugTools.install(namespace)
    local ok, dpAPI = pcall(require, "debugplus-api")
    if not ok or type(dpAPI) ~= "table" then return false end
    if not dpAPI.isVersionCompatible or not dpAPI.isVersionCompatible(1) then return false end
    local dp = dpAPI.registerID("Gradelatro")
    if not dp then return false end

    pcall(dp.addCommand, {
        name = "grdl",
        shortDesc = "Gradelatro debug toolkit",
        desc = HELP_TEXT,
        exec = function(args)
            return DebugTools.dispatch(namespace, args)
        end
    })

    return true
end

return DebugTools
