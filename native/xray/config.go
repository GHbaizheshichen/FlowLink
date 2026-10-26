package main

import (
	"github.com/xtls/xray-core/core"
	_ "github.com/xtls/xray-core/main/distro/all"
	"strings"
)

func loadJSON(config string) (*core.Config, error) {
	return core.LoadConfig("json", strings.NewReader(config))
}
