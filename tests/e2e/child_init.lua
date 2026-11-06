-- Init file for the Neovim that tests/e2e/ui_spec.lua runs in a pty. Not a spec.
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.env.NOICE_E2E_NUI)
vim.o.shiftwidth = 2

require("noice").setup({ notify = { enabled = false }, health = { checker = false } })

local E2E = {}
_G.E2E = E2E

-- The text of each open noice float
function E2E.floats()
  local ret = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_win_get_config(win).relative ~= "" and vim.bo[buf].filetype == "noice" then
      ret[#ret + 1] = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    end
  end
  return ret
end

function E2E.running()
  return require("noice.config").is_running()
end

function E2E.history(find)
  local ret = {}
  for _, message in ipairs(require("noice.message.manager").get({ find = find }, { history = true, sort = true })) do
    ret[#ret + 1] = message:content()
  end
  return ret
end

function E2E.position()
  return require("noice").api.get_cmdline_position()
end

-- Starts an in-process language server answering hover with `text`, or with nothing if text is false
function E2E.start_lsp(name, text)
  return vim.lsp.start({
    name = name,
    cmd = function(dispatchers)
      local closing = false
      return {
        request = function(method, _, callback)
          if method == "initialize" then
            callback(nil, { capabilities = { hoverProvider = true } })
          elseif method == "textDocument/hover" then
            callback(nil, text and { contents = { kind = "markdown", value = text } } or nil)
          else
            callback(nil, nil)
          end
          return true, 1
        end,
        notify = function() end,
        is_closing = function()
          return closing
        end,
        terminate = function()
          closing = true
          dispatchers.on_exit(0, 0)
        end,
      }
    end,
  }, {
    reuse_client = function()
      return false
    end,
  })
end
