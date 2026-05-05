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
