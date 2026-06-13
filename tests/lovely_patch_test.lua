local H = dofile("tests/test_helper.lua")

local file = assert(io.open("lovely.toml", "rb"))
local text = file:read("*a")
file:close()

H.assert_true(text:find("desc_nodes%.grdl_hide_title") ~= nil, "lovely patch checks the inscription title flag")
H.assert_true(text:find("table%.remove%(box%.nodes, 1%)") ~= nil, "lovely patch removes the title row")

print("lovely patch tests ok")
