package inventory

import (
	"bytes"
	"fmt"
	"sync"
	"time"

	"encoding/json"
	"io/ioutil"
	"net/http"

	"github.com/satori/go.uuid"
)

const (
	SENSOR_MAIL string = "sensor@example.tld"
)

type (
	asset struct {
		id         int
		ip_addr    string
		ip_ver     string
		attributes map[string]string
		createtime time.Time
		updatetime time.Time
		group      []string
		tag        []string
		prev, next *asset // 构成双向链表，用于删除长时间不用的条目
	}

	cache struct {
		head, tail *asset
		assets     map[string]*asset
		client     *http.Client
		nsot, site string
		siteId     int
		m          sync.Mutex
		size       int
		checkpoint int // 已经处理的变更id
	}

	assetNotExistError struct {
		ip string
	}

	assetCreateError struct {
		text string
	}

	siteNotExistError struct {
		name string
	}
)

func newAsset(id int, ip string, attributes map[string]interface{}) *asset {
	a := &asset{
		id:         id,
		ip_addr:    ip,
		attributes: map[string]string{},
		group:      []string{},
		tag:        []string{},
	}

	for _, k := range []string{"ip_ver", "name", "role", "vendor", "os_type"} {
		if v, ok := attributes[k]; ok {
			a.attributes[k] = v.(string)
		}
	}

	if v, ok := attributes["group"]; ok {
		for _, g := range v.([]interface{}) {
			a.group = append(a.group, g.(string))
		}
	}

	if v, ok := attributes["tag"]; ok {
		for _, t := range v.([]interface{}) {
			a.tag = append(a.tag, t.(string))
		}
	}

	return a
}

func (e *assetNotExistError) Error() string {
	return fmt.Sprintf("asset: %v not exist.", e.ip)
}

func (e *assetCreateError) Error() string {
	return e.text
}

func (e *siteNotExistError) Error() string {
	return fmt.Sprintf("site: %v not exist.", e.name)
}

func newCache(nsot, site string, size int) (*cache, error) {
	c := &cache{
		assets: map[string]*asset{},
		client: &http.Client{},
		nsot:   nsot,
		site:   site,
		size:   size,
	}

	// site id
	if id, err := c.fetchSiteId(); err != nil {
		return nil, err
	} else {
		c.siteId = id
	}

	// 获取最新的change编号
	lnk := fmt.Sprintf("%v/changes/?limit=1&resource_name=Device", c.nsot)
	if chgs, err := c.fetchChanges(lnk); err != nil {
		return nil, err
	} else {
		count := int(chgs["count"].(float64))
		if count > 0 {
			result := chgs["results"].([]interface{})[0]
			c.checkpoint = int(result.(map[string]interface{})["id"].(float64))
		} else {
			c.checkpoint = 0
		}
	}

	go func() {
		ticker := time.NewTicker(time.Second * 60)
		for {
			select {
			case <-ticker.C:
				c.pollChanges()
			}
		}
	}()

	return c, nil
}

func (c *cache) fetchSiteId() (int, error) {
	var body []interface{}

	lnk := fmt.Sprintf("%v/sites/?name=%v", c.nsot, c.site)
	req, err := http.NewRequest("GET", lnk, nil)
	if err != nil {
		return -1, err
	}

	req.Header.Add("X-NSoT-Email", SENSOR_MAIL)
	resp, err := c.client.Do(req)
	if err != nil {
		return -1, err
	}
	defer resp.Body.Close()

	if err = json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return -1, err
	}

	if len(body) > 0 {
		id := int(body[0].(map[string]interface{})["id"].(float64))
		return id, nil
	} else {
		return -1, &siteNotExistError{name: c.site}
	}
}

func (c *cache) createAsset(ip string, attr map[string]interface{}) (*asset, error) {
	attributes := map[string]interface{}{}
	for _, k := range []string{"vendor", "role", "os_type", "ip_ver", "name"} {
		if v, ok := attr[k]; ok {
			attributes[k] = v
		}
	}

	t := time.Now()
	attributes["createtime"] = t
	attributes["updatetime"] = t

	attributes["ip_addr"] = ip

	if v, ok := attr["group"]; ok {
		attributes["group"] = v.([]string)
	} else {
		attributes["group"] = []string{"未分配"}
	}

	if v, ok := attr["tag"]; ok {
		attributes["tag"] = v.([]string)
	}

	data, _ := json.Marshal(map[string]interface{}{
		"hostname":   uuid.NewV3(uuid.NamespaceDNS, ip), // 直接使用ip作为主机名非法，所以生成uuid
		"site_id":    fmt.Sprintf("%v", c.siteId),
		"attributes": attributes,
	})

	lnk := fmt.Sprintf("%v/devices/", c.nsot)
	req, err := http.NewRequest("POST", lnk, bytes.NewBuffer(data))
	if err != nil {
		return nil, err
	}

	req.Header.Add("X-NSoT-Email", SENSOR_MAIL)
	req.Header.Add("Content-Type", "application/json")
	req.Header.Add("Accept", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	// 如果状态码400，返回错误
	if resp.StatusCode == http.StatusBadRequest {
		if b, err := ioutil.ReadAll(resp.Body); err != nil {
			return nil, err
		} else {
			return nil, &assetCreateError{text: string(b)}
		}
	}

	var body map[string]interface{}
	if err = json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return nil, err
	}

	id := int(body["id"].(float64))
	a := newAsset(id, ip, body["attributes"].(map[string]interface{}))

	c.m.Lock()
	c.addAsset(a)
	c.m.Unlock()

	return a, nil
}

