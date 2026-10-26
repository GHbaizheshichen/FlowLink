// HarmonyProxy's small C ABI around Xray. No subscription is compiled into this library.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"sync"
	"unsafe"

	_ "golang.org/x/crypto/x509roots/fallback"

	"github.com/xtls/xray-core/core"
)

var mutex sync.Mutex
var instance *core.Instance

//export HPVersion
func HPVersion() *C.char { return C.CString(core.Version()) }

//export HPStart
func HPStart(config *C.char) *C.char {
	mutex.Lock()
	defer mutex.Unlock()
	if instance != nil {
		return C.CString("already_running")
	}
	parsed, err := loadJSON(C.GoString(config))
	if err != nil {
		return C.CString("invalid_config")
	}
	candidate, err := core.New(parsed)
	if err != nil {
		return C.CString("core_init_failed")
	}
	if err = candidate.Start(); err != nil {
		candidate.Close()
		return C.CString("core_start_failed")
	}
	instance = candidate
	return C.CString("")
}

//export HPStop
func HPStop() {
	mutex.Lock()
	defer mutex.Unlock()
	if instance != nil {
		instance.Close()
		instance = nil
	}
}

//export HPProbe
func HPProbe() *C.char {
	mutex.Lock()
	active := instance
	mutex.Unlock()
	if active == nil {
		return C.CString("")
	}
	client := newProbeClient(active)
	defer client.CloseIdleConnections()
	exits, err := probeExits(func(endpoint string, family int) (string, error) {
		return probeIP(client, endpoint, family)
	})
	if err != nil {
		return C.CString("error:probe_both_failed")
	}
	data, _ := json.Marshal(exits)
	return C.CString(string(data))
}

//export HPBeginLatencyBatch
func HPBeginLatencyBatch(id *C.char) *C.char { return C.CString(beginLatencyBatch(C.GoString(id))) }

//export HPMeasureLatency
func HPMeasureLatency(config, id *C.char) *C.char {
	result := measureNodeLatency(C.GoString(config), C.GoString(id))
	data, _ := json.Marshal(result)
	return C.CString(string(data))
}

//export HPCancelLatencyBatch
func HPCancelLatencyBatch(id *C.char) { cancelLatencyBatch(C.GoString(id), false) }

//export HPEndLatencyBatch
func HPEndLatencyBatch(id *C.char) { cancelLatencyBatch(C.GoString(id), true) }

//export HPFree
func HPFree(value *C.char) { C.free(unsafe.Pointer(value)) }

func main() {}
