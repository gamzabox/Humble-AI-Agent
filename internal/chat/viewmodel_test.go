package chat

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"
)

type fakeClient struct {
	mu           sync.Mutex
	lastAPIKey   string
	lastModel    string
	lastMessages []Message
	response     Message
	err          error
}

func (f *fakeClient) SendChat(ctx context.Context, apiKey, model string, messages []Message) (Message, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.lastAPIKey = apiKey
	f.lastModel = model
	f.lastMessages = append([]Message(nil), messages...)
	if f.err != nil {
		return Message{}, f.err
	}
	return f.response, nil
}

type blockingClient struct {
	called chan struct{}
}

func newBlockingClient() *blockingClient {
	return &blockingClient{called: make(chan struct{})}
}

func (b *blockingClient) SendChat(ctx context.Context, apiKey, model string, messages []Message) (Message, error) {
	close(b.called)
	select {
	case <-ctx.Done():
		return Message{}, ctx.Err()
	case <-time.After(time.Second):
		return Message{Role: RoleAssistant, Content: "late"}, nil
	}
}

type fakeStore struct {
	sessions   []Session
	saveCalls  int
	savedState []Session
	saveErr    error
}

func newFakeStore(sessions ...Session) *fakeStore {
	return &fakeStore{sessions: sessions}
}

func (f *fakeStore) LoadSessions() ([]Session, error) {
	return append([]Session(nil), f.sessions...), nil
}

func (f *fakeStore) SaveSessions(sessions []Session) error {
	if f.saveErr != nil {
		return f.saveErr
	}
	f.saveCalls++
	f.savedState = append([]Session(nil), sessions...)
	f.sessions = append([]Session(nil), sessions...)
	return nil
}

func TestSendRequiresAPIKey(t *testing.T) {
	client := &fakeClient{}
	store := newFakeStore()
	vm := NewViewModel(client, []string{"gpt-4"}, store)

	if err := vm.Send(context.Background(), "hello"); err == nil {
		t.Fatalf("expected error when API key is missing")
	}
}

