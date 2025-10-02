package main

import (
	"os"
	"strings"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"

	"humble-ai-agent/internal/chat"
	"humble-ai-agent/internal/ui"
)

func main() {
	application := app.New()
	window := application.NewWindow("Fyne LLM Chat")

	models := []string{"gpt-4o-mini", "gpt-4o", "gpt-3.5-turbo"}
	client := chat.NewOpenAIClient(nil)
	viewModel := chat.NewViewModel(client, models)

	if apiKey := strings.TrimSpace(os.Getenv("OPENAI_API_KEY")); apiKey != "" {
		viewModel.SetAPIKey(apiKey)
	}

	view := ui.BuildAppUI(viewModel)

	window.SetContent(view.Root)
	window.Resize(fyne.NewSize(900, 640))
	window.ShowAndRun()
}
