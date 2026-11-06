local Driver = require("e2e.driver")

for backend, repo in pairs({ snacks = "folke/snacks.nvim", notify = "rcarriga/nvim-notify" }) do
  describe("notifications through " .. backend, function()
    local nvim, lua, input, wait_for

    local function notifications(count)
      return wait_for(count .. " notifications", function()
        local all = lua("E2E.notifications()")
        return #all == count and all
      end)
    end

    local function notify(message, level, opts)
      lua("(function(...) vim.notify(...) end)(...) == nil", message, level, opts or vim.empty_dict())
    end

    before_each(function()
      nvim = Driver.start({ NOICE_E2E_BACKEND = backend, NOICE_E2E_PLUGIN = Driver.plugin(repo) })
      lua, input, wait_for = nvim.lua, nvim.input, nvim.wait_for
    end)

    after_each(function()
      nvim.stop()
    end)

    it("shows vim.notify with its level and title", function()
      notify("hello", vim.log.levels.WARN, { title = "Greeting" })
      local n = notifications(1)[1]
      assert.truthy(n.message:find("hello", 1, true), n.message)
      assert.equal("warn", n.level)
      assert.equal("Greeting", n.title)
      wait_for("a window", function()
        return lua("E2E.notification_windows()") == 1
      end)
    end)

    it("shows a notification for each of two identical messages", function()
      notify("twice", vim.log.levels.INFO)
      notifications(1)
      notify("twice", vim.log.levels.INFO)
      notifications(2)
    end)

    -- The default route for messages sets replace, which also explains why a repeat looks like one message
    it("shows two identical echoes in one window, and keeps both in the history", function()
      input(":echo 'twice'<cr>")
      wait_for("a window", function()
        return lua("E2E.notification_windows()") == 1
      end)
      input(":echo 'twice'<cr>")
      wait_for("both in the history", function()
        return #lua("E2E.history(...)", "^twice$") == 2
      end)
      vim.wait(200)
      assert.equal(1, lua("E2E.notification_windows()"))
    end)

    it("replaces an echo with the next one", function()
      input(":echo 'first'<cr>")
      wait_for("the first", function()
        return table.concat(lua("E2E.notification_texts()"), "\n"):find("first", 1, true)
      end)
      input(":echo 'second'<cr>")
      -- Checked together, since the first would also close by itself after a timeout
      local text = wait_for("the second", function()
        local current = table.concat(lua("E2E.notification_texts()"), "\n")
        return current:find("second", 1, true) and current
      end)
      assert.is_nil(text:find("first", 1, true), text)
    end)

    it("replaces a notification when asked", function()
      if backend == "snacks" then
        notify("first", vim.log.levels.INFO, { id = "job" })
        notifications(1)
        notify("second", vim.log.levels.INFO, { id = "job" })
      else
        lua([[(function() _G.first = vim.notify("first", vim.log.levels.INFO) end)() == nil]])
        notifications(1)
        lua([[(function() vim.notify("second", vim.log.levels.INFO, { replace = _G.first }) end)() == nil]])
      end
      wait_for("the new text", function()
        for _, content in ipairs(lua("E2E.notification_texts()")) do
          if content:find("second", 1, true) then
            return not content:find("first", 1, true)
          end
        end
      end)
      assert.equal(1, lua("E2E.notification_windows()"))
    end)

    it("shows an error message at error level", function()
      input(":echoerr 'broken'<cr>")
      local n = wait_for("the error", function()
        for _, candidate in ipairs(lua("E2E.notifications()")) do
          if candidate.message:find("broken", 1, true) then
            return candidate
          end
        end
      end)
      assert.equal("error", n.level)
    end)

    it("closes the windows on dismiss", function()
      -- No timeout, or it would close by itself while the spec waits
      notify("hello", vim.log.levels.INFO, { timeout = false })
      wait_for("a window", function()
        return lua("E2E.notification_windows()") == 1
      end)
      input(":Noice dismiss<cr>")
      wait_for("no windows", function()
        return lua("E2E.notification_windows()") == 0
      end)
    end)

    describe("on_notify", function()
      it("is called with what was shown", function()
        notify("logged", vim.log.levels.WARN, { title = "Log" })
        notifications(1)
        local calls = wait_for("the hook", function()
          local all = lua("_G.NoticedByHook")
          return #all > 0 and all
        end)
        assert.same({ content = "logged", level = "warn", title = "Log" }, calls[1])
      end)

      it("does not lose the notification when it fails", function()
        lua("(function() vim.g.e2e_hook_fails = true end)() == nil")
        notify("kept", vim.log.levels.INFO)
        wait_for("the notification", function()
          for _, n in ipairs(lua("E2E.notifications()")) do
            if n.message:find("kept", 1, true) then
              return true
            end
          end
        end)
      end)
    end)
  end)
end
