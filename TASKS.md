# Basic Implementation Tasks

- [x] Capture requirements and author initial task backlog.
- [x] Specify application architecture via tests (state model, OpenAI client abstraction, markdown handling).
- [x] Implement view model and supporting structures to satisfy architecture tests.
- [x] Build Fyne UI components (API key entry, model selector, chat view) backed by the view model; validate via tests.
- [x] Integrate markdown rendering and OpenAI client wiring, covering behaviours with tests.
- [x] Execute `go test ./...` and perform final verification.

# Chat History and Canceling Tasks

- [x] Capture detailed history and cancellation requirements in REQUIREMENTS.md.
- [x] Specify failing tests for history persistence, session selection, and cancel/send interaction.
- [x] Implement persistent session storage and list UI to satisfy the tests.
- [x] Wire cancellation flow, button toggling, and input state management to make tests pass.
- [x] Run gofmt and go test ./... for verification.

- [x] Ensure REQUIREMENTS.md reflects new session workflow.
- [x] Add tests for fresh-session startup, new-session creation, and split sizing.
- [x] Implement view-model and UI changes for new session button and defaults.
- [x] Run gofmt and go test ./... after implementation.
