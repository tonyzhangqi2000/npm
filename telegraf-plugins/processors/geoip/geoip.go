package geoip

import (
	"fmt"
	"log"
	"net"

	"github.com/influxdata/telegraf"
	"github.com/influxdata/telegraf/plugins/processors"
	"github.com/oschwald/geoip2-golang"
)

type Geoip struct {
	Tag  string `toml:"tag"`
	Mmdb string `toml:"mmdb"`
	db   *geoip2.Reader
}

var sampleConfig = `
## geoip2数据库
mmdb = "./GeoLite2-Country.mmdb"

## 需要进行解析的标签
tag = "ip"
`

func (g *Geoip) SampleConfig() string {
	return sampleConfig
}

func (g *Geoip) Description() string {
	return "为IP地址添加资产信息."
}

func (g *Geoip) Apply(in ...telegraf.Metric) []telegraf.Metric {
	if g.Tag == "" {
		return in
	}

	// 如果还没有打开mmdb数据库
	if g.db == nil {
		db, err := geoip2.Open(g.Mmdb)
		if err != nil {
			log.Fatal(err)
		}

		g.db = db
	}

	// 添加geoip信息
	for _, metric := range in {
		value, _ := metric.GetTag(g.Tag)
		ip := net.ParseIP(value)
		record, err := g.db.City(ip)
		if err == nil {
			if country, ok := record.Country.Names["zh-CN"]; ok {
				metric.AddTag("country", country)
			} else {
				metric.AddTag("country", record.Country.Names["en"])
			}

			if city, ok := record.City.Names["zh-CN"]; ok {
				metric.AddTag("city", city)
			} else {
				metric.AddTag("city", record.City.Names["en"])
			}

			metric.AddTag("isocode", record.Country.IsoCode)
			metric.AddTag("lat", fmt.Sprintf("%v", record.Location.Latitude))
			metric.AddTag("lon", fmt.Sprintf("%v", record.Location.Longitude))
		}
	}

	return in
}

func init() {
	processors.Add("geoip", func() telegraf.Processor {
		return &Geoip{
			Tag:  "",
			Mmdb: "./GeoLite2-Country.mmdb",
		}
	})
}
