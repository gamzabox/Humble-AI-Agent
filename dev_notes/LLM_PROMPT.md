# Coding Rules
- REQUIREMENTS.md 을 검토해 필요시 요구사항을 추가 또는 수정 할 것.
- Task 를 TASKS.md 파일에 정리하고 완료한 Task 를 체크 표시 할 것
- TDD 방법론을 적용해 반드시 다양한 케이스에 대해 테스트 코드를 먼저 작성한 다음 기능을 구현.
- 하나의 Task 구현이 완료되면 반드시 테스트를 수행해 PASS 를 확인 한 후 해당 Task 를 체크 표시 하고 다음 Task 를 진행 한다.
- Text encoding: UTF-8(NO BOM)

# 전체 기능 구현
REQUIREMENTS.md 파일에 기술된 요구사항을 파악해 LLM 채팅 프로그램 구현

# Theme 변경
macos ui 를 적용해 앱의 전체 테마를 변경

# 대화 화면 스타일 조정
- 대화 화면에 전반적으로 github 스타일 적용 필요
- horizon line 두깨를 얇게 만들어야 함
- Code block 배경색을 light gray 로 변경
- Table style 을 github 스타일로 변경

# 설정 화면 레이아웃 조정
- 설정 다이얼로그 레이아웃 조정이 필요함
- 설정 다이얼로그의 폭을 키우고 왼쪽과 오른쪽으로 split
- 왼쪽에는 설정 항목 리스트가 보여지고 설정항목을 선택하면 오른쪽 화면에 설정 화면이 보여짐
- 설정 항목은 다음과 같음
  - Models: 현재 구현된 Model Settings 화면을 그대로 사용
  - About: 앱 타이틀, 버전, 개발자(gamzabox) 가 노출됨
- 설정 다이얼로그 우측 하단에 Close 버튼을 제공

# 코드블럭 여러개 처리
- 현재 문서에 코드블럭이 여러개 있으면 첫번째 한개의 코드블럭에만 syntax highlighting 이 적용되고 있음.
- 문서에 모든 코드 블럭에 syntax highlighting 이 적용되로록 수정 해

# 코드 리팩토링
- 구현코드 및 테스트 코드 모두 하나의 파일에 너무 많은 로직이 구현되어 있음
- 이를 SRP 원칙을 적용해 로직을 여러 파일로 나누어 가독성과 유지보수성을 높힐 것.

# 세션 리스트 삭제 버튼 제거
- 세션 리스트의 삭제 버튼을 제거하고 그 대신 마우스 오른쪽 버튼 클릭시 Context menu 가 뜨고 여기서 Delete 를 선택시 삭제 되도록 수정
- 세션 리스트를 모두 삭제 할 경우 자동으로 New Session 생성
