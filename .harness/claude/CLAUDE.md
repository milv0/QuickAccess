# Chap — Claude Code 작업 지침

이 파일은 Claude Code 가 매 세션 자동 로드하는 프로젝트 지침이다.

## 프로젝트 구조

```
Chap/
├── .harness/                         ← AI 어시스턴트 harness (SSOT)
│   ├── shared/rules/                 ← 공유 규칙 (Claude + Kiro 공통)
│   ├── shared/hooks/                 ← 공유 훅 (swift-format.sh)
│   ├── claude/                       ← Claude Code 전용 (CLAUDE.md, commands/)
│   └── kiro/                         ← Kiro 전용
├── .claude → .harness/claude          (symlink)
├── .kiro → .harness/kiro              (symlink)
├── .github/workflows/release.yml     ← 릴리스 자동화 (workflow_dispatch)
├── Chap.xcodeproj/            ← Xcode 프로젝트 (xcodegen 으로 생성)
├── project.yml                       ← xcodegen 설정 파일 (타겟, 스킴 정의)
├── Sources/
│   ├── Chap/                  ← 앱 타겟 (Cmd+R 실행)
│   │   ├── main.swift                ← NSApplication 엔트리포인트
│   │   ├── AppDelegate.swift         ← 메뉴바, config I/O, 글로벌 핫키
│   │   ├── Views.swift               ← SwiftUI 뷰 (Settings, Welcome, Minimap)
│   │   └── Launchers/                ← 런처별 실행 로직
│   │       ├── ChromeLauncher.swift   ← URL → Chrome --app 모드
│   │       ├── AppLauncher.swift      ← macOS 앱 실행 + System Events 리사이즈
│   │       ├── FinderLauncher.swift   ← Finder 폴더 열기 + bounds 설정
│   │       ├── ShellLauncher.swift    ← 쉘 스크립트 실행
│   │       └── LauncherUtils.swift    ← 공통 유틸 (retryResize, showAlert)
│   └── ChapCore/              ← 핵심 로직 (테스트 대상)
│       ├── Models.swift              ← LaunchType, Site, Config, Defaults
│       ├── Validation.swift          ← isValidDomain, centeredBounds, targetScreen
│       └── SettingsViewModel.swift   ← SettingsViewModel (ObservableObject)
├── Tests/ChapCoreTests/       ← 테스트 (Cmd+U)
│   ├── ModelTests.swift
│   ├── ValidationTests.swift
│   └── SettingsViewModelTests.swift
├── Resources/AppIcon.icns            ← 앱 아이콘
├── assets/icons/                     ← 원본 SVG 아이콘
└── .swift-format                     ← swift-format 설정 (4 spaces, 100 cols)
```

## 빌드 & 실행 & 테스트

```bash
# Xcode 에서 (권장)
open Chap.xcodeproj            # 프로젝트 열기
# Cmd+R → 앱 실행 (.app 번들, 메뉴바 정상 동작)
# Cmd+U → 테스트 실행

# CLI 에서
xcodebuild -scheme Chap -configuration Debug -destination "platform=macOS" build
xcodebuild -scheme Chap -configuration Debug -destination "platform=macOS" test

# project.yml 수정 후 xcodeproj 재생성
xcodegen generate
```

## 릴리스

GitHub Actions `workflow_dispatch` 방식. 매 커밋에 실행되지 않음.

```
GitHub Actions 탭 → Release → Run workflow → 버전 입력 (e.g. 2.3.0)
```

자동 수행: 버전 업데이트 → 빌드 → 테스트 → zip → GitHub Release → 배포 레포 업데이트

## 글로벌 핫키

| 키 | 동작 |
|----|------|
| `⌥Q` | 메뉴바 메뉴 열기 |
| `⌥1`~`⌥9` | 해당 번호의 사이트 직접 실행 |
| `⌥,` | Settings 열기 |

구현: `AppDelegate.swift`의 `registerGlobalHotkeys()` — CGEvent tap 사용. Accessibility 권한 필요.

## LaunchType 별 동작

| 타입 | 실행 방식 | 창 제어 | Accessibility 필요 |
|------|-----------|---------|:-----------------:|
| `.url` | Chrome `--app` mode | Chrome AppleScript `set bounds` | X |
| `.app` | `NSWorkspace.openApplication` | System Events `set position/size` | O |
| `.finder` | Finder AppleScript `open` | Finder `set bounds` (atomic) | X |
| `.shell` | `Process` + `$SHELL -c` | N/A | X |

## Rules 참조

규칙 원본은 `.harness/shared/rules/` 에 있으며, `.claude/rules/` 는 symlink.

| 파일 | 내용 |
|------|------|
| `commit-convention.md` | 커밋 메시지 규약 (Conventional Commit, 금지 표현, push 정책) |
| `swift-conventions.md` | Swift 코딩 컨벤션 (naming, 구조, idioms, 아키텍처, 포맷팅) |
| `swift-testing.md` | 테스팅 규약 (Swift Testing, 테스트 대상/비대상) |

## 핵심 요약

### Commit
- `<type>(<scope>): <summary>` 형식 (영문, 72자 이내)
- scope 필수: `app`, `ui`, `model`, `build`, `docs`, `claude`, `repo`
- 이모지 금지, 한글 금지, AI attribution 금지
- `Co-Authored-By` 자동 footer 무효
- push 는 사용자 명시적 요청 시에만

### Swift
- 4 spaces 들여쓰기, 100자 줄 제한, K&R 중괄호
- `guard` early exit, `private` 기본, `self.` 최소화
- 데이터 모델은 struct, lifecycle 있는 것만 class (`final` 기본)
- SwiftUI `body` 20줄 넘으면 서브뷰 추출, `@State`는 항상 `private`
- AppDelegate 는 lifecycle/menu/window 만, 비즈니스 로직은 Launcher 로 분리

### Testing
- Swift Testing (`@Test`/`@Suite`) 사용
- 테스트 대상: Codable 모델, ViewModel 상태, validation, 순수 계산
- 테스트 안 함: SwiftUI body, NSWindow, NSAlert, Process 실행
- AAA 패턴 (Arrange-Act-Assert), 하나의 테스트 = 하나의 행위
