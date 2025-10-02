package chat

import (
	"context"
	"errors"
	"strings"
	"sync"
)

// Role represents the OpenAI chat role.
type Role string

const (
	// RoleSystem represents system instructions to the model.
	RoleSystem Role = "system"
	// RoleUser represents user supplied content.
	RoleUser Role = "user"
	// RoleAssistant represents assistant replies from the model.
	RoleAssistant Role = "assistant"
)

// Message captures a single chat exchange element.
type Message struct {
	Role    Role
	Content string
}

// ErrMissingAPIKey is returned when a request is attempted without an API key.
var ErrMissingAPIKey = errors.New("openai api key required")

// ErrEmptyMessage is returned when the user submits empty content.
var ErrEmptyMessage = errors.New("message content cannot be empty")

// Client defines the behaviour needed to talk to the OpenAI chat API.
type Client interface {
	SendChat(ctx context.Context, apiKey, model string, messages []Message) (Message, error)
}

// ViewModel owns the chat state shared between UI widgets and the OpenAI client.
type ViewModel struct {
	mu            sync.RWMutex
	client        Client
	store         SessionStore
	apiKey        string
	models        []string
	selectedModel string
	sessions      []Session
	currentID     string
	lastError     string
	isSending     bool
	cancel        context.CancelFunc
}

// NewViewModel constructs a chat view model with the provided client, allowed models, and storage backend.
func NewViewModel(client Client, models []string, store SessionStore) *ViewModel {
	vm := &ViewModel{
		client: client,
		store:  store,
		models: append([]string(nil), models...),
	}
	if len(models) > 0 {
		vm.selectedModel = models[0]
	}
	if store != nil {
		if sessions, err := store.LoadSessions(); err == nil {
			for i := range sessions {
				if sessions[i].ID == "" {
					sessions[i].ID = newSessionID()
				}
				sessions[i].Title = ensureTitle(sessions[i].Title)
			}
			vm.sessions = cloneSessions(sessions)
		}
	}
	if len(vm.sessions) == 0 {
		vm.currentID = newSessionID()
		vm.sessions = []Session{{ID: vm.currentID, Title: defaultSessionTitle}}
	} else {
		vm.currentID = vm.sessions[0].ID
	}
	return vm
}

// AvailableModels lists the selectable model identifiers.
func (vm *ViewModel) AvailableModels() []string {
	vm.mu.RLock()
	defer vm.mu.RUnlock()
	return append([]string(nil), vm.models...)
}

// SelectedModel returns the currently chosen model identifier.
func (vm *ViewModel) SelectedModel() string {
	vm.mu.RLock()
	defer vm.mu.RUnlock()
	return vm.selectedModel
}

// SelectModel updates the chosen model when it exists in the configured list.
func (vm *ViewModel) SelectModel(model string) {
	vm.mu.Lock()
	defer vm.mu.Unlock()
	for _, m := range vm.models {
		if m == model {
			vm.selectedModel = model
			break
		}
	}
}

// APIKey returns the currently stored API key.
func (vm *ViewModel) APIKey() string {
	vm.mu.RLock()
	defer vm.mu.RUnlock()
	return vm.apiKey
}

// SetAPIKey persists the API key trimming surrounding whitespace.
func (vm *ViewModel) SetAPIKey(key string) {
	vm.mu.Lock()
	defer vm.mu.Unlock()
	vm.apiKey = strings.TrimSpace(key)
}

// Sessions returns summaries of the persisted chat sessions.
func (vm *ViewModel) Sessions() []SessionSummary {
	vm.mu.RLock()
	defer vm.mu.RUnlock()
	summaries := make([]SessionSummary, len(vm.sessions))
	for i, session := range vm.sessions {
		summaries[i] = SessionSummary{ID: session.ID, Title: ensureTitle(session.Title)}
	}
	return summaries
}

// CurrentSessionID reports the active session identifier.
func (vm *ViewModel) CurrentSessionID() string {
	vm.mu.RLock()
	defer vm.mu.RUnlock()
	return vm.currentID
}

// CurrentSessionTitle returns the active session title.
func (vm *ViewModel) CurrentSessionTitle() string {
	vm.mu.RLock()
	defer vm.mu.RUnlock()
	if session := vm.sessionByIDLocked(vm.currentID); session != nil {
		return ensureTitle(session.Title)
	}
	return defaultSessionTitle
}

