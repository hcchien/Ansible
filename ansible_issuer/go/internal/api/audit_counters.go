package api

import "sync"

type AuditCounters interface {
	Increment(event string)
}

type MemoryAuditCounters struct {
	mu     sync.Mutex
	counts map[string]int
}

func NewMemoryAuditCounters() *MemoryAuditCounters {
	return &MemoryAuditCounters{counts: make(map[string]int)}
}

func (c *MemoryAuditCounters) Increment(event string) {
	if event == "" {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.counts[event]++
}

func (c *MemoryAuditCounters) Snapshot() map[string]int {
	c.mu.Lock()
	defer c.mu.Unlock()
	out := make(map[string]int, len(c.counts))
	for event, count := range c.counts {
		out[event] = count
	}
	return out
}
