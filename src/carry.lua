local Carry = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Condition = load_src("condition.lua")
local Rng = load_src("rng.lua")
local Storage = load_src("storage.lua")

local function carry_card(state)
    if not state or not state.carry then return nil end
    return Storage.find_card(state, state.carry.card_id)
end

function Carry.select_for_run(config, state, args)
    args = args or {}
    if not state then return { ok = false, reason = "missing_collection" } end
    if state.carry then return { ok = false, reason = "carry_taken" } end

    local card = Storage.find_card(state, args.card_id)
    if not card then return { ok = false, reason = "card_not_found" } end
    if (card.status or "raw") ~= "raw" then return { ok = false, reason = "not_raw" } end
    if not card.condition then return { ok = false, reason = "missing_condition" } end

    card.status = "carried"
    state.carry = {
        card_id = card.id,
        run_id = tostring(args.run_id or "unknown"),
        selected_at = args.now or os.time(),
        activations = {},
        uses = 0
    }
    return { ok = true, carry = state.carry, card = card }
end

function Carry.release(state)
    if not state or not state.carry then return { ok = false, reason = "no_carry" } end
    local card = carry_card(state)
    if card and card.status == "carried" then
        card.status = "raw"
    end
    state.carry = nil
    return { ok = true, card = card }
end

function Carry.withdraw(state)
    return Carry.release(state)
end

function Carry.reconcile(state, current_run_id)
    if not state or not state.carry then return { ok = true, released = false } end
    if tostring(current_run_id) == state.carry.run_id then
        return { ok = true, released = false }
    end
    Carry.release(state)
    return { ok = true, released = true }
end

function Carry.can_activate(state, args)
    args = args or {}
    if not state or not state.carry then return { ok = false, reason = "no_carry" } end
    if tostring(args.run_id) ~= state.carry.run_id then return { ok = false, reason = "wrong_run" } end
    local ante = math.floor(args.ante or 0)
    if state.carry.activations[tostring(ante)] then return { ok = false, reason = "ante_used" } end
    return { ok = true, ante = ante }
end

local function roll_wear(config, rand)
    local settings = config.carry
    local roll = rand()
    if roll < settings.minor_chance then
        return "minor", settings.minor_min + rand() * (settings.minor_max - settings.minor_min)
    end
    if roll < settings.minor_chance + settings.moderate_chance then
        return "moderate", settings.moderate_min + rand() * (settings.moderate_max - settings.moderate_min)
    end
    return "severe", settings.severe_min + rand() * (settings.severe_max - settings.severe_min)
end

function Carry.apply_use(config, state, args)
    args = args or {}
    local gate = Carry.can_activate(state, args)
    if not gate.ok then return gate end

    local card = carry_card(state)
    if not card then return { ok = false, reason = "card_not_found" } end
    if not card.condition then return { ok = false, reason = "missing_condition" } end

    local rand = Rng.lcg(args.rng_seed or args.now or os.time())
    local tier, intensity = roll_wear(config, rand)
    card.condition = Condition.apply_wear(card.condition, card.edition, intensity)
    card.wear_count = (card.wear_count or 0) + 1

    state.carry.activations[tostring(gate.ante)] = true
    state.carry.uses = (state.carry.uses or 0) + 1

    return {
        ok = true,
        ante = gate.ante,
        tier = tier,
        intensity = intensity,
        condition = card.condition
    }
end

function Carry.mark_lost(state, args)
    if not state or not state.carry then return { ok = false, reason = "no_carry" } end
    local card = carry_card(state)
    if card then
        Storage.mark_lost(state, card.id, (args and args.reason) or "carry")
    end
    state.carry = nil
    return { ok = true, card = card }
end

function Carry.sleeve_info(state)
    if not state or not state.carry then return nil end
    local card = carry_card(state)
    if not card then return nil end
    return {
        card_id = card.id,
        center_key = card.center_key,
        name_key = card.local_key or card.center_key or card.id,
        edition = card.edition or "base",
        run_id = state.carry.run_id,
        uses = state.carry.uses or 0
    }
end

return Carry
