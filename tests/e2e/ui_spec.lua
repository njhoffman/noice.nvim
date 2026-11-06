-- Real keys through a real terminal UI: a Neovim in a pty, driven and inspected over RPC.
-- Events only match real use with a UI attached. Without one, for example, confirm() returns at once.

describe("e2e", function()
  local job, chan, sock

  local function rpc(...)
    return vim.rpcrequest(chan, ...)
  end

  local function lua(code, ...)
    return rpc("nvim_exec_lua", "return " .. code, { ... })
  end

  local function input(keys)
    rpc("nvim_input", keys)
  end

  local function wait_for(what, fn)
    local value
    local ok = vim.wait(5000, function()
      value = fn()
      return value
    end, 10)
    assert.is_true(ok, "timed out waiting for " .. what)
    return value
  end

  -- The float containing `text`
  local function float(text)
    return wait_for("a float with " .. text, function()
      for _, content in ipairs(lua("E2E.floats()")) do
        if content:find(text, 1, true) then
          return content
        end
      end
    end)
  end

  local function no_float(text)
    wait_for("no float with " .. text, function()
      for _, content in ipairs(lua("E2E.floats()")) do
        if content:find(text, 1, true) then
          return false
        end
      end
      return true
    end)
  end

  local function mode(expected)
    wait_for("mode " .. expected, function()
      return rpc("nvim_get_mode").mode == expected
    end)
  end

  before_each(function()
    sock = vim.fn.tempname()
    job = vim.fn.jobstart({ vim.v.progpath, "--clean", "--listen", sock, "-u", "tests/e2e/child_init.lua" }, {
      pty = true,
      width = 100,
      height = 30,
      env = { NOICE_E2E_NUI = vim.fn.stdpath("data") .. "/lazy/nui.nvim", TERM = "xterm-256color" },
    })
    assert.is_true(vim.wait(5000, function()
      return vim.uv.fs_stat(sock) ~= nil
    end, 10))
    chan = vim.fn.sockconnect("pipe", sock, { rpc = true })
    wait_for("noice to start", function()
      return rpc("nvim_get_vvar", "vim_did_enter") == 1 and lua("E2E.running()")
    end)
  end)

  after_each(function()
    pcall(vim.fn.chanclose, chan)
    vim.fn.jobstop(job)
    vim.fn.jobwait({ job }, 2000)
  end)

  describe("cmdline", function()
    it("shows typed text in a popup and closes on escape", function()
      input(":lua pri")
      local content = float("pri")
      assert.is_nil(content:find("lua", 1, true))
      assert.equal("c", rpc("nvim_get_mode").mode)
      input("<esc>")
      no_float("pri")
      mode("n")
    end)

    it("reports where the cmdline is", function()
      input(":echo")
      float("echo")
      local position = wait_for("a position", function()
        return lua("E2E.position()")
      end)
      assert.is_true(position.screenpos.row > 0)
      assert.is_true(position.screenpos.col > 0)
    end)

    it("shows a search", function()
      input("/needle")
      float("needle")
      input("<esc>")
      no_float("needle")
    end)

    it("runs the command", function()
      input(":let g:ran = 1<cr>")
      wait_for("the command to run", function()
        return lua("vim.g.ran") == 1
      end)
      no_float("let g:ran")
    end)

    it("takes input() and returns the answer", function()
      input(":let g:answer = input('Name: ')<cr>")
      mode("c")
      input("bob")
      float("bob")
      input("<cr>")
      wait_for("the answer", function()
        return lua("vim.g.answer") == "bob"
      end)
      no_float("bob")
    end)
  end)

  describe("confirm", function()
    local ASK = [[:let g:choice = confirm('Save it?', "&Yes\n&No")<cr>]]

    it("shows the question and its choices, and returns the answer", function()
      input(ASK)
      local content = float("Save it?")
      assert.truthy(content:find("[Y]es", 1, true))
      assert.truthy(content:find("(N)o", 1, true))
      input("n")
      wait_for("the choice", function()
        return lua("vim.g.choice") == 2
      end)
      no_float("Save it?")
    end)

    it("shows the same question again", function()
      for choice, key in ipairs({ "y", "n" }) do
        input(ASK)
        float("Save it?")
        input(key)
        wait_for("the choice", function()
          return lua("vim.g.choice") == choice
        end)
        no_float("Save it?")
      end
    end)

    it("stays open through a redraw, without repeating the choices", function()
      input(ASK)
      float("Save it?")
      rpc("nvim_command", "redraw!")
      vim.wait(100)
      local content = float("Save it?")
      local _, count = content:gsub("%[Y%]es", "")
      assert.equal(1, count)
      input("y")
      no_float("Save it?")
    end)
  end)

  describe("messages", function()
    it("shows a repeated message each time", function()
      input(":echo 'twice'<cr>")
      float("twice")
      input(":echo 'twice'<cr>")
      wait_for("two messages", function()
        return #lua("E2E.history(...)", "^twice$") == 2
      end)
      float("twice\ntwice")
    end)

    it("continues a message with echon", function()
      input([[:echo 'left' | echon 'right'<cr>]])
      float("leftright")
    end)

    it("updates a message by id", function()
      lua([[vim.api.nvim_echo({ { "working" } }, false, { id = "job" })]])
      float("working")
      lua([[vim.api.nvim_echo({ { "finished" } }, false, { id = "job" })]])
      -- Checked together, since the mini view drops the old message by itself after a timeout
      assert.is_nil(float("finished"):find("working", 1, true))
    end)

    it("does not stop for a multi-line message", function()
      input([[:echo "one\ntwo"<cr>]])
      wait_for("the message", function()
        return #lua("E2E.history(...)", "one") == 1
      end)
      mode("n")
    end)

    it("keeps where an option was set in verbose output", function()
      input(":verbose set shiftwidth?<cr>")
      local content = wait_for("the output", function()
        return lua("E2E.history(...)", "shiftwidth=2")[1]
      end)
      assert.truthy(content:find("Last set from", 1, true), content)
    end)
  end)

  describe("hover with two language servers", function()
    local function start(...)
      local answers = { ... }
      local count = select("#", ...)
      for i = 1, count do
        lua("E2E.start_lsp(...) ~= nil", "server" .. i, answers[i])
      end
      wait_for("the servers", function()
        return lua("#vim.lsp.get_clients({ bufnr = 0 })") == count
      end)
    end

    it("shows both answers on the first K", function()
      start("first answer", "second answer")
      input("K")
      local content = float("first answer")
      assert.truthy(content:find("second answer", 1, true))
      assert.truthy(content:find("server1", 1, true))
      assert.truthy(content:find("server2", 1, true))
    end)

    it("shows one answer without a name when the other server has none", function()
      start(false, "only answer")
      input("K")
      local content = float("only answer")
      assert.is_nil(content:find("server", 1, true))
    end)
  end)
end)
