-- 资产--local network的主机
--
-- 说明，指标项之间的关系可以分为以下2类：
-- 1. 指标项相加是全集，可以放在饼图中进行可视化。这种需要生成多条记录，以k/v的方式组织数据，例如：
--    统计流量传输字节，需要生成以下多条记录：
--    a. protocol=udp,bytes_sent=10 bytes_rcvd=8
--    b. protocol=tcp,bytes_sent=1000 bytes_rcvd=29
--    c. protocol=icmp,bytes_sent=2 bytes_rcvd=400
--    d. protocol=other_ip,bytes_sent=0 bytes_rcvd=0
-- 2. 指标项相加是不是全集，或者根本就不是同一个单位(例如：字节数和报文数)或维度(例如：发送和接收)
--    这种情况下，所有指标项放在一条记录中。

dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path
require "lua_utils"
local json = require("dkjson")
sendHTTPContentTypeHeader('application/json', 'attachment; filename="assets_stats.json"')

local ifstats = interface.getStats()
local iface = ifstats.name

local hosts_retrv_function = interface.getLocalHostsInfo
local hosts = hosts_retrv_function(false)['hosts']
local flows = interface.getFlowsInfo(nil, {detailsLevel="max"})['flows']

-- 查询列表是否包含某个值
local function Set (list)
  local set = {}
  for _, l in ipairs(list) do set[l] = true end
  return set
end

-- 主机相关描述信息，作为tag使用
local common_tags = {
  ["name"] = "name",
  ["ip"] = "ip",
  ["mac"] = "mac",
  ["vlan"] = "vlan",
  -- ["systemhost"] = "systemhost", -- 表示检测系统本身，没什么用处，只注释不删除是为了备忘
  ["localhost"] = "localhost",
  ["privatehost"] = "privatehost",
  ["is_multicast"] = "is_multicast",
  ["is_broadcast"] = "is_broadcast",
  ["local_network_name"] = "local_network_name",
  ["seen.last"] = "seen_last",
}

-- 生成一个记录，使用common_tags初始化
local function newRecord(host)
  local record = {}
  for k, v in pairs(common_tags) do
    record[v] = host[k]
  end

  record['iface'] = iface

  if isIPv4(host["ip"]) then
    record["ip_ver"] = "4"
  elseif isIPv6(host["ip"]) then
    record["ip_ver"] = "6"
  else
    record["ip_ver"] = "INVALID"
  end

  return record
end

-- 可以用饼图表示，所以需要支持分组
local function makeFlowStats(host)
  local records = {}
  local fields = {
    ["flows.as_server"] = "server",
    ["flows.as_client"] = "client",
  }

  local record = newRecord(host)
  for k, v in pairs(fields) do
    local record = newRecord(host)
    record['as'] = v
    record['flows_num'] = host[k]

    record['metric_name'] = "hosts:flows"
    table.insert(records, record)
  end

  return records
end

-- rtt指标
local function makeRttL4Stats(host)
  local record = newRecord(host)

  -- 作为服务器，则提取cli2srv的指标
  record['rtt_max_as_server'] = 0
  record['rtt_min_as_server'] = 0
  record['rtt_avg_as_server'] = 0
  for _, flow in pairs(flows) do
    if host['ip'] == flow['srv.ip'] then
      local rtt = flow['interarrival.cli2srv']
      if record['rtt_max_as_server'] < rtt['max'] then
        record['rtt_max_as_server'] = rtt['max']
      end

      if record['rtt_min_as_server'] == 0 or record['rtt_min_as_server']>rtt['min'] then
        record['rtt_min_as_server'] = rtt['min']
      end

      record['rtt_avg_as_server'] = rtt['avg']
    end
  end

  -- 作为客户端，则提取srv2cli的指标
  record['rtt_max_as_client'] = 0
  record['rtt_min_as_client'] = 0
  record['rtt_avg_as_client'] = 0
  for _, flow in pairs(flows) do
    if host['ip'] == flow['cli.ip'] then
      local rtt = flow['interarrival.srv2cli']
      if record['rtt_max_as_client'] < rtt['max'] then
        record['rtt_max_as_client'] = rtt['max']
      end

      if record['rtt_min_as_client'] == 0 or record['rtt_min_as_client'] > rtt['min'] then
        record['rtt_min_as_client'] = rtt['min']
      end

      record['rtt_avg_as_client'] = rtt['avg']
    end
  end

  record['metric_name'] = 'hosts:rtt_l4'
  return { record }
end

local function makeTrafficStats(host)
  local records = {}
  for _, v in ipairs({'udp', 'tcp', 'icmp', 'other_ip'}) do
    local record = newRecord(host)
    record['protocol'] = v
    record['bytes_sent_num'] = host[v..".bytes.sent"]
    record['packets_sent_num'] = host[v..".packets.sent"]
    record['bytes_rcvd_num'] = host[v..".bytes.rcvd"]
    record['packets_rcvd_num'] = host[v..".packets.rcvd"]

    record['metric_name'] = 'hosts:traffic'
    table.insert(records, record)
  end

  return records
end