func TestSendAppendsConversationAndCallsClient(t *testing.T) {
	client := &fakeClient{response: Message{Role: RoleAssistant, Content: "hi"}}
	store := newFakeStore()
	vm := NewViewModel(client, []string{"gpt-4", "gpt-3.5"}, store)
	vm.SetAPIKey("sk-test")
	vm.SelectModel("gpt-3.5")

	if err := vm.Send(context.Background(), "hello"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	msgs := vm.Messages()
	if len(msgs) != 2 {
		t.Fatalf("expected 2 messages, got %d", len(msgs))
	}
	if msgs[0].Role != RoleUser || msgs[0].Content != "hello" {
		t.Fatalf("expected first message to be user input, got %+v", msgs[0])
	}
	if msgs[1].Role != RoleAssistant || msgs[1].Content != "hi" {
		t.Fatalf("expected assistant reply, got %+v", msgs[1])
	}
	if client.lastAPIKey != "sk-test" {
		t.Fatalf("expected client to receive API key, got %s", client.lastAPIKey)
	}
	if client.lastModel != "gpt-3.5" {
		t.Fatalf("expected client to receive selected model, got %s", client.lastModel)
	}
	if store.saveCalls == 0 {
		t.Fatalf("expected session persistence after send")
	}
}

func TestSendRecordsErrors(t *testing.T) {
	client := &fakeClient{err: errors.New("boom")}
	store := newFakeStore()
	vm := NewViewModel(client, []string{"gpt-4"}, store)
	vm.SetAPIKey("sk-test")

	if err := vm.Send(context.Background(), "hello"); err == nil {
		t.Fatalf("expected error from client")
	}
	if vm.LastError() == "" {
		t.Fatalf("expected error message to be recorded")
	}
	if len(vm.Messages()) != 1 {
		t.Fatalf("expected only user message when error occurs")
	}
}

func TestNewViewModelDefaultsToFirstModel(t *testing.T) {
	client := &fakeClient{}
	store := newFakeStore()
	vm := NewViewModel(client, []string{"gpt-4", "gpt-3.5"}, store)

	if vm.SelectedModel() != "gpt-4" {
		t.Fatalf("expected default model to be first entry")
	}
}

func TestNewViewModelStartsWithFreshSession(t *testing.T) {
	existing := Session{ID: "s1", Title: "Legacy", Messages: []Message{{Role: RoleUser, Content: "hi"}}}
	client := &fakeClient{}
	store := newFakeStore(existing)
	vm := NewViewModel(client, []string{"gpt-4"}, store)

	sessions := vm.Sessions()
	if len(sessions) != 2 {
		t.Fatalf("expected new session plus stored, got %d", len(sessions))
	}
	if sessions[0].Title != "New Chat" {
		t.Fatalf("expected first session to be new chat, got %q", sessions[0].Title)
	}
	if sessions[1].ID != "s1" {
		t.Fatalf("expected stored session to remain available")
	}
	if vm.CurrentSessionID() == "s1" {
		t.Fatalf("expected current session to be freshly created")
	}
	if len(vm.Messages()) != 0 {
		t.Fatalf("expected fresh session to start empty")
	}
}

func TestSelectSessionSwitchesMessages(t *testing.T) {
	s1 := Session{ID: "s1", Title: "First", Messages: []Message{{Role: RoleUser, Content: "hello"}}}
	s2 := Session{ID: "s2", Title: "Second", Messages: []Message{{Role: RoleUser, Content: "hi again"}}}
	client := &fakeClient{}
	store := newFakeStore(s1, s2)
	vm := NewViewModel(client, []string{"gpt-4"}, store)

	vm.SelectSession("s2")
	msgs := vm.Messages()
	if len(msgs) != 1 || msgs[0].Content != "hi again" {
		t.Fatalf("expected to see second session messages, got %+v", msgs)
	}
}

func TestSendUpdatesTitleAndPersistsSessions(t *testing.T) {
	client := &fakeClient{response: Message{Role: RoleAssistant, Content: "hi"}}
	store := newFakeStore()
	vm := NewViewModel(client, []string{"gpt-4"}, store)
	vm.SetAPIKey("sk")

	if vm.CurrentSessionTitle() != "New Chat" {
		t.Fatalf("expected default session title")
	}

	if err := vm.Send(context.Background(), "First question"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	sessions := vm.Sessions()
	if len(sessions) == 0 {
		t.Fatalf("expected sessions to exist")
	}
	if sessions[0].Title != "First question" {
		t.Fatalf("expected title to update from first user message, got %q", sessions[0].Title)
	}
	if store.saveCalls == 0 {
		t.Fatalf("expected sessions to be saved")
	}
}

func TestStartNewSessionClearsStateAndPersists(t *testing.T) {
	client := &fakeClient{response: Message{Role: RoleAssistant, Content: "ok"}}
	store := newFakeStore()
	vm := NewViewModel(client, []string{"gpt-4"}, store)
	vm.SetAPIKey("sk")

	if err := vm.Send(context.Background(), "hello"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	prevSaves := store.saveCalls
	prevSessionID := vm.CurrentSessionID()

	vm.StartNewSession()

	if vm.CurrentSessionID() == prevSessionID {
		t.Fatalf("expected a new current session after starting new one")
	}
	if len(vm.Messages()) != 0 {
		t.Fatalf("expected new session to have no messages")
	}
	if store.saveCalls <= prevSaves {
		t.Fatalf("expected sessions to be persisted when starting new session")
	}

	sessions := vm.Sessions()
	if len(sessions) < 2 {
		t.Fatalf("expected previous session to remain alongside new one")
	}
}

func TestCancelStopsAssistantResponse(t *testing.T) {
	client := newBlockingClient()
	store := newFakeStore()
	vm := NewViewModel(client, []string{"gpt-4"}, store)
	vm.SetAPIKey("sk")

	errCh := make(chan error, 1)
	go func() {
		errCh <- vm.Send(context.Background(), "hello")
	}()

	<-client.called
	vm.Cancel()

	err := <-errCh
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("expected context canceled error, got %v", err)
	}
	msgs := vm.Messages()
	if len(msgs) != 1 || msgs[0].Role != RoleUser {
		t.Fatalf("expected only user message after cancellation, got %+v", msgs)
	}
}
