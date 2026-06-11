local H = dofile("tests/test_helper.lua")
local Config = dofile("src/config.lua")
local Storage = dofile("src/storage.lua")
local Carry = dofile("src/carry.lua")

local config = Config.normalize({})

H.assert_near(config.carry.minor_chance, 0.70, 0.000001, "minor wear chance default")
H.assert_near(config.carry.moderate_chance, 0.25, 0.000001, "moderate wear chance default")
H.assert_true(config.carry.severe_max > config.carry.moderate_max, "severe wear outranks moderate")

local mint = { centering = 9.8, print_quality = 9.8, corners = 9.8, edges = 9.8, surface = 9.8 }

local function fresh_state()
    local state = Storage.normalize({})
    local raw = Storage.add_raw_card(state, {
        center_key = "j_joker",
        local_key = "joker",
        mod_id = "Balatro",
        rarity = "common",
        edition = "negative",
        condition = { centering = mint.centering, print_quality = mint.print_quality, corners = mint.corners, edges = mint.edges, surface = mint.surface },
        acquired_at = 1000
    })
    return state, raw
end

local state, raw = fresh_state()
local graded = Storage.add_raw_card(state, {
    center_key = "j_g",
    local_key = "g",
    mod_id = "Balatro",
    rarity = "common",
    edition = "base",
    condition = mint,
    acquired_at = 1001
})
graded.status = "graded"

H.assert_equal(Carry.select_for_run(config, state, { card_id = "grdl_999", run_id = "R1" }).reason, "card_not_found", "unknown card rejected")
H.assert_equal(Carry.select_for_run(config, state, { card_id = graded.id, run_id = "R1" }).reason, "not_raw", "graded card cannot be carried")

local selected = Carry.select_for_run(config, state, { card_id = raw.id, run_id = "R1", now = 2000 })
H.assert_equal(selected.ok, true, "raw card selected for run")
H.assert_equal(state.carry.card_id, raw.id, "carry stores card id")
H.assert_equal(state.carry.run_id, "R1", "carry stores run id")
H.assert_equal(raw.status, "carried", "card marked carried")

local second_raw = Storage.add_raw_card(state, {
    center_key = "j_two",
    local_key = "two",
    mod_id = "Balatro",
    rarity = "common",
    edition = "base",
    condition = mint,
    acquired_at = 1002
})
H.assert_equal(Carry.select_for_run(config, state, { card_id = second_raw.id, run_id = "R1" }).reason, "carry_taken", "one carry per run")

local sleeve = Carry.sleeve_info(state)
H.assert_equal(sleeve.card_id, raw.id, "sleeve info card id")
H.assert_equal(sleeve.edition, "negative", "sleeve info edition")
H.assert_equal(sleeve.uses, 0, "sleeve info uses start at zero")

H.assert_equal(Carry.can_activate(state, { run_id = "R2", ante = 1 }).reason, "wrong_run", "wrong run cannot activate")
H.assert_equal(Carry.can_activate(state, { run_id = "R1", ante = 1 }).ok, true, "fresh ante can activate")

local used = Carry.apply_use(config, state, { run_id = "R1", ante = 1, rng_seed = 5 })
H.assert_equal(used.ok, true, "activation applies wear")
H.assert_true(used.tier == "minor" or used.tier == "moderate" or used.tier == "severe", "wear tier reported")
H.assert_true(used.intensity > 0, "wear intensity positive")
H.assert_equal(raw.condition.centering, mint.centering, "centering immutable")
H.assert_equal(raw.condition.print_quality, mint.print_quality, "print quality immutable")
H.assert_true(raw.condition.corners < mint.corners, "corners wear down")
H.assert_true(raw.condition.edges < mint.edges, "edges wear down")
H.assert_true(raw.condition.surface < mint.surface, "surface wears down")
H.assert_true((mint.surface - raw.condition.surface) > (mint.corners - raw.condition.corners), "negative edition wears surface harder than corners")
H.assert_equal(raw.wear_count, 1, "wear count incremented")
H.assert_equal(Carry.sleeve_info(state).uses, 1, "sleeve info counts uses")

H.assert_equal(Carry.can_activate(state, { run_id = "R1", ante = 1 }).reason, "ante_used", "same ante blocked")
H.assert_equal(Carry.apply_use(config, state, { run_id = "R1", ante = 1, rng_seed = 6 }).reason, "ante_used", "same ante cannot reuse")
H.assert_equal(Carry.can_activate(state, { run_id = "R1", ante = 2 }).ok, true, "next ante can activate")

local replay_state, replay_raw = fresh_state()
Carry.select_for_run(config, replay_state, { card_id = replay_raw.id, run_id = "R1" })
Carry.apply_use(config, replay_state, { run_id = "R1", ante = 1, rng_seed = 5 })
H.assert_near(replay_raw.condition.surface, raw.condition.surface, 0.000001, "same seed reproduces wear")

local minor_count = 0
for seed = 1, 40 do
    local tier_state, tier_raw = fresh_state()
    Carry.select_for_run(config, tier_state, { card_id = tier_raw.id, run_id = "R1" })
    local result = Carry.apply_use(config, tier_state, { run_id = "R1", ante = 1, rng_seed = seed })
    if result.tier == "minor" then minor_count = minor_count + 1 end
    for _, part in ipairs({ "corners", "edges", "surface" }) do
        H.assert_true(tier_raw.condition[part] >= 1.0 and tier_raw.condition[part] <= 10.0, "wear stays in bounds")
    end
end
H.assert_true(minor_count >= 20, "minor wear dominates the tier distribution")

local lost = Carry.mark_lost(state, { now = 3000, reason = "sold" })
H.assert_equal(lost.ok, true, "loss succeeds")
H.assert_equal(raw.status, "lost", "card permanently lost")
H.assert_equal(raw.lost_reason, "sold", "loss reason stored")
H.assert_equal(state.carry, nil, "carry cleared after loss")

local release_state, release_raw = fresh_state()
Carry.select_for_run(config, release_state, { card_id = release_raw.id, run_id = "R1" })
local released = Carry.release(release_state)
H.assert_equal(released.ok, true, "release succeeds")
H.assert_equal(release_raw.status, "raw", "released card back to raw")
H.assert_equal(release_state.carry, nil, "carry cleared on release")
H.assert_near(release_raw.condition.surface, mint.surface, 0.000001, "release applies no wear")
H.assert_equal(Carry.release(release_state).reason, "no_carry", "double release rejected")

local rec_state, rec_raw = fresh_state()
Carry.select_for_run(config, rec_state, { card_id = rec_raw.id, run_id = "R1" })
H.assert_equal(Carry.reconcile(rec_state, "R1").released, false, "same run keeps carry")
H.assert_true(rec_state.carry ~= nil, "carry survives same-run reconcile")
H.assert_equal(Carry.reconcile(rec_state, "R2").released, true, "stale run releases carry")
H.assert_equal(rec_raw.status, "raw", "reconciled card back to raw")
H.assert_equal(Carry.reconcile(rec_state, "R2").released, false, "reconcile without carry is a no-op")

print("carry tests ok")
