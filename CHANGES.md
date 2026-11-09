# 수정 기록

## 2026-11-09 — SPI/FT4232H USB 개선 후속

- SPI RX/TX 시프트 상태를 분리하고 마지막 상승 에지에서 RX 완료를 확정한다.
  마지막 하강과 CS 해제가 겹쳐도 완료 바이트가 다시 전송되지 않는다.
  부분 바이트 중단 시 재전송, 빈 전송의 0 패딩, 늦게 도착한 TX 데이터의
  바이트 경계 적용은 보존한다.
- 입력 동기화기 속성을 명시하고 `spi_cdc.xdc`는 입력 pin→첫 단계만 제외한다.
  두 번째 단계의 실제 timing path와 속성을 검사하며 MISO는 IOB에 배치한다.
  출력이 미사용인 MOSI 로직의 제거는 허용한다. 외부 배선 지연/FTDI 측정값이
  없어 외부 setup/hold 여유는 미확정으로 남겼다. clock-wide false path는 추가하지 않았다.
- 전체 회귀 13개 스크립트/16개 top 통과. 7.5 MHz 연속 전송 25위상 및 짧은
  CS 종료 125조건에서 오류 0. 10/12.5 MHz 이상적 모델 결과는 실물 보장이 아니다.
- 내부 routed WNS/WHS: 기본 구성 +0.536/+0.007 ns, 데이터 텔레메트리 활성
  검증 구성 +0.230/+0.011 ns. 실패 endpoint 0/0. 경로는
  `tests/design_0_spi2_scoped.sim/`, `tests/design_1_spi2.sim/`이다.
  기본 구성은 동일 HDL 합성 체크포인트에서 scoped 제약을 재적용해 구현하고
  별도 SPI 경로 검사를 통과했다. methodology 0건, DRC 오류 0건이며 기존 경고 유형은 남아 있다.
- 호스트 수정은 로컬 복사본에서 `host-patches/sunnypilot-spi-usb.patch`로 만들었다.
  FTDI divide-by-5/분주 반올림, 최대 2청크 요청, 부분 수신 보존, timeout 재개,
  fatal 이전 prefix 전달, 종료 drain/고정 deadline, 주기 계측을 포함한다.
  깨끗한 기준 코드에 적용 후 실제 C 코드/reader의 native GCC -Werror 모의 시험을
  통과했다. Linux 앱 전체 빌드와 실제 USB 측정은 미수행이며 외부 push도 하지 않았다.
- 지시문은 `docs/sunnypilot-flexray-handoff.txt` 하나이며 패치 본문을 내장한다.
  `spi-review.txt`는 개선 전 재현 기록으로 구분했다. 보드 프로그래밍은 수행하지 않았다.

## 2026-11-09 — 양방향 로그 FIFO 및 CAN 진단

- DADC→BCM 출력과 BCM 측→DADC 출력을 각각 디코딩한다. 방향별 독립 FIFO는
  완전한 프레임 32개를 저장하며 공통 활성 로거 요청은 별도로 유지한다.
  처음의 2개 대기 슬롯에서 확장하면서 packed record와 LUTRAM을 사용해
  프레임마다 플립플롭을 늘리는 비용을 줄였다. 깊이는 1~64로 설정할 수 있다.
  라운드로빈 중재 후 기존 128 KiB 바이트 FIFO와 SPI 경로를 사용한다.
- DADC 로그의 `CA A0`는 유지하고 BCM 측 로그는 `CA 80`으로 구분한다.
  SPI wire 형식에 timestamp/sequence/진단 바이트를 추가하지 않는다.
- 정상 수신·방향별 큐 드롭·큐 최대 사용량·바이트 FIFO 사용량/최대 사용량·
  full 진입 횟수를 집계한다. 큐가 가득 차도 FlexRay 전달을 기다리게 하지 않는다.
