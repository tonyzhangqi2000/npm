dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path
require "lua_utils"
local json = require("dkjson")
sendHTTPContentTypeHeader('application/json', 'attachment; filename="hosts_stats.json"')

local hosts_stats = {}
local hosts_info = interface.getHostsInfo(false)
hosts_info = hosts_info["hosts"]

print("{")
local count = 0
for key, value in pairs(hosts_info) do
  host = interface.getHostInfo(key, value['vlan'])
  if (host ~= nil) then
    --hosts_stats[key] = json.decode(host['json'])
    if count ~= 0 then
        print(',')
    end
    print('"' .. key .. '"' .. ': '.. host.json)
    count = count + 1
  end
end

print("}")
