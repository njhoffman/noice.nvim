-- Real keys through a real terminal UI: a Neovim in a pty, driven and inspected over RPC.
-- Events only match real use with a UI attached. Without one, for example, confirm() returns at once.
local M = {}

-- A plugin for specs to run against, cloned once. Not a lazy.nvim spec of tests/minit.lua, since every
-- other spec would then load it through require("notify") and change what they test.
---@param repo string
---@return string path
function M.plugin(repo)
  local path = vim.fn.stdpath("data") .. "/e2e/" .. repo:match("[^/]+$")
  if not vim.uv.fs_stat(path) then
    local ret = vim.system({ "git", "clone", "--depth", "1", "https://github.com/" .. repo, path }):wait(120000)
    assert(ret.code == 0, ret.stderr)
  end
  return path
end

---@param env? table<string, string> extra environment for tests/e2e/child_init.lua
function M.start(env)
  local sock = vim.fn.tempname()
  local job = vim.fn.jobstart({ vim.v.progpath, "--clean", "--listen", sock, "-u", "tests/e2e/child_init.lua" }, {
    pty = true,
    width = 100,
    height = 30,
    env = vim.tbl_extend("force", {
      NOICE_E2E_NUI = vim.fn.stdpath("data") .. "/lazy/nui.nvim",
      TERM = "xterm-256color",
    }, env or {}),
  })
  assert.is_true(vim.wait(5000, function()
    return vim.uv.fs_stat(sock) ~= nil
  end, 10))
  local chan = vim.fn.sockconnect("pipe", sock, { rpc = true })

  local self = {}

  function self.rpc(...)
    return vim.rpcrequest(chan, ...)
  end

  function self.lua(code, ...)
    return self.rpc("nvim_exec_lua", "return " .. code, { ... })
  end

  function self.input(keys)
    self.rpc("nvim_input", keys)
  end

  function self.wait_for(what, fn)
    local value
    local ok = vim.wait(5000, function()
      value = fn()
      return value
    end, 10)
    assert.is_true(ok, "timed out waiting for " .. what)
    return value
  end

  -- The float containing `text`
  function self.float(text)
    return self.wait_for("a float with " .. text, function()
      for _, content in ipairs(self.lua("E2E.floats()")) do
        if content:find(text, 1, true) then
          return content
        end
      end
    end)
  end

  function self.no_float(text)
    self.wait_for("no float with " .. text, function()
      for _, content in ipairs(self.lua("E2E.floats()")) do
        if content:find(text, 1, true) then
          return false
        end
      end
      return true
    end)
  end

  function self.mode(expected)
    self.wait_for("mode " .. expected, function()
      return self.rpc("nvim_get_mode").mode == expected
    end)
  end

  function self.stop()
    pcall(vim.fn.chanclose, chan)
    vim.fn.jobstop(job)
    vim.fn.jobwait({ job }, 2000)
  end

  self.wait_for("noice to start", function()
    return self.rpc("nvim_get_vvar", "vim_did_enter") == 1 and self.lua("E2E.running()")
  end)
  return self
end

return M