- 사용자 지정 표준 CAN ID `0x1FA`, DLC 8로 1초마다 같은 시점의 카운터를 담은
  48바이트 스냅샷을 6바이트씩 8페이지로 전송한다. packed 버전 2의 첫 바이트는
  `0x20~0x27`이며 다음 바이트는 스냅샷 번호다. 예약 바이트 없이 12개 little-endian
  uint32를 보낸다. 항목은 페이지 경계에 걸칠 수 있어 호스트가 먼저 재조립한다.
  기존 비동기 CAN 큐의 full/만료 처리 및 단일 송신기를 재사용한다.
  데이터 텔레메트리와 진단 요청은 CAN 클록 영역의 공통 중재기를 통과한다.
- 7.5 MHz SPI의 여유를 확인하기 위해 방향별 입력 로그 바이트 요구량,
  SPI prefetch가 받은 유효 바이트, 패딩 포함 완료 SPI 바이트를 추가했다.
  마지막 항목은 실제 `SPI_SLAVE.DOUT_VLD`에서 집계한다. 바이트 누계는
  32비트 순환으로 장시간 rate 계산이 가능하며 이벤트 누계는 포화한다.
  USB/호스트 도착 확인이나 FlexRay 버스 점유율과는 다른 지표다.
- 저장된 BD에서는 진단과 공통 CAN 송신기를 활성화했다. 차량 FlexRay 데이터
  텔레메트리는 비활성 상태이며 HDL enable generic 기본값도 false를 유지한다.
  `TEST_LCA`는 false이다. BD와 모듈 참조 descriptor는 Vivado로 재생성했다.
- SPI 7.5 MHz는 사용자가 기존에 이상 없이 확인했다고 보고한 설정이다.
  이번 작업에서 10 MHz 시험·보드 프로그래밍·실차 검증은 수행하지 않았다.
- 호스트 수정 지시문: `docs/sunnypilot-flexray-handoff.txt`. 양방향 파서,
  rlog source 번호, 유실 통계, 진단 CAN 바이트 맵과 테스트를 명시했다.
- 추가 시험은 양방향 동시 도착/큐 full/포인터 순환/요청 유지/reset,
  양방향 0~26 및 254바이트 로그의 전체 바이트, 혼합 방향/같은 ID/CRC 불량,
  FIFO 사용량, 진단 스냅샷/CDC/공통 송신기의 CAN CRC·스터핑·외부 ACK를 포함한다.
  에코 모델의 50 ns는 보드 측정값이 아닌 시험 가정이다. 지연 없는 에코 모델은
  기존 전달 로직에서 실패하므로 실제 PHY 지연 범위의 검증을 대체하지 않는다.
- 최종 버전 2/32프레임 FIFO 구성의 `tests/run_all.ps1` 전체 통과:
  12개 스크립트, 15개 test top, 종료 코드 0, `ALL_LOCAL_SIMULATIONS_PASS`.
  로그: `tests/bidirectional_validation.sim/all_tests_packed.log`.
- 두 전체 구현 모두 진단 CAN을 활성화했다. 데이터 텔레메트리만 별도로
  끄거나 켜서 검증했으며, 실제 저장된 소스 BD의 데이터 수집은 비활성이다.

  | 데이터 텔레메트리 | WNS | WHS | setup / hold 실패 endpoint |
  | --- | ---: | ---: | ---: |
  | 비활성 | +0.210 ns | +0.015 ns | 0 / 0 |
  | 검증 프로젝트에서만 활성 | +0.285 ns | +0.010 ns | 0 / 0 |

  결과: `tests/design_0_packed.sim/`, `tests/design_1_packed.sim/`.
  두 구성 모두 RAM 추론 확인, methodology 0건, DRC 오류 0건이다.
  기존 종류의 DRC 경고와 mailbox/async FIFO의 CDC-15 경고는 남아 있으며
  bus skew와 제어 동기화 단계 2개의 scoped constraint 확인은 통과했다.
  외부 I/O 제약의 미완성 범위는 그대로다. 7.5 MHz의 실제 처리 여유와
  차량 CAN 영향에 대한 보드/실차 측정 결과는 이번 검증에 포함하지 않는다.

