local Config = require("noice.config")
Config.setup()

local Manager = require("noice.message.manager")
local Msg = require("noice.ui.msg")
local State = require("noice.ui.state")

local function show(text, opts)
  opts = opts or {}
  Msg.on_show(
    "msg_show",
    opts.kind or "echo",
    { { 0, text, 0 } },
    opts.replace_last or false,
    false,
    opts.append,
    opts.id
  )
end

local function contents()
  local ret = {}
  for _, message in ipairs(Manager.get({ event = "msg_show" }, { history = true, sort = true })) do
    ret[#ret + 1] = message:content()
  end
  return ret
end

describe("msg_show", function()
  before_each(function()
    Manager._messages = {}
    Manager._history = {}
    State.clear("msg_show")
    Msg.last = nil
    Msg._by_id = {}
  end)

  describe("repeats", function()
    it("keeps an identical message that has a new id", function()
      show("test", { id = 1 })
      show("test", { id = 2 })
      assert.same({ "test", "test" }, contents())
    end)

    it("skips a replay with the same id", function()
      show("test", { id = 1 })
      show("test", { id = 1 })
      assert.same({ "test" }, contents())
    end)

    it("skips an identical message when Neovim sends no id", function()
      show("test")
      show("test")
      assert.same({ "test" }, contents())
    end)
  end)

  describe("append", function()
    it("continues the previous message", function()
      show("x", { id = 1 })
      show("y", { id = 2, append = true })
      assert.same({ "xy" }, contents())
    end)

    it("starts a message when there is nothing to continue", function()
      show("y", { id = 1, append = true })
      assert.same({ "y" }, contents())
    end)

    it("does not continue a message of another kind", function()
      show("failed", { id = 1, kind = "emsg" })
      show("y", { id = 2, append = true })
      assert.same({ "failed", "y" }, contents())
    end)

    it("does not continue a message from before a clear", function()
      show("x", { id = 1 })
      Msg.on_clear()
      show("y", { id = 2, append = true })
      assert.same({ "x", "y" }, contents())
    end)
  end)

  describe("id", function()
    it("updates the message with that id", function()
      show("working", { id = "job" })
      show("other", { id = 1 })
      show("done", { id = "job" })
      local result = contents()
      table.sort(result)
      assert.same({ "done", "other" }, result)
    end)

    it("updates a message by a numeric id", function()
      show("working", { id = 7 })
      show("done", { id = 7 })
      assert.same({ "done" }, contents())
    end)

    it("takes the kind and level of the update", function()
      show("failed", { id = "job", kind = "emsg" })
      show("recovered", { id = "job", kind = "echo" })
      local message = Manager.get({ event = "msg_show" }, { history = true })[1]
      assert.equal("echo", message.kind)
      assert.is_nil(message.level)
    end)

    it("shows an update again after the message left the history", function()
      show("working", { id = "job" })
      Manager.clear_history()
      show("again", { id = "job" })
      assert.same({ "again" }, contents())
    end)
  end)
end)
