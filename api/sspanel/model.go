package sspanel

import (
	"encoding/json"
	"strings"
)

// NodeInfoResponse is the response of node
type NodeInfoResponse struct {
	Group           int             `json:"node_group"`
	Class           int             `json:"node_class"`
	SpeedLimit      float64         `json:"node_speedlimit"`
	TrafficRate     float64         `json:"traffic_rate"`
	Sort            int             `json:"sort"`
	RawServerString string          `json:"server"`
	Type            string          `json:"type"`
	CustomConfig    json.RawMessage `json:"custom_config"`
	Version         string          `json:"version"`
}

type CustomConfig struct {
	OffsetPortNode string          `json:"offset_port_node"`
	Host           string          `json:"host"`
	Method         string          `json:"method"`
	ServerKey      string          `json:"server_key"`
	TLS            string          `json:"tls"`
	EnableVless    string          `json:"enable_vless"`
	Network        string          `json:"network"`
	Security       string          `json:"security"`
	Path           string          `json:"path"`
	Mode           string          `json:"mode"` // xhttp / splithttp 模式: auto, packet-up, stream-up, stream-one
	VerifyCert     bool            `json:"verify_cert"`
	Obfs           string          `json:"obfs"`
	Header         json.RawMessage `json:"header"`
	AllowInsecure  string          `json:"allow_insecure"`
	Servicename    string          `json:"servicename"`
	EnableXtls     string          `json:"enable_xtls"`
	Flow           string          `json:"flow"`
	EnableREALITY  bool            `json:"enable_reality"`
	RealityOpts    *REALITYConfig  `json:"reality-opts"`
	// REALITY 平铺兼容字段：reality-opts 中缺失或为零值的字段回退到这里取。
	// 平铺也没有时，再由 controller 回退到本地 config.yml 的 REALITYConfigs 默认值。
	Show                  bool          `json:"show"`                  // 平铺 show
	ShortId               string        `json:"shortId"`               // 平铺 shortId → ShortIds
	Sni                   string        `json:"sni"`                   // 平铺 sni → ServerNames / Dest
	Dest                  string        `json:"dest"`                  // 平铺 dest
	ServerNames           []string      `json:"serverNames"`           // 平铺 serverNames
	ShortIds              []string      `json:"shortIds"`              // 平铺 shortIds
	PrivateKey            string        `json:"privateKey"`            // 平铺 privateKey
	ProxyProtocolVer      uint64        `json:"proxyProtocolVer"`      // 平铺 proxyProtocolVer
	MinClientVer          string        `json:"minClientVer"`          // 平铺 minClientVer
	MaxClientVer          string        `json:"maxClientVer"`          // 平铺 maxClientVer
	MaxTimeDiff           uint64        `json:"maxTimeDiff"`           // 平铺 maxTimeDiff
	Mldsa65Seed           string        `json:"mldsa65Seed"`           // 平铺 mldsa65Seed
	LimitFallbackUpload   LimitFallback `json:"limitFallbackUpload"`   // 平铺 limitFallbackUpload
	LimitFallbackDownload LimitFallback `json:"limitFallbackDownload"` // 平铺 limitFallbackDownload
}

// UnmarshalJSON 在标准解析前做一次兼容处理，用于吃下各面板不一致的写法：
//  1. 把 "reality-opts.private_key" 这类点号平铺键归并成嵌套的 reality-opts 对象，
//     嵌套对象里已有的字段优先，点号键只补齐缺失项；
//  2. 把 enable_reality / verify_cert 的 "true" / "1" / "on" 等字符串写法归一成布尔值。
func (c *CustomConfig) UnmarshalJSON(data []byte) error {
	// 用别名类型避免递归调用本方法
	type plain CustomConfig

	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}

	const realityOptsPrefix = "reality-opts."

	// 先取出已经写成嵌套对象的 reality-opts
	opts := map[string]json.RawMessage{}
	if v, ok := raw["reality-opts"]; ok {
		if err := json.Unmarshal(v, &opts); err != nil {
			opts = map[string]json.RawMessage{}
		}
	}

	// 再把 "reality-opts.xxx" 点号键并入，已存在的字段不覆盖
	merged := false
	for k, v := range raw {
		field, ok := strings.CutPrefix(k, realityOptsPrefix)
		if !ok {
			continue
		}
		merged = true
		delete(raw, k)
		if _, exists := opts[field]; !exists {
			opts[field] = v
		}
	}

	// 部分面板会直接沿用 reality-opts 内的键名平铺下发（如 private_key / server_names）
	for _, field := range realityFlatSnakeKeys {
		v, ok := raw[field]
		if !ok {
			continue
		}
		delete(raw, field)
		if _, exists := opts[field]; exists {
			continue
		}
		merged = true
		opts[field] = v
	}

	if merged {
		b, err := json.Marshal(opts)
		if err != nil {
			return err
		}
		raw["reality-opts"] = b
	}

	// 布尔字段兼容字符串写法
	for _, key := range []string{"enable_reality", "verify_cert"} {
		if v, ok := raw[key]; ok {
			raw[key] = normalizeJSONBool(v)
		}
	}

	b, err := json.Marshal(raw)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, (*plain)(c))
}

