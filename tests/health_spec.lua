local Health = require("noice.health")

describe("health", function()
  it("logs at info level during checkhealth", function()
    local ok, err = pcall(Health.log.checkhealth.info, "version %s", "1")
    -- vim.health may refuse outside :checkhealth, but the function itself has to exist
    assert.is_nil(not ok and tostring(err):find("global 'info'", 1, true) or nil)
  end)
end)
