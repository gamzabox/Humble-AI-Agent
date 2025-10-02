package chat

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// HTTPDoer abstracts http.Client for testability.
type HTTPDoer interface {
	Do(req *http.Request) (*http.Response, error)
}

// OpenAIClient implements the Client interface using OpenAI's chat completion API.
type OpenAIClient struct {
	HTTPClient HTTPDoer
	BaseURL    string
}

// NewOpenAIClient builds a client with the provided HTTPDoer (defaults to http.Client).
func NewOpenAIClient(httpClient HTTPDoer) *OpenAIClient {
	if httpClient == nil {
		httpClient = &http.Client{Timeout: 30 * time.Second}
	}
	return &OpenAIClient{
		HTTPClient: httpClient,
		BaseURL:    "https://api.openai.com/v1",
	}
}

// SendChat dispatches the chat completion request and returns the first assistant message.
func (c *OpenAIClient) SendChat(ctx context.Context, apiKey, model string, messages []Message) (Message, error) {
	payload := struct {
		Model    string           `json:"model"`
		Messages []map[string]any `json:"messages"`
	}{
		Model: model,
	}
	for _, msg := range messages {
		payload.Messages = append(payload.Messages, map[string]any{
			"role":    string(msg.Role),
			"content": msg.Content,
		})
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return Message{}, fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, fmt.Sprintf("%s/chat/completions", c.BaseURL), bytes.NewReader(body))
	if err != nil {
		return Message{}, fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", apiKey))
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return Message{}, fmt.Errorf("send request: %w", err)
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return Message{}, fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode >= 400 {
		return Message{}, fmt.Errorf("openai error: %s", bytes.TrimSpace(data))
	}

	var parsed struct {
		Choices []struct {
			Message struct {
				Role    string `json:"role"`
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(data, &parsed); err != nil {
		return Message{}, fmt.Errorf("decode response: %w", err)
	}
	if len(parsed.Choices) == 0 {
		return Message{}, fmt.Errorf("openai response missing choices")
	}
	first := parsed.Choices[0].Message
	return Message{Role: Role(first.Role), Content: first.Content}, nil
}

var _ Client = (*OpenAIClient)(nil)
