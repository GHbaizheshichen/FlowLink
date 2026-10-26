package main

import (
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"net/netip"
	"strings"
	"sync"
	"time"

	"github.com/xtls/xray-core/core"
)

const latencyTarget = "https://api64.ipify.org"
const latencyTimeout = 8 * time.Second

type latencyResult struct {
	Status    string `json:"status"`
	LatencyMs int64  `json:"latencyMs"`
}
type latencyBatch struct {
	id     string
	ctx    context.Context
	cancel context.CancelFunc
}

var latencyMutex sync.Mutex
var activeLatencyBatch *latencyBatch
var latencySlots = make(chan struct{}, 3)

func beginLatencyBatch(id string) string {
	latencyMutex.Lock()
	defer latencyMutex.Unlock()
	if id == "" || len(id) > 64 {
		return "invalid_batch"
	}
	if activeLatencyBatch != nil {
		return "batch_busy"
	}
	ctx, cancel := context.WithCancel(context.Background())
	activeLatencyBatch = &latencyBatch{id, ctx, cancel}
	return ""
}
func cancelLatencyBatch(id string, finish bool) {
	latencyMutex.Lock()
	defer latencyMutex.Unlock()
	if activeLatencyBatch != nil && activeLatencyBatch.id == id {
		activeLatencyBatch.cancel()
		// Cancellation retains the batch until all workers finish. Late queued
		// calls must see a cancelled context instead of creating a fresh batch.
		if finish {
			activeLatencyBatch = nil
		}
	}
}
func measureNodeLatency(config, id string) latencyResult {
	latencyMutex.Lock()
	batch := activeLatencyBatch
	latencyMutex.Unlock()
	if batch == nil || batch.id != id {
		return latencyResult{Status: "cancelled"}
	}
	ctx, cancel := context.WithTimeout(batch.ctx, latencyTimeout)
	defer cancel()
	select {
	case latencySlots <- struct{}{}:
		defer func() { <-latencySlots }()
	case <-ctx.Done():
		return latencyError(ctx, ctx.Err())
	}
	if ctx.Err() != nil {
		return latencyError(ctx, ctx.Err())
	}
	parsed, err := loadJSON(config)
	if err != nil || parsed == nil || len(parsed.Inbound) != 0 {
		return latencyResult{Status: "failed"}
	}
	instance, err := core.New(parsed)
	if err != nil {
		return latencyResult{Status: "failed"}
	}
	defer instance.Close()
	if err := instance.Start(); err != nil {
		return latencyResult{Status: "failed"}
	}
	client := newProbeClient(instance)
	defer client.CloseIdleConnections()
	client.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	return measureLatencyRequest(ctx, client, latencyTarget)
}
func latencyError(ctx context.Context, err error) latencyResult {
	if errors.Is(ctx.Err(), context.Canceled) || errors.Is(err, context.Canceled) {
		return latencyResult{Status: "cancelled"}
	}
	var timeout net.Error
	if errors.Is(ctx.Err(), context.DeadlineExceeded) || errors.As(err, &timeout) && timeout.Timeout() {
		return latencyResult{Status: "timeout"}
	}
	return latencyResult{Status: "failed"}
}
func measureLatencyRequest(ctx context.Context, client *http.Client, endpoint string) latencyResult {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return latencyResult{Status: "failed"}
	}
	request.Header.Set("Cache-Control", "no-cache")
	started := time.Now()
	response, err := client.Do(request)
	if err != nil {
		return latencyError(ctx, err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return latencyResult{Status: "failed"}
	}
	body, err := io.ReadAll(io.LimitReader(response.Body, 65))
	if err != nil {
		return latencyError(ctx, err)
	}
	if len(body) > 64 {
		return latencyResult{Status: "failed"}
	}
	if _, err := netip.ParseAddr(strings.TrimSpace(string(body))); err != nil {
		return latencyResult{Status: "failed"}
	}
	if ctx.Err() != nil {
		return latencyError(ctx, ctx.Err())
	}
	elapsed := time.Since(started).Milliseconds()
	if elapsed < 1 {
		elapsed = 1
	}
	return latencyResult{Status: "success", LatencyMs: elapsed}
}