## 2026-11-03 — 반복 검토: 전달 경로 reset 및 실제 로그 FIFO

- 기준 커밋: `f960425`.
- 재현: dominant 전달/override 중 reset을 걸면 출력 레지스터가 이전 값을
  유지하고 enable도 idle 값으로 돌아가지 않았다. reset에서 TX 두 개, RX,
  enable 두 개를 기존 idle 값 1로 초기화하고 피드백 이력도 1로 채운다.
- 재현: 실제 IP는 `Standard_FIFO`, embedded output register 미사용이다.
  기존 코드는 읽기 요청과 같은 클록에 이전 `dout`을 전달하여 첫 로그 바이트부터
  어긋났다. 읽기 요청 → 완료 데이터 캡처 → 소비 대기 단계를 추가했다.
  마지막 FIFO 읽기로 empty가 되어도 보관된 마지막 바이트를 전달하며, stall 동안
  데이터를 유지하고 reset에서는 보관 상태를 비운다.
- 추가 재현: FIFO 순서를 고친 뒤 로그 프레임 끝에 불필요한 바이트가 남았다.
  serializer가 마지막 CRC를 준비한 시점에 종료 상태로 전환하도록 경계를 수정했다.
- 검증: 저장소의 실제 FIFO XCI에서 시뮬레이션 모델을 생성한다. 양방향 전달과
  override의 warm reset, reset 후 첫 dominant 입력, 0~26바이트 페이로드의
  로그 전체 바이트·정확한 길이·마지막 CRC·stall·reset flush를 확인했다.
  변경 전 재현 로그는 `tests/frontend.sim/before_*_fix.log`에 보관했다.
- 전체 회귀 11개 묶음 통과 (`ALL_LOCAL_SIMULATIONS_PASS`, 종료 코드 0,
  `--rangecheck` 적용). 두 구성의 전체 합성·배치·배선도 통과했다.
  결과 경로는 `tests/design_0_front.sim/`, `tests/design_1_front.sim/`이다.

  | 구성 | WNS | WHS | setup / hold 실패 endpoint |
  | --- | ---: | ---: | ---: |
  | CAN 텔레메트리 비활성 | +0.685 ns | +0.023 ns | 0 / 0 |
  | 검증 프로젝트에서만 활성 | +0.227 ns | +0.020 ns | 0 / 0 |

- 두 구성 모두 methodology 지적 0건, DRC 오류 0건이다. 기존 DRC·CDC 경고와
  별도로 두 routed checkpoint의 CDC 예외·데이터 경로·bus skew 재확인도 통과했다.
  외부 I/O 타이밍 제약의 미완성 범위는 남아 있다. 보드·실차 적용과 비트스트림
  생성은 하지 않았다.

## 2026-11-03 — 반복 검토: SPI 로그의 CS 중단 복구

- 기준 커밋: `fba6445`.
- 재현: SPI mode 0 전송을 바이트 중간에 CS high로 끊고 다시 시작하면,
  이전 비트 카운터와 MOSI로 변형된 공용 shift register가 남아 다음 TX/RX
  바이트가 어긋났다. 변경 전 재현 로그는 `tests/spi.sim/before_fix.log`에 보관했다.
- 수정: CS가 비활성일 때 비트 위치와 마지막 비트 판정을 초기화한다.
  수신 완료·다음 데이터 요청은 선택된 상태에서만 발생하고 reset 중에는 막는다.
- 수정: FIFO에서 미리 받은 TX 바이트를 별도 레지스터로 보관한다. 부분 전송이
  중단되면 다음 CS에서 같은 바이트를 처음부터 재전송한다. 부분 RX는 전달하지 않는다.
  한 바이트를 완료한 뒤 미리 받은 다음 바이트도 CS 경계에서 유지한다.
