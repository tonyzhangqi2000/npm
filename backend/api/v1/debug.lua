dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path
require "lua_utils"
local json = require("dkjson")
sendHTTPContentTypeHeader('application/json', 'attachment; filename="hosts_stats.json"')

local mode = _GET["mode"] or 'local'

if mode == "all" then
  hosts_retrv_function = interface.getHostsInfo
elseif mode == "local" then
  hosts_retrv_function = interface.getLocalHostsInfo
elseif mode == "remote" then
  hosts_retrv_function = interface.getRemoteHostsInfo
end

local records = {}
local hosts = hosts_retrv_function(false)['hosts']
for key, value in pairs(hosts) do
  host = interface.getHostInfo(key, value['vlan'])
  if (host ~= nil) then
    table.insert(records, host)
  end
end

print(json.encode(records))
