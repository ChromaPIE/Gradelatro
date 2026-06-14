local H = dofile("tests/test_helper.lua")
local Storage = dofile("src/core/storage.lua")

local state = Storage.normalize(nil)
H.assert_equal(state.schema_version, 1, "schema version")
H.assert_equal(state.currency_g, 0, "initial currency")
H.assert_equal(#state.cards, 0, "initial cards")
H.assert_equal(state.next_cert_id, 1, "initial cert id")
H.assert_true(type(state.settlements) == "table", "initial settlements table")

Storage.add_currency(state, 120)
Storage.add_currency(state, -20)
H.assert_equal(state.currency_g, 100, "currency mutation")
H.assert_equal(Storage.spend_currency(state, 40), true, "spend available currency")
H.assert_equal(state.currency_g, 60, "currency after spend")
H.assert_equal(Storage.spend_currency(state, 100), false, "reject overspend")
H.assert_equal(state.currency_g, 60, "currency unchanged after failed spend")

local card = Storage.add_raw_card(state, {
    center_key = "j_joker",
    local_key = "joker",
    series_key = "BALATRO Series",
    mod_id = "Balatro",
    rarity = "common",
    edition = "base",
    condition = {
        centering = 9.1,
        print_quality = 9.0,
        corners = 8.9,
        edges = 9.2,
        surface = 9.0
    },
    acquired_at = 1000,
    acquired_year = 2026,
    source_run_id = "run_abc",
    source_run_started_at = 900,
    source = "win_buyout"
})

H.assert_equal(card.id, "grdl_1", "first card id")
H.assert_equal(card.status, "raw", "raw status")
H.assert_equal(card.local_key, "joker", "local key stored")
H.assert_equal(card.series_key, "BALATRO Series", "series key stored")
H.assert_equal(card.acquired_year, 2026, "acquired year stored")
H.assert_equal(card.source_run_id, "run_abc", "source run id stored")
H.assert_equal(card.source_run_started_at, 900, "source run start stored")
H.assert_equal(state.next_card_id, 2, "next id")
H.assert_equal(Storage.count_owned_center(state, "j_joker"), 1, "owned count")

local index = Storage.build_index(state)
H.assert_equal(index.by_id[card.id], card, "index by id")
H.assert_equal(index.center_counts.j_joker, 1, "index center count")

Storage.mark_lost(state, card.id, "destroyed_in_run")
H.assert_equal(state.cards[1].status, "lost", "lost status")
H.assert_equal(state.cards[1].lost_reason, "destroyed_in_run", "lost reason")
H.assert_equal(Storage.count_owned_center(state, "j_joker"), 0, "lost cards not counted")

local post_loss_index = Storage.build_index(state)
H.assert_equal(post_loss_index.center_counts.j_joker or 0, 0, "lost cards not counted in index")

H.assert_equal(Storage.allocate_cert_number(state), "000001", "first cert number")
H.assert_equal(Storage.allocate_cert_number(state), "000002", "second cert number")
H.assert_equal(state.next_cert_id, 3, "next cert id")

local migrated = Storage.normalize({
    cards = {
        { id = "grdl_m1", center_key = "j_joker", status = "carried", edition = "base" }
    },
    carry = { card_id = "grdl_m1", run_id = "OLD" }
})
H.assert_equal(migrated.cards[1].status, "raw", "legacy carried card migrates to raw")
H.assert_equal(migrated.carry, nil, "legacy carry block cleared")

local polluted = Storage.normalize({
    cards = {
        {
            id = "grdl_dirty",
            status = "graded",
            center_key = "j_joker",
            local_key = "joker",
            edition = "negative",
            name = "中文牌名",
            loc_txt = { name = "中文牌名", text = { "中文描述" } },
            config = { center = { key = "j_joker", loc_txt = { name = "中文牌名" } } },
            ability_UIBox_table = { main = { "localized ui" } },
            children = { h_popup = true },
            grade = 10,
            cert_number = "000123",
            proficiency = {
                antes = 100,
                note = "刻字\n第二行",
                badge_text = "徽标中文",
                badge_colour = "00FF80",
                tooltip_colour = "1A2B3C",
                eternal = true,
                loc_txt = { text = "remove me" }
            }
        }
    }
})
local clean = polluted.cards[1]
H.assert_equal(clean.name, nil, "localized card name stripped")
H.assert_equal(clean.loc_txt, nil, "localized card loc_txt stripped")
H.assert_equal(clean.config, nil, "runtime card config stripped")
H.assert_equal(clean.ability_UIBox_table, nil, "runtime tooltip table stripped")
H.assert_equal(clean.children, nil, "runtime children stripped")
H.assert_equal(clean.grade, 10, "grade preserved")
H.assert_equal(clean.cert_number, "000123", "cert preserved")
H.assert_equal(clean.proficiency.note, "刻字\n第二行", "custom inscription preserved")
H.assert_equal(clean.proficiency.badge_text, "徽标中文", "custom badge text preserved")
H.assert_equal(clean.proficiency.badge_colour, "00FF80", "custom badge colour preserved")
H.assert_equal(clean.proficiency.tooltip_colour, "1A2B3C", "custom tooltip colour preserved")
H.assert_equal(clean.proficiency.eternal, true, "custom eternal preserved")
H.assert_equal(clean.proficiency.loc_txt, nil, "localized proficiency junk stripped")

print("storage tests ok")
