// Package atomicfile provides crash-safe, durable file writes for the issuer's
// security-critical JSON stores (personhood bindings and provider sessions).
//
// Write performs a write-to-temp, fsync, atomic-rename sequence and fsyncs the
// containing directory so a successful return means the bytes are durably on
// disk. This matters on Cloud Run, where instances receive SIGTERM and may be
// SIGKILLed shortly after: a personhood binding that has been acknowledged to a
// caller must not be lost, or duplicate-prevention would silently regress.
//
// Atomic rename requires POSIX rename semantics. A Cloud Run NFS (Filestore)
// volume or a real persistent disk provides them; a Cloud Storage FUSE mount
// emulates rename as copy+delete and does not, so prefer NFS/disk for these
// stores.
package atomicfile

import (
	"fmt"
	"os"
	"path/filepath"
)

// Write durably writes data to path via a temp file + atomic rename. The parent
// directory is created with mode 0o700 if missing.
func Write(path string, data []byte, perm os.FileMode) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return fmt.Errorf("create store directory: %w", err)
	}

	tmp := path + ".tmp"
	f, err := os.OpenFile(tmp, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, perm)
	if err != nil {
		return fmt.Errorf("open temp store file: %w", err)
	}

	if _, err := f.Write(data); err != nil {
		f.Close()
		os.Remove(tmp)
		return fmt.Errorf("write temp store file: %w", err)
	}
	if err := f.Sync(); err != nil {
		f.Close()
		os.Remove(tmp)
		return fmt.Errorf("sync temp store file: %w", err)
	}
	if err := f.Close(); err != nil {
		os.Remove(tmp)
		return fmt.Errorf("close temp store file: %w", err)
	}

	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		return fmt.Errorf("replace store file: %w", err)
	}

	// Fsync the directory so the rename itself is durable. Best-effort: some
	// filesystems do not support directory fsync.
	if d, err := os.Open(dir); err == nil {
		_ = d.Sync()
		_ = d.Close()
	}
	return nil
}
