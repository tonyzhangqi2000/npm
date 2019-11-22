# 说明

利用telegraf作为ntopng->db(elasticsearch,influxdb)的数据pipeline，需要开发实现以下功能的插件：

1. 周期提取主机信息，为新出现主机创建资产信息。
2. 在统计指标中加入资产相关维度。

