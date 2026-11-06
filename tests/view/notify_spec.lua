local Config = require("noice.config")
Config.setup()

local Message = require("noice.message")
local NotifyView = require("noice.view.backend.notify")
local Util = require("noice.util")

---@param content string
---@param level? string
---@return NoiceMessage
local function msg(content, level)
  local m = Message("notify", level)
  m:set(content)
  m.level = level
  return m
end

describe("notify view on_notify", function()
  local saved, shown, errors, seen

  ---@param opts? table view options
  ---@return NoiceView
  local function view(opts)
    local ret = NotifyView(vim.tbl_extend("force", {
      format = "notify",
      on_notify = function(info)
        seen[#seen + 1] = info
      end,
    }, opts or {}))
    ret:update_options()
    return ret
  end

  before_each(function()
    shown, errors, seen = {}, {}, {}
    Util._once = {}
    saved = package.loaded["notify"]
    package.loaded["notify"] = setmetatable({
      notify = function(text)
        errors[#errors + 1] = text
      end,
    }, {
      __call = function(_, content, level, opts)
        shown[#shown + 1] = { content = content, level = level, opts = opts }
        return #shown
      end,
    })
  end)

  after_each(function()
    package.loaded["notify"] = saved
  end)

  it("receives each notification with its content, level, title and message", function()
    local v = view()
    local m = msg("hello", "warn")
    m.opts.title = "Greeting"
    v._messages = { m }
    v:show()

    assert.equal(1, #seen)
    assert.equal("hello", seen[1].content)
    assert.equal("warn", seen[1].level)
    assert.equal("Greeting", seen[1].title)
    assert.same({ m }, seen[1].messages)
    assert.equal(1, #shown)
  end)

  it("reports the level the notification uses when the view overrides it", function()
    local v = view({ level = vim.log.levels.ERROR })
    v._messages = { msg("hello", "info") }
    v:show()

    assert.equal(vim.log.levels.ERROR, seen[1].level)
    assert.equal(vim.log.levels.ERROR, shown[1].level)
  end)

  it("falls back to the view title", function()
    local v = view({ title = "From view" })
    v._messages = { msg("hello") }
    v:show()

    assert.equal("From view", seen[1].title)
  end)

  it("runs once per message, or once when merging", function()
    local v = view()
    v._messages = { msg("one"), msg("two") }
    v:show()
    assert.equal(2, #seen)

    seen = {}
    v = view({ merge = true })
    v._messages = { msg("one"), msg("two") }
    v:show()
    assert.equal(1, #seen)
    assert.equal(2, #seen[1].messages)
  end)

  it("skips notifications without content", function()
    local v = view()
    local m = msg("ignored")
    m.opts.is_nil = true
    v._messages = { m }
    v:show()

    assert.equal(0, #seen)
    assert.equal(1, #shown)
  end)

  it("is optional", function()
    local v = view({ on_notify = false })
    v._messages = { msg("hello") }
    v:show()

    assert.equal(1, #shown)
  end)

  it("shows the notification and reports once when the hook fails", function()
    local v = view({
      on_notify = function()
        error("100% broken", 0)
      end,
    })
    v._messages = { msg("one"), msg("two") }
    v:show()

    assert.equal(2, #shown)
    assert.equal(1, #errors)
    assert.truthy(errors[1]:find("100% broken", 1, true))
  end)
end)
