local Config = require("noice.config")
Config.setup()

local Cmdline = require("noice.ui.cmdline")
local Manager = require("noice.message.manager")
local Message = require("noice.message")
local State = require("noice.ui.state")

---@return NoiceMessage
local function confirm_message()
  local m = Message("msg_show", "confirm")
  m:set("Save changes?")
  return m
end

local function show(prompt)
  Cmdline.on_show("cmdline_show", {}, 0, "", prompt, 0, 1)
end

local function hide()
  Cmdline.on_hide(nil, 1)
end

-- Lets the callback scheduled by on_hide run
local function settle()
  vim.wait(20)
end

describe("cmdline confirm", function()
  after_each(function()
    -- An open cmdline counts as blocking for every spec after this one
    Cmdline.cmdlines = {}
    Cmdline.active = nil
  end)

  before_each(function()
    Cmdline.confirm = nil
    Cmdline._on_hide = nil
    Cmdline.cmdlines = {}
    Cmdline.active = nil
    Manager._messages = {}
    Manager._history = {}
  end)

  it("shows the message with its prompt", function()
    local m = confirm_message()
    assert.is_true(Cmdline.on_confirm(m))
    show("(Y)es, (N)o: ")
    assert.is_true(Manager.has(m))
    assert.truthy(m:content():find("(Y)es, (N)o: ", 1, true))
    assert.is_nil(Cmdline.cmdlines[1])
  end)

  it("removes the message when the prompt is answered", function()
    local m = confirm_message()
    Cmdline.on_confirm(m)
    show("(Y)es, (N)o: ")
    hide()
    settle()
    assert.is_false(Manager.has(m))
  end)

  it("keeps the message and does not repeat the prompt when redrawn", function()
    local m = confirm_message()
    Cmdline.on_confirm(m)
    show("(Y)es, (N)o: ")
    hide()
    show("(Y)es, (N)o: ")
    settle()

    assert.is_true(Manager.has(m))
    assert.is_nil(Cmdline.cmdlines[1])
    local _, count = m:content():gsub("%(Y%)es", "")
    assert.equal(1, count)
  end)

  it("shows the message again when redrawn after hiding", function()
    local m = confirm_message()
    Cmdline.on_confirm(m)
    show("(Y)es, (N)o: ")
    hide()
    settle()
    assert.is_false(Manager.has(m))

    show("(Y)es, (N)o: ")
    assert.is_true(Manager.has(m))
    assert.is_nil(Cmdline.cmdlines[1])
  end)

  it("allows the same message to show twice in a row", function()
    local m = confirm_message()
    Cmdline.on_confirm(m)
    show("(Y)es, (N)o: ")
    State.set("msg_show", "confirm", {})
    hide()
    assert.is_nil(State.state["msg_show"])
  end)

  it("cleans up when another prompt arrives before the hide callback runs", function()
    local m = confirm_message()
    Cmdline.on_confirm(m)
    show("(Y)es, (N)o: ")
    hide()
    show("other prompt: ")
    settle()

    assert.is_nil(Cmdline.confirm)
    assert.is_false(Manager.has(m))
    assert.is_not_nil(Cmdline.cmdlines[1])
  end)
end)