- 수정: reset 시 shift register·보관 데이터·MISO를 초기화한다. 다음 TX 데이터가
  없으면 0을 내보내며, 공용 shift register에 남은 MOSI를 다시 출력하지 않는다.
- 새 테스트: 1~7비트 각각에서 중단 후 복구, 연속 CS의 바이트 순서와 FIFO 소비 횟수,
  CS 경계의 prefetch 유지, 비선택 상태의 SCLK 무시, TX 소진 시 0 filler, warm reset.
- 검증 상태: 확장 SPI 테스트를 포함한 전체 회귀 10개 묶음이 `--rangecheck`를 켠
  상태에서 통과했다 (`ALL_LOCAL_SIMULATIONS_PASS`, 종료 코드 0).
- 전체 합성·배치·배선도 두 구성 모두 통과했다. 이번 결과는
  `tests/design_0_spi.sim/`, `tests/design_1_spi.sim/`에 보관했다.

  | 구성 | WNS | WHS | setup / hold 실패 endpoint |
  | --- | ---: | ---: | ---: |
  | CAN 텔레메트리 비활성 | +0.749 ns | +0.016 ns | 0 / 0 |
  | 검증 프로젝트에서만 활성 | +0.533 ns | +0.022 ns | 0 / 0 |

- 두 구성 모두 methodology 지적 0건, DRC 오류 0건이다. 기존 DRC·CDC 구조 경고와
  외부 I/O 타이밍 제약의 미완성 범위는 남아 있다. 두 routed checkpoint의 CDC 예외,
  데이터 경로, bus skew 재확인도 통과했다. 보드 프로그래밍, 비트스트림 생성,
  실차 검증은 수행하지 않았다.

## 2026-11-03 — 반복 검토: 프레임 길이 경계와 수신 카운터

- 기준 커밋: `0612b90`.
- 재현: XSim `--rangecheck` 사용 시 긴 정상 프레임에서 `bit_counter` 값
  2048이 선언 범위 0~2047을 초과했다. 범위 검사 없는 실행에서는 같은 입력이
  통과하므로 기존 테스트만으로는 놓칠 수 있었다. 변경 전 재현 로그는 로컬
  `tests/bounds.sim/before_fix.log`에 보관했다.
- 수정: 두 FlexRay 디코더의 BSS 위치 카운터를 0~9 순환 위상으로 바꿨다.
  전체 길이를 저장하지 않아도 기존 `mod 10` 판정과 같고 장시간 TSS에서도 넘치지 않는다.
- 수정: 조향 모듈의 전체 데이터 위치 카운터와 대응 변수를 12비트 범위로 늘렸다.
  최대 페이로드 254바이트에 헤더·CRC·종료부를 더한 위치를 수용한다.
- 수정: TSS 대기 중에는 데이터 인덱스를 증가시키지 않는다. 긴 dominant 입력
  뒤에도 범위 초과 없이 idle과 다음 프레임을 통해 복구한다.
- 검증 강화: 모든 로컬 VHDL 테스트 elaboration에 `--rangecheck`를 적용했다.
  새 `run_bounds_tests.ps1`은 0~127의 모든 페이로드 길이, 긴 프레임의 실제 조향
  변경과 끝 바이트 보존, 최대 길이 CRC 오류 거부, 1 ms stuck-low 후 복구를 검증한다.
- 검증 상태: `--rangecheck`를 적용한 전체 회귀 9개 묶음 통과
  (`ALL_LOCAL_SIMULATIONS_PASS`, 종료 코드 0). 0~127의 모든 페이로드 길이와
  기존 정상 상태 출력 비교를 포함한다.
