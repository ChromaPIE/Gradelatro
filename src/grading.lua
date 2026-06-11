local Grading = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Condition = load_src("condition.lua")
local Economy = load_src("economy.lua")
local Storage = load_src("storage.lua")

local function complete_condition(condition)
    condition = condition or {}
    return {
        centering = condition.centering or 8.0,
        print_quality = condition.print_quality or 8.0,
        corners = condition.corners or 8.0,
        edges = condition.edges or 8.0,
        surface = condition.surface or 8.0
    }
end

function Grading.duration_for(config, service)
    local grading = config.grading or {}
    local durations = grading.durations or {}
    local scale = durations[grading.time_scale] or durations.arcade or {}
    return scale[service or grading.default_service]
end

function Grading.fee_for(config, card, service)
    local rav = Economy.raw_anchor_value(config, {
        rarity = card and card.rarity or nil,
        edition = card and card.edition or nil
    })
    return Economy.grading_fee(config, rav, service)
end

function Grading.submit(config, state, args)
    args = args or {}
    local card = Storage.find_card(state, args.card_id)
    if not card then
        return { ok = false, reason = "card_not_found" }
    end
    if (card.status or "raw") ~= "raw" then
        return { ok = false, reason = "not_raw" }
    end

    local service = args.service or config.grading.default_service
    local duration = Grading.duration_for(config, service)
    if not duration then
        return { ok = false, reason = "unknown_service" }
    end

    local fee = Grading.fee_for(config, card, service)
    if not Storage.spend_currency(state, fee) then
        return { ok = false, reason = "insufficient_funds", fee = fee }
    end

    local now = args.now or os.time()
    card.status = "queued"
    local entry = {
        card_id = card.id,
        service = service,
        fee = fee,
        submitted_at = now,
        due_at = now + duration
    }
    state.grading_queue[#state.grading_queue + 1] = entry

    return { ok = true, entry = entry, fee = fee, card = card }
end

function Grading.process_due(config, state, now)
    now = now or os.time()
    local revealed = {}
    local remaining = {}
    local index = Storage.build_index(state)

    for _, entry in ipairs(state.grading_queue or {}) do
        local card = Storage.find_card(state, entry.card_id, index)
        if not card then
            -- orphaned entry: drop it instead of blocking the queue forever
        elseif (entry.due_at or 0) <= now then
            card.status = "graded"
            card.grade = Condition.grade(complete_condition(card.condition))
            card.graded_at = entry.due_at
            card.grade_service = entry.service
            card.cert_number = Storage.allocate_cert_number(state)
            revealed[#revealed + 1] = card
        else
            remaining[#remaining + 1] = entry
        end
    end

    state.grading_queue = remaining
    return { revealed = revealed, remaining = #remaining }
end

function Grading.queue_rows(state, now)
    now = now or os.time()
    local rows = {}
    local index = Storage.build_index(state)

    for _, entry in ipairs(state.grading_queue or {}) do
        local card = Storage.find_card(state, entry.card_id, index)
        local remaining = math.max(0, (entry.due_at or now) - now)
        local duration = math.max(1, (entry.due_at or now) - (entry.submitted_at or entry.due_at or now))
        rows[#rows + 1] = {
            card_id = entry.card_id,
            center_key = card and card.center_key or nil,
            name_key = card and (card.local_key or card.center_key) or entry.card_id,
            edition = card and (card.edition or "base") or nil,
            service = entry.service,
            submitted_at = entry.submitted_at,
            due_at = entry.due_at,
            remaining = remaining,
            progress = math.max(0, math.min(1, 1 - remaining / duration)),
            ready = (entry.due_at or 0) <= now
        }
    end

    return rows
end

return Grading
