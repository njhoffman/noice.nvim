local Config = require("noice.config")
Config.setup()

local Manager = require("noice.message.manager")
local Message = require("noice.message")
local Router = require("noice.message.router")
local Util = require("noice.util")

-- Longer than several throttle periods
local IDLE_MS = 150

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

describe("routing", function()
  local saved_routes

  local function fake_view()
    local view = { _messages = {}, _errors = 0, _opts = {}, pushed = {}, displays = 0 }
    function view.push(self, message)
      self.pushed[#self.pushed + 1] = message
    end
    function view.display(self)
      self.displays = self.displays + 1
    end
    return view
  end

  local function route(filter, view, opts)
    Router._routes[#Router._routes + 1] = { filter = filter, view = view, opts = opts or {} }
  end

  before_each(function()
    Router.disable()
    Manager._messages = {}
    Manager._history = {}
    saved_routes = Router._routes
    Router._routes = {}
  end)

  after_each(function()
    Router._routes = saved_routes
    Manager._messages = {}
    Manager._history = {}
  end)

  it("sends a message to the first matching route only", function()
    local first, second = fake_view(), fake_view()
    route({ event = "msg_show" }, first)
    route({ event = "msg_show" }, second)
    local m = add("hello")
    Router.update()
    assert.same({ m }, first.pushed)
    assert.same({}, second.pushed)
  end)

  it("continues past a route with stop = false", function()
    local first, second = fake_view(), fake_view()
    route({ event = "msg_show" }, first, { stop = false })
    route({ event = "msg_show" }, second)
    local m = add("hello")
    Router.update()
    assert.same({ m }, first.pushed)
    assert.same({ m }, second.pushed)
  end)

  it("drops a message matching a skip route", function()
    local skipping, view = fake_view(), fake_view()
    route({ event = "msg_show" }, skipping, { skip = true })
    route({ event = "msg_show" }, view)
    local m = add("hello")
    Router.update()
    assert.same({}, skipping.pushed)
    assert.same({}, view.pushed)
    assert.is_false(Manager.has(m))
    assert.is_true(Manager.has(m, { history = true }))
  end)

  it("passes over routes that do not match", function()
    local other, view = fake_view(), fake_view()
    route({ event = "notify" }, other)
    route({ event = "msg_show" }, view)
    add("hello")
    Router.update()
    assert.same({}, other.pushed)
    assert.equal(1, #view.pushed)
  end)

  it("applies route options to the view", function()
    local view = fake_view()
    route({ event = "msg_show" }, view, { timeout = 5 })
    add("hello")
    Router.update()
    assert.equal(5, view._route_opts.timeout)
  end)

  it("does no work when nothing changed", function()
    route({ event = "msg_show" }, fake_view())
    add("hello")
    Router.update()
    Router.update()
    local get = Manager.get
    local calls = 0
    Manager.get = function(...)
      calls = calls + 1
      return get(...)
    end
    Router.update()
    Manager.get = get
    assert.equal(0, calls)
  end)

  describe("with a real view", function()
    local view

    local function is_open()
      return view._nui ~= nil and view._nui.winid ~= nil and vim.api.nvim_win_is_valid(view._nui.winid)
    end

    before_each(function()
      Router.add({ view = "popup", filter = { event = "msg_show" }, opts = {} })
      view = Router._routes[#Router._routes].view
    end)

    after_each(function()
      view:clear()
      view:hide()
    end)

    it("shows a message and closes when it leaves the history", function()
      local m = add("hello")
      Router.update()
      assert.is_true(is_open())
      assert.same("hello", vim.api.nvim_buf_get_lines(view._nui.bufnr, 0, -1, false)[1])
      Manager.remove(m)
      Router.update()
      assert.is_false(is_open())
    end)

    it("redirects a command's messages to a temporary route", function()
      local split
      Router.redirect(function()
        add("captured")
        split = Router._routes[1].view
      end, { { view = "split", filter = { event = "msg_show" } } })
      assert.same({ "captured" }, vim.api.nvim_buf_get_lines(split._nui.bufnr, 0, -1, false))
      assert.is_false(is_open())
      assert.equal(1, #Router._routes)
      split:clear()
      split:hide()
    end)
  end)
end)

describe("Util.interval", function()
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
