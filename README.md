# SRTgo: K-Train (KTX, SRT) Reservation Macro

- ⚠️본 프로그램의 모든 상업적, 영리적 이용을 엄격히 금지합니다. 본 프로그램 사용에 따른 민형사상 책임을 포함한 모든 책임은 사용자에게 따르며, 본 프로그램의 개발자는 민형사상 책임을 포함한 어떠한 책임도 부담하지 아니합니다. 📥본 프로그램을 다운받음으로서 모든 사용자는 위 사항에 아무런 이의 없이 동의하는 것으로 간주됩니다.
- SRT 및 KTX 기차표 예매를 자동화하는 매크로입니다.
- 아이디, 비번, 카드번호, 예매 설정 등은 로컬 컴퓨터에 [keyring 모듈](https://pypi.org/project/keyring/)을 통하여 저장하며 공유되지 않습니다.
- 예약이 완료되면 텔레그램 알림을 전송합니다.
  - [Bot Token 및 Chat Id 얻기](https://gabrielkim.tistory.com/entry/Telegram-Bot-Token-%EB%B0%8F-Chat-Id-%EC%96%BB%EA%B8%B0).
- 예매 확인/취소의 경우 SRT는 모든 티켓을, KTX는 결제하지 않은 티켓만 확인 취소 할 수 있습니다.
- SRT의 경우 신용카드 정보를 입력해두면, 예매 직후에 결제되도록 할 수 있습니다.
- [New] **계정 다중 관리:** 여러 개의 계정을 별명으로 구분하여 저장하고 선택할 수 있습니다.
- [New] **예매 방식 선택:** 즉시 시작 또는 특정 시간 예약 실행을 선택할 수 있습니다.
- [New] **자동 종료 옵션:** 예매 성공 또는 시간 초과 시 컴퓨터를 자동으로 종료할 수 있습니다.

---

SRTgo is:

- This module is designed to automate the reservation of SRT and KTX train tickets.
- Through the keyring module, the information such as username, password, credit card, departure station, and arrival station is stored on the local computer.
- After the reservation is completed, a Telegram notification will be sent.
- In the case of reservation confirmation/cancellation, for SRT, all tickets can be confirmed or canceled, while for KTX, only unpaid tickets can be confirmed or canceled.

## Installation / Update

```bash
pip install srtgo -U
```

## start srtgo

```bash
python -m srtgo.srtgo
# 또는
srtgo
```

## Using SRTgo

### 1. 메인 메뉴
```bash
[?] 메뉴 선택 (↕:이동, Enter: 선택):
 > 예매 시작
   예매 확인/결제/취소
   로그인 설정
   텔레그램 설정
   카드 설정
   역 설정
   역 직접 수정
   예매 옵션 설정
   기타 설정
   나가기
```

### 2. 예매 방식 선택 (New)
*   **🚀 바로 예매:** 설정을 마치는 즉시 예매 시도를 시작합니다.
*   **⏰ 예약 실행:** 예매 시도를 시작할 시간을 지정합니다 (예: 명절 예매 등 특정 시간 오픈 대비).

### 3. 주요 설정
*   **로그인 설정:** 여러 계정을 별명(alias)으로 등록하고 전환하며 사용할 수 있습니다.
*   **카드 설정:** 결제에 사용할 카드를 별명으로 등록합니다. 예매 성공 시 자동 결제 여부를 선택할 수 있습니다.
*   **기타 설정:** 예매 지속 시간(분) 설정 및 작업 완료 후 컴퓨터 자동 종료 여부를 설정할 수 있습니다.

---

## Acknowledgments

This project is heavily dependent on [SRT](https://github.com/ryanking13/SRT) and [korail2](https://github.com/carpedm20/korail2).

## Development Log

### 2026-01-18: Python to Flutter Conversion Initiative

**Objective:**
Convert the existing Python-based CLI tool (`srtgo`) into a cross-platform mobile application (`srtgo_mobile`) using Flutter, targeting Android and iOS users.

**Architectural Strategy:**
- **Feature-First Structure:** organized by functional modules (auth, reservation, settings).
- **Global State Management:** `Riverpod` for business logic and session management.
- **UI State Management:** `ValueNotifier` for lightweight UI-only states (toggles, loading indicators).
- **Core Logic:** Analyze Python implementations (`SRT`, `Korail`) and port HTTP/Encryption logic to Dart.
- **Cross-Platform UI:** Modern Material Design 3 interface with a global SRT/KTX switch.

**Current Status:**
- `srtgo_mobile` project initialized.
- Python source code analysis (`srtgo.py`, `srt.py`, `ktx.py`) completed.
- CLI workflow mapped to mobile UX requirements.
- **Authentication Core:** SRT and KTX (AES Encrypted) login fully implemented.
- **Network Layer:** Session persistence and NetFunnel (Waiting list) logic ported.
- **UI:** Home Dashboard and Reservation Form (Station/Date/Time/Passenger) implemented.
- Next Step: Implement Train Search API and Result List UI.