// SelectSession switches the active session when the identifier exists.
func (vm *ViewModel) SelectSession(id string) {
	vm.mu.Lock()
	defer vm.mu.Unlock()
	if session := vm.sessionByIDLocked(id); session != nil {
		vm.currentID = session.ID
	}
}

// Messages returns a copy of the active conversation history.
func (vm *ViewModel) Messages() []Message {
	vm.mu.RLock()
	defer vm.mu.RUnlock()
	if session := vm.sessionByIDLocked(vm.currentID); session != nil {
		out := make([]Message, len(session.Messages))
		copy(out, session.Messages)
		return out
	}
	return nil
}

// LastError exposes the most recent error message.
func (vm *ViewModel) LastError() string {
	vm.mu.RLock()
	defer vm.mu.RUnlock()
	return vm.lastError
}

// ClearError clears any recorded error state.
func (vm *ViewModel) ClearError() {
	vm.mu.Lock()
	defer vm.mu.Unlock()
	vm.lastError = ""
}

// IsSending reports whether a chat request is currently in flight.
func (vm *ViewModel) IsSending() bool {
	vm.mu.RLock()
	defer vm.mu.RUnlock()
	return vm.isSending
}

// Cancel aborts any in-flight send operation.
func (vm *ViewModel) Cancel() {
	vm.mu.Lock()
	cancel := vm.cancel
	vm.cancel = nil
	vm.isSending = false
	vm.mu.Unlock()
	if cancel != nil {
		cancel()
	}
}

// Send validates input, appends the user message, and invokes the client for a response.
func (vm *ViewModel) Send(ctx context.Context, content string) error {
	trimmed := strings.TrimSpace(content)
	if trimmed == "" {
		return ErrEmptyMessage
	}

	vm.mu.Lock()
	if vm.apiKey == "" {
		vm.mu.Unlock()
		return ErrMissingAPIKey
	}
	apiKey := vm.apiKey
	model := vm.selectedModel
	if vm.currentID == "" {
		vm.currentID = newSessionID()
		vm.sessions = append(vm.sessions, Session{ID: vm.currentID, Title: defaultSessionTitle})
	}
	session := vm.ensureCurrentSessionLocked()
	userMsg := Message{Role: RoleUser, Content: trimmed}
	session.Messages = append(session.Messages, userMsg)
	vm.updateSessionTitleLocked(session)
	vm.saveSessionsLocked()
	history := make([]Message, len(session.Messages))
	copy(history, session.Messages)
	vm.lastError = ""
	vm.isSending = true
	if vm.cancel != nil {
		vm.cancel()
	}
	sendCtx, cancel := context.WithCancel(ctx)
	vm.cancel = cancel
	vm.mu.Unlock()

	resp, err := vm.client.SendChat(sendCtx, apiKey, model, history)

	vm.mu.Lock()
	defer vm.mu.Unlock()
	vm.isSending = false
	vm.cancel = nil
	if err != nil {
		if errors.Is(err, context.Canceled) {
			vm.lastError = ""
		} else {
			vm.lastError = err.Error()
		}
		vm.saveSessionsLocked()
		return err
	}
	session = vm.ensureCurrentSessionLocked()
	session.Messages = append(session.Messages, resp)
	vm.updateSessionTitleLocked(session)
	vm.saveSessionsLocked()
	return nil
}

func (vm *ViewModel) sessionByIDLocked(id string) *Session {
	for i := range vm.sessions {
		if vm.sessions[i].ID == id {
			return &vm.sessions[i]
		}
	}
	return nil
}

func (vm *ViewModel) ensureCurrentSessionLocked() *Session {
	if session := vm.sessionByIDLocked(vm.currentID); session != nil {
		return session
	}
	vm.currentID = newSessionID()
	vm.sessions = append(vm.sessions, Session{ID: vm.currentID, Title: defaultSessionTitle})
	return &vm.sessions[len(vm.sessions)-1]
}

func (vm *ViewModel) updateSessionTitleLocked(session *Session) {
	session.Title = ensureTitle(deriveTitle(session.Messages))
}

func (vm *ViewModel) saveSessionsLocked() {
	if vm.store == nil {
		return
	}
	_ = vm.store.SaveSessions(cloneSessions(vm.sessions))
}