- 전체 합성·배치·배선도 두 구성 모두 통과했다. 아래 `_r3` 결과와 구분되는
  이번 결과는 `tests/design_0_bounds.sim/`, `tests/design_1_bounds.sim/`에 있다.

  | 구성 | WNS | WHS | setup / hold 실패 endpoint |
  | --- | ---: | ---: | ---: |
  | CAN 텔레메트리 비활성 | +0.560 ns | +0.015 ns | 0 / 0 |
  | 검증 프로젝트에서만 활성 | +0.633 ns | +0.008 ns | 0 / 0 |

- 두 구성 모두 methodology 지적 0건이며 DRC 오류는 없다. 기존 BRAM/LUT/부하
  관련 DRC 경고와 CDC 구조 경고, 외부 I/O 타이밍 제약의 미완성 범위는 유지된다.
  두 routed checkpoint의 CDC 예외 적용·데이터 경로·bus skew 재확인도 통과했다.
  비트스트림 생성이나 보드·실차 적용은 하지 않았다.

## 2026-11-03 — 두 번째 소스 검토 결과 반영

작업 브랜치: `ai`. 저장소 자료와 검증은 로컬에서만 처리했다.
`cantx` 브랜치를 변경하지 않았으며, `TEST_LCA = false`와 CAN 텔레메트리
기본 비활성 설정을 유지한다. 아래 내용은 소스 수정 및 시뮬레이션 결과이며
실차 검증 결과가 아니다.

### 1. 입력 FlexRay CRC 오류 보존

- 문제: 입력 CRC가 틀린 변경 대상 프레임도 새로 계산한 정상 CRC로 출력되어
  수신 측에서 정상 프레임으로 받아들이는 현상을 재현했다.
- 수정: 출력 CRC를 아래와 같이 변환한다. 입력 CRC의 오류 차이가 출력에도 남는다.

  ```text
  CRC 차이 = 원본 헤더·페이로드의 계산 CRC XOR 변경된 데이터의 계산 CRC
  출력 CRC = 수신 CRC XOR CRC 차이
  ```

- 적용 파일: `flexray_torque_intercept.vhd`.
- 검증: CRC의 24개 비트를 각각 반전한 입력, 변경 영역과 미변경 영역의
  페이로드 비트를 CRC 계산 후 반전한 입력을 보낸다. 독립 출력 디코더가 모두
  거부해야 한다. 정상 프레임의 출력 CRC는 계속 유효해야 한다.
- 한계: 스트리밍 변경 방식이므로 입력 전체 검증 전에 일부 데이터가 출력될 수
  있다. 전체 프레임을 버퍼링해 송신을 차단하는 방식은 아니다.

### 2. 캐시 만료와 HUD 갱신 시 프레임 완결성 유지

- 문제: cycle-1 프레임 변경 도중 `cache_1_valid`가 만료되면 변경을 중단하여
  일부 페이로드만 변경되고 CRC가 맞지 않는 프레임이 출력됐다.
- 수정: 캐시 유효 여부와 HUD 명령을 헤더에서 캡처한다. 페이로드·CRC 동안
  동일한 판단과 명령을 사용한다. 헤더 이후의 상태 변화는 다음 프레임에 반영한다.
  기존 enable·동기 상태의 프레임 단위 처리와 같은 정책이다.
- 적용 파일: `flexray_torque_intercept.vhd`.
- 검증: 캐시 수명을 테스트용 600 µs로 줄여 전송 중 만료시키고, 별도로 HUD를
  전송 중 해제해도 현재 프레임의 변경 데이터와 CRC가 끝까지 유효한지 확인한다.
  기본 캐시·동기 수명은 기존 100 ms를 유지한다.

### 3. cycle-3 누락 시 최신 토크 반영

- 문제: 토크를 enable 재진입 때만 저장해 cycle-3이 누락되면 새 명령이 있어도
  이전 토크가 유지됐다. `9000 → 9010` 명령 변경 후 출력이 9000인 것을 재현했다.
