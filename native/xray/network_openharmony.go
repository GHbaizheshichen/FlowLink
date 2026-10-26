//go:build openharmony

package main

/*
#cgo LDFLAGS: -lnet_connection
#include <network/netmanager/net_connection.h>
*/
import "C"

import (
	"errors"
	"sync/atomic"
	"syscall"

	"github.com/xtls/xray-core/transport/internet"
)

var physicalNetwork atomic.Int32

//export HPSetNetwork
func HPSetNetwork(netID C.int) { physicalNetwork.Store(int32(netID)) }

func init() {
	internet.RegisterDialerController(func(network, address string, raw syscall.RawConn) error {
		id := physicalNetwork.Load()
		if id <= 0 {
			return errors.New("underlay_not_selected")
		}
		result := C.int32_t(-1)
		err := raw.Control(func(fd uintptr) {
			handle := C.NetConn_NetHandle{netId: C.int32_t(id)}
			result = C.OH_NetConn_BindSocket(C.int32_t(fd), &handle)
		})
		if err != nil {
			return err
		}
		if result != 0 {
			return errors.New("underlay_socket_bind_failed")
		}
		return nil
	})
}
