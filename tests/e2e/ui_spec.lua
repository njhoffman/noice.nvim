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

  describe("lsp progress", function()
    local function start(name)
      local id = lua("E2E.start_lsp(...)", name, false)
      wait_for("the server", function()
        return lua("vim.lsp.get_client_by_id(...).initialized", id)
      end)
      return id
    end

    local function progress(name, token, value)
      lua("E2E.progress(...) == nil", name, token, value)
    end

    it("shows the title, the message and the server's name", function()
      start("server")
      progress("server", "t", { kind = "begin", title = "Indexing", message = "file.lua" })
      local content = float("Indexing")
      assert.truthy(content:find("file.lua", 1, true), content)
      assert.truthy(content:find("server", 1, true), content)
    end)

    it("updates as reports arrive", function()
      start("server")
      progress("server", "t", { kind = "begin", title = "Indexing", message = "one" })
      float("one")
      progress("server", "t", { kind = "report", message = "two", percentage = 50 })
      local content = float("two")
      assert.is_nil(content:find("one", 1, true), content)
      assert.equal(1, #lua("E2E.progress_messages()"))
    end)

    it("removes the message after the end", function()
      start("server")
      progress("server", "t", { kind = "begin", title = "Indexing" })
      float("Indexing")
      progress("server", "t", { kind = "end" })
      wait_for("the message to go", function()
        return #lua("E2E.progress_messages()") == 0
      end)
      no_float("Indexing")
    end)

    it("keeps tokens and servers apart", function()
      start("one")
      start("two")
      progress("one", "a", { kind = "begin", title = "First" })
      progress("one", "b", { kind = "begin", title = "Second" })
      progress("two", "a", { kind = "begin", title = "Third" })
      local content = float("Third")
      assert.truthy(content:find("First", 1, true), content)
      assert.truthy(content:find("Second", 1, true), content)
      assert.equal(3, #lua("E2E.progress_messages()"))
    end)

    it("takes a numeric token", function()
      start("server")
      progress("server", 7, { kind = "begin", title = "Indexing" })
      float("Indexing")
    end)

    it("drops the message when the server stops halfway", function()
      local id = start("server")
      progress("server", "t", { kind = "begin", title = "Indexing" })
      float("Indexing")
      lua("vim.lsp.get_client_by_id(...):stop(true) == nil", id)
      wait_for("the server to stop", function()
        return lua("vim.lsp.get_client_by_id(...) == nil", id)
      end)
      vim.wait(300)
      assert.same({}, lua("E2E.progress_messages()"))
      no_float("Indexing")
    end)
  end)

  describe("popupmenu", function()
    -- A nil comes back over RPC as vim.NIL, which is truthy
    local function current_menu()
      local ret = lua("E2E.menu()")
      return ret ~= vim.NIL and ret or nil
    end

    local function menu()
      return wait_for("the menu", current_menu)
    end

    local function no_menu()
      wait_for("the menu to close", function()
        return current_menu() == nil and not lua("E2E.menu_win_open()")
      end)
    end

    local function selected(line)
      wait_for("line " .. line .. " selected", function()
        local m = current_menu()
        return m and m.selected == line
      end)
    end

    describe("in the cmdline", function()
      -- Sent apart, since Neovim shows no menu while more typed keys are pending
      local function complete(text)
        input(text)
        wait_for("the cmdline", function()
          return lua("vim.fn.getcmdline()") == text:sub(2)
        end)
        input("<tab>")
      end

      local function items(count)
        return wait_for(count .. " items", function()
          local current = current_menu()
          return current and #current.lines == count and current
        end)
      end

      it("lists completions and selects the first", function()
        complete(":E2eFoo ")
        assert.same({ "alpha", "alpine", "beta" }, items(3).lines)
        selected(1)
      end)

      it("narrows to what was typed", function()
        complete(":E2eFoo al")
        assert.same({ "alpha", "alpine" }, items(2).lines)
      end)

      it("moves the selection and fills the cmdline", function()
        complete(":E2eFoo ")
        menu()
        input("<tab>")
        wait_for("the second item", function()
          return lua("vim.fn.getcmdline()") == "E2eFoo alpine"
        end)
        selected(2)
      end)

      it("closes on escape", function()
        complete(":E2eFoo ")
        menu()
        input("<esc>")
        no_menu()
        mode("n")
      end)

      it("runs the command with the choice", function()
        complete(":E2eFoo ")
        menu()
        input("<tab>")
        selected(2)
        input("<tab>")
        selected(3)
        input("<cr>")
        wait_for("the command to run", function()
          return lua("vim.g.foo_arg") == "beta"
        end)
        no_menu()
      end)

      it("sizes itself to its items", function()
        lua("(function() vim.g.foo_words = { 'short', 'a_rather_longer_word' } end)() == nil")
        complete(":E2eFoo ")
        local m = items(2)
        assert.equal(2, m.height)
        assert.is_true(m.width >= #"a_rather_longer_word")
      end)

      it("opens under the cmdline, at the start of the completed word", function()
        complete(":E2eFoo ")
        local m = items(3)
        local cmdline = wait_for("a position", function()
          local position = lua("E2E.position()")
          return position ~= vim.NIL and position
        end)
        assert.is_true(m.position[1] >= cmdline.screenpos.row - 1, vim.inspect({ m.position, cmdline.screenpos }))
        -- The window starts one column early, since its text has a column of padding on the left
        assert.equal(
          cmdline.screenpos.col + #"E2eFoo " - 1,
          m.position[2],
          vim.inspect({ m.position, cmdline.screenpos })
        )
      end)
    end)

    describe("in insert mode", function()
      before_each(function()
        lua("vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'apple', 'apricot', 'banana', '' }) == nil")
        lua("vim.api.nvim_win_set_cursor(0, { 4, 0 }) == nil")
      end)

      it("lists matches next to the cursor", function()
        input("ia<C-n>")
        local m = wait_for("two items", function()
          local current = current_menu()
          return current and #current.lines == 2 and current
        end)
        assert.same({ "apple", "apricot" }, m.lines)
      end)

      it("moves the selection and inserts the choice", function()
        input("ia<C-n>")
        selected(1)
        input("<C-n>")
        selected(2)
        input("<C-y>")
        no_menu()
        wait_for("the text", function()
          return lua("vim.api.nvim_get_current_line()") == "apricot"
        end)
      end)

      it("closes on leaving insert mode", function()
        input("ia<C-n>")
        menu()
        input("<esc>")
        no_menu()
        mode("n")
      end)

      it("shows the menu text and kind of an item", function()
        input(
          "i<cmd>lua vim.fn.complete(1, { { word = 'one', kind = 'Function', menu = 'extra' }, { word = 'two' } })<cr>"
        )
        local line = menu().lines[1]
        assert.truthy(line:find("one", 1, true), line)
        assert.truthy(line:find("extra", 1, true), line)
        assert.truthy(line:find("Function", 1, true), line)
      end)

      it("keeps a multi-line item on one line", function()
        input("i<cmd>lua vim.fn.complete(1, { { word = 'one', menu = 'line1\\nline2' }, { word = 'two' } })<cr>")
        local m = wait_for("two items", function()
          local current = current_menu()
          return current and #current.lines == 2 and current
        end)
        assert.truthy(m.lines[1]:find("one", 1, true), m.lines[1])
      end)

      it("caps its height and scrolls to the selection", function()
        local words = {}
        for i = 1, 25 do
          words[i] = ("{ word = 'word%d' }"):format(i)
        end
        input("i<cmd>lua vim.fn.complete(1, { " .. table.concat(words, ", ") .. " })<cr>")
        local m = wait_for("all the items", function()
          local current = current_menu()
          return current and #current.lines == 25 and current
        end)
        assert.is_true(m.height <= 20)
        input(string.rep("<C-n>", 24))
        wait_for("the last item", function()
          local current = current_menu()
          return current and current.selected == 25
        end)
        assert.equal("word25", lua("vim.api.nvim_get_current_line()"))
      end)
    end)
  end)

  describe("a route that throws", function()
    it("does not stop later messages", function()
      lua("E2E.add_throwing_route(...) == nil", "poison")
      input(":echo 'poison'<cr>")
      vim.wait(200)
      input(":echo 'healthy'<cr>")
      float("healthy")
      input(":echo 'still fine'<cr>")
      float("still fine")
      assert.is_true(lua("E2E.running()"))
      assert.equal(1, #lua("E2E.history(...)", "^poison$"))
    end)

    it("disables noice if it throws for every message, including the errors it causes", function()
      lua("E2E.add_throwing_route() == nil")
      input(":echo 'anything'<cr>")
      wait_for("noice to disable itself", function()
        return not lua("E2E.running()")
      end)
      mode("n")
      input(":let g:still_works = 1<cr>")
      wait_for("the command to run", function()
        return lua("vim.g.still_works") == 1
      end)
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
