local Config = require("noice.config")
Config.setup()

local ConfigViews = require("noice.config.views")
local Message = require("noice.message")

local function msg(content, title)
  local m = Message("msg_show", "echo")
  m:set(content)
  m.title = title
  return m
end

local function lines(view)
  return vim.api.nvim_buf_get_lines(view._nui.bufnr, 0, -1, false)
end

local function is_open(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

describe("nui views", function()
  local opened

  -- A fresh view with the defaults of `name`, since View.get_view shares instances
  local function new_view(name, opts)
    local merged = vim.tbl_deep_extend("force", ConfigViews.get_options(name), opts or {}, { view = name })
    merged.format = merged.format or { "{message}" }
    local view = require("noice.view.backend." .. name)(merged)
    opened[#opened + 1] = view
    return view
  end

  local function show(view, ...)
    view:set({ ... }, { format = false })
    view:display()
  end

  before_each(function()
    opened = {}
  end)

  after_each(function()
    for _, view in ipairs(opened) do
      view:clear()
      view:hide()
    end
  end)

  describe("popup", function()
    it("opens a float showing the message", function()
      local view = new_view("popup")
      show(view, msg("hello"))
      assert.is_true(is_open(view._nui.winid))
      assert.is_true(vim.api.nvim_win_get_config(view._nui.winid).relative ~= "")
      assert.same({ "hello" }, lines(view))
      assert.equal(0, view._errors)
    end)

    it("marks its buffer and leaves it read-only", function()
      local view = new_view("popup")
      show(view, msg("hello"))
      assert.equal("noice", vim.bo[view._nui.bufnr].filetype)
      assert.equal("nofile", vim.bo[view._nui.bufnr].buftype)
      assert.is_false(vim.bo[view._nui.bufnr].modifiable)
    end)

    it("sizes itself to the message with auto size", function()
      local view = new_view("popup", { size = { width = "auto", height = "auto" }, border = { style = "none" } })
      show(view, msg("hello\nsecond line"))
      assert.equal(#"second line", vim.api.nvim_win_get_width(view._nui.winid))
      assert.equal(2, vim.api.nvim_win_get_height(view._nui.winid))
    end)

    it("reuses the window when the messages change", function()
      local view = new_view("popup")
      show(view, msg("one"))
      local win = view._nui.winid
      show(view, msg("two"), msg("three"))
      assert.equal(win, view._nui.winid)
      assert.same({ "two", "three" }, lines(view))
    end)

    it("resizes the same window when only the layout changes", function()
      local view = new_view("popup", { size = { width = "auto", height = "auto" } })
      show(view, msg("one"))
      local win = view._nui.winid
      show(view, msg("one\ntwo\nthree"))
      assert.equal(win, view._nui.winid)
      assert.equal(3, vim.api.nvim_win_get_height(win))
    end)

    it("recreates the window when other options change", function()
      local view = new_view("popup")
      show(view, msg("one"))
      local win = view._nui.winid
      view._route_opts = { win_options = { wrap = true } }
      view:push(msg("two"), { format = false })
      view:display()
      assert.is_false(is_open(win))
      assert.is_true(is_open(view._nui.winid))
      assert.is_true(vim.wo[view._nui.winid].wrap)
    end)

    it("closes when it has no messages", function()
      local view = new_view("popup")
      show(view, msg("hello"))
      local win = view._nui.winid
      view:clear()
      view:display()
      assert.is_false(is_open(win))
      assert.is_false(view._visible)
    end)

    it("opens again after closing", function()
      local view = new_view("popup")
      show(view, msg("one"))
      view:clear()
      view:display()
      show(view, msg("two"))
      assert.is_true(is_open(view._nui.winid))
      assert.same({ "two" }, lines(view))
    end)

    it("hides after its timeout", function()
      local view = new_view("popup", { timeout = 20 })
      show(view, msg("hello"))
      local win = view._nui.winid
      assert.is_true(vim.wait(1000, function()
        return not is_open(win)
      end, 5))
      assert.is_false(view._visible)
    end)

    it("shows message titles on the border", function()
      local view = new_view("popup", { border = { style = "single" } })
      show(view, msg("one", "first"), msg("two", "second"))
      assert.equal("first | second", view._opts.border.text.top)
    end)

    it("hides when a close key is pressed", function()
      local view = new_view("popup", { enter = true, close = { keys = { "q" } } })
      show(view, msg("hello"))
      local win = view._nui.winid
      vim.api.nvim_set_current_win(win)
      vim.api.nvim_feedkeys("q", "xt", false)
      assert.is_false(is_open(win))
    end)

    it("hides when a close event fires", function()
      local origin = vim.api.nvim_get_current_win()
      local view = new_view("popup", { close = { events = { "BufLeave" } } })
      show(view, msg("hello"))
      local win = view._nui.winid
      vim.api.nvim_set_current_win(win)
      vim.api.nvim_set_current_win(origin)
      assert.is_false(is_open(win))
    end)

    it("recovers when its window is closed from outside", function()
      local view = new_view("popup")
      show(view, msg("one"))
      vim.api.nvim_win_close(view._nui.winid, true)
      show(view, msg("two"))
      assert.equal(0, view._errors)
      assert.is_true(is_open(view._nui.winid))
      assert.same({ "two" }, lines(view))
    end)

    it("recreates after being destroyed", function()
      local view = new_view("popup")
      show(view, msg("one"))
      local win = view._nui.winid
      view:destroy()
      vim.wait(20)
      assert.is_false(is_open(win))
      show(view, msg("two"))
      assert.is_true(is_open(view._nui.winid))
      assert.same({ "two" }, lines(view))
    end)
  end)

  describe("split", function()
    it("opens a normal window showing the message", function()
      local view = new_view("split")
      show(view, msg("hello"))
      assert.is_true(is_open(view._nui.winid))
      assert.equal("", vim.api.nvim_win_get_config(view._nui.winid).relative)
      assert.same({ "hello" }, lines(view))
    end)

    it("closes when it has no messages", function()
      local view = new_view("split")
      show(view, msg("hello"))
      local win = view._nui.winid
      view:clear()
      view:display()
      assert.is_false(is_open(win))
    end)
  end)

  describe("mini", function()
    local function mini_lines(view)
      return vim.api.nvim_buf_get_lines(view.view._nui.bufnr, 0, -1, false)
    end

    it("keeps showing earlier messages", function()
      local view = new_view("mini", { reverse = false, align = "left" })
      show(view, msg("one"))
      show(view, msg("two"))
      assert.same({ "one", "two" }, mini_lines(view))
    end)

    it("puts the newest first when reversed", function()
      local view = new_view("mini", { reverse = true, align = "left" })
      show(view, msg("one"))
      show(view, msg("two"))
      assert.same({ "two", "one" }, mini_lines(view))
    end)

    it("drops each message after the timeout and closes when empty", function()
      local view = new_view("mini", { timeout = 20, align = "left" })
      show(view, msg("one"))
      local win = view.view._nui.winid
      assert.is_true(is_open(win))
      assert.is_true(vim.wait(1000, function()
        return not is_open(win)
      end, 5))
      assert.same({}, view.active)
    end)

    it("waits while a message asks to be kept", function()
      local view = new_view("mini", { timeout = 20, align = "left" })
      local keep = true
      local m = msg("one")
      m.opts.keep = function()
        return keep
      end
      show(view, m)
      vim.wait(100)
      assert.is_not_nil(view.active[m.id])
      keep = false
      assert.is_true(vim.wait(1000, function()
        return view.active[m.id] == nil
      end, 5))
    end)

    it("dismiss closes it at once", function()
      local view = new_view("mini", { align = "left" })
      show(view, msg("one"))
      local win = view.view._nui.winid
      view:dismiss()
      assert.is_false(is_open(win))
    end)
  end)

  describe("virtualtext", function()
    local function marks()
      return vim.api.nvim_buf_get_extmarks(0, Config.ns, 0, -1, { details = true })
    end

    before_each(function()
      vim.api.nvim_buf_clear_namespace(0, Config.ns, 0, -1)
    end)

    it("shows the first message at the cursor line", function()
      local view = new_view("virtualtext")
      show(view, msg("  hello  "), msg("ignored"))
      local all = marks()
      assert.equal(1, #all)
      assert.equal("hello", all[1][4].virt_text[1][1])
    end)

    it("replaces its mark on the next message", function()
      local view = new_view("virtualtext")
      show(view, msg("one"))
      show(view, msg("two"))
      local all = marks()
      assert.equal(1, #all)
      assert.equal("two", all[1][4].virt_text[1][1])
    end)

    it("removes its mark when it has no messages", function()
      local view = new_view("virtualtext")
      show(view, msg("one"))
      view:clear()
      view:display()
      assert.same({}, marks())
    end)
  end)
end)
