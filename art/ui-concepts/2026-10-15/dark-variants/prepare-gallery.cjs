const fs = require('node:fs');
const path = require('node:path');
const src = fs.readFileSync(path.join(__dirname,'..','index.html'),'utf8');
const config = {
 d:{name:'D · 잉크 민트',file:'d-ink-mint.png',sub:'무광 남색 / 민트 / 얇은 둥근 프레임',details:[['로비 · 정돈된 민트 강조','색을 출발과 선택 상태에 모으고, 표면과 프레임은 무광 남색으로 차분하게 정리합니다.'],['전투 · 기존의 얇은 배치','작은 스킬 원 6개와 가는 영웅 캡슐 3개. 큰 카드와 직업명 줄 없이 기존 필드 점유를 유지합니다.'],['장비 · 필요한 정보만 선명하게','낮은 대비의 칸과 밝은 수치, 선택 체크를 사용합니다. 희귀도와 행동색은 분리합니다.']]},
 e:{name:'E · 그래픽 바이올렛',file:'e-graphic-violet.png',sub:'흑보라 / 라일락 / 잘린 모서리와 굵은 제목',details:[['로비 · 형태와 타이포의 개성','메뉴의 잘린 모서리와 짧은 사선, 굵은 제목으로 게임의 개성을 만듭니다.'],['전투 · 표현을 덜어낸 HUD','메뉴의 큰 그래픽은 전투에서 빼고, 준비 상태의 가는 표시와 원래 크기의 캡슐만 사용합니다.'],['장비 · 그래픽으로 명확한 구분','선택 직업은 평평한 탭으로, 장비 칸은 얇은 라인으로 나눕니다. 주 행동에만 작은 밝은 악센트를 둡니다.']]},
 f:{name:'F · 미드나이트 브라스',file:'f-midnight-brass.png',sub:'따뜻한 차콜 / 황동 / 얕은 에나멜 표면',details:[['로비 · 따뜻한 어두움','낮은 채도의 황동과 밝은 아이보리 글자로 모닥불의 따뜻한 분위기를 이어갑니다.'],['전투 · 가는 테두리와 작은 상태줄','스킬과 영웅 정보의 원래 높이를 유지합니다. 황동은 가는 포인트로만 사용합니다.'],['장비 · 장난감 장비함의 재질','큰 패널에는 얕은 에나멜 느낌을, 칸에는 무광 바탕을 사용해 아이템이 먼저 읽히게 합니다.']]}
};
let html=src;
function replace(from,to){if(!html.includes(from))throw new Error('Missing gallery marker: '+from.slice(0,50));html=html.replaceAll(from,to);}
replace('TRIO CHESS — UI 스타일 탐색','TRIO CHESS — 어두운 UI 변형');
replace('UI DESIGN STUDY','DARK UI VARIATIONS');
replace('같은 게임, 세 가지 표정','선택한 C안에서 확장한 세 가지 방향');
replace('세 영웅의 모험에 어울리는 UI.','전투 공간은 그대로, 어두운 스타일은 더 다양하게.');
replace('실제 로비 · 전투 · 장비 화면을 기준으로, 스타일과 정보의 우선순위를 함께 정리했습니다.','최근 UI 사례를 참고해 로비 · 전투 · 장비를 다시 그렸습니다. 스킬과 영웅 상태줄은 기존의 얇은 배치를 기준으로 합니다.');
replace('data-style="a"','data-style="d"');replace('data-style="b"','data-style="e"');replace('data-style="c"','data-style="f"');
replace('A · 토이 팝','D · 잉크 민트');replace('B · 모험수첩','E · 그래픽 바이올렛');replace('C · 나이트 아케이드','F · 미드나이트 브라스');
replace('장난감 같은 입체감 · 밝은 아이보리','무광 남색 · 얇은 민트 강조');replace('종이와 에나멜 · 따뜻한 원정 분위기','그래픽 탭 · 절제된 사선');replace('잉크 남색과 민트 · 선명한 전투 정보','따뜻한 차콜 · 황동 포인트');
replace('아이보리 / 둥근 프레임 / 얕은 입체감',config.d.sub);
replace('a-toy-pop.png','d-ink-mint.png');replace('b-field-journal.png','e-graphic-violet.png');replace('c-night-arcade.png','f-midnight-brass.png');
replace('references/','../references/');
replace('캐릭터와 3D 월드는 유지하고, 패널 재질·형태·타이포·강조색을 비교합니다.','캐릭터·필드는 유지. 작은 스킬 원과 얇은 상태줄의 위치·높이는 기존 게임을 기준으로 합니다.');
replace('설계 메모 읽기 ↗','이번 변경 기준 ↗');
replace('</nav><button class="zoom"','</nav><a class="outline-link" style="font-size:12px" href="RESEARCH.md">리서치 ↗</a><button class="zoom"');
replace('우선 추천하는 방향','이번 변형의 기준');
const noteStart=html.indexOf('<section class="selection-note">');
const noteEnd=html.indexOf('</section>',noteStart)+10;
html=html.slice(0,noteStart)+'<section class="selection-note"><h2>이번 변형의 기준</h2><p><b>추천: D · 잉크 민트.</b> 선택한 C안의 느낌을 가장 직접적으로 이어갑니다. E는 형태와 타이포, F는 따뜻한 재질감으로 차이를 줍니다. 세 안의 전투 화면은 큰 영웅 카드 대신 기존의 얇은 스킬·상태줄을 기준으로 합니다. <a class="outline-link" href="RESEARCH.md">조사 근거와 원본 규격 보기 ↗</a></p></section>'+html.slice(noteEnd);
const styleStart=html.indexOf('const styles={');
const runtimeStart=html.indexOf("let current='a',view='single';",styleStart);
if(styleStart<0||runtimeStart<0)throw new Error('Missing style data');
html=html.slice(0,styleStart)+'const styles='+JSON.stringify(config)+';\n'+html.slice(runtimeStart);
replace("let current='a',view='single';","let current='d',view='single';");
replace("selectStyle('a');","selectStyle('d');");
const palettes=[['#FFF5DD','#1B2237'],['#243047','#28334A'],['#FFD34D','#79DFC4'],['#FF785E','#F0F3F8'],['#41BBA8','#9AA9BC'],['#F3E7CB','#202032'],['#294D46','#A895F2'],['#463B30','#ECEBF5'],['#D8A84F','#D6F47A'],['#8AAB91','#67617B'],['#191D35','#292830'],['#2B3150','#393541'],['#70E1C6','#C8A76C'],['#AC9CF4','#F0E7DA'],['#FF806E','#779D98']];
for(const [from,to] of palettes)html=html.replaceAll('background:'+from,'background:'+to);
fs.writeFileSync(path.join(__dirname,'index.html'),html);
console.log('Created dark variation gallery');
