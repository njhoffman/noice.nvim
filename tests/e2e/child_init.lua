-- Init file for the Neovim that tests/e2e/ui_spec.lua runs in a pty. Not a spec.
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.env.NOICE_E2E_NUI)
vim.o.shiftwidth = 2

-- Set by tests/e2e/notify_spec.lua to run against a real notification plugin
local backend = vim.env.NOICE_E2E_BACKEND
local opts = { notify = { enabled = false }, health = { checker = false } }

if backend then
  vim.opt.rtp:append(vim.env.NOICE_E2E_PLUGIN)
  vim.o.termguicolors = true
  _G.NoticedByHook = {}
  opts.notify.enabled = true
  opts.views = {
    notify = {
      backend = backend,
      fallback = "popup",
      on_notify = function(info)
        if vim.g.e2e_hook_fails then
          error("hook failed")
        end
        table.insert(_G.NoticedByHook, { content = info.content, level = info.level, title = info.title })
      end,
    },
  }
  if backend == "snacks" then
    require("snacks").setup({ notifier = { enabled = true } })
  else
    require("notify").setup({ background_colour = "#000000", stages = "static" })
  end
end

if vim.env.NOICE_E2E_VIEWS then
  opts.views = vim.tbl_deep_extend("force", opts.views or {}, vim.json.decode(vim.env.NOICE_E2E_VIEWS))
end

require("noice").setup(opts)

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

-- The open popupmenu: its lines, and the selected line if any
function E2E.menu()
  local menu = require("noice.ui.popupmenu.nui").menu
  if not (menu and menu.winid and vim.api.nvim_win_is_valid(menu.winid)) then
    return nil
  end
  E2E.menu_win = menu.winid
  return {
    lines = vim.tbl_map(vim.trim, vim.api.nvim_buf_get_lines(menu.bufnr, 0, -1, false)),
    selected = vim.wo[menu.winid].cursorline and vim.api.nvim_win_get_cursor(menu.winid)[1] or nil,
    height = vim.api.nvim_win_get_height(menu.winid),
    width = vim.api.nvim_win_get_width(menu.winid),
    position = vim.api.nvim_win_get_position(menu.winid),
    -- The rows it covers, border included
    top = vim.api.nvim_win_get_position(menu.border.winid or menu.winid)[1],
    bottom = vim.api.nvim_win_get_position(menu.border.winid or menu.winid)[1] + vim.api.nvim_win_get_height(
      menu.border.winid or menu.winid
    ) - 1,
  }
end

-- Notifications the real plugin received, oldest first, as { message, level, title }
function E2E.notifications()
  local ret = {}
  if backend == "snacks" then
    local history = Snacks.notifier.get_history({ reverse = false })
    table.sort(history, function(a, b)
      return a.added < b.added or (a.added == b.added and tostring(a.id) < tostring(b.id))
    end)
    for _, notif in ipairs(history) do
      ret[#ret + 1] = { message = notif.msg, level = notif.level:lower(), title = notif.title or "" }
    end
  else
    for _, record in ipairs(require("notify").history({ include_hidden = true })) do
      ret[#ret + 1] = {
        message = table.concat(record.message, "\n"),
        level = record.level:lower(),
        title = record.title[1] or "",
      }
    end
  end
  return vim.tbl_filter(function(n)
    return not n.message:find("E1568", 1, true)
  end, ret)
end

-- The text of each open notification window
function E2E.notification_texts()
  local ret = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "notify" or vim.bo[buf].filetype == "snacks_notif" then
      ret[#ret + 1] = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    end
  end
  return ret
end

-- The number of notification windows open now
function E2E.notification_windows()
  local count = 0
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
    if ft == "notify" or ft == "snacks_notif" then
      count = count + 1
    end
  end
  return count
end

-- Whether the last menu seen still has a window, whatever noice itself remembers
function E2E.menu_win_open()
  return E2E.menu_win ~= nil and vim.api.nvim_win_is_valid(E2E.menu_win)
end

-- A command completing from a fixed list
vim.api.nvim_create_user_command("E2eFoo", function(args)
  vim.g.foo_arg = args.args
end, {
  nargs = 1,
  complete = function(lead)
    return vim.tbl_filter(function(word)
      return word:find(lead, 1, true) == 1
    end, vim.g.foo_words or { "alpha", "alpine", "beta" })
  end,
})

-- Adds a route ahead of the others whose filter throws for messages that are exactly `text`, or for all
-- messages without one. Exactly, since the reported error is itself a message, and mentions `text`.
function E2E.add_throwing_route(text)
  require("noice.message.router").add({
    view = "mini",
    filter = {
      cond = function(message)
        if not text or message:content() == text then
          error("filter failed on " .. text)
        end
        return false
      end,
    },
  }, 1)
end

-- What each server can send to Neovim, so specs can send real notifications
E2E.servers = {}

-- Sends $/progress the way a real server does
function E2E.progress(name, token, value)
  E2E.servers[name].notification("$/progress", { token = token, value = value })
end

function E2E.progress_messages()
  local ret = {}
  for _, message in
    ipairs(require("noice.message.manager").get({ event = "lsp", kind = "progress" }, { history = true }))
  do
    ret[#ret + 1] = message:content()
  end
  return ret
end

-- Starts an in-process language server answering hover with `text`, or with nothing if text is false
function E2E.start_lsp(name, text)
  return vim.lsp.start({
    name = name,
    cmd = function(dispatchers)
      local closing = false
      E2E.servers[name] = dispatchers
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