-- 报文大小分布，为了便于分组，生成多条记录
local function makePacketsDistributeionStats(host)
  local fields = {
    ["upTo64"] = "upTo64",
    ["upTo128"] = "upTo128",
    ["upTo256"] = "upTo256",
    ["upTo512"] = "upTo512",
    ["upTo1024"] = "upTo1024",
    ["upTo1518"] = "upTo1518",
    ["upTo6500"] = "upTo6500",
    ["above9000"] = "above9000"
  }

  local records = {}
  local sent = host["pktStats.sent"]
  local rcvd = host["pktStats.recv"]

  for k, v in pairs(fields) do
    local record = newRecord(host)
    record['size'] = v
    record['sent_num'] = sent[k]
    record['rcvd_num'] = rcvd[k]

    record['metric_name'] = "hosts:packets_distribution"
    table.insert(records, record)
  end

  return records
end

-- tcp状态
local function makeTcpFlagStats(host)
  local fields = {
    ["finack"] = "finack",
    ["rst"] = "rst",
    ["synack"] = "synack",
    ["syn"] = "syn",
  }

  local record = newRecord(host)

  local sent = host["pktStats.sent"]
  local recv = host["pktStats.recv"]
  for k, v in pairs(fields) do
    record[v .. '_sent'] = sent[k]
    record[v .. '_recv'] = recv[k]
  end

  record['metric_name'] = "hosts:tcp_flag"
  return {record}
end

-- tcp传输状态，用于统计传输质量
local function makeTcpTransStats(host)
  local fields = {
    ["tcp.packets.out_of_order"] = "out_of_order",
    ["tcp.packets.retransmissions"]  = "retransmissions",
    ["tcp.packets.lost"] = "lost"
  }

  local records = {}
  if "tcp.packets.seq_problems" then
    local abnormal = 0
    local record = newRecord(host)
    for k, v in pairs(fields) do
      record[v] = host[k]
      abnormal = abnormal + host[k]
    end

    record['other'] = host["tcp.packets.sent"] + host["tcp.packets.rcvd"] - abnormal
    record['metric_name'] = "hosts:tcp_transmission"
    table.insert(records, record)
  end

  return records
end

-- dpi协议统计
local category_names = {
  ["Unspecified"] = "未分类协议",
  ["VoIP"] = "VoIP",
  ["Chat"] = "聊天",
  ["Database"] = "数据库",
  ["VPN"] = "VPN",
  ["Collaborative"] = "协作",
  ["RPC"] = "RPC",
  ["Email"] = "电子邮件",
  ["Network"] = "网络设施",
  ["System"] = "系统层协议",
  ["RemoteAccess"] = "远程访问",
  ["Download-FileTransfer-FileSharing"] = "文件下载传输共享",
  ["Web"] = "Web",
  ["Game"] = "游戏",
  ["SocialNetwork"] = "社交网络",
}

local function makeDpiStats(host)
  category_fields = {
    ["bytes"] = "bytes",
    ["bytes.sent"] = "bytes_sent",
    ["bytes.rcvd"] = "bytes_rcvd"
  }

  dpi_fields = {
    ["packets.rcvd"] = "packets_rcvd",
    ["packets.sent"] = "packets_sent",
    ["bytes.rcvd"] = "bytes_rcvd",
    ["bytes.sent"] = "bytes_sent"
  }

  local records = {}

  local category = host["ndpi_categories"]
  for c, v in pairs(category) do
    local record = newRecord(host)
    record["dpi_category"] = category_names[c] or c
    for field, name in pairs(category_fields) do
      record[name] = v[field]
    end

    record['metric_name'] = "hosts:dpi_categories"
    table.insert(records, record)
  end

  local dpi = host['ndpi']
  for p, v in pairs(dpi) do
    local record = newRecord(host)
    record['dpi_protocol'] = p
    for field, name in pairs(dpi_fields) do
      record[name] = v[field]
    end

    record['bytes'] = record['bytes_rcvd'] + record['bytes_sent']
    record['packets'] = record['packets_rcvd'] + record['packets_sent']

    record['metric_name'] = "hosts:dpi_protocols"
    table.insert(records, record)
  end

  return records
end

