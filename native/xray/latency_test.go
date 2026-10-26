package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestLatencyValidatesResponseAndClassifiesErrors(t *testing.T) {
	for _, tc := range []struct {
		name, body string
		status     int
		want       string
	}{
		{"success IPv4", "192.0.2.1", 200, "success"},
		{"success IPv6", "2001:db8::1", 200, "success"},
		{"HTTP failure", "192.0.2.1", 503, "failed"},
		{"unexpected content", "login required", 200, "failed"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(tc.status)
				w.Write([]byte(tc.body))
			}))
			defer server.Close()
			result := measureLatencyRequest(context.Background(), server.Client(), server.URL)
			if result.Status != tc.want {
				t.Fatalf("got %+v; want %s", result, tc.want)
			}
			if (result.LatencyMs > 0) != (result.Status == "success") {
				t.Fatalf("false latency: %+v", result)
			}
		})
	}
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { <-r.Context().Done() }))
	defer server.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Millisecond)
	defer cancel()
	if result := measureLatencyRequest(ctx, server.Client(), server.URL); result.Status != "timeout" {
		t.Fatalf("timeout misclassified: %+v", result)
	}
	ctx, cancel = context.WithCancel(context.Background())
	cancel()
	if result := measureLatencyRequest(ctx, server.Client(), server.URL); result.Status != "cancelled" {
		t.Fatalf("cancel misclassified: %+v", result)
	}
}

func TestLatencyBatchCancellationRejectsLateWork(t *testing.T) {
	defer cancelLatencyBatch("test-batch", true)
	if result := beginLatencyBatch("test-batch"); result != "" {
		t.Fatal(result)
	}
	if result := beginLatencyBatch("another-batch"); result != "batch_busy" {
		t.Fatal("overlapping batch accepted")
	}
	cancelLatencyBatch("wrong-batch", false)
	if activeLatencyBatch.ctx.Err() != nil {
		t.Fatal("wrong batch cancelled current work")
	}
	cancelLatencyBatch("test-batch", false)
	if result := measureNodeLatency("{}", "test-batch"); result.Status != "cancelled" {
		t.Fatalf("late work not cancelled: %+v", result)
	}
	if result := beginLatencyBatch("another-batch"); result != "batch_busy" {
		t.Fatal("cancelled batch released before drain")
	}
}

func TestLatencyBatchRejectsInboundListenersAndMalformedConfig(t *testing.T) {
	if err := beginLatencyBatch("validation"); err != "" {
		t.Fatal(err)
	}
	defer cancelLatencyBatch("validation", true)
	for _, config := range []string{"{", `{"inbounds":[{"port":10808,"protocol":"socks"}],"outbounds":[{"protocol":"freedom"}]}`} {
		if result := measureNodeLatency(config, "validation"); result.Status != "failed" {
			t.Fatalf("unsafe config accepted: %+v", result)
		}
	}
}
