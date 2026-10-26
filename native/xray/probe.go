package main

import (
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"net/netip"
	"strings"
	"time"

	xnet "github.com/xtls/xray-core/common/net"
	"github.com/xtls/xray-core/core"
)

func newProbeClient(active *core.Instance) *http.Client {
	return &http.Client{Timeout: 20 * time.Second, Transport: &http.Transport{
		DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
			destination, err := xnet.ParseDestination("tcp:" + address)
			if err != nil {
				return nil, err
			}
			return core.Dial(ctx, active, destination)
		},
	}}
}

type exitAddresses struct {
	IPv4 string `json:"ipv4"`
	IPv6 string `json:"ipv6"`
}

// Each family uses a family-specific endpoint: a dual-stack endpoint can silently
// fall back to IPv4 and therefore cannot establish IPv6 capability.
func probeExits(probe func(string, int) (string, error)) (exitAddresses, error) {
	type result struct {
		family int
		ip     string
	}
	results := make(chan result, 2)
	for family, endpoint := range map[int]string{4: "https://api4.ipify.org", 6: "https://api6.ipify.org"} {
		go func(f int, target string) {
			ip, err := probe(target, f)
			if err != nil {
				ip = ""
			}
			results <- result{f, ip}
		}(family, endpoint)
	}
	var exits exitAddresses
	for range 2 {
		r := <-results
		if r.family == 4 {
			exits.IPv4 = r.ip
		} else {
			exits.IPv6 = r.ip
		}
	}
	if exits.IPv4 == "" && exits.IPv6 == "" {
		return exits, errors.New("probe_both_failed")
	}
	return exits, nil
}

func probeIP(client *http.Client, endpoint string, family int) (string, error) {
	response, err := client.Get(endpoint)
	if err != nil {
		return "", errors.New("probe_network")
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return "", errors.New("probe_http")
	}
	data, err := io.ReadAll(io.LimitReader(response.Body, 65))
	if err != nil || len(data) > 64 {
		return "", errors.New("probe_response")
	}
	ip, err := netip.ParseAddr(strings.TrimSpace(string(data)))
	if err != nil || ip.Zone() != "" || (family == 4 && !ip.Is4()) ||
		(family == 6 && (!ip.Is6() || ip.Is4In6())) {
		return "", errors.New("probe_family")
	}
	return ip.String(), nil
}
