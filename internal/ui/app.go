package ui

import (
	"context"
	"errors"
	"strings"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/widget"

	"humble-ai-agent/internal/chat"
)

// ChatViewModel captures the behaviour required by the UI layer.
type ChatViewModel interface {
	AvailableModels() []string
	SelectedModel() string
	SelectModel(string)
	APIKey() string
	SetAPIKey(string)
	Sessions() []chat.SessionSummary
	CurrentSessionID() string
	CurrentSessionTitle() string
	SelectSession(string)
	Messages() []chat.Message
	Send(ctx context.Context, content string) error
	Cancel()
	StartNewSession() string
	LastError() string
	ClearError()
	IsSending() bool
}

// AppView bundles the root widget and key controls for easy testing.
type AppView struct {
	Root             fyne.CanvasObject
	SessionsList     *widget.List
	NewSessionButton *widget.Button
	ModelSelect      *widget.Select
	APIKeyEntry      *widget.Entry
	InputEntry       *widget.Entry
	SendButton       *widget.Button
	ChatOutput       *widget.RichText
	ErrorLabel       *widget.Label
}

// BuildAppUI assembles the Fyne widgets and binds them to the supplied view model.
func BuildAppUI(vm ChatViewModel) *AppView {
	modelSelect := widget.NewSelect(vm.AvailableModels(), func(sel string) {
		vm.SelectModel(sel)
	})
	if current := vm.SelectedModel(); current != "" {
		modelSelect.SetSelected(current)
	}

	apiEntry := widget.NewPasswordEntry()
	apiEntry.SetText(vm.APIKey())
	apiEntry.OnChanged = func(value string) {
		vm.SetAPIKey(value)
	}

	inputEntry := widget.NewMultiLineEntry()
	inputEntry.SetPlaceHolder("Type your message and press Send…")

	chatOutput := widget.NewRichText()
	chatOutput.Wrapping = fyne.TextWrapWord

	errorLabel := widget.NewLabel("")
	errorLabel.Wrapping = fyne.TextWrapWord
	errorLabel.TextStyle = fyne.TextStyle{Italic: true}

	sendButton := widget.NewButton("Send", nil)
	newSessionButton := widget.NewButton("새 새션", nil)

	view := &AppView{
		ModelSelect:      modelSelect,
		APIKeyEntry:      apiEntry,
		InputEntry:       inputEntry,
		SendButton:       sendButton,
		NewSessionButton: newSessionButton,
		ChatOutput:       chatOutput,
		ErrorLabel:       errorLabel,
	}

	transcriptContainer := container.NewVScroll(chatOutput)
	transcriptContainer.SetMinSize(fyne.NewSize(400, 300))

	var sessions []chat.SessionSummary

	sessionList := widget.NewList(
		func() int { return len(sessions) },
		func() fyne.CanvasObject { return widget.NewLabel("") },
		func(id widget.ListItemID, item fyne.CanvasObject) {
			label := item.(*widget.Label)
			if id < 0 || id >= len(sessions) {
				label.SetText("")
				return
			}
			summary := sessions[id]
			label.SetText(summary.Title)
			if summary.ID == vm.CurrentSessionID() {
				label.TextStyle = fyne.TextStyle{Bold: true}
			} else {
				label.TextStyle = fyne.TextStyle{}
			}
		},
	)
	view.SessionsList = sessionList

	refreshSessions := func(selectCurrent bool) {
		sessions = vm.Sessions()
		sessionList.Refresh()
		if selectCurrent {
			currentID := vm.CurrentSessionID()
			for idx, summary := range sessions {
				if summary.ID == currentID {
					sessionList.Select(idx)
					break
				}
			}
		}
	}

	refreshTranscript := func() {
		renderTranscript(chatOutput, vm.Messages())
	}
	refreshTranscript()
	refreshSessions(true)

	sessionList.OnSelected = func(id widget.ListItemID) {
		if id < 0 || id >= len(sessions) {
			return
		}
		vm.SelectSession(sessions[id].ID)
		refreshTranscript()
		refreshSessions(true)
	}

	var send func()
	var setSending func(bool)

	setSending = func(sending bool) {
		if sending {
			inputEntry.Disable()
			sendButton.SetText("Cancel")
			sendButton.OnTapped = func() {
				vm.Cancel()
				setSending(false)
				refreshTranscript()
				refreshSessions(true)
			}
		} else {
			inputEntry.Enable()
			sendButton.SetText("Send")
			sendButton.OnTapped = send
		}
		sendButton.Refresh()
	}

	newSessionButton.OnTapped = func() {
		vm.ClearError()
		errorLabel.SetText("")
		vm.StartNewSession()
		setSending(false)
		inputEntry.SetText("")
		refreshSessions(true)
		refreshTranscript()
	}

	send = func() {
		content := strings.TrimSpace(inputEntry.Text)
		if content == "" {
			return
		}
		errorLabel.SetText("")
		setSending(true)
		go func(text string) {
			err := vm.Send(context.Background(), text)
			runOnMain(func() {
				refreshTranscript()
				refreshSessions(true)
				if err != nil {
					if errors.Is(err, context.Canceled) {
						errorLabel.SetText("")
					} else {
						errorLabel.SetText(err.Error())
					}
				} else {
					vm.ClearError()
					errorLabel.SetText("")
					inputEntry.SetText("")
				}
				setSending(false)
			})
		}(content)
	}

	sendButton.OnTapped = send
	inputEntry.OnSubmitted = func(_ string) {
		send()
	}

	updatedControls := container.NewVBox(
		container.NewGridWithColumns(2,
			widget.NewLabelWithStyle("Model", fyne.TextAlignLeading, fyne.TextStyle{Bold: true}),
			modelSelect,
		),
		container.NewGridWithColumns(2,
			widget.NewLabelWithStyle("OpenAI API Key", fyne.TextAlignLeading, fyne.TextStyle{Bold: true}),
			apiEntry,
		),
	)

	inputRow := container.NewBorder(nil, nil, nil, sendButton, inputEntry)

	left := container.NewBorder(newSessionButton, nil, nil, nil, sessionList)
	right := container.NewBorder(updatedControls, container.NewVBox(errorLabel, inputRow), nil, nil, transcriptContainer)
	split := container.NewHSplit(left, right)
	split.SetOffset(0.3)
	view.Root = split

	setSending(vm.IsSending())

	return view
}

func renderTranscript(rt *widget.RichText, messages []chat.Message) {
	transcript := buildTranscript(messages)
	if strings.TrimSpace(transcript) == "" {
		rt.Segments = nil
		rt.Refresh()
		return
	}

	updated := widget.NewRichTextFromMarkdown(transcript)
	rt.Segments = make([]widget.RichTextSegment, len(updated.Segments))
	copy(rt.Segments, updated.Segments)
	rt.Refresh()
}

func buildTranscript(messages []chat.Message) string {
	if len(messages) == 0 {
		return ""
	}
	var b strings.Builder
	for _, msg := range messages {
		switch msg.Role {
		case chat.RoleUser:
			b.WriteString("**You:**\n")
		case chat.RoleAssistant:
			b.WriteString("**Assistant:**\n")
		case chat.RoleSystem:
			b.WriteString("**System:**\n")
		default:
			b.WriteString("**" + strings.ToUpper(string(msg.Role)) + ":**\n")
		}
		b.WriteString(msg.Content)
		b.WriteString("\n\n")
	}
	return b.String()
}

func runOnMain(fn func()) {
	if app := fyne.CurrentApp(); app != nil {
		if drv := app.Driver(); drv != nil {
			drv.DoFromGoroutine(fn, true)
			return
		}
	}
	fn()
}
