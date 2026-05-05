package api_test

import (
	"testing"

	"github.com/trisaura/ansible_issuer/internal/api"
)

func TestMemoryAuditCountersSnapshotCountsEventsOnly(t *testing.T) {
	counters := api.NewMemoryAuditCounters()

	counters.Increment("tw_callback_verified")
	counters.Increment("tw_callback_verified")
	counters.Increment("tw_callback_replay")

	snapshot := counters.Snapshot()
	if snapshot["tw_callback_verified"] != 2 {
		t.Fatalf("unexpected verified count: %v", snapshot)
	}
	if snapshot["tw_callback_replay"] != 1 {
		t.Fatalf("unexpected replay count: %v", snapshot)
	}
}
