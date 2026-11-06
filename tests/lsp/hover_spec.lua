---@param values string[] markdown hover contents
---@return {notes: string[], lines: string[]|vim.NIL}[]
local function hover(values)
  local ret = vim
    .system({
      vim.v.progpath,
      "--headless",
      "--clean",
      "-u",
      "NONE",
      "-l",
      "tests/lsp/hover_driver.lua",
      vim.fn.stdpath("data") .. "/lazy/nui.nvim",
      vim.json.encode(values),
    }, { text = true })
    :wait(30000)
  assert.equal(0, ret.code, ret.stderr)
  return vim.json.decode(ret.stdout)
end

describe("lsp hover with empty code fences", function()
  it("renders text after a leading empty fence", function()
    for _, ret in ipairs(hover({ "```lua\n```\nhello", "```markdown\n```\nhello", "```zig\n```\nhello" })) do
      assert.same({}, ret.notes)
      assert.same({ "hello" }, ret.lines)
    end
  end)

  it("treats a blank-only fence as empty", function()
    local ret = hover({ "```lua\n   \n```\nhello" })[1]
    assert.same({}, ret.notes)
    assert.same({ "hello" }, ret.lines)
  end)

  it("reports no information for a hover that is only an empty fence", function()
    local ret = hover({ "```lua\n```" })[1]
    assert.same({ "No information available" }, ret.notes)
    assert.same(vim.NIL, ret.lines)
  end)

  it("keeps a paragraph break where an empty fence is dropped", function()
    local ret = hover({ "hello\n```lua\n```\nworld" })[1]
    assert.same({}, ret.notes)
    assert.same({ "hello", "", "world" }, ret.lines)
  end)

  it("still renders a fence with content", function()
    local ret = hover({ "```lua\nlocal a\n```\nhello" })[1]
    assert.same({}, ret.notes)
    assert.same({ "local a", "", "hello" }, ret.lines)
  end)
end)
