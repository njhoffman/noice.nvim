local require = require("noice.util.lazy")

local Cmdline = require("noice.ui.cmdline")
local Manager = require("noice.message.manager")
local Status = require("noice.api.status")

local M = {}

M.status = Status

M.history = {
  ---@param filter? NoiceFilter
  ---@return integer
  count = function(filter)
    return Manager.history_count(filter)
  end,
  -- Also closes views showing the removed messages
  ---@param filter? NoiceFilter
  ---@return integer removed
  clear = function(filter)
    return Manager.clear_history(filter)
  end,
}

---@deprecated
M.statusline = Status

---@return CmdlinePosition?
function M.get_cmdline_position()
  return Cmdline.position and vim.deepcopy(Cmdline.position)
end

return M
