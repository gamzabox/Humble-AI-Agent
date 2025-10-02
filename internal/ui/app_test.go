package ui

import (
	"context"
	"errors"
	"fmt"
	"math"
	"strings"
	"testing"
	"time"

	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/test"
	"fyne.io/fyne/v2/widget"

	"humble-ai-agent/internal/chat"
)

type stubViewModel struct {
	models                []string
	selected              string
	apiKey                string
	sessions              []chat.SessionSummary
	messages              map[string][]chat.Message
	currentID             string
	sendErr               error
	sendInvoked           bool
	cancelCalled          bool
	isSending             bool
	startNewSessionCalled bool
	lastNewID             string
	nextID                int
}

func newStubViewModel() *stubViewModel {
	sessions := []chat.SessionSummary{
		{ID: "s1", Title: "First Chat"},
		{ID: "s2", Title: "Second Chat"},
	}
	messages := map[string][]chat.Message{
		"s1": []chat.Message{{Role: chat.RoleAssistant, Content: "**hi**"}},
		"s2": []chat.Message{{Role: chat.RoleAssistant, Content: "previous"}},
	}
	return &stubViewModel{
		models:    []string{"gpt-4", "gpt-3.5"},
		selected:  "gpt-4",
		sessions:  sessions,
		messages:  messages,
		currentID: sessions[0].ID,
		nextID:    3,
	}
}

func (s *stubViewModel) AvailableModels() []string { return append([]string(nil), s.models...) }
func (s *stubViewModel) SelectedModel() string     { return s.selected }
func (s *stubViewModel) SelectModel(model string)  { s.selected = model }
func (s *stubViewModel) APIKey() string            { return s.apiKey }
func (s *stubViewModel) SetAPIKey(key string)      { s.apiKey = key }
func (s *stubViewModel) Sessions() []chat.SessionSummary {
	return append([]chat.SessionSummary(nil), s.sessions...)
}
func (s *stubViewModel) CurrentSessionTitle() string {
	for _, summary := range s.sessions {
		if summary.ID == s.currentID {
			return summary.Title
		}
	}
	return "New Chat"
}
func (s *stubViewModel) CurrentSessionID() string { return s.currentID }
func (s *stubViewModel) SelectSession(id string) {
	s.currentID = id
}
func (s *stubViewModel) StartNewSession() string {
	s.startNewSessionCalled = true
	newID := fmt.Sprintf("s%d", s.nextID)
	s.nextID++
	s.sessions = append([]chat.SessionSummary{{ID: newID, Title: "New Chat"}}, s.sessions...)
	s.messages[newID] = nil
	s.currentID = newID
	s.lastNewID = newID
	return newID
}
func (s *stubViewModel) Messages() []chat.Message {
	return append([]chat.Message(nil), s.messages[s.currentID]...)
}
func (s *stubViewModel) LastError() string { return "" }
func (s *stubViewModel) ClearError()       {}
func (s *stubViewModel) IsSending() bool   { return s.isSending }
func (s *stubViewModel) Cancel()           { s.cancelCalled = true }
func (s *stubViewModel) Send(ctx context.Context, content string) error {
	s.sendInvoked = true
	if s.sendErr != nil {
		return s.sendErr
	}
	msgs := append([]chat.Message(nil), s.messages[s.currentID]...)
	msgs = append(msgs, chat.Message{Role: chat.RoleUser, Content: content})
	msgs = append(msgs, chat.Message{Role: chat.RoleAssistant, Content: "**response**"})
	s.messages[s.currentID] = msgs
	trimmed := strings.TrimSpace(content)
	if trimmed != "" {
		for i := range s.sessions {
			if s.sessions[i].ID == s.currentID {
				s.sessions[i].Title = trimmed
				break
			}
		}
	}
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

	if view.SendButton.Text != "Send" {
		t.Fatalf("expected button to return to Send label after completion")
	}

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

func TestSessionsListPopulatedAndSelects(t *testing.T) {
	app := test.NewApp()
	defer app.Quit()

	vm := newStubViewModel()
	view := BuildAppUI(vm)

	if got := view.SessionsList.Length(); got != len(vm.sessions) {
		t.Fatalf("expected %d sessions in list, got %d", len(vm.sessions), got)
	}

	view.SessionsList.Select(1)
	if vm.currentID != "s2" {
		t.Fatalf("expected selecting list item to update current session")
	}
}

func TestNewSessionButtonCreatesFreshSession(t *testing.T) {
	app := test.NewApp()
	defer app.Quit()

	vm := newStubViewModel()
	view := BuildAppUI(vm)

	view.NewSessionButton.OnTapped()
	waitFor(t, func() bool { return vm.startNewSessionCalled })

	if vm.currentID != vm.lastNewID {
		t.Fatalf("expected new session to be current")
	}
	if view.NewSessionButton.Text != "새 새션" {
		t.Fatalf("expected button label to match requirement, got %s", view.NewSessionButton.Text)
	}
}

func TestRootLayoutIsHorizontalSplitWithOffset(t *testing.T) {
	app := test.NewApp()
	defer app.Quit()

	vm := newStubViewModel()
	view := BuildAppUI(vm)

	split, ok := view.Root.(*container.Split)
	if !ok {
		t.Fatalf("expected root to be a split container")
	}
	if !split.Horizontal {
		t.Fatalf("expected split to be horizontal")
	}
	if math.Abs(split.Offset-0.3) > 0.01 {
		t.Fatalf("expected split offset near 0.3, got %f", split.Offset)
	}
}

func TestSendButtonShowsCancelWhileSending(t *testing.T) {
	app := test.NewApp()
	defer app.Quit()

	vm := newStubViewModel()
	vm.isSending = true
	view := BuildAppUI(vm)

	if view.SendButton.Text != "Cancel" {
		t.Fatalf("expected button label to be Cancel while sending")
	}
	if !view.InputEntry.Disabled() {
		t.Fatalf("expected input to be disabled during send")
	}
}

func TestCancelButtonInvokesCancelOnViewModel(t *testing.T) {
	app := test.NewApp()
	defer app.Quit()

	vm := newStubViewModel()
	vm.isSending = true
	view := BuildAppUI(vm)

	view.SendButton.OnTapped()
	if !vm.cancelCalled {
		t.Fatalf("expected cancel to be invoked when tapping Cancel")
	}
	if vm.sendInvoked {
		t.Fatalf("did not expect send to be invoked while cancelling")
	}
}

func TestSendFailureReenablesInputAndShowsError(t *testing.T) {
	app := test.NewApp()
	defer app.Quit()

	vm := newStubViewModel()
	vm.sendErr = errors.New("boom")
	view := BuildAppUI(vm)

	view.InputEntry.SetText("hello")
	view.SendButton.OnTapped()
	waitFor(t, func() bool { return !view.InputEntry.Disabled() })

	if view.SendButton.Text != "Send" {
		t.Fatalf("expected button to reset to Send after failure")
	}
	if view.ErrorLabel.Text == "" {
		t.Fatalf("expected error to be shown")
	}
}

func waitFor(t *testing.T, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(500 * time.Millisecond)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("condition not met within timeout")
}
