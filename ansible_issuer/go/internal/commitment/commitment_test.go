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

func TestSet_PrimaryCommitmentUsesPrimaryPepper(t *testing.T) {
	set := commitment.NewSet("primary-pepper", []string{"old-pepper"})
	got := set.PrimaryCommitment("A123456789", "tw_natural_person_certificate")
	want := commitment.Compute("primary-pepper", "A123456789", "tw_natural_person_certificate")
	if got != want {
		t.Fatalf("PrimaryCommitment did not use primary pepper: %q vs %q", got, want)
	}
}

func TestSet_ComputeAllYieldsPrimaryThenPrevious(t *testing.T) {
	set := commitment.NewSet("primary-pepper", []string{"old-1", "old-2"})
	all := set.ComputeAll("A123456789", "tw_natural_person_certificate")
	if len(all) != 3 {
		t.Fatalf("expected 3 commitments (primary + 2 previous), got %d", len(all))
	}
	if all[0] != commitment.Compute("primary-pepper", "A123456789", "tw_natural_person_certificate") {
		t.Fatal("element 0 must be the primary commitment")
	}
	if all[1] != commitment.Compute("old-1", "A123456789", "tw_natural_person_certificate") {
		t.Fatal("element 1 must be the first previous commitment")
	}
	if all[2] != commitment.Compute("old-2", "A123456789", "tw_natural_person_certificate") {
		t.Fatal("element 2 must be the second previous commitment")
	}
}

func TestNewSet_DropsEmptyAndDuplicatePreviousPeppers(t *testing.T) {
	// A previous pepper equal to the primary, an empty entry, and a real dup
	// should all be dropped so ComputeAll never emits duplicate commitments.
	set := commitment.NewSet("primary", []string{"", "primary", "old", "old"})
	all := set.ComputeAll("subject", "ctx")
	if len(all) != 2 {
		t.Fatalf("expected primary + 1 unique previous, got %d: %v", len(all), all)
	}
}

// TestSet_RotationRecognisesOldPepperEnrolment models the rotation invariant:
// a person enrolled under the OLD pepper is still matched after rotation,
// because ComputeAll emits their old commitment alongside the new primary one.
func TestSet_RotationRecognisesOldPepperEnrolment(t *testing.T) {
	// Person was first committed under the old pepper only.
	oldCommitment := commitment.Compute("old-pepper", "A123456789", "tw_natural_person_certificate")

	// After rotation, primary=new-pepper, previous=[old-pepper].
	set := commitment.NewSet("new-pepper", []string{"old-pepper"})
	all := set.ComputeAll("A123456789", "tw_natural_person_certificate")

	found := false
	for _, c := range all {
		if c == oldCommitment {
			found = true
		}
	}
	if !found {
		t.Fatal("post-rotation dual-check failed to reproduce the old-pepper commitment")
	}
}