-- dns，分为server和client
local function makeDnsStats(host)
  if host["dns"]==nil then
    return {}
  end

  local dns_rcvd = host['dns']['rcvd']
  local dns_sent = host['dns']['sent']

  if dns_rcvd == nil or dns_sent == nil then
    return {}
  end

  local metric_names = {
    "num_ptr",
    "num_a",
    "num_other",
    "num_mx",
    "num_aaaa",
    "num_soa",
    "num_txt",
    "num_ns",
    "num_any",
    "num_cname"
  }

  local records = {}

  -- 有dns reply则视为dns服务器
  if dns_sent["num_replies_error"] > 0 or dns_sent["num_replies_ok"] > 0 then
    -- 收到的查询请求分项数据
    for _, v in pairs(metric_names) do
      if dns_rcvd[v]~=nil and dns_rcvd[v] > 0 then
        local record = newRecord(host)
        record["query"] = v
        record["query_num"] = dns_rcvd[v]

        record['metric_name'] = "hosts:dns_server_query"
        table.insert(records, record)
      end
    end

    -- 发送的响应
    for _, v in pairs({"num_replies_error", "num_replies_ok"}) do
      local record = newRecord(host)
      record["reply"] = v
      record["reply_num"] = dns_sent[v]

      record['metric_name'] = "hosts:dns_server_reply"
      table.insert(records, record)
    end

    -- 合计
    local record = newRecord(host)
    record["query_total"] = dns_rcvd["num_queries"]
    record["reply_total"] = dns_sent["num_replies_error"] + dns_sent["num_replies_ok"]

    record['metric_name'] = "hosts:dns_server"
    table.insert(records, record)
  end

  -- 发送过dns请求则统计作为dns客户端的相关指标
  -- FIXME： 有可能没有必要
  if dns_sent["num_queries"] >0 then
    -- 发送的查询请求分项数据
    for _, v in pairs(metric_names) do
      if dns_sent[v] ~= nil and dns_sent[v] > 0 then
        local record = newRecord(host)
        record["dns_query"] = v
        record["dns_query_num"] = dns_sent[v]

        record['metric_name'] = "hosts:dns_client_query"
        table.insert(records, record)
      end
    end

    -- 收到的响应
    for _, v in pairs({"num_replies_error", "num_replies_ok"}) do
      local record = newRecord(host)
      record["dns_reply"] = v
      record["dns_reply_num"] = dns_rcvd[v]

      record['metric_name'] = "hosts:dns_client_reply"
      table.insert(records, record)
    end

    -- 合计
    local record = newRecord(host)
    record["dns_query_total"] = dns_sent["num_queries"]
    record["dns_reply_total_num"] = dns_rcvd["num_replies_error"] + dns_rcvd["num_replies_ok"]

    record['metric_name'] = "hosts:dns_client"
    table.insert(records, record)
  end

  return records
end

-- http，分为server和client
local function makeHttpStats(host)
  if host["http"]==nil then
    return {}
  end

  local receiver = host['http']['receiver']
  local sender = host['http']['sender']

  if receiver == nil or sender == nil then
    return {}
  end

  local request_fields = { "get", "other", "head", "put", "post"}
  local response_fields = { "5xx", "4xx", "3xx", "2xx", "1xx" }

  local records = {}

  -- 发出响应，则表示提供http服务
  local resp = receiver['response']
  local req = receiver['query']
  if req ~= nil and resp ~= nil then
    -- 请求方法
    for _, v in ipairs(request_fields) do
      if req['num_'..v] >0 then
        local record = newRecord(host)
        record['method'] = v
        record['method_num'] = req['num_' .. v]
        record['metric_name'] = 'hosts:http_server_request'
        table.insert(records, record)
      end
    end

    -- 响应状态
    for _, v in ipairs(response_fields) do
      if resp['num_'..v]>0 then
        local record = newRecord(host)
        record['status'] = v
        record['status_num'] = resp['num_' .. v]
        record['metric_name'] = 'hosts:http_server_response'
        table.insert(records, record)
      end
    end

    -- 合计
    if req['total']>0 or resp['total']>0 then
      local record = newRecord(host)
      record['request_total'] = req['total']
      record['response_total'] = resp['total']
      record['metric_name'] = 'hosts:http_server'
      table.insert(records, record)
    end
  end

  -- 作为http客户端的统计
  local req = sender['query']
  local resp = sender['response']
  if req ~= nil and resp ~= nil then
    -- 请求方法
    for _, v in ipairs(request_fields) do
      if req['num_'..v]>0 then
        local record = newRecord(host)
        record['http_request_method'] = v
        record['http_request_method_num'] = req['num_' .. v]
        record['metric_name'] = 'hosts:http_client_request'
        table.insert(records, record)
      end
    end

    -- 响应状态
    for _, v in ipairs(response_fields) do
      if resp['num_'..v]>0 then
        local record = newRecord(host)
        record['http_response_status'] = v
        record['http_response_status_num'] = resp['num_' .. v]
        record['metric_name'] = 'hosts:http_client_response'
        table.insert(records, record)
      end
    end

    -- 合计
    if req['total']>0 or resp['total']>0 then
      local record = newRecord(host)
      record['http_request_total'] = req['total']
      record['http_response_total'] = resp['total']
      record['metric_name'] = 'hosts:http_client'
      table.insert(records, record)
    end
  end

  return records
end

-- 提取主机信息
local records = {}

local time = ''..os.time()*1000
local ifaces = interface.getIfNames() -- a table containing (ifid -> ifname) mappings.
for key, value in pairs(hosts) do
  host = interface.getHostInfo(key, value['vlan'])
  if (host ~= nil) then
    for _, f in pairs({makeFlowStats, makeRttL4Stats, makeTrafficStats,
                       makePacketsStats, makeTcpFlagStats, makeTcpTransStats,
                       makePacketsDistributeionStats, makeDpiStats,
                       makeDnsStats, makeHttpStats}) do
      local results = f(host)
      for _, item in pairs(results) do
        item['time'] = time
        table.insert(records, item)
      end
    end
  end
end

print(json.encode(records))
