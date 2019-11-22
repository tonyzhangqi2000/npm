dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path
require "lua_utils"
local json = require("dkjson")
local flows_stats = interface.getFlowsInfo(nil, {detailsLevel="max"})
sendHTTPContentTypeHeader('application/json', 'attachment; filename="flows.json"')
print(json.encode(flows_stats or {}))
