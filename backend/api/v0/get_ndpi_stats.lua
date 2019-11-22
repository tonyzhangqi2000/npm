dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path
require "lua_utils"
local json = require("dkjson")
sendHTTPContentTypeHeader('application/json', 'attachment; filename="dpi_stats.json"')

print(json.encode(interface.getnDPIStats() or {}))
