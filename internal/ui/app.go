package ui

import (
	"context"
	"fmt"
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
	Messages() []chat.Message
	Send(ctx context.Context, content string) error
	LastError() string
	ClearError()
	IsSending() bool
}

// AppView bundles the root widget and key controls for easy testing.
type AppView struct {
	Root        fyne.CanvasObject
	ModelSelect *widget.Select
	APIKeyEntry *widget.Entry
	InputEntry  *widget.Entry
	SendButton  *widget.Button
	ChatOutput  *widget.RichText
	ErrorLabel  *widget.Label
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

	view := &AppView{
		ModelSelect: modelSelect,
		APIKeyEntry: apiEntry,
		InputEntry:  inputEntry,
		SendButton:  sendButton,
		ChatOutput:  chatOutput,
		ErrorLabel:  errorLabel,
	}

	transcriptContainer := container.NewVScroll(chatOutput)
	transcriptContainer.SetMinSize(fyne.NewSize(400, 300))

	refreshTranscript := func() {
		renderTranscript(chatOutput, vm.Messages())
	}
	refreshTranscript()

	send := func() {
		content := strings.TrimSpace(inputEntry.Text)
		if content == "" {
			return
		}
		view.ErrorLabel.SetText("")
		view.SendButton.Disable()
		go func(text string) {
			err := vm.Send(context.Background(), text)
			runOnMain(func() {
				refreshTranscript()
				if err != nil {
					view.ErrorLabel.SetText(err.Error())
				} else {
					vm.ClearError()
					view.ErrorLabel.SetText("")
					view.InputEntry.SetText("")
				}
				view.SendButton.Enable()
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

	view.Root = container.NewBorder(updatedControls, container.NewVBox(errorLabel, inputRow), nil, nil, transcriptContainer)

	if vm.IsSending() {
		sendButton.Disable()
	}

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
			b.WriteString(fmt.Sprintf("**%s:**\n", strings.ToUpper(string(msg.Role))))
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
