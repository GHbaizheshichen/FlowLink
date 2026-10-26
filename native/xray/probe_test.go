package main

import (
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/xtls/xray-core/core"
)

func TestProbeIPValidatesFamilyAndResponse(t *testing.T) {
	for _, tc := range []struct {
		name, body     string
		family, status int
		want           string
	}{
		{"ipv4", "192.0.2.1\n", 4, 200, "192.0.2.1"},
		{"ipv6 canonical", "2001:0DB8:0000:0000:0000:0000:0000:0001\n", 6, 200, "2001:db8::1"},
		{"ipv4 is not ipv6", "192.0.2.1", 6, 200, ""},
		{"ipv6 is not ipv4", "2001:db8::1", 4, 200, ""},
		{"mapped ipv4", "::ffff:192.0.2.1", 6, 200, ""},
		{"zone", "fe80::1%eth0", 6, 200, ""},
		{"invalid", "not an IP", 6, 200, ""},
		{"http failure", "2001:db8::1", 6, 503, ""},
		{"oversize", strings.Repeat(" ", 65) + "2001:db8::1", 6, 200, ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(tc.status)
				w.Write([]byte(tc.body))
			}))
			defer server.Close()
			got, err := probeIP(server.Client(), server.URL, tc.family)
			if got != tc.want || ((err == nil) != (tc.want != "")) {
				t.Fatalf("got %q, %v; want %q", got, err, tc.want)
			}
		})
	}
}

// Exercise a real IPv6 TCP connection through Xray, independently of public
// subscription servers or the availability of an external IPv6 probe service.
func TestProbeThroughXrayIPv6(t *testing.T) {
	listener, err := net.Listen("tcp6", "[::1]:0")
	if err != nil {
		t.Fatalf("IPv6 loopback required for integration test: %v", err)
	}
	server := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("2001:db8::1234"))
	}))
	server.Listener.Close()
	server.Listener = listener
	server.Start()
	defer server.Close()
	config, err := loadJSON(`{"log":{"loglevel":"none"},"outbounds":[{"protocol":"freedom"}]}`)
	if err != nil {
		t.Fatal(err)
	}
	instance, err := core.New(config)
	if err != nil {
		t.Fatal(err)
	}
	if err := instance.Start(); err != nil {
		t.Fatal(err)
	}
	defer instance.Close()
	client := newProbeClient(instance)
	defer client.CloseIdleConnections()
	ip, err := probeIP(client, server.URL, 6)
	if err != nil || ip != "2001:db8::1234" {
		t.Fatalf("IPv6 through Xray failed: %q, %v", ip, err)
	}
}

func TestProbeExitsAllowsOneFamilyWithoutClaimingTheOther(t *testing.T) {
	for _, enabled := range []int{0, 4, 6, 46} {
		exits, err := probeExits(func(endpoint string, family int) (string, error) {
			if enabled != 46 && family != enabled {
				return "", errors.New("unreachable")
			}
			if family == 4 {
				if endpoint != "https://api4.ipify.org" {
					t.Error("incorrect IPv4 endpoint")
				}
				return "192.0.2.1", nil
			}
			if endpoint != "https://api6.ipify.org" {
				t.Error("IPv6 probe must not fall back to IPv4")
			}
			return "2001:db8::1", nil
		})
		if (err != nil) != (enabled == 0) {
			t.Fatalf("enabled=%d error=%v", enabled, err)
		}
		if (exits.IPv4 != "") != (enabled == 4 || enabled == 46) {
			t.Fatalf("wrong IPv4 capability: %+v", exits)
		}
		if (exits.IPv6 != "") != (enabled == 6 || enabled == 46) {
			t.Fatalf("wrong IPv6 capability: %+v", exits)
		}
	}
}
