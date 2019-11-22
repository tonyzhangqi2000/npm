dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path
require "lua_utils"
local json = require("dkjson")
sendHTTPContentTypeHeader('application/json', 'attachment; filename="hosts_stats.json"')

-- 只统计本地主机： interface.getLocalHostsInfo
local hosts_info = interface.getLocalHostsInfo(true)

local function Set (list)
  local set = {}
  for _, l in ipairs(list) do set[l] = true end
  return set
end

local tags = {
  ["name"] = "name",
  ["ip"] = "ip",
  ["mac"] = "mac",
  ["vlan"] = "vlan",
  ["systemhost"] = "systemhost",
  ["localhost"] = "localhost",
  ["privatehost"] = "privatehost",
  ["is_multicast"] = "is_multicast",
  ["is_broadcast"] = "is_broadcast",
  ["local_network_name"] = "local_network_name",
}

local flows_fields = {
  ["flows.as_server"] = "flows_as_server",
  ["flows.as_client"] = "flows_as_client",
  ["active_flows.as_server"] = "active_flows_as_server",
  ["active_flows.as_client"] = "active_flows_as_client",
  ["low_goodput_flows.as_server"] = "low_goodput_flows_as_server",
  ["low_goodput_flows.as_client"] = "low_goodput_flows_as_client"
}

local t = "" .. os.time()*1000
local records = {}

local hosts = hosts_info['hosts']
for key, value in pairs(hosts) do
  local record = {}
  for k, v in pairs(tags) do
    record[v] = value[k]
  end
  for k, v in pairs(flows_fields) do
    record[v] = value[k]
  end
  record['time'] = t
  record['url'] = '/host_stats'
  table.insert(records, record)
end

print(json.encode(records))
