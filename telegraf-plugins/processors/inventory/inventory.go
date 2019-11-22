package inventory

import (
	"github.com/influxdata/telegraf"
	"github.com/influxdata/telegraf/plugins/processors"
	"github.com/prometheus/common/log"
)

type (
	Inventory struct {
		NSot      string `toml:"nsot"`
		Site      string `toml:"site"`
		Tag       string `toml:"tag"`
		CacheSize int    `toml:"cache"`

		c *cache
	}
)

var sampleConfig = `
## 资产管理服务的入口
nsot = "http://localhost:8990/api"
site = "app"

## 需要加入元数据的标签，默认是ip
tag = "ip"

## 缓存大小
cache = 8192
`

func (i *Inventory) SampleConfig() string {
	return sampleConfig
}

func (i *Inventory) Description() string {
	return "为IP地址添加资产信息."
}

func (i *Inventory) Apply(in ...telegraf.Metric) []telegraf.Metric {
	if i.c == nil {
		if c, err := newCache(i.NSot, i.Site, i.CacheSize); err == nil {
			i.c = c
		} else if _, ok := err.(*siteNotExistError); ok {
			log.Fatal(err)
		} else {
			log.Error(err)
			return in
		}
	}

	out := []telegraf.Metric{}

	for _, metric := range in {
		metric.RemoveTag("url") // 清理掉没有意义的url tag
		switch metric.Name() {
		case "discovery":
			// 处理discovery
		default:
			for _, m := range i.processMetric(metric) {
				out = append(out, m)
			}
		}
	}

	return out
}

func (i *Inventory) processMetric(metric telegraf.Metric) []telegraf.Metric {
	out := []telegraf.Metric{}

	if ip, ok := metric.GetTag(i.Tag); ok {
		// 广播和多播地址不作为资产
		for _, name := range []string{"is_broadcast", "is_multicast"} {
			tag, ok := metric.GetTag(name)
			if ok && tag == "true" {
				out = append(out, metric)
				return out
			}
		}

		a, err := i.c.lookupAsset(ip)
		if _, ok := err.(*assetNotExistError); ok {
			attr := map[string]interface{}{}
			for _, k := range []string{"name", "ip_ver"} {
				if v, ok := metric.GetTag(k); ok {
					attr[k] = v
				}
			}

			a, err = i.c.createAsset(ip, attr)
			if err != nil {
				log.Error(err)
			}
		} else if err != nil {
			log.Error(err)
		}

		if a == nil {
			out = append(out, metric)
			return out
		}

		for _, group := range a.group {
			m := metric.Copy()
			m.AddTag("group", group)
			out = append(out, m)
		}

		metric.Drop()
	} else {
		out = append(out, metric)
	}

	return out
}

func (i *Inventory) processDiscovery(in telegraf.Metric) {

}

func init() {
	processors.Add("inventory", func() telegraf.Processor {
		return &Inventory{
			Tag:       "ip",
			Site:      "app",
			CacheSize: 8192,
		}
	})
}
