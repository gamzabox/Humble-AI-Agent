# Requirements

## Functional
- Provide a desktop chat client built with Go and the Fyne toolkit.
- Allow the user to configure an OpenAI API key inside the application; the key must be required before requesting completions.
- Offer a dropdown (or equivalent control) letting the user select from multiple LLM model identifiers before sending a prompt.
- Send chat requests to the OpenAI API when a key is configured and render the assistant responses in the UI.
- During answer is comming, text input must be disabled and allow to cancel watting by push cancel button changed from send button.
- Render assistant responses as formatted Markdown inside the application window.
- Maintain the running conversation history during the app session so that new completions include prior exchanges.
- Provide basic error feedback inside the UI when API calls fail or required inputs are missing.
- Save chat history and show chat history title on left split view.

## Non-Functional
- Keep networking and OpenAI access abstracted behind a client layer that can be mocked for tests.
- Structure UI updates so they remain responsive and avoid blocking the main thread during requests.
- Cover core behaviours with automated Go tests prior to implementing the production logic.
- Ensure the project builds with Go 1.21+ and Fyne v2.

## Out of Scope / Assumptions
- API usage is limited to text completion/chat models accessible via OpenAI's current API.
- Internationalization/localization is not required for the initial version.
