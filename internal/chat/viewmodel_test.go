package chat

import (
    "context"
    "errors"
    "testing"
)

type fakeClient struct {
    lastAPIKey string
    lastModel  string
    lastMessages []Message
    response   Message
    err        error
}

func (f *fakeClient) SendChat(ctx context.Context, apiKey, model string, messages []Message) (Message, error) {
    f.lastAPIKey = apiKey
    f.lastModel = model
    f.lastMessages = append([]Message(nil), messages...)
    if f.err != nil {
        return Message{}, f.err
    }
    return f.response, nil
}

func TestSendRequiresAPIKey(t *testing.T) {
    client := &fakeClient{}
    vm := NewViewModel(client, []string{"gpt-4"})

    if err := vm.Send(context.Background(), "hello"); err == nil {
        t.Fatalf("expected error when API key is missing")
    }
}

func TestSendAppendsConversationAndCallsClient(t *testing.T) {
    client := &fakeClient{response: Message{Role: RoleAssistant, Content: "hi"}}
    vm := NewViewModel(client, []string{"gpt-4", "gpt-3.5"})
    vm.SetAPIKey("sk-test")
    vm.SelectModel("gpt-3.5")

    if err := vm.Send(context.Background(), "hello" ); err != nil {
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
}

func TestSendRecordsErrors(t *testing.T) {
    client := &fakeClient{err: errors.New("boom")}
    vm := NewViewModel(client, []string{"gpt-4"})
    vm.SetAPIKey("sk-test")

    if err := vm.Send(context.Background(), "hello" ); err == nil {
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
    vm := NewViewModel(client, []string{"gpt-4", "gpt-3.5"})

    if vm.SelectedModel() != "gpt-4" {
        t.Fatalf("expected default model to be first entry")
    }
}
