local Config = require("noice.config")
local View = require("noice.view")
Config.setup()

describe("checking views", function()
  it("view is loaded only once", function()
    local opts = { enter = true, format = "details" }
    local view1 = View.get_view("split", opts)
    local view2 = View.get_view("split", opts)
    assert.equal(view1, view2)
  end)
end)
