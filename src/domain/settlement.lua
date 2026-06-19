local Settlement = {}

local function load_src(path)
    return assert(SMODS.load_file("src/" .. path))()
end

local Economy = load_src("domain/economy.lua")
local StakeEconomy = load_src("domain/stake_economy.lua")
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
        stake_level = args.stake_level,
        won = args.won,
        dollars = args.dollars
    })
    local quote = args.won and StakeEconomy.win_quote(args.stake_level or 1, args.dollars) or nil
    Storage.add_currency(state, amount)

    local entry = {
        key = key,
        run_id = args.run_id,
        run_started_at = args.run_started_at,
        gate = args.gate,
        stake_level = args.stake_level,
        entry_fee = quote and quote.entry_fee or nil,
        fixed_reward = quote and quote.fixed_reward or nil,
        cash_cap = quote and quote.cash_cap or nil,
        cash_component = quote and quote.cash_component or nil,
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
