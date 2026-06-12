local H = dofile("tests/test_helper.lua")
local Stakes = dofile("src/domain/stakes.lua")

local anchors = {
    stake_red = 2,
    stake_blue = 5,
    stake_gold = 8
}

H.assert_equal(Stakes.gate_for_level(nil, 1), "red", "nil anchors default")
H.assert_equal(Stakes.gate_for_level(anchors, 1), "red", "white below red")
H.assert_equal(Stakes.gate_for_level(anchors, 2), "red", "red gate")
H.assert_equal(Stakes.gate_for_level(anchors, 4), "blue", "between red and blue")
H.assert_equal(Stakes.gate_for_level(anchors, 6), "pre_gold", "between blue and gold")
H.assert_equal(Stakes.gate_for_level(anchors, 8), "gold_plus", "gold gate")
H.assert_equal(Stakes.can_buyout("red", "common"), true, "red common")
H.assert_equal(Stakes.can_buyout("red", "uncommon"), false, "red uncommon blocked")
H.assert_equal(Stakes.can_buyout("blue", "uncommon"), true, "blue uncommon")
H.assert_equal(Stakes.can_buyout("pre_gold", "rare"), true, "pre-gold rare")
H.assert_equal(Stakes.can_buyout("pre_gold", "legendary"), false, "pre-gold legendary blocked")
H.assert_equal(Stakes.can_buyout("gold_plus", "exotic"), true, "gold exotic")
H.assert_equal(Stakes.can_buyout("gold_plus", "unknown_high"), true, "gold unknown high")

print("stakes tests ok")
