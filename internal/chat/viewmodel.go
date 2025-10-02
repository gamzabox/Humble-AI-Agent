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
	apiKey        string
	models        []string
	selectedModel string
	messages      []Message
	lastError     string
	isSending     bool
}

// NewViewModel constructs a chat view model with the provided client and allowed models.
func NewViewModel(client Client, models []string) *ViewModel {
	vm := &ViewModel{
		client: client,
		models: append([]string(nil), models...),
	}
	if len(models) > 0 {
		vm.selectedModel = models[0]
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

// Messages returns a copy of the conversation history.
func (vm *ViewModel) Messages() []Message {
	vm.mu.RLock()
	defer vm.mu.RUnlock()
	out := make([]Message, len(vm.messages))
	copy(out, vm.messages)
	return out
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
	history := append([]Message(nil), vm.messages...)
	userMsg := Message{Role: RoleUser, Content: trimmed}
	history = append(history, userMsg)
	vm.messages = append(vm.messages, userMsg)
	vm.lastError = ""
	vm.isSending = true
	vm.mu.Unlock()

	resp, err := vm.client.SendChat(ctx, apiKey, model, history)

	vm.mu.Lock()
	defer vm.mu.Unlock()
	vm.isSending = false
	if err != nil {
		vm.lastError = err.Error()
		return err
	}
	vm.messages = append(vm.messages, resp)
	return nil
}
