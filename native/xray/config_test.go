package main

import "testing"

func TestJSONLoaderAcceptsReader(t *testing.T) {
	config, err := loadJSON(`{"log":{"loglevel":"none"},"outbounds":[{"protocol":"blackhole"}]}`)
	if err != nil || config == nil {
		t.Fatalf("JSON reader failed: %v", err)
	}
}
func TestJSONLoaderRejectsInvalidConfig(t *testing.T) {
	for _, input := range []string{"{", `{"outbounds":[{"protocol":"unknown-protocol"}]}`} {
		if _, err := loadJSON(input); err == nil {
			t.Fatal("invalid configuration was accepted")
		}
	}
}

func TestJSONLoaderAcceptsDualStackDNS(t *testing.T) {
	_, err := loadJSON(`{"dns":{"servers":["https://1.1.1.1/dns-query"],"queryStrategy":"UseIP"},"outbounds":[{"protocol":"dns","settings":{"nonIPQuery":"drop","blockTypes":[65]}}]}`)
	if err != nil {
		t.Fatalf("dual stack DNS config rejected: %v", err)
	}
}
