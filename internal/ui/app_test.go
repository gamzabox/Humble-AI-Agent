package ui

import (
	"context"
	"testing"
	"time"

	"fyne.io/fyne/v2/test"
	"fyne.io/fyne/v2/widget"

	"humble-ai-agent/internal/chat"
)

type stubViewModel struct {
	models      []string
	selected    string
	apiKey      string
	messages    []chat.Message
	sendErr     error
	sendInvoked bool
}

func newStubViewModel() *stubViewModel {
	return &stubViewModel{
		models:   []string{"gpt-4", "gpt-3.5"},
		selected: "gpt-4",
		messages: []chat.Message{{Role: chat.RoleAssistant, Content: "**hi**"}},
	}
}

func (s *stubViewModel) AvailableModels() []string { return append([]string(nil), s.models...) }
func (s *stubViewModel) SelectedModel() string     { return s.selected }
func (s *stubViewModel) SelectModel(model string)  { s.selected = model }
func (s *stubViewModel) APIKey() string            { return s.apiKey }
func (s *stubViewModel) SetAPIKey(key string)      { s.apiKey = key }
func (s *stubViewModel) Messages() []chat.Message  { return append([]chat.Message(nil), s.messages...) }
func (s *stubViewModel) LastError() string         { return "" }
func (s *stubViewModel) ClearError()               {}
func (s *stubViewModel) IsSending() bool           { return false }
func (s *stubViewModel) Send(ctx context.Context, content string) error {
	s.sendInvoked = true
	if s.sendErr != nil {
		return s.sendErr
	}
	s.messages = append(s.messages, chat.Message{Role: chat.RoleUser, Content: content})
	s.messages = append(s.messages, chat.Message{Role: chat.RoleAssistant, Content: "**response**"})
	return nil
}

func TestBuildUIBindsModelSelection(t *testing.T) {
	app := test.NewApp()
	defer app.Quit()

	vm := newStubViewModel()
	view := BuildAppUI(vm)

	if got := view.ModelSelect.Options; len(got) != len(vm.models) {
		t.Fatalf("expected %d options, got %d", len(vm.models), len(got))
	}

	view.ModelSelect.SetSelected("gpt-3.5")
	if vm.selected != "gpt-3.5" {
		t.Fatalf("expected view model to update selected model")
	}
}

func TestBuildUIBindsAPIKeyEntry(t *testing.T) {
	app := test.NewApp()
	defer app.Quit()

	vm := newStubViewModel()
	view := BuildAppUI(vm)

	view.APIKeyEntry.SetText("sk-test")
	if vm.apiKey != "sk-test" {
		t.Fatalf("expected API key to propagate to view model")
	}
}

func TestSendButtonTriggersViewModelAndUpdatesTranscript(t *testing.T) {
	app := test.NewApp()
	defer app.Quit()

	vm := newStubViewModel()
	view := BuildAppUI(vm)

	view.InputEntry.SetText("hello")
	view.SendButton.OnTapped()
	waitFor(t, func() bool { return vm.sendInvoked })
	waitFor(t, func() bool { return view.InputEntry.Text == "" })
	// The stub appends a markdown-formatted assistant response; ensure the view renders it.
	segments := view.ChatOutput.Segments
	if len(segments) == 0 {
		t.Fatalf("expected markdown segments to be present")
	}
	found := false
	for _, seg := range segments {
		if text, ok := seg.(*widget.TextSegment); ok && text.Text == "response" {
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("expected transcript to include assistant response text, got %#v", segments)
	}
}

func TestInitialTranscriptRendersMarkdown(t *testing.T) {
	app := test.NewApp()
	defer app.Quit()

	vm := newStubViewModel()
	view := BuildAppUI(vm)

	if len(view.ChatOutput.Segments) == 0 {
		t.Fatalf("expected chat output to contain markdown segments")
	}
	if seg, ok := view.ChatOutput.Segments[0].(*widget.TextSegment); !ok || seg.Style != widget.RichTextStyleStrong {
		t.Fatalf("expected first segment to be bold markdown text, got %#v", view.ChatOutput.Segments[0])
	}
}

func waitFor(t *testing.T, cond func() bool) {
	deadline := time.Now().Add(500 * time.Millisecond)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("condition not met within timeout")
}
