local Config = require("noice.config")
Config.setup()

local Cmdline = require("noice.ui.cmdline")
local Hacks = require("noice.util.hacks")
local Manager = require("noice.message.manager")

local LEVEL = 1

---@param text string
---@param opts? {firstc?: string, prompt?: string, pos?: integer, level?: integer}
local function show(text, opts)
  opts = opts or {}
  Cmdline.on_show(
    "cmdline_show",
    { { 0, text } },
    opts.pos or #text,
    opts.firstc == nil and ":" or opts.firstc,
    opts.prompt or "",
    0,
    opts.level or LEVEL
  )
end

local function shown()
  return Manager.has(Cmdline.message) and Cmdline.message:content() or nil
end

describe("cmdline", function()
  before_each(function()
    Cmdline.cmdlines = {}
    Cmdline.active = nil
    Cmdline.skipped = false
    Cmdline.confirm = nil
    Cmdline._on_hide = nil
    Manager._messages = {}
    Manager._history = {}
  end)

  after_each(function()
    Cmdline.cmdlines = {}
    Cmdline.active = nil
  end)

  describe("format", function()
    local function format_of(text, opts)
      show(text, opts)
      return Cmdline.active:get_format().name
    end

    for _, case in ipairs({
      { "plain command", "echo 1", {}, "cmdline" },
      { "search down", "foo", { firstc = "/" }, "search_down" },
      { "search up", "foo", { firstc = "?" }, "search_up" },
      { "filter", "!ls", {}, "filter" },
      { "filter with a space", " !ls", {}, "filter" },
      { "lua", "lua print(1)", {}, "lua" },
      { "lua expression", "lua= 1", {}, "lua" },
      { "equals expression", "= 1", {}, "lua" },
      { "help", "help foo", {}, "help" },
      { "short help", "he foo", {}, "help" },
      { "calculator", "1+1", { firstc = "=" }, "calculator" },
      { "input prompt", "text", { firstc = "", prompt = "Name: " }, "input" },
    }) do
      it("detects " .. case[1], function()
        assert.equal(case[4], format_of(case[2], case[3]))
      end)
    end

    it("prefers input for any prompt, whatever the text looks like", function()
      assert.equal("input", format_of("lua x", { prompt = "Name: " }))
    end)

    it("does not use a longer format until the cursor is past its pattern", function()
      assert.equal("cmdline", format_of("lua print(1)", { pos = 1 }))
    end)

    it("falls back to the popup view for an unknown first character", function()
      show("text", { firstc = ">" })
      local format = Cmdline.active:get_format()
      assert.equal(">", format.kind)
      assert.equal("cmdline_popup", format.view)
    end)
  end)

  describe("message", function()
    it("shows the text after the icon, without the first character", function()
      show("echo 1")
      assert.truthy(shown():find("echo 1", 1, true))
      assert.is_nil(shown():find(":", 1, true))
    end)

    it("hides the matched prefix", function()
      show("lua print(1)")
      assert.truthy(shown():find("print(1)", 1, true))
      assert.is_nil(shown():find("lua", 1, true))
    end)

    it("keeps the first character when the format does not conceal", function()
      local format = Config.options.cmdline.format.cmdline
      format.conceal = false
      show("echo 1")
      format.conceal = true
      assert.truthy(shown():find(":echo 1", 1, true))
    end)

    it("sets the kind to the format's name", function()
      show("help foo")
      assert.equal("help", Cmdline.message.kind)
    end)

    it("uses a short prompt as the title, without its colon", function()
      show("text", { firstc = "", prompt = "Name: " })
      assert.equal(" Name ", Cmdline.message.title)
      assert.is_nil(shown():find("Name", 1, true))
      assert.truthy(shown():find("text", 1, true))
    end)

    it("keeps a long prompt inline", function()
      local prompt = string.rep("x", 61)
      show("text", { firstc = "", prompt = prompt })
      assert.is_nil(Cmdline.message.title)
      assert.truthy(shown():find(prompt .. "text", 1, true))
    end)

    it("keeps a multi-line prompt inline", function()
      show("text", { firstc = "", prompt = "one\ntwo: " })
      assert.is_nil(Cmdline.message.title)
      assert.truthy(shown():find("two: text", 1, true))
    end)

    it("clears the title left by an earlier prompt", function()
      show("text", { firstc = "", prompt = "Name: " })
      Cmdline.on_hide(nil, LEVEL)
      show("echo 1")
      assert.is_nil(Cmdline.message.title)
    end)
  end)

  describe("events", function()
    it("does not touch the message when the state is unchanged", function()
      show("echo 1")
      local tick = Manager.tick()
      show("echo 1")
      assert.equal(tick, Manager.tick())
    end)

    it("updates the message as text is typed", function()
      show("ec")
      show("ech")
      assert.truthy(shown():find("ech", 1, true))
    end)

    it("removes the message on hide", function()
      show("echo 1")
      Cmdline.on_hide(nil, LEVEL)
      assert.is_nil(shown())
      assert.is_false(Manager.has(Cmdline.message, { history = true }))
    end)

    it("ignores a hide for a level that is not open", function()
      show("echo 1")
      Cmdline.on_hide(nil, 2)
      assert.is_not_nil(shown())
    end)

    it("shows the deepest level, and returns to the outer one", function()
      show("outer")
      show("inner", { level = 2 })
      assert.truthy(shown():find("inner", 1, true))
      Cmdline.on_hide(nil, 2)
      assert.truthy(shown():find("outer", 1, true))
      assert.is_nil(shown():find("inner", 1, true))
    end)

    it("keeps active briefly after hide, so messages can still see it", function()
      show("echo 1")
      local active = Cmdline.active
      Cmdline.on_hide(nil, LEVEL)
      assert.equal(active, Cmdline.active)
      assert.is_true(vim.wait(1000, function()
        return Cmdline.active == nil
      end, 5))
    end)

    it("does not clear a newer active cmdline", function()
      show("first")
      Cmdline.on_hide(nil, LEVEL)
      show("second")
      local active = Cmdline.active
      vim.wait(150)
      assert.equal(active, Cmdline.active)
    end)

    it("moves the cursor on pos", function()
      show("echo 1")
      local tick = Manager.tick()
      Cmdline.on_pos(nil, 2, LEVEL)
      assert.equal(2, Cmdline.cmdlines[LEVEL].state.pos)
      assert.is_true(Manager.tick() > tick)
    end)

    it("does nothing for an unchanged pos", function()
      show("echo 1")
      local tick = Manager.tick()
      Cmdline.on_pos(nil, #"echo 1", LEVEL)
      assert.equal(tick, Manager.tick())
    end)

    it("ignores pos for a level that is not open", function()
      show("echo 1")
      Cmdline.on_pos(nil, 2, 2)
      assert.is_nil(Cmdline.cmdlines[2])
    end)
  end)

  describe("forced redraws", function()
    it("skips the cmdline event a forced redraw causes, and its pos", function()
      show("echo 1")
      local tick = Manager.tick()
      show("echo 1" .. Hacks.SPECIAL)
      assert.is_true(Cmdline.skipped)
      Cmdline.on_pos(nil, 1, LEVEL)
      assert.equal(tick, Manager.tick())
      assert.equal(#"echo 1", Cmdline.cmdlines[LEVEL].state.pos)
    end)

    it("stops skipping at the next real event", function()
      show("echo 1" .. Hacks.SPECIAL)
      show("echo 2")
      assert.is_false(Cmdline.skipped)
      assert.truthy(shown():find("echo 2", 1, true))
    end)
  end)

  describe("last", function()
    it("is nil with no cmdline open", function()
      assert.is_nil(Cmdline.last())
    end)

    it("finds the deepest level even when level 1 is closed", function()
      show("inner", { level = 3 })
      assert.equal(Cmdline.cmdlines[3], Cmdline.last())
    end)
  end)
end)
