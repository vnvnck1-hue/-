## 실행 (내 PC에서 더블클릭)

### 1) 최초 1회: Node.js 설치

- Windows용 **Node.js LTS**를 설치하세요. (npm 포함)
- 설치 후 PowerShell/터미널을 **전부 닫고 다시 열기**

정상 확인:

```bash
node -v
npm -v
```

### 2) 개발 실행(추천)

프로젝트 폴더에서 `run-dev.cmd`를 **더블클릭**하면 됩니다.

- 첫 실행 때만 `npm install`을 자동 수행합니다.
- 이후 브라우저가 `http://localhost:5173` 로 자동으로 열립니다.

### 3) 빌드 결과 미리보기(선택)

`run-preview.cmd` 더블클릭:

- `npm run build` 후 `npm run preview`를 실행합니다.
- 브라우저가 `http://localhost:4173` 로 열립니다.

