local DebugTools = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Catalog = load_src("catalog.lua")
local Persistence = load_src("persistence.lua")
local Storage = load_src("storage.lua")

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

    local created = {}
    local cursor = {}
    local mod_index = 0
    while #created < count and #mod_order > 0 do
        mod_index = mod_index % #mod_order + 1
        local mod_id = mod_order[mod_index]
        cursor[mod_id] = (cursor[mod_id] or 0) + 1
        local entry = by_mod[mod_id][cursor[mod_id]]
        if entry then
            local n = #created + 1
            local grade = SEED_GRADES[(n - 1) % #SEED_GRADES + 1]
            local edition_index = ((n - 1) + math.floor((n - 1) / #SEED_EDITIONS)) % #SEED_EDITIONS + 1
            local edition = SEED_EDITIONS[edition_index]
            local card = Storage.add_raw_card(state, {
                center_key = entry.center_key,
                local_key = entry.local_key,
                series_key = entry.series_key,
                mod_id = entry.mod_id,
                rarity = entry.rarity,
                edition = edition,
                condition = DebugTools.condition_for_grade(grade),
                acquired_at = now,
                acquired_year = tonumber(os.date("%Y", now)),
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

function DebugTools.install(namespace)
    local ok, dpAPI = pcall(require, "debugplus-api")
    if not ok or type(dpAPI) ~= "table" then return false end
    if not dpAPI.isVersionCompatible or not dpAPI.isVersionCompatible(1) then return false end
    local dp = dpAPI.registerID("Gradelatro")
    if not dp then return false end

    pcall(dp.addCommand, {
        name = "grdlg",
        shortDesc = "Adjust Gradelatro G balance",
        desc = "Show or adjust the Gradelatro G balance. Usage:\ngrdlg - show current balance\ngrdlg set [amount]\ngrdlg add [amount]\ngrdlg sub [amount]",
        exec = function(args)
            local collection = namespace and namespace.collection or nil
            if not collection then return "Gradelatro collection unavailable.", "ERROR" end
            if not args[1] then
                return "G balance: " .. tostring(collection.currency_g or 0)
            end
            local result = DebugTools.adjust_currency(collection, args[1], args[2])
            if not result.ok then
                return "Usage: grdlg set|add|sub [amount] (" .. tostring(result.reason) .. ")", "ERROR"
            end
            Persistence.save(namespace)
            return "G balance: " .. tostring(result.currency_g)
        end
    })

    pcall(dp.addCommand, {
        name = "grdlseed",
        shortDesc = "Seed test cards",
        desc = "Seed Jokers into the Gradelatro binder for testing; grades and editions cycle, source mods rotate. Usage:\ngrdlseed [count] - graded cards, default 10\ngrdlseed g [count] - graded cards\ngrdlseed ug [count] - ungraded raw cards",
        exec = function(args)
            local collection = namespace and namespace.collection or nil
            local config = namespace and namespace.config or nil
            local runtime = rawget(_G, "G")
            if not collection or not config then return "Gradelatro state unavailable.", "ERROR" end
            if not runtime or not runtime.P_CENTERS then return "Game centers not loaded yet.", "ERROR" end
            local parsed = DebugTools.parse_seed_args(args)
            if not parsed.ok then
                return "Usage: grdlseed [g|ug] [count]", "ERROR"
            end
            local smods = rawget(_G, "SMODS")
            local catalog = Catalog.discover(config, runtime.P_CENTERS, smods and smods.Mods or nil)
            local result = DebugTools.seed_cards(collection, catalog, { count = parsed.count, graded = parsed.graded })
            if not result.ok then
                return "Seeding failed: " .. tostring(result.reason), "ERROR"
            end
            Persistence.save(namespace)
            return "Seeded " .. tostring(#result.cards) .. (parsed.graded and " graded" or " ungraded") .. " cards into the binder."
        end
    })

    pcall(dp.addCommand, {
        name = "grdlclear",
        shortDesc = "Clear the Gradelatro binder",
        desc = "Remove every card and grading queue entry from the Gradelatro collection. Currency, certificate counters, and settlement history are kept. Usage:\ngrdlclear",
        exec = function()
            local collection = namespace and namespace.collection or nil
            if not collection then return "Gradelatro collection unavailable.", "ERROR" end
            local result = DebugTools.clear_collection(collection)
            if not result.ok then
                return "Clear failed: " .. tostring(result.reason), "ERROR"
            end
            Persistence.save(namespace)
            return "Cleared " .. tostring(result.cards_removed) .. " cards and " .. tostring(result.queue_removed) .. " queue entries."
        end
    })

    return true
end

return DebugTools
