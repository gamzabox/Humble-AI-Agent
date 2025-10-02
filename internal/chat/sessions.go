package chat

import (
	"fmt"
	"strings"
	"time"
)

const defaultSessionTitle = "New Chat"

// Session captures a persisted conversation.
type Session struct {
	ID       string    `json:"id"`
	Title    string    `json:"title"`
	Messages []Message `json:"messages"`
}

// SessionSummary contains the minimal information required to render a history list.
type SessionSummary struct {
	ID    string
	Title string
}

// SessionStore loads and saves persisted chat sessions.
type SessionStore interface {
	LoadSessions() ([]Session, error)
	SaveSessions([]Session) error
}

func newSessionID() string {
	return fmt.Sprintf("session-%d", time.Now().UnixNano())
}

func cloneSessions(in []Session) []Session {
	out := make([]Session, len(in))
	for i, s := range in {
		out[i].ID = s.ID
		out[i].Title = s.Title
		if len(s.Messages) > 0 {
			out[i].Messages = make([]Message, len(s.Messages))
			copy(out[i].Messages, s.Messages)
		}
	}
	return out
}

func deriveTitle(messages []Message) string {
	for _, msg := range messages {
		if msg.Role != RoleUser {
			continue
		}
		title := strings.TrimSpace(msg.Content)
		if title == "" {
			continue
		}
		if len(title) > 60 {
			title = title[:60]
		}
		return title
	}
	return defaultSessionTitle
}

func ensureTitle(title string) string {
	t := strings.TrimSpace(title)
	if t == "" {
		return defaultSessionTitle
	}
	return t
}
