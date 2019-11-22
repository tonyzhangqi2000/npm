dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path
require "lua_utils"
local json = require("dkjson")

sendHTTPContentTypeHeader('application/json', 'attachment; filename="assets.json"')

local discover = require "discover_utils"
local discovered = discover.discover2table(ifname)

-- 加入厂商信息
for _, device in pairs(discovered["devices"] or {}) do
	device["manufacturer"] = (device["manufacturer"] or get_manufacturer_mac(device["mac"]))
end

print(json.encode(discovered or {}))
