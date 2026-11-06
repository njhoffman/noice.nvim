local Config = require("noice.config")
Config.setup()

local Manager = require("noice.message.manager")
local Message = require("noice.message")
local Router = require("noice.message.router")
local Util = require("noice.util")

-- Longer than several throttle periods
local IDLE_MS = 150

local is_exiting = Util.is_exiting
local redraw = Util.redraw

-- The test runner has v:exiting set, which would stop the router and every interval
local function not_exiting()
  Util.is_exiting = function()
    return false
  end
end

local function add(text)
  local m = Message("msg_show", "echo")
  m:set(text)
  Manager.add(m)
  return m
end

describe("router", function()
  local update, updates, saved_routes

  local function settle()
    assert.is_true(vim.wait(1000, function()
      return Router._tick == Manager.tick()
    end, 5))
  end

  before_each(function()
    not_exiting()
    -- A flush inside vim.wait can stall timers for the rest of that wait, without any noice code involved
    Util.redraw = function() end
    Router.disable()
    Manager._messages = {}
    Manager._history = {}
    saved_routes = Router._routes
    Router._routes = {}
    updates = 0
    update = Router.update
    Router.update = function()
      updates = updates + 1
      update()
    end
    Router.enable()
    settle()
  end)

  after_each(function()
    Router.disable()
    Router.update = update
    Router._routes = saved_routes
    Util.is_exiting = is_exiting
    Util.redraw = redraw
  end)

  it("does not wake while idle", function()
    updates = 0
    vim.wait(IDLE_MS)
    assert.equal(0, updates)
  end)

  it("routes a message that arrives while it sleeps", function()
    vim.wait(IDLE_MS)
    local m = add("hello")
    assert.is_true(Manager.has(m))
    settle()
    assert.is_false(Manager.has(m))
  end)

  it("sleeps again after routing", function()
    add("hello")
    settle()
    updates = 0
    vim.wait(IDLE_MS)
    assert.equal(0, updates)
  end)

  it("keeps routing across repeated sleeps", function()
    for i = 1, 3 do
      local m = add("message " .. i)
      settle()
      assert.is_false(Manager.has(m))
      vim.wait(IDLE_MS)
    end
  end)

  it("wakes when a message is removed", function()
    local m = add("hello")
    settle()
    updates = 0
    Manager.remove(m)
    settle()
    assert.is_true(updates > 0)
  end)

  it("accepts a message from a fast event", function()
    vim.wait(IDLE_MS)
    local m = Message("msg_show", "echo")
    m:set("hello")
    local failed
    local timer = assert(vim.uv.new_timer())
    timer:start(0, 0, function()
      timer:close()
      local ok, err = pcall(Manager.add, m)
      failed = not ok and err or false
    end)
    assert.is_true(vim.wait(1000, function()
      return failed ~= nil
    end, 5))
    assert.is_false(failed)
    settle()
    assert.is_false(Manager.has(m))
  end)

  it("keeps retrying while a view fails to display", function()
    local view = {
      _messages = {},
      _errors = 0,
      _opts = {},
      push = function() end,
    }
    local displays = 0
    function view.display(self)
      displays = displays + 1
      self._errors = displays < 3 and 1 or 0
    end
    Router._routes = { { filter = {}, opts = {}, view = view } }
    add("hello")
    assert.is_true(vim.wait(1000, function()
      return displays >= 3
    end, 5))
    settle()
  end)

  it("stops waking once disabled", function()
    Router.disable()
    assert.is_nil(Manager.on_change)
    updates = 0
    add("hello")
    vim.wait(IDLE_MS)
    assert.equal(0, updates)
  end)
end)

describe("Util.interval", function()
  before_each(not_exiting)

  after_each(function()
    Util.is_exiting = is_exiting
  end)

  it("restarts after being stopped from inside its own callback", function()
    local enabled = true
    local calls = 0
    local interval
    interval = Util.interval(5, function()
      calls = calls + 1
      -- Starts the next timer, so the check after the callback finds one running and must stop it
      interval()
      enabled = false
    end, {
      enabled = function()
        return enabled
      end,
    })
    interval()
    assert.is_true(vim.wait(500, function()
      return calls == 1 and not interval.running()
    end, 5))

    enabled = true
    interval()
    assert.is_true(interval.running())
    enabled = false
    interval.stop()
    assert.is_false(interval.running())
  end)
end)
