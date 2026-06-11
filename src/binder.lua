local Binder = {}

local STATUS_KEYS = {
    raw = "grdl_k_status_raw",
    carried = "grdl_k_status_carried",
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

local function newest_first(a, b)
    if a.acquired_at ~= b.acquired_at then return a.acquired_at > b.acquired_at end
    return tostring(a.id) < tostring(b.id)
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

function Binder.entries(collection, args)
    collection = collection or {}
    args = args or {}
    local centers = args.centers
    local entries = {}
    local hidden = 0

    for _, card in ipairs(collection.cards or {}) do
        if args.include_lost or is_owned(card) then
            if centers and card.center_key and not centers[card.center_key] then
                hidden = hidden + 1
            else
                entries[#entries + 1] = {
                    id = card.id,
                    center_key = card.center_key,
                    name_key = card.local_key or card.center_key or card.id,
                    local_key = card.local_key,
                    edition = card.edition or "base",
                    rarity = card.rarity,
                    status = card.status or "raw",
                    status_key = status_key(card.status),
                    grade = card.grade,
                    cert_number = card.cert_number,
                    acquired_at = card.acquired_at or 0,
                    acquired_year = card.acquired_year,
                    acquired_month = card.acquired_month,
                    acquired_day = card.acquired_day,
                    acquired_price = card.acquired_price,
                    mod_id = card.mod_id
                }
            end
        end
    end

    table.sort(entries, newest_first)
    return { entries = entries, hidden = hidden }
end

function Binder.page(entries, page, per_page)
    entries = entries or {}
    per_page = math.max(1, per_page or 10)
    local total = #entries
    local pages = math.max(1, math.ceil(total / per_page))
    page = math.max(1, math.min(page or 1, pages))

    local items = {}
    local offset = (page - 1) * per_page
    for i = 1, per_page do
        local entry = entries[offset + i]
        if not entry then break end
        items[#items + 1] = entry
    end

    return {
        items = items,
        page = page,
        pages = pages,
        total = total,
        per_page = per_page
    }
end


return Binder
