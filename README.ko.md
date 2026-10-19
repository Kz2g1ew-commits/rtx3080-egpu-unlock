# RTX 3080 eGPU unlock (Linux)

[English](README.md) | **한국어**

> **상태: 실험 중.** ZOTAC RTX 3080 10GB 한 장에서 실제 부팅 1회 성공(2026-10-19). 다른 보드, 장시간 안정성, 게임은 확인하지 않았습니다.

[Zagitta/gpu-unlock](https://github.com/Zagitta/gpu-unlock)(RTX 3090, Linux 커널 모듈)을 **USB4/Thunderbolt eGPU로 연결한 RTX 3080 10GB**용으로 옮긴 포크입니다. NVIDIA 드라이버가 카드에 붙기 전에 FWSEC → V67 → 속도 선택 레지스터(SS0 `0x88888888`, SS1 `0x8`) → FLR 순서로 실행해서, GeForce에 걸린 **FP16/BF16 입력·FP32 누산 텐서 연산의 절반 속도 제한**을 풉니다. NVIDIA 드라이버 파일은 수정하지 않습니다. 플래시와 eFuse에도 쓰지 않아서 카드 전원이 꺼지면 원래 상태로 돌아갑니다.

## 선행 작업

| 프로젝트 | 내용 |
| --- | --- |
| [Zagitta/gpu-unlock](https://github.com/Zagitta/gpu-unlock) | 이 포크의 기반. RTX 3090에서 Linux initramfs 단계로 실행 |
| [rough2515-hub/rtx3080-unlock-public](https://github.com/rough2515-hub/rtx3080-unlock-public) | 같은 코어로 MSI RTX 3080 10GB(`1462:3890`)에서 Windows/UEFI로 확인. GEMM에서 FP16 +79%, BF16 +86% |
| [IHaBiS02/ga107-unlock](https://github.com/IHaBiS02/ga107-unlock) | 노트북 GA107로 옮긴 사례. 첫 실패 분석(FWSEC DMEM 정렬, BAR 보유) 참고 |
| [WildFlash1st/cmp90hx-unlock](https://github.com/WildFlash1st/cmp90hx-unlock) | V67 페이로드 원본(CMP 90HX) |

## upstream과 다른 점

- **대상 카드**: `10de:2206`(RTX 3080 10GB, non-LHR)만 받습니다. 그리고 `kernel/gpu_unlock/board.h`의 보드 목록(서브시스템 ID)에 있는 보드만 처리합니다. 목록에 없는 보드는 펌웨어 요청이나 MMIO 전에 건너뜁니다. 펌웨어 단계 중간과 FLR 뒤에 하는 PCI ID 재검사도 3080 기준으로 바꿨습니다.
- **실행 시점**: upstream은 initramfs에서 PCI를 한 번 훑습니다. USB4 eGPU는 boltd 승인 뒤(부팅 후 몇 초)에야 나타나므로 거기서는 카드를 찾지 못합니다. 그래서 이 포크는 `nvidia`의 modprobe `install` 훅(`egpu/gpu-unlock-gate`)에서 실행합니다.
  - nvidia-smi, CUDA, prime-run, `nvidia_drm`/`nvidia_uvm` 의존성 로드 등 nvidia를 올리는 모든 경로가 이 훅을 지나갑니다.
  - 전제: `nvidia` 자동 로드가 꺼져 있어야 합니다(modprobe.d의 `blacklist nvidia`). 그래야 카드가 나타난 뒤에도 아무 드라이버가 붙지 않은 상태로 남습니다.
  - 카드를 꽂을 때마다 한 번만 시도합니다. 카드가 PCI에서 빠지면 udev 규칙이 기록을 지워서, 다시 꽂으면 새로 시도합니다.
- 언락 코어(FWSEC, Booter, V67, FLR, 검사와 실패 처리)는 upstream 그대로입니다.

## 테스트 환경

| 항목 | 값 |
| --- | --- |
| 카드 | ZOTAC RTX 3080 10GB, `10de:2206`, 서브시스템 `19da:3612`, VBIOS `94.02.42.00.ae` |
| 연결 | AOOSTAR AG02(ASMedia 246x), USB4 40 Gb/s(2레인 × 20 Gb/s), 카드 BAR0 16 MiB / BAR1 256 MiB(ReBAR 없음) |
| 호스트 | Lenovo Legion Go(Ryzen Z1 Extreme) |
| OS | CachyOS(rolling), KDE Plasma 6.8.0 Wayland(KWin 6.8.0), bolt 0.9.11, kmod 34.2 |
| 커널 | `6.18.55-2-cachyos-lts`(실행), `7.2.9-2-cachyos-deckify`(빌드만). 둘 다 GCC 빌드, 모듈은 GCC 16.2.1로 빌드 |
| NVIDIA | open 커널 모듈 615.78.08(`linux-cachyos-lts-nvidia-open`), `nvidia-utils` 615.78.08, `linux-firmware-nvidia` 20260916. 언락 자산은 upstream과 같은 610.43.03에서 생성 |
| 측정 | PyTorch 2.14.1+cu130(CUDA 13.0, cuDNN 9.24.0), ComfyUI. 언락 빌드·생성 스크립트는 Python 3.14.8 |
| 전력 | 250 W, SM 최대 1800 MHz(부팅 때 nvidia-smi로 설정) |

rough2515가 확인한 MSI 보드의 VBIOS는 `94.02.59.00.aa`이고, 이 카드는 `94.02.42.00.ae`입니다. FWSEC는 카드 ROM에서 읽어 형식과 fuse 버전을 검사하므로, 맞지 않으면 실행 전에 거부됩니다.

부팅 순서(이 환경): boltd가 독을 승인하면 카드가 PCI에 나타나고, udev가 전력 제한 서비스를 시작합니다. 이 서비스의 `nvidia-smi`가 nvidia를 처음 올리는데, 그 직전에 게이트가 언락을 실행합니다. 그 서비스는 `timeout 3 nvidia-smi`를 쓰기 때문에 첫 시도가 언락을 기다리다 끊길 수 있습니다. 게이트는 그 신호를 무시하고 언락을 끝까지 실행하며, 서비스가 다시 시도할 때는 표시가 남아 있어 언락 없이 nvidia가 바로 로드됩니다.

## 확인한 것

**실제 실행 (2026-10-19, 위 테스트 환경, 250 W 제한)**

- 부팅 중 게이트가 nvidia보다 먼저 언락을 실행했습니다. 카드 ROM의 FWSEC와 V67 단계를 통과했고, SS0가 `0x55717001` → `0x88888888`, SS1이 `0x6` → `0x8`로 바뀌었으며 FLR 뒤에도 유지됐습니다. 이후 nvidia 615.78.08이 오류나 Xid 없이 초기화됐고, 외장 화면도 정상입니다. 로그: [research/first-run-2026-10-19.log](research/first-run-2026-10-19.log)
- GEMM 성능: BF16(FP32 누산) 1.65배, FP16(FP32 누산) 1.67~1.69배, TF32 1.62배. FP32는 변화 없음. 계산 오차도 적용 전과 같습니다. 250 W 제한에 걸려 텐서 연산 중 클럭이 1425~1515 MHz로 내려갔습니다. 자세한 수치: [bench/gemm-results.md](bench/gemm-results.md)
- ComfyUI Anima(bf16): 샘플링 1.36배, 이미지 한 장 전체 시간 −16%. 자세한 수치: [bench/comfyui-anima.md](bench/comfyui-anima.md)

**빌드와 모의 검사**

- 빌드: CachyOS `6.18.55-2-cachyos-lts`, `7.2.9-2-cachyos-deckify`(GCC)에서 경고 없이 빌드
- 펌웨어: upstream이 고정한 610.43.03 입력을 받아 SHA-256 검사를 통과하고 자산 5개 생성
- 모의 검사: `tests/`의 컴포넌트 테스트 통과. 생성된 실제 펌웨어 자산으로 모의 하드웨어에서 전체 언락 과정을 실행하는 검사 포함. 보드 목록에 없는 보드를 건너뛰는 검사를 추가
- `modprobe -n -v`로 `nvidia`, `nvidia_uvm`, `nvidia_drm`, `nvidia_modeset`을 올릴 때 모두 install 훅을 지나가는 것을 확인

## 사용 순서

```sh
make inputs INPUTS=$PWD/build/inputs                          # NVIDIA 입력 다운로드 + SHA-256 확인
make firmware INPUTS=$PWD/build/inputs ASSETS=$PWD/build/assets
egpu/build.sh                                                 # 헤더가 있는 모든 커널용 .ko
tools/egpu-preflight.sh                                       # 읽기 전용 상태 점검
sudo egpu/install.sh                                          # 설치(ENABLE=0으로 시작)
```

켜기: `/etc/gpu-unlock-egpu.conf`에서 `ENABLE=1`로 바꿉니다.
한 번만 끄기: 부트 메뉴 편집 화면에서 커널 인자에 `gpu_unlock.egpu=0`을 추가합니다.
완전히 제거: `sudo egpu/uninstall.sh`.

`packaging/`, `debian/`과 `make install-arch|deb|rpm`은 upstream의 initramfs 방식이라 eGPU에서는 카드를 찾지 못합니다. 쓰지 마세요.

### 시도할 때

1. 작업을 저장하고 PC를 끕니다. **eGPU 독의 전원도 끕니다.** 카드가 실제로 꺼져야 하고, 드라이버가 한 번이라도 쓴 카드는 모듈이 거부합니다(`card already initialised since power on`).
2. 독을 켜고 PC를 켭니다. 부팅 중에 무언가 nvidia를 처음 올릴 때 언락이 먼저 실행됩니다.
3. 결과 확인:

```sh
journalctl -b -t gpu-unlock-gate
journalctl -k -b -g gpu_unlock
```

실패했다면 같은 전원 주기 안에서 다시 시도하지 않습니다. PC와 독 전원을 모두 끈 뒤 `ENABLE=0`으로 부팅합니다.

### 성능 측정

```sh
python -I bench/gemm.py --label off -o bench/results/off.json   # 언락 전
python -I bench/gemm.py --label on  -o bench/results/on.json    # 언락 후
python -I bench/gemm.py --compare bench/results/off.json bench/results/on.json
```

PyTorch CUDA가 설치된 Python으로 실행합니다. 4096과 8192 크기 GEMM에서 FP32, TF32, FP16/BF16(FP32 누산)을 재고, nvidia-smi로 클럭·전력·온도를 같이 기록합니다.

## 위험과 한계

- 실험 코드입니다. 실패하면 GPU가 멈출 수 있고, 펌웨어가 멈추지 않으면 DMA 버퍼를 일부러 잡아 둡니다. 이때는 PC와 독 전원을 모두 꺼야 풀립니다.
- USB4 링크가 펌웨어 단계 도중에 끊기면 위와 같은 상태가 됩니다. 링크가 안정적인지 먼저 확인합니다.
- SS0 전체 필드를 full-rate 값으로 씁니다. 연산별 비트 의미가 모두 밝혀진 것은 아닙니다.
- 지속 부하, 게임, 장시간 안정성은 확인하지 않았습니다. 전력 제한을 걸어 두면 실제 향상 폭은 벤치마크보다 작을 수 있습니다.
- 직접 빌드한 모듈은 서명되지 않아서 커널에 `E` taint가 붙습니다. `module.sig_enforce`나 lockdown이 켜져 있으면 로드되지 않습니다.

## 라이선스

커널 모듈과 스크립트는 GPL-2.0-only입니다(upstream과 같음). NVIDIA 바이너리는 각자의 라이선스를 따릅니다. 저장소에는 포함하지 않고 빌드할 때 생성합니다. `licenses/`와 `firmware/NOTICE.md`를 참고하세요. upstream 원문 README는 [README.upstream.md](README.upstream.md)에 있습니다.
