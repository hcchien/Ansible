package otp_test

import (
	"errors"
	"testing"
	"time"

	"github.com/trisaura/ansible_issuer/internal/otp"
)

func TestStore_IssueAndVerify(t *testing.T) {
	s := otp.NewStore(5 * time.Minute)
	code, err := s.Issue("did:plc:abcdefghijkl", "alice@example.com")
	if err != nil {
		t.Fatal(err)
	}
	if len(code) != 6 {
		t.Fatalf("expected 6-digit code, got %q", code)
	}
	if err := s.VerifyAndConsume("did:plc:abcdefghijkl", "alice@example.com", code); err != nil {
		t.Fatal(err)
	}
}

func TestStore_SingleUse(t *testing.T) {
	s := otp.NewStore(5 * time.Minute)
	code, _ := s.Issue("did:plc:abcdefghijkl", "alice@example.com")
	_ = s.VerifyAndConsume("did:plc:abcdefghijkl", "alice@example.com", code)
	err := s.VerifyAndConsume("did:plc:abcdefghijkl", "alice@example.com", code)
	if !errors.Is(err, otp.ErrInvalidOTP) {
		t.Fatalf("expected ErrInvalidOTP on second use, got %v", err)
	}
}

func TestStore_WrongCode(t *testing.T) {
	s := otp.NewStore(5 * time.Minute)
	_, _ = s.Issue("did:plc:abcdefghijkl", "alice@example.com")
	err := s.VerifyAndConsume("did:plc:abcdefghijkl", "alice@example.com", "000000")
	if !errors.Is(err, otp.ErrInvalidOTP) {
		t.Fatalf("expected ErrInvalidOTP, got %v", err)
	}
}

func TestStore_Expired(t *testing.T) {
	s := otp.NewStore(1 * time.Millisecond)
	code, _ := s.Issue("did:plc:abcdefghijkl", "alice@example.com")
	time.Sleep(5 * time.Millisecond)
	err := s.VerifyAndConsume("did:plc:abcdefghijkl", "alice@example.com", code)
	if !errors.Is(err, otp.ErrExpiredOTP) {
		t.Fatalf("expected ErrExpiredOTP, got %v", err)
	}
}

func TestStore_WrongEmail(t *testing.T) {
	s := otp.NewStore(5 * time.Minute)
	code, _ := s.Issue("did:plc:abcdefghijkl", "alice@example.com")
	err := s.VerifyAndConsume("did:plc:abcdefghijkl", "bob@example.com", code)
	if !errors.Is(err, otp.ErrInvalidOTP) {
		t.Fatalf("expected ErrInvalidOTP for wrong email, got %v", err)
	}
}

func TestStore_AttemptCapDestroysEntry(t *testing.T) {
	s := otp.NewStore(5 * time.Minute)
	code, _ := s.Issue("did:plc:abcdefghijkl", "alice@example.com")

	// Four wrong guesses stay guessable; the fifth exhausts the cap.
	for i := 0; i < 4; i++ {
		if err := s.VerifyAndConsume("did:plc:abcdefghijkl", "alice@example.com", "000000"); !errors.Is(err, otp.ErrInvalidOTP) {
			t.Fatalf("guess %d: expected ErrInvalidOTP, got %v", i, err)
		}
	}
	if err := s.VerifyAndConsume("did:plc:abcdefghijkl", "alice@example.com", "000000"); !errors.Is(err, otp.ErrTooManyAttempts) {
		t.Fatalf("expected ErrTooManyAttempts on the capped guess, got %v", err)
	}

	// The entry is now destroyed: even the correct code no longer verifies.
	if err := s.VerifyAndConsume("did:plc:abcdefghijkl", "alice@example.com", code); !errors.Is(err, otp.ErrInvalidOTP) {
		t.Fatalf("expected ErrInvalidOTP after cap destroyed the entry, got %v", err)
	}
}

func TestStore_IssueSweepsExpiredEntries(t *testing.T) {
	// A very short TTL: every issued OTP expires almost immediately.
	s := otp.NewStore(1 * time.Millisecond)

	// Simulate an attacker minting many distinct DIDs, none of which ever
	// verify. Without a sweep these would accumulate forever.
	for i := 0; i < 100; i++ {
		if _, err := s.Issue("did:plc:attacker"+string(rune('a'+i%26))+string(rune('0'+i/26)), "spam@example.com"); err != nil {
			t.Fatalf("issue %d: %v", i, err)
		}
	}

	// Let all the attacker entries expire, then a fresh Issue must sweep them.
	time.Sleep(5 * time.Millisecond)
	if _, err := s.Issue("did:plc:realuser0001", "alice@example.com"); err != nil {
		t.Fatalf("final issue: %v", err)
	}

	// Only the last (unexpired) entry should remain — the expired ones were
	// swept, so the map cannot grow without bound.
	if got := s.Len(); got != 1 {
		t.Fatalf("expected sweep to leave 1 entry, got %d", got)
	}
}
