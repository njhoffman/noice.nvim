---@param values (string|string[])[] one case per entry: markdown, or a list with one markdown per client
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
      vim.json.encode(vim.tbl_map(function(value)
        return type(value) == "table" and value or { value }
      end, values)),
    }, { text = true })
    :wait(30000)
  assert.equal(0, ret.code, ret.stderr)
  return vim.json.decode(ret.stdout)
end

describe("lsp hover with several clients", function()
  it("merges the answers under each client's name", function()
    local ret = hover({ { "first", "second" } })[1]
    assert.same({}, ret.notes)
    assert.same("1", ret.lines[1])
    assert.truthy(vim.tbl_contains(ret.lines, "first"))
    assert.truthy(vim.tbl_contains(ret.lines, "2"))
    assert.truthy(vim.tbl_contains(ret.lines, "second"))
  end)

  it("orders the answers by client id", function()
    local lines = hover({ { "first", "second" } })[1].lines
    local joined = table.concat(lines, "\n")
    assert.is_true(joined:find("first", 1, true) < joined:find("second", 1, true))
  end)

  it("shows no name for a single answer", function()
    local ret = hover({ { "only" } })[1]
    assert.same({}, ret.notes)
    assert.same({ "only" }, ret.lines)
  end)

  it("ignores a client with no result", function()
    local ret = hover({ { false, "only" } })[1]
    assert.same({}, ret.notes)
    assert.same({ "only" }, ret.lines)
  end)

  it("ignores a client with empty contents", function()
    local ret = hover({ { "", "only" }, { "   ", "only" } })
    for _, r in ipairs(ret) do
      assert.same({}, r.notes)
      assert.same({ "only" }, r.lines)
    end
  end)

  it("reports no information when no client has anything", function()
    local ret = hover({ { false, "" } })[1]
    assert.same({ "No information available" }, ret.notes)
    assert.same(vim.NIL, ret.lines)
  end)

  it("handles a leading empty fence from any client", function()
    local ret = hover({ { "```lua\n```\nfirst", "second" }, { "first", "```lua\n```\nsecond" } })
    for _, r in ipairs(ret) do
      assert.same({}, r.notes)
      assert.truthy(vim.tbl_contains(r.lines, "first"))
      assert.truthy(vim.tbl_contains(r.lines, "second"))
    end
  end)
end)

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
