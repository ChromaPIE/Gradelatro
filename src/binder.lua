local Binder = {}

local STATUS_KEYS = {
    raw = "grdl_k_status_raw",
    graded = "grdl_k_status_graded",
    queued = "grdl_k_status_queued",
    sold = "grdl_k_status_sold",
    lost = "grdl_k_status_lost"
}

local function is_owned(card)
    return card.status ~= "lost" and card.status ~= "sold"
end

local function status_key(status)
    return STATUS_KEYS[status or "raw"] or "grdl_k_status_unknown"
end

function Binder.summary(collection)
    collection = collection or {}
    local summary = {
        currency_g = math.max(0, math.floor(collection.currency_g or 0)),
        total_cards = 0,
        owned_cards = 0,
        raw_cards = 0,
        graded_cards = 0,
        grading_queue = #(collection.grading_queue or {})
    }

    for _, card in ipairs(collection.cards or {}) do
        summary.total_cards = summary.total_cards + 1
        if is_owned(card) then
            summary.owned_cards = summary.owned_cards + 1
        end
        if card.status == "graded" then
            summary.graded_cards = summary.graded_cards + 1
        elseif card.status == "raw" or card.status == nil then
            summary.raw_cards = summary.raw_cards + 1
        end
    end

    return summary
end

function Binder.card_rows(collection, args)
    collection = collection or {}
    args = args or {}
    local limit = args.limit or 20
    local rows = {}

    for _, card in ipairs(collection.cards or {}) do
        if args.include_lost or is_owned(card) then
            rows[#rows + 1] = {
                id = card.id,
                center_key = card.center_key,
                name_key = card.local_key or card.center_key or card.id,
                edition = card.edition or "base",
                status = card.status or "raw",
                status_key = status_key(card.status),
                grade = card.grade,
                acquired_at = card.acquired_at or 0
            }
        end
    end

    table.sort(rows, function(a, b)
        if a.acquired_at ~= b.acquired_at then return a.acquired_at > b.acquired_at end
        return tostring(a.id) < tostring(b.id)
    end)

    while #rows > limit do
        table.remove(rows)
    end

    return rows
end

return Binder
