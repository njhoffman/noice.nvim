local require = require("noice.util.lazy")

local Config = require("noice.config")
local Format = require("noice.text.format")
local Manager = require("noice.message.manager")
local Message = require("noice.message")
local Router = require("noice.message.router")
local Util = require("noice.util")

local M = {}

---@type table<string, NoiceMessage>
M._progress = {}
M._running = false

---@param data {client_id: integer, params: lsp.ProgressParams}
function M.progress(data)
  local client_id = data.client_id
  local params = data.params
  local id = client_id .. "." .. params.token

  local message = M._progress[id]
  if not message then
    local client = vim.lsp.get_clients({ id = client_id })[1]
    -- should not happen, but it does for some reason
    if not client then
      return
    end
    message = Message("lsp", "progress")
    message.opts.progress = {
      client_id = client_id,
      ---@type string
      client = client and client.name or ("lsp-" .. client_id),
    }
    M._progress[id] = message
  end

  message.opts.progress = vim.tbl_deep_extend("force", message.opts.progress, params.value)
  message.opts.progress.id = id

  if params.value.kind == "end" then
    if message.opts.progress.percentage then
      message.opts.progress.percentage = 100
    end
    vim.defer_fn(function()
      M.close(id)
    end, 100)
  end

  M.update()
end

function M.close(id)
  local message = M._progress[id]
  if message then
    M.update()
    Router.update()
    Manager.remove(message)
    M._progress[id] = nil
  end
end

function M._update()
  if next(M._progress) ~= nil then
    for id, message in pairs(M._progress) do
      local client = vim.lsp.get_clients({ id = message.opts.progress.client_id })[1]
      if not client then
        M.close(id)
      end
      if message.opts.progress.kind == "end" then
        Manager.add(Format.format(message, Config.options.lsp.progress.format_done))
      else
        Manager.add(Format.format(message, Config.options.lsp.progress.format))
      end
    end
    return
  end
end

function M.update()
  error("should never be called")
end

function M.setup()
  M.update = Util.interval(Config.options.lsp.progress.throttle, M._update, {
    enabled = function()
      return next(M._progress) ~= nil
    end,
  })

  vim.api.nvim_create_autocmd("LspProgress", {
    group = vim.api.nvim_create_augroup("noice_lsp_progress", { clear = true }),
    callback = function(event)
      M.progress(event.data)
    end,
  })
end

return M
