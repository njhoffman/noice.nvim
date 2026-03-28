local Config = require("noice.config")
Config.setup()

local Message = require("noice.message")
local View = require("noice.view")

--- Helper: create a message with content
---@param content string
---@return NoiceMessage
local function msg(content)
  local m = Message("msg_show", "echo")
  m:set(content)
  return m
end

describe("view tail option", function()
  it("tail option is preserved in view opts", function()
    local view = View.get_view("split", { tail = true })
    assert.is_true(view._opts.tail)
  end)

  it("tail option defaults to nil/false", function()
    local view = View.get_view("split", { enter = true })
    assert.is_falsy(view._opts.tail)
  end)

  it("scroll_to_bottom method exists on view", function()
    local view = View.get_view("popup", { tail = true })
    assert.is_function(view.scroll_to_bottom)
  end)

  it("set_win_options calls scroll_to_bottom when tail is true", function()
    local view = View.get_view("split", { tail = true, format = "details" })
    local called = false
    local orig = view.scroll_to_bottom
    view.scroll_to_bottom = function(self, win)
      called = true
    end
    -- create a dummy window to pass
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line1", "line2", "line3" })
    local win = vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      width = 40,
      height = 5,
      row = 0,
      col = 0,
    })
    view:set_win_options(win)
    assert.is_true(called)
    -- cleanup
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })
    view.scroll_to_bottom = orig
  end)

  it("set_win_options sets cursor to top when tail is false", function()
    local view = View.get_view("popup", { enter = false })
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line1", "line2", "line3" })
    local win = vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      width = 40,
      height = 5,
      row = 0,
      col = 0,
    })
    view:set_win_options(win)
    local cursor = vim.api.nvim_win_get_cursor(win)
    assert.equal(1, cursor[1])
    -- cleanup
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("scroll_to_bottom positions cursor at last line", function()
    local view = View.get_view("popup", { tail = true })
    local buf = vim.api.nvim_create_buf(false, true)
    local lines = {}
    for i = 1, 50 do
      lines[i] = "line " .. i
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local win = vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      width = 40,
      height = 10,
      row = 0,
      col = 0,
    })
    view:scroll_to_bottom(win)
    -- scroll_to_bottom uses vim.schedule, so we need to process pending callbacks
    vim.wait(100, function()
      return vim.api.nvim_win_get_cursor(win)[1] == 50
    end)
    local cursor = vim.api.nvim_win_get_cursor(win)
    assert.equal(50, cursor[1])
    -- cleanup
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