func (c *cache) lookupAsset(ip string) (*asset, error) {
	if a, ok := c.assets[ip]; ok {
		// 从缓存中删除，然后添加，以保证最新访问的条目在队尾
		c.m.Lock()
		c.removeAsset(a)
		c.addAsset(a)
		c.m.Unlock()

		return a, nil
	}

	// 如果内存中没有缓存相关记录，则从nsot提取
	lnk := fmt.Sprintf("%v/devices/query/?query=ip_addr=%v", c.nsot, ip)
	req, err := http.NewRequest("GET", lnk, nil)
	if err != nil {
		return nil, err
	}

	req.Header.Add("X-NSoT-Email", SENSOR_MAIL)
	resp, err := c.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var body []interface{}
	if err = json.NewDecoder(resp.Body).Decode(&body); err == nil {
		if len(body) > 0 {
			attributes := body[0].(map[string]interface{})["attributes"].(map[string]interface{})
			id := int(body[0].(map[string]interface{})["id"].(float64))
			a := newAsset(id, ip, attributes)

			c.m.Lock()
			c.addAsset(a)
			c.m.Unlock()

			return a, nil
		} else {
			return nil, &assetNotExistError{ip: ip}
		}
	} else {
		return nil, err
	}
}

// 删除
func (c *cache) removeAsset(a *asset) {
	if c.head == a {
		c.head = a.next
	}

	if c.tail == a {
		c.tail = a.prev
	}

	if a.prev != nil {
		a.prev.next = a.next
	}

	if a.next != nil {
		a.next.prev = a.prev
	}

	delete(c.assets, a.ip_addr)
}

// 添加缓存
func (c *cache) addAsset(a *asset) {
	// 如果大于最大大小，则先删除
	if len(c.assets) >= c.size {
		k := c.head.ip_addr
		c.head = c.head.next
		c.head.prev = nil
		delete(c.assets, k)
	}

	if c.head == nil {
		c.head = a
		c.tail = a
	} else {
		c.tail.next = a
		a.prev = c.tail
		c.tail = a
	}

	c.assets[a.ip_addr] = a
}

// 轮寻变更，返回最近变更的IP地址列表
func (c *cache) pollChanges() {
	lnk := fmt.Sprintf("%v/changes/?limit=10&resource_name=Device", c.nsot)
	ips := []string{}
	lastId := 0

Out:
	for {
		if chgs, err := c.fetchChanges(lnk); err == nil {
			count := int(chgs["count"].(float64))
			if count > 0 {
				results := chgs["results"].([]interface{})
				headId := int(results[0].(map[string]interface{})["id"].(float64))

				// NOTE: 如果期间没有变更发生，这里只会在第一页触发一次，
				//       但是如果发生大量变更，会发生下一页比上一页更靠前的情况。
				//       nsot不支持查询小于或大于某个id的变更
				if headId > lastId {
					lastId = headId
				}

				for _, result := range results {
					id := int(result.(map[string]interface{})["id"].(float64))
					if id <= c.checkpoint {
						break Out
					}

					resource := result.(map[string]interface{})["resource"]
					attributes := resource.(map[string]interface{})["attributes"]
					if ip, ok := attributes.(map[string]interface{})["ip_addr"]; ok {
						ips = append(ips, ip.(string))
					}
				}

				if next := chgs["next"]; next == nil {
					break Out
				} else {
					lnk = next.(string)
				}
			} else {
				break Out
			}
		}
	}

	if lastId > c.checkpoint {
		c.checkpoint = lastId
	}

	c.m.Lock()
	for _, ip := range ips {
		if a, ok := c.assets[ip]; ok {
			c.removeAsset(a)
		}
	}
	c.m.Unlock()
}

func (c *cache) fetchChanges(lnk string) (map[string]interface{}, error) {
	req, err := http.NewRequest("GET", lnk, nil)
	if err != nil {
		return nil, err
	}

	req.Header.Add("X-NSoT-Email", SENSOR_MAIL)
	req.Header.Add("Accept", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var body map[string]interface{}
	if err = json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return nil, err
	}

	return body, nil
}