- 수정: enable이 유효한 헤더마다 최신 토크를 캡처한다. 페이로드 동안에는
  캡처한 값을 유지하므로 한 프레임에 서로 다른 토크가 섞이지 않는다.
- 적용 파일: `flexray_torque_intercept.vhd`.
- 검증: cycle-3 없이 enable을 계속 유지하고 토크만 9010으로 갱신했을 때 다음
  변경 프레임의 토크 바이트가 `0x2332` 기반 값으로 바뀌는지 확인한다.

### 4. CAN 명령 DLC 검증

- 문제: `0x1F0` 명령이 DLC 5여도 애플리케이션 CRC가 맞으면 조향을 활성화했다.
- 수정: `0x1F0` 토크 명령과 `0x1F9` HUD 명령 모두 DLC 8과 애플리케이션 CRC를
  통과해야 데이터를 갱신한다. 잘못된 명령은 enable을 해제하고 토크·HUD 값은
  갱신하지 않는다. HUD 상태 감시 갱신도 기존 길이·CRC·카운터 검사를 유지한다.
- 적용 파일: `joystick_decoder.vhd`.
- 검증: DLC 0~7 토크 명령의 거부, DLC 8 명령의 수락, 짧은 HUD의 갱신 거부와
  정상 길이 HUD의 갱신을 확인한다.

### 회귀 테스트 및 검증 상태

```powershell
./tests/run_remaining_review.ps1
./tests/run_all.ps1
```

- `review_remaining_tb.vhd`: 기존 결함 재현을 수정 후 기대 동작 검증으로 전환했다.
- `review_can_length_tb.vhd`: 잘못된 DLC 거부와 정상 명령 수락을 검증한다.
- 새 테스트는 `run_all.ps1`에 포함했다.
- 과거 소스와의 직렬 출력 비교는 동일한 토크 명령을 유지하는 정상 상태를 비교한다.
  헤더별 토크 갱신은 의도적으로 달라진 동작이므로 별도 회귀 테스트로 검증한다.
- 전체 회귀 실행 통과: `run_all.ps1` 종료 코드 0,
  `ALL_LOCAL_SIMULATIONS_PASS` 확인. CAN 진단·프로토콜·큐·통합,
  정상 상태 출력 비교, 제어 mailbox, 기존 검토 회귀, 이번 추가 회귀의
  8개 테스트 묶음을 모두 실행했다.
- 수정 후 전체 합성·배치·배선 보고서의 내부 타이밍 결과:

  | 구성 | WNS | WHS | setup / hold 실패 endpoint |
  | --- | ---: | ---: | ---: |
  | CAN 텔레메트리 비활성 | +0.741 ns | +0.015 ns | 0 / 0 |
  | 검증 프로젝트에서만 활성 | +0.477 ns | +0.015 ns | 0 / 0 |

- Vivado 2024.2, `xa7s50csga324-1Q`, 결과 경로:
  `tests/design_0_r3.sim/`, `tests/design_1_r3.sim/`.
  이전 `_r2` 결과와 구분해 이번 수정 소스를 별도로 합성했다.
- 두 구성 모두 methodology 지적 0건, DRC 오류 0건이다. BRAM 비동기 제어,
  LUT 배치, 부하 없는 넷에 대한 DRC 경고와 CDC 구조 경고는 남아 있다.
  두 routed checkpoint에서 CDC 제약의 적용 범위·데이터 경로·bus skew
  재확인도 통과했다. 제어 mailbox의 첫 동기화 단계 2개, 유지 데이터 24비트,
  최적화 후 전달 데이터 22비트를 확인했다. bus skew 위반은 없었다.

비트스트림 생성, 보드 프로그래밍, 실차 시험은 수행하지 않았다. CAN 송수신 코어의
기존 프로토콜 제한과 외부 I/O 타이밍 제약의 미완성 범위는 README에 기록되어 있다.
