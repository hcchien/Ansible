package api

import "testing"

func TestTWPersonBindingInputMatchesNoirCircuitVector(t *testing.T) {
	const expected = "0x001037d8c7c8f25cdb65aa76b4b82da09b4ad4a12453cb0b39d553fc75d44fa7"
	if got := twPersonBindingInput("A123456789"); got != expected {
		t.Fatalf("binding input = %q, want %q", got, expected)
	}
}
