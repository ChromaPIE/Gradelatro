local Settlement = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Economy = load_src("domain/economy.lua")
local Storage = load_src("core/storage.lua")

local function run_key(args)
    return tostring(args.run_id or "unknown") .. ":" .. tostring(args.run_started_at or "unknown")
end

function Settlement.apply(config, state, args)
    args = args or {}
    if not state then return { ok = false, reason = "missing_collection" } end

    state.settlements = type(state.settlements) == "table" and state.settlements or {}
    local key = run_key(args)
    if state.settlements[key] then
        return {
            ok = true,
            duplicate = true,
            key = key,
            amount = 0,
            entry = state.settlements[key]
        }
    end

    local amount = Economy.settlement_g(config, {
        gate = args.gate,
        won = args.won,
        dollars = args.dollars
    })
    Storage.add_currency(state, amount)

    local entry = {
        key = key,
        run_id = args.run_id,
        run_started_at = args.run_started_at,
        gate = args.gate,
        won = args.won == true,
        dollars = math.max(0, math.floor(args.dollars or 0)),
        amount = amount,
        settled_at = args.settled_at
    }
    state.settlements[key] = entry

    return {
        ok = true,
        duplicate = false,
        key = key,
        amount = amount,
        entry = entry
    }
end

return Settlement
