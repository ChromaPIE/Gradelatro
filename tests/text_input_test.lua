local H = dofile("tests/test_helper.lua")
local TextInput = dofile("src/ui/text_input.lua")

local text = "Alpha\r\n中文第二行\nThird"
local lines = TextInput.split_lines(text)
H.assert_equal(#lines, 3, "split preserves three logical lines")
H.assert_equal(lines[1], "Alpha", "first line normalized")
H.assert_equal(lines[2], "中文第二行", "unicode line preserved")
H.assert_equal(lines[3], "Third", "third line preserved")

local capped = TextInput.split_lines("A\nB\nC\nD", 3)
H.assert_equal(#capped, 3, "line cap applied")
H.assert_equal(capped[3], "C", "cap keeps original order")

local state = { text = "" }
local pasted = TextInput.apply_paste(state, function() return "刻字\n第二行" end)
H.assert_equal(pasted.ok, true, "paste succeeds")
H.assert_equal(state.text, "刻字\n第二行", "paste stores unicode and newline")

local empty = TextInput.apply_paste(state, function() return nil end)
H.assert_equal(empty.ok, false, "nil clipboard rejected")
H.assert_equal(empty.reason, "empty_clipboard", "nil clipboard reason")

TextInput.clear(state)
H.assert_equal(state.text, "", "clear resets text")

TextInput.accept_textinput(state, "未来IME")
H.assert_equal(state.text, "未来IME", "future textinput entry appends text")

print("text input tests ok")
