# 프리즘 방어선 v0.1

네온 자동 포탑으로 에너지 코어를 지키는 Windows용 2D 타워 디펜스입니다. 포탑과 드론은 각각 1종이며, 웨이브는 플레이어가 직접 시작합니다.

## 실행

Windows 10/11 x64에서 `dist/PrismFront.exe`를 실행하세요. 게임 리소스는 EXE에 내장되어 있습니다. Godot 프로젝트를 열어 실행하려면 Godot 4.7.2에서 `project.godot`을 가져온 뒤 F5로 프로젝트를 실행하세요.

- **게임 시작** 후 **포탑 설치** 또는 숫자 **1**을 누르고 빈 타일을 좌클릭합니다. 우클릭하면 설치를 취소합니다.
- 설치된 포탑을 클릭하면 사거리와 능력치가 표시됩니다. **포탑 판매**는 설치 비용을 전액 환급합니다.
- **웨이브 시작**을 누르면 드론이 등장합니다. 기지에 도달한 드론은 남은 체력만큼 기지 피해를 줍니다.
- **Esc**는 일시정지 메뉴를 엽니다. 설정과 최고 도달 웨이브는 Godot의 사용자 데이터 경로에 저장됩니다. 새로운 게임은 체력 100, 재화 50에서 시작합니다.

## Windows 빌드

[Godot 4.7.2 안정 버전](https://godotengine.org/download/archive/4.7.2-stable/)과 같은 버전의 표준 내보내기 템플릿을 준비하세요. Godot의 **편집기 → 내보내기 템플릿 관리**에서 템플릿을 설치할 수 있습니다. 프로젝트 루트에서 PowerShell로 실행합니다.

```powershell
$Godot = 'C:/path/to/Godot_v4.7.2-stable_win64_console.exe'
& $Godot --headless --editor --path . --import --quit
New-Item -ItemType Directory -Force dist | Out-Null
& $Godot --headless --path . --export-release 'Windows Desktop' dist/PrismFront.exe
```

배포 시에는 `assets/Godot-LICENSE.txt`, `assets/Godot-COPYRIGHT.txt`, `assets/OFL.txt`의 고지를 함께 포함합니다. 세 고지는 Windows 빌드에도 들어 있습니다. 게임용 스프라이트는 `assets/make_sprites.py`에서 생성한 원본 이미지이고, 효과음은 `scripts/sound.gd`에서 파형을 생성합니다. 소스 실행 및 빌드에 Pillow는 필요하지 않습니다.

## 맵과 밸런스 데이터

- 기본 전장은 `data/sample_map.json`의 **샘플 맵**입니다. 사용자 좌표가 확정되면 같은 형식으로 `data/map.json`을 추가하면 됩니다. 그 파일의 `sample`을 `false`로 설정하면 샘플 표기가 사라집니다.
- 좌표는 0부터 시작하는 `[x, y]`이고 오른쪽과 아래쪽으로 증가합니다. `tiles`는 30자씩 18행입니다. `.`는 설치 가능, `#`는 장애물, `=`는 경로, `S`는 시작, `E`는 출구입니다. `path`는 `spawn`부터 `exit`까지 순서대로 각 경로 칸을 한 번씩 포함해야 합니다. 경로 좌표가 격자를 벗어나거나 상하좌우로 이어지지 않으면 메인 메뉴에 오류가 표시됩니다.
- 웨이브 간격은 임시로 0.5초입니다. 확정된 공식은 `scripts/battle_data.gd`의 `spawn_interval(wave)`에 적용하고 관련 계수는 `data/balance.json`에 둡니다. 적 수와 완료 보상은 각각 원래 수식에서 계산한 뒤 반올림합니다.
- 포탑과 드론의 수치 및 색상은 각각 `data/turret.json`, `data/drone.json`에 있습니다. 새 종류를 추가할 때는 같은 스키마로 데이터를 만들고, `Battle`의 포탑과 드론 상태가 각 정의를 참조하도록 확장합니다. 배치 UI와 시각 리소스는 `Front`와 `FieldView`에서 연결합니다. 연구, 강화와 추가 게임 모드는 이 버전의 범위 밖입니다.
- 아주 큰 웨이브 수치와 재화는 정수 오버플로를 막기 위해 9,000,000,000,000,000에서 포화됩니다. 예정된 적 수만큼 오브젝트를 한꺼번에 생성하지 않습니다.

검증 절차와 결과는 [TESTING.md](TESTING.md)에 있습니다.
