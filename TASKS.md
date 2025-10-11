# Tasks

- [x] Define data models (Session, Message)
- [x] Storage service for config/sessions (with base dir override)
- [x] LLM client abstraction + fake client for tests
- [x] Chat controller: send/cancel/stream, session management
- [x] UI: split layout (30/70), session list, chat view, input bar
- [x] Markdown rendering (baseline) and streaming updates
- [x] Model settings dialog: add/select/remove models, validation rules
- [x] Persistence: load/save config and sessions on startup/shutdown
- [x] Tests: chat flow (send/cancel/stream)
- [x] Tests: session title and selection
- [x] Tests: config validation and persistence
- [x] Tests: initial layout proportions




# New Enhancements
- [x] Code block highlight with GitHub theme
- [x] Session list: bold selected + delete
- [x] Error banner with Retry for network issues

## 2025-10-11
- [x] 세션 삭제 UX 변경: 인라인 삭제 버튼 제거, 세션 항목 우클릭(혹은 롱프레스) 컨텍스트 메뉴에서 Delete 제공
- [x] 모든 세션 삭제 시 자동으로 New Session 생성되도록 처리
- [x] 테스트 안정화: 파일 IO를 유발하는 `deleteSessionAt()` 호출을 `tester.runAsync`로 래핑


