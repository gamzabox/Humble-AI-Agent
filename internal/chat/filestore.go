package chat

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sync"
)

// FileSessionStore persists sessions to a JSON file on disk.
type FileSessionStore struct {
	path string
	mu   sync.Mutex
}

// NewFileSessionStore creates a session store writing to the provided path.
func NewFileSessionStore(path string) *FileSessionStore {
	return &FileSessionStore{path: path}
}

// LoadSessions reads the sessions from disk, returning an empty slice when the file does not exist.
func (s *FileSessionStore) LoadSessions() ([]Session, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	data, err := os.ReadFile(s.path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, nil
		}
		return nil, err
	}

	var sessions []Session
	if err := json.Unmarshal(data, &sessions); err != nil {
		return nil, err
	}
	return sessions, nil
}

// SaveSessions writes the provided sessions to disk atomically.
func (s *FileSessionStore) SaveSessions(sessions []Session) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	dir := filepath.Dir(s.path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	tmp := s.path + ".tmp"
	data, err := json.MarshalIndent(sessions, "", "  ")
	if err != nil {
		return err
	}
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, s.path)
}

var _ SessionStore = (*FileSessionStore)(nil)
