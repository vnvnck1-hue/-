# 장비 리소스 도감

- 열기: 이 폴더의 index.html을 일반 브라우저에서 열면 됩니다.
- HTML에 목록 데이터가 포함되어 있어 서버나 외부 라이브러리가 필요 없습니다.
- PNG는 기존 art 폴더의 실제 파일을 상대 경로로 연결합니다. 폴더 구조를 유지하세요.
- 99종: 기본 장비 64 + 고유 장비 11 + 초월 장비 11 + 유물 7 + 소모품 5 + 공통 스킬북 1.
- 현재 PNG 시안 99종(장비 86, 유물 7, 소모품 5, 스킬북 1), PNG 제작 대기 0종. 도감의 모든 항목에 개별 투명 PNG가 연결되어 있습니다.
- 일반 검 iron-sword.png는 sword1(낡은 검)의 시안으로 임시 배치했습니다.
- PNG 시안 존재 여부는 최종 승인 또는 게임에 적용된 상태를 뜻하지 않습니다.
- 게임 적용: ItemIcon이 godot/art/items/<게임ID>.png가 있으면 PNG를, 없으면 기존 절차적 그림을 씁니다.
  초월(9등급+) 기본 장비는 태초(8등급) PNG 위에 별을 겹쳐 표시합니다.
  스킬북 PNG는 잠긴 그림이라, 감정된 책은 우하단에 금색 별 배지를 겹쳐 구분합니다.

검색, 제작 상태, 분류, 장착 부위로 필터링할 수 있습니다.
아이콘을 클릭하면 원본, 효과/능력치, 64/48/32px 미리보기를 확인할 수 있습니다.
전체 99종 CSV 내보내기와 현재 필터된 목록의 인쇄/PDF 저장도 제공합니다.
9등급 이상의 무한 초월 장비는 8등급 아이콘 + 별 오버레이 제작 계획으로 수량을 계산했습니다.

## 목록 갱신

프로젝트 루트에서:
    node art/catalog/build-catalog.mjs

build-catalog.mjs는 godot/scripts/defs.gd와 gear.gd의 정의를 읽습니다.
그림을 추가할 때는 이 파일의 assets 매핑에 게임 ID와 PNG 경로를 넣고 다시 실행하세요.
equipment-icons/v3-complete 및 special-icons/v1-complete의 generation-manifest.json에 기록된 PNG는 실제 파일이 있으면 자동으로 연결됩니다. 제작 현황 수치는 연결된 파일 수로 계산됩니다.
catalog-data.json은 목록의 별도 데이터 사본이며, index.html 안에도 동일한 데이터가 포함됩니다.
디자인과 동작은 template.html을 수정한 뒤 다시 생성하세요.

## 게임에 반영

catalog-data.json의 image가 있는 항목을 256px로 정리해 godot/art/items/로 복사합니다(프로젝트 루트에서):
    python tools/icon_import/import_icons.py

그다음 Godot 에디터를 한 번 열면(또는 --headless --import) 새 PNG가 임포트됩니다.
새 파일의 .import에서 mipmaps/generate=true로 두면 작은 칸에서도 깔끔하게 줄어듭니다.
마지막으로 godot/build의 exe(Windows Desktop)와 web(Web) 프리셋을 다시 내보내야 실행 파일에 반영됩니다.

## 로컬 미리보기

프로젝트 루트에서:
    node art/catalog/preview.mjs

주소:
    http://127.0.0.1:8765/catalog/index.html

미리보기 서버는 로컬 컴퓨터에서만 접속할 수 있고 art 폴더만 제공합니다.
종료하려면 터미널에서 Ctrl+C를 누르세요.

## 검증

2026-10-11: 전체 99개 카드, 실 PNG 13종, 이미지 로딩 오류 0건 확인.
이름 검색, 시안/대기 필터, 유물 분류, 무기 부위 필터, 원본 확대, 배경 변경 확인.
넓은 화면의 8등급 비교표 및 좁은 화면의 카드 배열 확인.


2026-10-11 추가 제작: 빈 기본 장비 53종을 개별 투명 PNG로 생성하고 연결했습니다. 기본 64종 모두 파일 존재, 고유 파일 해시, HTML 내장 데이터와 JSON 일치 확인. 전체 시안은 71종이며 나머지 28종은 고유·초월·소모품·스킬북입니다.
생성 프롬프트와 원본 경로: ../equipment-icons/v3-complete/generation-manifest.json

2026-10-11 전체 도감 완성: 남은 고유 11종, 초월 11종, 소모품 5종, 스킬북 1종을 built-in image_gen으로 개별 생성했습니다. 초월형은 해당 고유 장비 PNG를 직접 참고했습니다. 전체 99종의 파일 존재·고유 해시·PNG 디코딩·투명 배경 확인, 새 28종 원본 복사 일치, HTML 내장 JSON 일치 확인. 브라우저의 99개 고유 이미지 경로 및 198개 이미지 요소 모두 로딩 성공, 오류 0건.
생성 프롬프트와 원본 경로: ../special-icons/v1-complete/generation-manifest.json
검증 기록: ../special-icons/v1-complete/validation-report.json, alpha-validation.json, browser-validation.json
