local H = dofile("tests/test_helper.lua")
local Proficiency = dofile("src/domain/proficiency.lua")

local card = { status = "graded" }
H.assert_equal(Proficiency.level(card), 0, "fresh card level zero")
H.assert_equal(Proficiency.next_threshold(card), 5, "first threshold five")

for _ = 1, 5 do Proficiency.record_ante(card) end
H.assert_equal(Proficiency.antes(card), 5, "antes accumulate")
H.assert_equal(Proficiency.level(card), 1, "level one at five")
H.assert_equal(Proficiency.allows_edition(card), true, "level one unlocks edition")
H.assert_equal(Proficiency.can_note(card), false, "note locked below two")

card.proficiency.antes = 13
H.assert_equal(Proficiency.level(card), 2, "level two at thirteen")
H.assert_equal(Proficiency.can_note(card), true, "note unlocked")
card.proficiency.antes = 34
H.assert_equal(Proficiency.level(card), 3, "level three at thirty-four")
H.assert_equal(Proficiency.can_eternal(card), true, "eternal unlocked")
card.proficiency.antes = 89
H.assert_equal(Proficiency.level(card), 4, "level four at eighty-nine")
H.assert_equal(Proficiency.can_badge(card), true, "badge unlocked")
card.proficiency.antes = 100
H.assert_equal(Proficiency.level(card), 5, "g level at one hundred")
H.assert_equal(Proficiency.can_tint(card), true, "tint unlocked")
H.assert_equal(Proficiency.next_threshold(card), nil, "maxed has no next threshold")
H.assert_equal(Proficiency.level_label(5), "G", "g label")
H.assert_equal(Proficiency.level_label(0), "0", "zero label")
H.assert_equal(Proficiency.level_label(3), "III", "roman label")

local raw = { status = "raw", proficiency = { antes = 100 } }
H.assert_equal(Proficiency.level(raw), 0, "raw card pinned to level zero")
H.assert_equal(Proficiency.record_ante(raw), false, "raw card never accrues")
H.assert_equal(Proficiency.allows_edition(raw), false, "raw card never has edition")

-- metadata setters
local low = { status = "graded", proficiency = { antes = 5 } }
H.assert_equal(Proficiency.set_note(low, "hi").reason, "locked", "note gated")
local high = { status = "graded", proficiency = { antes = 100 } }
H.assert_equal(Proficiency.set_note(high, "my note").ok, true, "note set")
H.assert_equal(high.proficiency.note, "my note", "note stored")
H.assert_equal(Proficiency.set_badge(high, "OG COLLECTION").ok, true, "badge set")
H.assert_equal(high.proficiency.badge_text, "OG COLLECTION", "badge stored")
H.assert_equal(Proficiency.set_eternal(high, true).ok, true, "eternal pref set")
H.assert_equal(high.proficiency.eternal, true, "eternal stored")
H.assert_equal(Proficiency.set_tint(high, "#1A2b3C").ok, true, "tint accepts hash hex")
H.assert_equal(high.proficiency.tooltip_colour, "1A2B3C", "tint stored upper no hash")
H.assert_equal(Proficiency.set_tint(high, "red").reason, "invalid_hex", "garbage hex rejected")
H.assert_equal(Proficiency.set_tint(high, "").ok, true, "empty clears tint")
H.assert_equal(high.proficiency.tooltip_colour, nil, "tint cleared")
H.assert_equal(Proficiency.set_note(high, "").ok, true, "empty clears note")
H.assert_equal(high.proficiency.note, nil, "note cleared")

local colour = Proficiency.parse_hex("FF8000")
H.assert_near(colour[1], 1, 0.001, "red channel")
H.assert_near(colour[2], 0.502, 0.001, "green channel")
H.assert_near(colour[3], 0, 0.001, "blue channel")
H.assert_equal(colour[4], 1, "alpha one")
H.assert_equal(Proficiency.parse_hex("12345"), nil, "short hex rejected")

print("proficiency tests ok")
