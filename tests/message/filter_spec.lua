local Config = require("noice.config")
Config.setup()

local Filter = require("noice.message.filter")
local Message = require("noice.message")

--- Helper: create a message with content
---@param event string
---@param kind? string
---@param content? string
---@return NoiceMessage
local function msg(event, kind, content)
  local m = Message(event, kind)
  if content then
    m:set(content)
  end
  return m
end

describe("filter", function()
  describe("event", function()
    it("matches string event", function()
      local m = msg("msg_show", "echo")
      assert.is_true(Filter.is(m, { event = "msg_show" }))
      assert.is_false(Filter.is(m, { event = "notify" }))
    end)

    it("matches array of events", function()
      local m = msg("notify", "info")
      assert.is_true(Filter.is(m, { event = { "msg_show", "notify" } }))
      assert.is_false(Filter.is(m, { event = { "msg_show", "cmdline" } }))
    end)
  end)

  describe("kind", function()
    it("matches string kind", function()
      local m = msg("msg_show", "echo")
      assert.is_true(Filter.is(m, { kind = "echo" }))
      assert.is_false(Filter.is(m, { kind = "error" }))
    end)

    it("matches array of kinds", function()
      local m = msg("msg_show", "echo")
      assert.is_true(Filter.is(m, { kind = { "echo", "search_count" } }))
      assert.is_false(Filter.is(m, { kind = { "error", "warning" } }))
    end)
  end)

  describe("error and warning", function()
    it("matches error level", function()
      local m = msg("msg_show", "echo")
      m.level = "error"
      assert.is_true(Filter.is(m, { error = true }))
      assert.is_false(Filter.is(m, { error = false }))
    end)

    it("matches warning level", function()
      local m = msg("msg_show", "echo")
      m.level = "warn"
      assert.is_true(Filter.is(m, { warning = true }))
      assert.is_false(Filter.is(m, { warning = false }))
    end)

    it("non-error message does not match error filter", function()
      local m = msg("msg_show", "echo")
      m.level = "info"
      assert.is_false(Filter.is(m, { error = true }))
      assert.is_true(Filter.is(m, { error = false }))
    end)
  end)

  describe("find", function()
    it("matches content substring", function()
      local m = msg("msg_show", "echo", "hello world")
      assert.is_truthy(Filter.is(m, { find = "hello" }))
      assert.is_truthy(Filter.is(m, { find = "world" }))
      assert.is_falsy(Filter.is(m, { find = "goodbye" }))
    end)

    it("matches content with pattern", function()
      local m = msg("msg_show", "echo", "error: line 42")
      assert.is_truthy(Filter.is(m, { find = "line %d+" }))
    end)
  end)

  describe("dimensions", function()
    it("min_height", function()
      local m = msg("msg_show", "echo", "line1\nline2\nline3")
      assert.is_true(Filter.is(m, { min_height = 3 }))
      assert.is_true(Filter.is(m, { min_height = 1 }))
      assert.is_false(Filter.is(m, { min_height = 4 }))
    end)

    it("max_height", function()
      local m = msg("msg_show", "echo", "line1\nline2\nline3")
      assert.is_true(Filter.is(m, { max_height = 3 }))
      assert.is_true(Filter.is(m, { max_height = 5 }))
      assert.is_false(Filter.is(m, { max_height = 2 }))
    end)

    it("min_length and max_length", function()
      local m = msg("msg_show", "echo", "hello")
      assert.is_true(Filter.is(m, { min_length = 5 }))
      assert.is_true(Filter.is(m, { max_length = 5 }))
      assert.is_false(Filter.is(m, { min_length = 6 }))
      assert.is_false(Filter.is(m, { max_length = 4 }))
    end)
  end)

  describe("combinators", function()
    it("any matches if any sub-filter matches", function()
      local m = msg("notify", "info")
      assert.is_true(Filter.is(m, {
        any = {
          { event = "msg_show" },
          { event = "notify" },
        },
      }))
    end)

    it("any returns false if no sub-filter matches", function()
      local m = msg("notify", "info")
      assert.is_false(Filter.is(m, {
        any = {
          { event = "msg_show" },
          { event = "cmdline" },
        },
      }))
    end)

    it("not inverts filter", function()
      local m = msg("msg_show", "echo")
      assert.is_true(Filter.is(m, { ["not"] = { event = "notify" } }))
      assert.is_false(Filter.is(m, { ["not"] = { event = "msg_show" } }))
    end)
  end)

  describe("M.is with multiple keys", function()
    it("ANDs multiple filter keys", function()
      local m = msg("msg_show", "echo", "hello")
      m.level = "error"
      assert.is_true(Filter.is(m, { event = "msg_show", error = true }))
      assert.is_false(Filter.is(m, { event = "msg_show", error = false }))
      assert.is_false(Filter.is(m, { event = "notify", error = true }))
    end)

    it("empty filter matches everything", function()
      local m = msg("msg_show", "echo")
      assert.is_true(Filter.is(m, {}))
    end)

    it("unknown filter key returns false", function()
      local m = msg("msg_show", "echo")
      assert.is_false(Filter.is(m, { nonexistent_key = true }))
    end)
  end)

  describe("M.filter", function()
    it("filters message list", function()
      local m1 = msg("msg_show", "echo")
      local m2 = msg("notify", "info")
      local m3 = msg("msg_show", "error")
      local result = Filter.filter({ m1, m2, m3 }, { event = "msg_show" })
      assert.equal(2, #result)
    end)

    it("invert flag reverses filter", function()
      local m1 = msg("msg_show", "echo")
      local m2 = msg("notify", "info")
      local result = Filter.filter({ m1, m2 }, { event = "msg_show" }, true)
      assert.equal(1, #result)
      assert.equal("notify", result[1].event)
    end)
  end)

  describe("M.has", function()
    it("returns true if any message matches", function()
      local m1 = msg("msg_show", "echo")
      local m2 = msg("notify", "info")
      assert.is_true(Filter.has({ m1, m2 }, { event = "notify" }))
    end)

    it("returns false if no message matches", function()
      local m1 = msg("msg_show", "echo")
      assert.is_false(Filter.has({ m1 }, { event = "notify" }))
    end)
  end)
end)
