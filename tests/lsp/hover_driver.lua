-- Runs hover cases in a clean Neovim, because the hover view does not open under the test runner.
-- Usage: nvim --headless --clean -u NONE -l tests/lsp/hover_driver.lua <nui path> <json list of markdown strings>
-- Prints a JSON list of { notes = string[], lines = string[]|vim.NIL } to stdout.
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(_G.arg[1])

local notes = {}
vim.notify = function(msg)
  notes[#notes + 1] = tostring(msg)
end

local Config = require("noice.config")
require("noice").setup({ notify = { enabled = false }, health = { checker = false } })
vim.wait(2000, function()
  return Config.is_running() and Config.options.lsp ~= nil
end, 10)

local Docs = require("noice.lsp.docs")
local Hover = require("noice.lsp.hover")

local results = {}
for _, value in ipairs(vim.json.decode(_G.arg[2])) do
  notes = {}
  Hover.on_hover(nil, { contents = { kind = "markdown", value = value } }, { bufnr = 0 })
  -- Docs.get clears the message, so read it directly
  local message = Docs._messages.hover
  vim.wait(500, function()
    return message and message:win() ~= nil or #notes > 0
  end, 10)
  vim.wait(50)
  local win = message and message:win()
  local lines = win and vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false) or vim.NIL
  results[#results + 1] = { notes = notes, lines = lines }
  if message then
    Docs.hide(message)
    vim.wait(100)
  end
end

io.stdout:write(vim.json.encode(results))
vim.cmd("qa!")
