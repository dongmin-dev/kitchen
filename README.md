# kitchen

Herdr 안에서 Fable 오케스트레이터가 Opus 워커와 Codex 리뷰어/테스터를 부리는 작은 도구 모음.

- `kitchen.zsh`   : `chef` 명령과 PATH 설정. `~/.zshrc`에서 source 한다.
- `kitchen.conf`  : 모델, effort, 권한. 바꾸고 싶은 것은 전부 여기.
- `roles/*.md`    : 각 에이전트의 역할 지시문 (영어).
- `bin/kitchen`   : 워커/리뷰/테스트/정리 명령.
- 실행 중 데이터(worktree, 살아 있는 워커 기록)는 이 폴더 밖 `~/.kitchen/`에 생긴다. 그래서 이 폴더는 통째로 교체해도 안전하다.

설치 확인: Herdr 안에서 `kitchen doctor`.
제거: 이 폴더를 지우고 `~/.zshrc`의 source 한 줄을 지운다.
