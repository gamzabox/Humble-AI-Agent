# humble ai agent

Be humble. Be useful.

소개
- LLM 기반 대화형 에이전트의 데스크톱 앱(Flutter)입니다.
- 메시지 스트리밍, 세션 관리, 모델 관리, Markdown 코드 하이라이트 등을 지원합니다.

핵심 기능
- 채팅 스트리밍: 토큰 단위로 수신하여 대화가 실시간으로 렌더링됩니다.
- 취소/재시도: 응답 대기 중 취소 가능, 오류 배너에서 재시도로 마지막 프롬프트 재전송.
- 세션 관리: 세션 목록, 선택 시 볼드 표시, 삭제, New Chat로 초기화.
- 모델 관리: OpenAI·Ollama 모델 추가/선택 드롭다운 지원.
  - OpenAI: API Key 필요
  - Ollama: Base URL 필요 (예: http://localhost:11434)
- Markdown 렌더링: fenced code block 하이라이트(인용된 코드 블록은 제외), 선택 가능한 코드 텍스트.
- 단축키: Shift+Enter 로 메시지 전송.

프로젝트 구조(요약)
- UI: `lib/widgets/` (예: `chat_page.dart`, `chat_view.dart`, `input_bar.dart`)
- 로직: `lib/controllers/chat_controller.dart`
- LLM 연동: `lib/services/llm_client.dart`, `lib/services/llm_client_impl.dart`
- 스토리지: `lib/services/storage_service.dart`
- 테스트: `test/` (위젯/흐름/Markdown 렌더링)

사전 준비물
- Git
- Flutter SDK (안정 채널 권장)
  - 설치 후 `flutter doctor` 로 환경 점검
- 데스크톱 빌드 도구
  - Windows: Visual Studio 2022 (Desktop development with C++ 워크로드)
  - Linux: GTK 및 빌드 툴 패키지
    - Debian/Ubuntu: `sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev` 등

소스 가져오기
```bash
git clone https://github.com/gamzabox/humble_ai_agent.git
cd humble_ai_agent
```

의존성 다운로드
```bash
flutter pub get
```

테스트 실행
```bash
flutter test
```

개발 실행 (데스크톱)
- 데스크톱 타겟 활성화:
```bash
flutter config --enable-windows-desktop   # Windows
flutter config --enable-linux-desktop     # Linux
```
- 실행:
```bash
flutter run -d windows   # Windows
flutter run -d linux     # Linux
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 3000  # Web
```

앱 내 모델/키 설정
- 앱 실행 후 Settings/Models 화면에서 OpenAI 또는 Ollama 모델을 추가하세요.
- OpenAI는 API Key, Ollama는 Base URL이 필요합니다.
- 선택된 모델은 상단 드롭다운(`model-dropdown`)으로 전환할 수 있습니다.

Windows 빌드 가이드
1) 필수 도구 설치
   - Visual Studio 2022 + Desktop development with C++ 워크로드
   - Flutter SDK 설치 후 `flutter doctor`로 확인
2) 데스크톱 타겟 활성화
```powershell
flutter config --enable-windows-desktop
```
3) 릴리즈 빌드
```powershell
flutter build windows --release
```
4) 산출물 위치
   - `build\windows\runner\Release` (또는 Flutter 버전에 따라 `build\windows\x64\runner\Release`)

Linux 빌드 가이드
1) 필수 패키지 설치 (Debian/Ubuntu 예시)
```bash
sudo apt-get update
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
```
2) 데스크톱 타겟 활성화
```bash
flutter config --enable-linux-desktop
```
3) 릴리즈 빌드
```bash
flutter build linux --release
```
4) 산출물 위치
   - `build/linux/x64/release/bundle`

자주 묻는 문제
- flutter doctor 경고/오류가 있을 때 먼저 해결하세요.
- Windows에서 VS C++ 워크로드가 누락되면 빌드가 실패합니다.
- Linux에서 GTK 개발 패키지나 빌드 툴이 없으면 CMake 단계에서 실패합니다.

라이선스
- 해당 프로젝트의 라이선스 정책을 확인하세요.