// realityFlatSnakeKeys 是 reality-opts 内部键名被平铺到 custom_config 顶层时的写法。
var realityFlatSnakeKeys = []string{
	"show",
	"dest",
	"proxy_protocol_ver",
	"server_names",
	"private_key",
	"min_client_ver",
	"max_client_ver",
	"max_time_diff",
	"short_ids",
	"mldsa65Seed",
	"limit_fallback_upload",
	"limit_fallback_download",
}

// normalizeJSONBool 把 "true" / "1" / "on" 这类字符串归一成 JSON 布尔字面量；
// 已经是布尔值或无法识别的写法按 false 处理，避免整个 custom_config 解析失败。
func normalizeJSONBool(raw json.RawMessage) json.RawMessage {
	switch strings.ToLower(strings.Trim(strings.TrimSpace(string(raw)), `"`)) {
	case "true", "1", "on", "yes":
		return json.RawMessage("true")
	default:
		return json.RawMessage("false")
	}
}

// UserResponse is the response of user
type UserResponse struct {
	ID          int     `json:"id"`
	Passwd      string  `json:"passwd"`
	Port        uint32  `json:"port"`
	Method      string  `json:"method"`
	SpeedLimit  float64 `json:"node_speedlimit"`
	DeviceLimit int     `json:"node_iplimit"`
	UUID        string  `json:"uuid"`
	AliveIP     int     `json:"alive_ip"`
}

// Response is the common response
type Response struct {
	Ret  uint            `json:"ret"`
	Data json.RawMessage `json:"data"`
}

// PostData is the data structure of post data
type PostData struct {
	Data interface{} `json:"data"`
}

// SystemLoad is the data structure of system load
type SystemLoad struct {
	Uptime string `json:"uptime"`
	Load   string `json:"load"`
}

// OnlineUser is the data structure of online user
type OnlineUser struct {
	UID int    `json:"user_id"`
	IP  string `json:"ip"`
}

// UserTraffic is the data structure of traffic
type UserTraffic struct {
	UID      int   `json:"user_id"`
	Upload   int64 `json:"u"`
	Download int64 `json:"d"`
}

type RuleItem struct {
	ID      int    `json:"id"`
	Content string `json:"regex"`
}

type IllegalItem struct {
	ID  int `json:"list_id"`
	UID int `json:"user_id"`
}

type REALITYConfig struct {
	Show                  bool          `json:"show,omitempty"`
	Dest                  string        `json:"dest,omitempty"`
	ProxyProtocolVer      uint64        `json:"proxy_protocol_ver,omitempty"`
	ServerNames           []string      `json:"server_names,omitempty"`
	PrivateKey            string        `json:"private_key,omitempty"`
	MinClientVer          string        `json:"min_client_ver,omitempty"`
	MaxClientVer          string        `json:"max_client_ver,omitempty"`
	MaxTimeDiff           uint64        `json:"max_time_diff,omitempty"`
	ShortIds              []string      `json:"short_ids,omitempty"`
	Mldsa65Seed           string        `json:"mldsa65Seed,omitempty"`
	LimitFallbackUpload   LimitFallback `json:"limit_fallback_upload,omitempty"`
	LimitFallbackDownload LimitFallback `json:"limit_fallback_download,omitempty"`
}

// LimitFallback limits the traffic that fails REALITY authentication and is
// forwarded to dest. All zeros means no limit.
type LimitFallback struct {
	AfterBytes       uint64 `json:"after_bytes,omitempty"`
	BytesPerSec      uint64 `json:"bytes_per_sec,omitempty"`
	BurstBytesPerSec uint64 `json:"burst_bytes_per_sec,omitempty"`
}
