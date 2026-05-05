package commitment_test

import (
	"strings"
	"testing"

	"github.com/trisaura/ansible_issuer/internal/commitment"
)

func TestCompute_Deterministic(t *testing.T) {
	a := commitment.Compute("pepper", "A123456789", "tw_natural_person_certificate")
	b := commitment.Compute("pepper", "A123456789", "tw_natural_person_certificate")
	if a != b {
		t.Fatalf("commitment not deterministic: %q vs %q", a, b)
	}
}

func TestCompute_DoesNotExposeSubject(t *testing.T) {
	subject := "A123456789"
	got := commitment.Compute("pepper", subject, "tw_natural_person_certificate")
	if strings.Contains(got, subject) {
		t.Fatalf("commitment exposes raw subject: %q", got)
	}
}

func TestCompute_DifferentPeppersDiffer(t *testing.T) {
	a := commitment.Compute("pepper-a", "A123456789", "tw_natural_person_certificate")
	b := commitment.Compute("pepper-b", "A123456789", "tw_natural_person_certificate")
	if a == b {
		t.Fatal("different peppers should produce different commitments")
	}
}

func TestCompute_DifferentContextsDiffer(t *testing.T) {
	a := commitment.Compute("pepper", "A123456789", "tw_natural_person_certificate")
	b := commitment.Compute("pepper", "A123456789", "other_context")
	if a == b {
		t.Fatal("different assurance contexts should produce different commitments")
	}
}
