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
end)
