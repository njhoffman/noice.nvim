local Config = require("noice.config")
Config.setup()

local Manager = require("noice.message.manager")
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

--- Reset manager state between tests
local function reset()
  Manager._messages = {}
  Manager._history = {}
end

describe("manager", function()
  before_each(function()
    reset()
  end)

  describe("add", function()
    it("adds a message with content", function()
      local m = msg("msg_show", "echo", "hello")
      Manager.add(m)
      assert.is_true(Manager.has(m))
    end)

    it("skips empty messages with empty opts", function()
      local m = msg("msg_show", "echo")
      -- message is empty (no content) and opts is empty
      Manager.add(m)
      assert.is_false(Manager.has(m))
    end)

    it("adds empty message if opts is non-empty", function()
      local m = msg("msg_show", "echo")
      m.opts.some_key = true
      Manager.add(m)
      assert.is_true(Manager.has(m))
    end)

    it("increments tick on add", function()
      local tick_before = Manager.tick()
      local m = msg("msg_show", "echo", "hello")
      Manager.add(m)
      assert.is_true(Manager.tick() > tick_before)
    end)

    it("adds to both messages and history", function()
      local m = msg("msg_show", "echo", "hello")
      Manager.add(m)
      assert.is_true(Manager.has(m))
      assert.is_true(Manager.has(m, { history = true }))
    end)
  end)

  describe("has", function()
    it("returns false for unknown message", function()
      local m = msg("msg_show", "echo", "hello")
      assert.is_false(Manager.has(m))
    end)

    it("checks current messages by default", function()
      local m = msg("msg_show", "echo", "hello")
      Manager.add(m)
      assert.is_true(Manager.has(m))
    end)

    it("checks history when option is set", function()
      local m = msg("msg_show", "echo", "hello")
      Manager.add(m)
      Manager._messages[m.id] = nil -- remove from current but keep in history
      assert.is_false(Manager.has(m))
      assert.is_true(Manager.has(m, { history = true }))
    end)
  end)

  describe("remove", function()
    it("removes from both messages and history", function()
      local m = msg("msg_show", "echo", "hello")
      Manager.add(m)
      Manager.remove(m)
      assert.is_false(Manager.has(m))
      assert.is_false(Manager.has(m, { history = true }))
    end)

    it("increments tick on remove", function()
      local m = msg("msg_show", "echo", "hello")
      Manager.add(m)
      local tick_before = Manager.tick()
      Manager.remove(m)
      assert.is_true(Manager.tick() > tick_before)
    end)
  end)

  describe("clear", function()
    it("clears all current messages without filter", function()
      local m1 = msg("msg_show", "echo", "hello")
      local m2 = msg("notify", "info", "world")
      Manager.add(m1)
      Manager.add(m2)
      Manager.clear()
      assert.is_false(Manager.has(m1))
      assert.is_false(Manager.has(m2))
      -- history should still have them
      assert.is_true(Manager.has(m1, { history = true }))
      assert.is_true(Manager.has(m2, { history = true }))
    end)

    it("clears only matching messages with filter", function()
      local m1 = msg("msg_show", "echo", "hello")
      local m2 = msg("notify", "info", "world")
      Manager.add(m1)
      Manager.add(m2)
      Manager.clear({ event = "msg_show" })
      assert.is_false(Manager.has(m1))
      assert.is_true(Manager.has(m2))
    end)
  end)

  describe("get", function()
    it("returns all current messages without filter", function()
      local m1 = msg("msg_show", "echo", "hello")
      local m2 = msg("notify", "info", "world")
      Manager.add(m1)
      Manager.add(m2)
      local result = Manager.get()
      assert.equal(2, #result)
    end)

    it("returns filtered messages", function()
      local m1 = msg("msg_show", "echo", "hello")
      local m2 = msg("notify", "info", "world")
      Manager.add(m1)
      Manager.add(m2)
      local result = Manager.get({ event = "msg_show" })
      assert.equal(1, #result)
      assert.equal("msg_show", result[1].event)
    end)

    it("respects count option", function()
      local m1 = msg("msg_show", "echo", "first")
      local m2 = msg("msg_show", "echo", "second")
      local m3 = msg("msg_show", "echo", "third")
      Manager.add(m1)
      Manager.add(m2)
      Manager.add(m3)
      local result = Manager.get(nil, { count = 2 })
      assert.equal(2, #result)
    end)

    it("uses history when option set", function()
      local m = msg("msg_show", "echo", "hello")
      Manager.add(m)
      Manager._messages[m.id] = nil
      local current = Manager.get()
      local history = Manager.get(nil, { history = true })
      assert.equal(0, #current)
      assert.equal(1, #history)
    end)
  end)

  describe("get_by_id", function()
    it("retrieves message from history by id", function()
      local m = msg("msg_show", "echo", "hello")
      Manager.add(m)
      local found = Manager.get_by_id(m.id)
      assert.equal(m, found)
    end)

    it("returns nil for unknown id", function()
      assert.is_nil(Manager.get_by_id(99999))
    end)
  end)

  describe("sort", function()
    it("sorts by mtime then id", function()
      local m1 = msg("msg_show", "echo", "first")
      local m2 = msg("msg_show", "echo", "second")
      m1.mtime = 100
      m2.mtime = 200
      local messages = { m2, m1 }
      Manager.sort(messages)
      assert.equal(m1, messages[1])
      assert.equal(m2, messages[2])
    end)

    it("sorts reverse", function()
      local m1 = msg("msg_show", "echo", "first")
      local m2 = msg("msg_show", "echo", "second")
      m1.mtime = 100
      m2.mtime = 200
      local messages = { m1, m2 }
      Manager.sort(messages, true)
      assert.equal(m2, messages[1])
      assert.equal(m1, messages[2])
    end)
  end)

  describe("prune", function()
    it("keeps only N most recent messages", function()
      local m1 = msg("msg_show", "echo", "first")
      local m2 = msg("msg_show", "echo", "second")
      local m3 = msg("msg_show", "echo", "third")
      Manager.add(m1)
      Manager.add(m2)
      Manager.add(m3)
      Manager.prune(2)
      local result = Manager.get()
      assert.equal(2, #result)
    end)
  end)

  describe("history_count", function()
    it("counts messages by id, however the ids are spaced", function()
      Manager._history = { [10] = msg("msg_show", "echo", "a"), [11] = msg("msg_show", "echo", "b") }
      assert.equal(2, Manager.history_count())
    end)

    it("is zero when empty", function()
      assert.equal(0, Manager.history_count())
    end)

    it("counts only matching messages with a filter", function()
      Manager._history = { msg("msg_show", "echo", "a"), msg("notify", "info", "b") }
      assert.equal(1, Manager.history_count({ event = "notify" }))
    end)

    it("includes messages already routed out of the live list", function()
      local m = msg("msg_show", "echo", "a")
      Manager.add(m)
      Manager.clear()
      assert.equal(1, Manager.history_count())
    end)
  end)

  describe("clear_history", function()
    local function routed(event, kind, content)
      local m = msg(event, kind, content)
      Manager.add(m)
      Manager.clear({ message = m })
      return m
    end

    it("removes routed messages and returns how many", function()
      local a, b = routed("msg_show", "echo", "a"), routed("notify", "info", "b")
      assert.equal(2, Manager.clear_history())
      assert.is_false(Manager.has(a, { history = true }))
      assert.is_false(Manager.has(b, { history = true }))
      assert.equal(0, Manager.history_count())
    end)

    it("advances the tick so views notice", function()
      routed("msg_show", "echo", "a")
      local tick = Manager.tick()
      Manager.clear_history()
      assert.is_true(Manager.tick() > tick)
    end)

    it("does not advance the tick when nothing was removed", function()
      local tick = Manager.tick()
      assert.equal(0, Manager.clear_history())
      assert.equal(tick, Manager.tick())
    end)

    it("keeps messages that have not been routed yet", function()
      local pending = msg("msg_show", "echo", "pending")
      Manager.add(pending)
      assert.equal(0, Manager.clear_history())
      assert.is_true(Manager.has(pending))
      assert.is_true(Manager.has(pending, { history = true }))
    end)

    it("removes only matching messages with a filter", function()
      local a, b = routed("msg_show", "echo", "a"), routed("notify", "info", "b")
      assert.equal(1, Manager.clear_history({ event = "notify" }))
      assert.is_true(Manager.has(a, { history = true }))
      assert.is_false(Manager.has(b, { history = true }))
    end)

    it("runs on_remove", function()
      local m = routed("msg_show", "echo", "a")
      local called = false
      m.on_remove = function()
        called = true
      end
      Manager.clear_history()
      assert.is_true(called)
    end)
  end)

  describe("api.history", function()
    it("exposes count and clear", function()
      local Api = require("noice.api")
      local m = msg("msg_show", "echo", "a")
      Manager.add(m)
      Manager.clear({ message = m })
      assert.equal(1, Api.history.count())
      assert.equal(1, Api.history.clear())
      assert.equal(0, Api.history.count())
    end)
  end)
end)
