package atomicfile

import (
	"os"
	"path/filepath"
	"testing"
)

func TestWriteCreatesFileAndParentDir(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "nested", "store.json")

	if err := Write(path, []byte(`{"a":1}`), 0o600); err != nil {
		t.Fatalf("Write: %v", err)
	}

	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	if string(got) != `{"a":1}` {
		t.Fatalf("content = %q, want %q", got, `{"a":1}`)
	}

	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("Stat: %v", err)
	}
	if perm := info.Mode().Perm(); perm != 0o600 {
		t.Fatalf("perm = %o, want 600", perm)
	}
}

func TestWriteOverwritesAndLeavesNoTemp(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "store.json")

	if err := Write(path, []byte("first"), 0o600); err != nil {
		t.Fatalf("first Write: %v", err)
	}
	if err := Write(path, []byte("second"), 0o600); err != nil {
		t.Fatalf("second Write: %v", err)
	}

	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	if string(got) != "second" {
		t.Fatalf("content = %q, want %q", got, "second")
	}

	if _, err := os.Stat(path + ".tmp"); !os.IsNotExist(err) {
		t.Fatalf("temp file should not linger, stat err = %v", err)
	}
}
