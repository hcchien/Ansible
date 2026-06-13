// Package metrics is a dependency-free Prometheus text-format metrics registry
// for the issuer (service architecture plan, Phase 0 — observability baseline,
// closes G17).
//
// It exposes labeled counters and a /metrics handler. client_golang would be
// the heavier idiomatic choice; a hand-rolled counter set keeps the issuer free
// of new module dependencies while still emitting standard Prometheus
// exposition that a scraper consumes identically.
//
// Exposed series:
//
//	issuer_requests_total{endpoint}          — HTTP requests by endpoint
//	issuer_credentials_issued_total{type}    — credentials issued by type
//	issuer_errors_total{endpoint}            — handler error responses by endpoint
package metrics

import (
	"fmt"
	"net/http"
	"sort"
	"strings"
	"sync"
)

type counterVec struct {
	name   string
	help   string
	label  string
	mu     sync.Mutex
	values map[string]int64
}

func newCounterVec(name, help, label string) *counterVec {
	return &counterVec{name: name, help: help, label: label, values: map[string]int64{}}
}

func (c *counterVec) inc(labelValue string) {
	c.mu.Lock()
	c.values[labelValue]++
	c.mu.Unlock()
}

func (c *counterVec) render(b *strings.Builder) {
	c.mu.Lock()
	defer c.mu.Unlock()

	fmt.Fprintf(b, "# HELP %s %s\n# TYPE %s counter\n", c.name, c.help, c.name)
	if len(c.values) == 0 {
		// Emit the series at zero so it is discoverable before the first event.
		fmt.Fprintf(b, "%s 0\n", c.name)
		return
	}
	keys := make([]string, 0, len(c.values))
	for k := range c.values {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		fmt.Fprintf(b, "%s{%s=%q} %d\n", c.name, c.label, k, c.values[k])
	}
}

// Registry holds the issuer's metric series.
type Registry struct {
	requests    *counterVec
	credentials *counterVec
	errors      *counterVec
}

// NewRegistry builds the issuer metric registry.
func NewRegistry() *Registry {
	return &Registry{
		requests:    newCounterVec("issuer_requests_total", "HTTP requests by endpoint.", "endpoint"),
		credentials: newCounterVec("issuer_credentials_issued_total", "Credentials issued by type.", "type"),
		errors:      newCounterVec("issuer_errors_total", "Handler error responses by endpoint.", "endpoint"),
	}
}

// IncRequest records a request to the named endpoint.
func (r *Registry) IncRequest(endpoint string) {
	if r == nil {
		return
	}
	r.requests.inc(endpoint)
}

// IncCredentialIssued records a credential issued of the given type.
func (r *Registry) IncCredentialIssued(credType string) {
	if r == nil {
		return
	}
	r.credentials.inc(credType)
}

// IncError records an error response from the named endpoint.
func (r *Registry) IncError(endpoint string) {
	if r == nil {
		return
	}
	r.errors.inc(endpoint)
}

// Render returns the Prometheus text exposition of all series.
func (r *Registry) Render() string {
	var b strings.Builder
	r.requests.render(&b)
	r.credentials.render(&b)
	r.errors.render(&b)
	return b.String()
}

// Handler serves the registry at GET /metrics in Prometheus text format.
func (r *Registry) Handler() http.HandlerFunc {
	return func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(r.Render()))
	}
}
