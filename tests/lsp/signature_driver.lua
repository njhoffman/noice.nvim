-- Runs signature cases in a clean Neovim, because docs views do not open under the test runner.
-- Usage: nvim --headless --clean -u NONE -l tests/lsp/signature_driver.lua <nui path>
-- Prints JSON describing the windows around a repeated signature request to stdout.
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
local Signature = require("noice.lsp.signature")

local result = { signatures = { { label = "add(a, b)" } } }
local origin = vim.api.nvim_get_current_win()

Signature.on_signature(nil, vim.deepcopy(result), { bufnr = 0 }, {})
local message = Docs._messages.signature
vim.wait(500, function()
  return message:win() ~= nil or #notes > 0
end, 10)
vim.wait(50)
local opened = message:win()

Signature.on_signature(nil, vim.deepcopy(result), { bufnr = 0 }, {})
vim.wait(100)

io.stdout:write(vim.json.encode({
  notes = notes,
  opened = opened ~= nil,
  stayed = vim.api.nvim_get_current_win() == origin,
  still_open = message:win() ~= nil,
}))
vim.cmd("qa!")
