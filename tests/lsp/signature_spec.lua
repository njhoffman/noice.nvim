local Config = require("noice.config")
Config.setup()

local Signature = require("noice.lsp.signature")

describe("lsp signature", function()
  it("keeps the cursor where it is when requested again with the window open", function()
    local ret = vim
      .system({
        vim.v.progpath,
        "--headless",
        "--clean",
        "-u",
        "NONE",
        "-l",
        "tests/lsp/signature_driver.lua",
        vim.fn.stdpath("data") .. "/lazy/nui.nvim",
      }, { text = true })
      :wait(30000)
    assert.equal(0, ret.code, ret.stderr)

    local state = vim.json.decode(ret.stdout)
    assert.same({}, state.notes)
    assert.is_true(state.opened)
    assert.is_true(state.stayed)
    assert.is_true(state.still_open)
  end)

  describe("with no signature available", function()
    local notify, notes

    before_each(function()
      notify = vim.notify
      notes = {}
      vim.notify = function(text)
        notes[#notes + 1] = text
      end
    end)

    after_each(function()
      vim.notify = notify
      Config.options.lsp.signature.silent = false
    end)

    for name, result in pairs({ ["no result"] = false, ["no signatures"] = { signatures = {} } }) do
      it("says so for " .. name, function()
        Signature.on_signature(nil, result or nil, { bufnr = 0 }, {})
        assert.same({ "No signature help available" }, notes)
      end)

      it("stays quiet for " .. name .. " when silent", function()
        Config.options.lsp.signature.silent = true
        Signature.on_signature(nil, result or nil, { bufnr = 0 }, {})
        assert.same({}, notes)
      end)

      it("stays quiet for " .. name .. " when triggered by typing", function()
        Signature.on_signature(nil, result or nil, { bufnr = 0 }, { trigger = true })
        assert.same({}, notes)
      end)
    end
  end)
end)
