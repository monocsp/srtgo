from curl_cffi.requests.exceptions import ConnectionError
from datetime import datetime, timedelta
from json.decoder import JSONDecodeError
from random import gammavariate
from termcolor import colored
from typing import Awaitable, Callable, List, Optional, Tuple, Union

import asyncio
import click
import inquirer
import keyring
import telegram
import time
import re
from . import scheduler 

from .ktx import (
    Korail,
    KorailError,
    ReserveOption,
    TrainType,
    AdultPassenger,
    ChildPassenger,
    SeniorPassenger,
    Disability1To3Passenger,
    Disability4To6Passenger,
)

from .srt import (
    SRT,
    SRTError,
    SRTNetFunnelError,
    SeatType,
    Adult,
    Child,
    Senior,
    Disability1To3,
    Disability4To6,
)

from .accounts import list_aliases, add_account, get_account_credentials
from .cards import list_card_aliases, add_card as add_card_info, get_card_credentials as get_card_info, remove_card as remove_card_info



STATIONS = {
    "SRT": [
        "수서",
        "동탄",
        "평택지제",
        "경주",
        "곡성",
        "공주",
        "광주송정",
        "구례구",
        "김천(구미)",
        "나주",
        "남원",
        "대전",
        "동대구",
        "마산",
        "목포",
        "밀양",
        "부산",
        "서대구",
        "순천",
        "여수EXPO",
        "여천",
        "오송",
        "울산(통도사)",
        "익산",
        "전주",
        "정읍",
        "진영",
        "진주",
        "창원",
        "창원중앙",
        "천안아산",
        "포항",
    ],
    "KTX": [
        "서울",
        "용산",
        "영등포",
        "광명",
        "수원",
        "천안아산",
        "오송",
        "대전",
        "서대전",
        "김천구미",
        "동대구",
        "경주",
        "포항",
        "밀양",
        "구포",
        "부산",
        "울산(통도사)",
        "마산",
        "창원중앙",
        "경산",
        "논산",
        "익산",
        "정읍",
        "광주송정",
        "목포",
        "전주",
        "순천",
        "여수EXPO",
        "청량리",
        "강릉",
        "행신",
        "정동진",
    ],
}
DEFAULT_STATIONS = {
    "SRT": ["수서", "대전", "동대구", "부산"],
    "KTX": ["서울", "대전", "동대구", "부산"],
}

# 예약 간격 (평균 간격 (초) = SHAPE * SCALE): gamma distribution (1.25 +/- 0.25 s)
RESERVE_INTERVAL_SHAPE = 4
RESERVE_INTERVAL_SCALE = 0.25
RESERVE_INTERVAL_MIN = 0.25

WAITING_BAR = ["|", "/", "-", "\\"]

RailType = Union[str, None]
ChoiceType = Union[int, None]


@click.command()
@click.option("--debug", is_flag=True, help="Debug mode")
def srtgo(debug=False):
    MENU_CHOICES = [
        ("예매 시작", 1),
        ("예매 확인/결제/취소", 2),
        ("로그인 설정", 3),
        ("텔레그램 설정", 4),
        ("카드 설정", 5),
        ("역 설정", 6),
        ("역 직접 수정", 7),
        ("예매 옵션 설정", 8),
        ("기타 설정", 9),
        ("나가기", -1),
    ]

    RAIL_CHOICES = [
        (colored("SRT", "red"), "SRT"),
        (colored("KTX", "cyan"), "KTX"),
        ("취소", -1),
    ]

    ACTIONS = {
        1: lambda rt: pre_check_reserve(rt, debug), 
        2: lambda rt: check_reservation(rt, debug),
        3: lambda rt: login_menu(rt, debug),
        4: lambda _: set_telegram(),
        5: lambda _: set_card(),
        6: lambda rt: set_station(rt),
        7: lambda rt: edit_station(rt),
        8: lambda _: set_options(),
        9: lambda _: set_misc_options(),
    }

    while True:
        choice = inquirer.list_input(
            message="메뉴 선택 (↕:이동, Enter: 선택)", choices=MENU_CHOICES
        )

        if choice == -1:
            break

        if choice in {1, 2, 3, 6, 7}:
            rail_type = inquirer.list_input(
                message="열차 선택 (↕:이동, Enter: 선택, Ctrl-C: 취소)",
                choices=RAIL_CHOICES,
            )
            if rail_type in {-1, None}:
                continue
        else:
            rail_type = None

        action = ACTIONS.get(choice)
        if action:
            action(rail_type)
            
def pre_check_reserve(rail_type, debug):
    """
    예매 시작 전, '바로 예매'인지 '예약 실행'인지 선택
    """
    mode = inquirer.list_input(
        message="예매 방식을 선택하세요",
        choices=[
            ("🚀 바로 예매 (지금 즉시 시작)", False),    # False 반환
            ("⏰ 예약 실행 (설정 후 특정 시간에 시작)", True) # True 반환
        ]
    )

    # 선택한 모드(True/False)를 reserve 함수로 전달
    reserve(rail_type, debug, is_schedule_mode=mode)

def set_station(rail_type: RailType) -> bool:
    stations, default_station_key = get_station(rail_type)

    if not (
        station_info := inquirer.prompt(
            [
                inquirer.Checkbox(
                    "stations",
                    message="역 선택 (↕:이동, Space: 선택, Enter: 완료, Ctrl-A: 전체선택, Ctrl-R: 선택해제, Ctrl-C: 취소)",
                    choices=stations,
                    default=default_station_key,
                )
            ]
        )
    ):
        return False

    if not (selected := station_info["stations"]):
        print("선택된 역이 없습니다.")
        return False

    keyring.set_password(
        rail_type, "station", (selected_stations := ",".join(selected))
    )
    print(f"선택된 역: {selected_stations}")
    return True


def edit_station(rail_type: RailType) -> bool:
    stations, default_station_key = get_station(rail_type)
    station_info = inquirer.prompt(
        [
            inquirer.Text(
                "stations",
                message="역 수정 (예: 수서,대전,동대구)",
                default=keyring.get_password(rail_type, "station") or "",
            )
        ]
    )
    if not station_info:
        return False

    if not (selected := station_info["stations"]):
        print("선택된 역이 없습니다.")
        return False

    selected = [s.strip() for s in selected.split(",")]

    # Verify all stations contain Korean characters
    hangul = re.compile("[가-힣]+")
    for station in selected:
        if not hangul.search(station):
            print(f"'{station}'는 잘못된 입력입니다. 기본 역으로 설정합니다.")
            selected = DEFAULT_STATIONS[rail_type]
            break

    keyring.set_password(
        rail_type, "station", (selected_stations := ",".join(selected))
    )
    print(f"선택된 역: {selected_stations}")
    return True


def get_station(rail_type: RailType) -> Tuple[List[str], List[int]]:
    stations = STATIONS[rail_type]
    station_key = keyring.get_password(rail_type, "station")

    if not station_key:
        return stations, DEFAULT_STATIONS[rail_type]

    valid_keys = [x for x in station_key.split(",")]
    return stations, valid_keys


def set_options():
    default_options = get_options()
    choices = inquirer.prompt(
        [
            inquirer.Checkbox(
                "options",
                message="예매 옵션 선택 (Space: 선택, Enter: 완료, Ctrl-A: 전체선택, Ctrl-R: 선택해제, Ctrl-C: 취소)",
                choices=[
                    ("어린이", "child"),
                    ("경로우대", "senior"),
                    ("중증장애인", "disability1to3"),
                    ("경증장애인", "disability4to6"),
                    ("KTX만", "ktx"),
                ],
                default=default_options,
            )
        ]
    )

    if choices is None:
        return

    options = choices.get("options", [])
    keyring.set_password("SRT", "options", ",".join(options))


def get_options():
    options = keyring.get_password("SRT", "options") or ""
    return options.split(",") if options else []


def set_telegram() -> bool:
    token = keyring.get_password("telegram", "token") or ""
    chat_id = keyring.get_password("telegram", "chat_id") or ""

    telegram_info = inquirer.prompt(
        [
            inquirer.Text(
                "token",
                message="텔레그램 token (Enter: 완료, Ctrl-C: 취소)",
                default=token,
            ),
            inquirer.Text(
                "chat_id",
                message="텔레그램 chat_id (Enter: 완료, Ctrl-C: 취소)",
                default=chat_id,
            ),
        ]
    )
    if not telegram_info:
        return False

    token, chat_id = telegram_info["token"], telegram_info["chat_id"]

    try:
        keyring.set_password("telegram", "ok", "1")
        keyring.set_password("telegram", "token", token)
        keyring.set_password("telegram", "chat_id", chat_id)
        tgprintf = get_telegram()
        asyncio.run(tgprintf("[SRTGO] 텔레그램 설정 완료"))
        return True
    except Exception as err:
        print(err)
        keyring.delete_password("telegram", "ok")
        return False


def get_telegram() -> Optional[Callable[[str], Awaitable[None]]]:
    token = keyring.get_password("telegram", "token")
    chat_id = keyring.get_password("telegram", "chat_id")

    async def tgprintf(text):
        if token and chat_id:
            bot = telegram.Bot(token=token)
            async with bot:
                await bot.send_message(chat_id=chat_id, text=text)

    return tgprintf


# def set_card() -> None:
#     card_info = {
#         "number": keyring.get_password("card", "number") or "",
#         "password": keyring.get_password("card", "password") or "",
#         "birthday": keyring.get_password("card", "birthday") or "",
#         "expire": keyring.get_password("card", "expire") or "",
#     }

#     card_info = inquirer.prompt(
#         [
#             inquirer.Password(
#                 "number",
#                 message="신용카드 번호 (하이픈 제외(-), Enter: 완료, Ctrl-C: 취소)",
#                 default=card_info["number"],
#             ),
#             inquirer.Password(
#                 "password",
#                 message="카드 비밀번호 앞 2자리 (Enter: 완료, Ctrl-C: 취소)",
#                 default=card_info["password"],
#             ),
#             inquirer.Password(
#                 "birthday",
#                 message="생년월일 (YYMMDD) / 사업자등록번호 (Enter: 완료, Ctrl-C: 취소)",
#                 default=card_info["birthday"],
#             ),
#             inquirer.Password(
#                 "expire",
#                 message="카드 유효기간 (YYMM, Enter: 완료, Ctrl-C: 취소)",
#                 default=card_info["expire"],
#             ),
#         ]
#     )
#     if card_info:
#         for key, value in card_info.items():
#             keyring.set_password("card", key, value)
#         keyring.set_password("card", "ok", "1")
def set_card() -> None:
    
    # 1) 민감 정보 입력
    info = inquirer.prompt([
        inquirer.Text("number",   message="신용카드 번호 (하이픈 제외)"),
        inquirer.Text("password", message="카드 비밀번호 앞 2자리"),
        inquirer.Text("birthday", message="생년월일 (YYMMDD) 또는 사업자등록번호"),
        inquirer.Text("expire",   message="카드 유효기간 (YYMM)"),
        inquirer.Text("alias",    message="별명 (ex: 회사, 개인)"),
    ])
    if not info:
        return

    # 2) 카드정보 Keyring + alias JSON 저장
    try:
        add_card_info(
            info["alias"],
            info["number"],
            info["password"],
            info["birthday"],
            info["expire"],
        )
        print(f"✅ 카드 '{info['alias']}' 등록 완료")
    except Exception as e:
        print(f"❌ 카드 등록 실패: {e}")



def pay_card(rail, reservation) -> bool:
    if keyring.get_password("card", "ok"):
        birthday = keyring.get_password("card", "birthday")
        return rail.pay_with_card(
            reservation,
            keyring.get_password("card", "number"),
            keyring.get_password("card", "password"),
            birthday,
            keyring.get_password("card", "expire"),
            0,
            "J" if len(birthday) == 6 else "S",
        )
    return False


def login(rail_type: str = "SRT", debug: bool = False):
    credentials = {
        "id": keyring.get_password(rail_type, "id") or "",
        "pass": keyring.get_password(rail_type, "pass") or "",
    }

    login_info = inquirer.prompt(
        [
            inquirer.Text(
                "id",
                message=f"{rail_type} 계정 아이디 (멤버십 번호, 이메일, 전화번호)",
                default=credentials["id"],
            ),
            inquirer.Password(
                "pass",
                message=f"{rail_type} 계정 패스워드",
                default=credentials["pass"],
            ),
        ]
    )
    if not login_info:
        return False

    try:
        SRT(
            login_info["id"], login_info["pass"], verbose=debug
        ) if rail_type == "SRT" else Korail(
            login_info["id"], login_info["pass"], verbose=debug
        )

        keyring.set_password(rail_type, "id", login_info["id"])
        keyring.set_password(rail_type, "pass", login_info["pass"])
        keyring.set_password(rail_type, "ok", "1")
        return True
    except SRTError as err:
        print(err)
        keyring.delete_password(rail_type, "ok")
        return False


# def login(rail_type="SRT", debug=False):
#     if (
#         keyring.get_password(rail_type, "id") is None
#         or keyring.get_password(rail_type, "pass") is None
#     ):
#         set_login(rail_type)

#     user_id = keyring.get_password(rail_type, "id")
#     password = keyring.get_password(rail_type, "pass")

#     rail = SRT if rail_type == "SRT" else Korail
#     return rail(user_id, password, verbose=debug)

def login(rail_type: str = "SRT", debug: bool = False, auto_alias: str = None): # [수정] auto_alias 추가
    """
    JSON 에 저장된 alias 목록을 보여주고,
    선택된 계정 정보로 Rail 인스턴스 생성·반환.
    """
    rail_cls = SRT if rail_type == "SRT" else Korail

    # [추가] 자동 로그인 모드일 경우 메뉴 스킵
    if auto_alias:
        chosen = auto_alias
    else:
        # 1) alias 선택 또는 새 계정 추가 (alias 문자열 or None 반환)
        chosen = login_menu(rail_type, debug)

    if not chosen:
        # 사용자가 '돌아가기'를 선택했거나 오류 발생
        raise RuntimeError("로그인이 취소되었습니다.")

    # 2) 선택된 alias 로 바로 Rail 인스턴스 생성
    user_id, password = get_account_credentials(rail_type, chosen)
    return (SRT if rail_type=="SRT" else Korail)(
        user_id, password, verbose=debug
    )


# [수정] 인자 변경: scheduled_dt -> is_schedule_mode (기본값 False)
def reserve(rail_type="SRT", debug=False, is_schedule_mode=False):
    # 1. 재로그인을 위해 계정 정보를 미리 확보
    current_alias = login_menu(rail_type, debug)
    if not current_alias:
        return

    # 2. 로그인 수행
    user_id, password = get_account_credentials(rail_type, current_alias)
    rail = (SRT if rail_type == "SRT" else Korail)(user_id, password, verbose=debug)
    
    is_srt = rail_type == "SRT"

    # --- (기존 입력 로직 생략 없이 그대로 유지) ---
    # ... departure, arrival, date, time, adult 등 defaults 설정 ...
    # ... stations, station_key 가져오기 ...
    # ... date_choices, time_choices 생성 ...
    # ... q_info 생성 및 inquirer.prompt 실행 ...
    # ... info 검증 및 keyring 저장 ...
    # ... passengers 리스트 생성 ...
    # ... search_train 및 열차 선택 ...
    # ... 좌석 타입 및 카드 결제 여부(options) 선택 ...
    # ... pay_now 및 selected_card_alias 설정 ...
    
    # (위쪽 코드는 기존과 완전히 동일하므로 생략했습니다. 카드 선택 부분까지 쭉 진행됩니다.)

    # =========================================================================
    # [기존 코드의 이 부분부터 수정/추가 됩니다]
    # 카드 선택 로직 (기존 코드 참고용)
    now = datetime.now() + timedelta(minutes=10)
    today = now.strftime("%Y%m%d")
    this_time = now.strftime("%H%M%S")

    defaults = {
        "departure": keyring.get_password(rail_type, "departure")
        or ("수서" if is_srt else "서울"),
        "arrival": keyring.get_password(rail_type, "arrival") or "동대구",
        "date": keyring.get_password(rail_type, "date") or today,
        "time": keyring.get_password(rail_type, "time") or "120000",
        "adult": int(keyring.get_password(rail_type, "adult") or 1),
        "child": int(keyring.get_password(rail_type, "child") or 0),
        "senior": int(keyring.get_password(rail_type, "senior") or 0),
        "disability1to3": int(keyring.get_password(rail_type, "disability1to3") or 0),
        "disability4to6": int(keyring.get_password(rail_type, "disability4to6") or 0),
    }

    if defaults["departure"] == defaults["arrival"]:
        defaults["arrival"] = (
            "동대구" if defaults["departure"] in ("수서", "서울") else None
        )
        defaults["departure"] = (
            defaults["departure"]
            if defaults["arrival"]
            else ("수서" if is_srt else "서울")
        )

    stations, station_key = get_station(rail_type)
    options = get_options()

    date_choices = [
        (
            (now + timedelta(days=i)).strftime("%Y/%m/%d %a"),
            (now + timedelta(days=i)).strftime("%Y%m%d"),
        )
        for i in range(28)
    ]
    time_choices = [(f"{h:02d}", f"{h:02d}0000") for h in range(24)]

    q_info = [
        inquirer.List(
            "departure",
            message="출발역 선택 (↕:이동, Enter: 선택, Ctrl-C: 취소)",
            choices=station_key,
            default=defaults["departure"],
        ),
        inquirer.List(
            "arrival",
            message="도착역 선택 (↕:이동, Enter: 선택, Ctrl-C: 취소)",
            choices=station_key,
            default=defaults["arrival"],
        ),
        inquirer.List(
            "date",
            message="출발 날짜 선택 (↕:이동, Enter: 선택, Ctrl-C: 취소)",
            choices=date_choices,
            default=defaults["date"],
        ),
        inquirer.List(
            "time",
            message="출발 시각 선택 (↕:이동, Enter: 선택, Ctrl-C: 취소)",
            choices=time_choices,
            default=defaults["time"],
        ),
        inquirer.List(
            "adult",
            message="성인 승객수 (↕:이동, Enter: 선택, Ctrl-C: 취소)",
            choices=range(10),
            default=defaults["adult"],
        ),
    ]

    passenger_types = {
        "child": "어린이",
        "senior": "경로우대",
        "disability1to3": "1~3급 장애인",
        "disability4to6": "4~6급 장애인",
    }

    passenger_classes = {
        "adult": Adult if is_srt else AdultPassenger,
        "child": Child if is_srt else ChildPassenger,
        "senior": Senior if is_srt else SeniorPassenger,
        "disability1to3": Disability1To3 if is_srt else Disability1To3Passenger,
        "disability4to6": Disability4To6 if is_srt else Disability4To6Passenger,
    }

    PASSENGER_TYPE = {
        passenger_classes["adult"]: "어른/청소년",
        passenger_classes["child"]: "어린이",
        passenger_classes["senior"]: "경로우대",
        passenger_classes["disability1to3"]: "1~3급 장애인",
        passenger_classes["disability4to6"]: "4~6급 장애인",
    }

    for key, label in passenger_types.items():
        if key in options:
            q_info.append(
                inquirer.List(
                    key,
                    message=f"{label} 승객수 (↕:이동, Enter: 선택, Ctrl-C: 취소)",
                    choices=range(10),
                    default=defaults[key],
                )
            )

    info = inquirer.prompt(q_info)

    if not info:
        print(colored("예매 정보 입력 중 취소되었습니다", "green", "on_red") + "\n")
        return

    if info["departure"] == info["arrival"]:
        print(colored("출발역과 도착역이 같습니다", "green", "on_red") + "\n")
        return

    for key, value in info.items():
        keyring.set_password(rail_type, key, str(value))

    if info["date"] == today and int(info["time"]) < int(this_time):
        info["time"] = this_time

    passengers = []
    total_count = 0
    for key, cls in passenger_classes.items():
        if key in info and info[key] > 0:
            passengers.append(cls(info[key]))
            total_count += info[key]

    if not passengers:
        print(colored("승객수는 0이 될 수 없습니다", "green", "on_red") + "\n")
        return

    if total_count >= 10:
        print(colored("승객수는 10명을 초과할 수 없습니다", "green", "on_red") + "\n")
        return

    msg_passengers = [
        f"{PASSENGER_TYPE[type(passenger)]} {passenger.count}명"
        for passenger in passengers
    ]
    print(*msg_passengers)

    params = {
        "dep": info["departure"],
        "arr": info["arrival"],
        "date": info["date"],
        "time": info["time"],
        "passengers": [passenger_classes["adult"](total_count)],
        **(
            {"available_only": False}
            if is_srt
            else {
                "include_no_seats": True,
                **({"train_type": TrainType.KTX} if "ktx" in options else {}),
            }
        ),
    }

    trains = rail.search_train(**params)

    def train_decorator(train):
        msg = train.__repr__()
        return (
            msg.replace("예약가능", colored("가능", "green"))
            .replace("가능", colored("가능", "green"))
            .replace("신청하기", colored("가능", "green"))
        )

    if not trains:
        print(colored("예약 가능한 열차가 없습니다", "green", "on_red") + "\n")
        return

    q_choice = [
        inquirer.Checkbox(
            "trains",
            message="예약할 열차 선택 (↕:이동, Space: 선택, Enter: 완료, Ctrl-A: 전체선택, Ctrl-R: 선택해제, Ctrl-C: 취소)",
            choices=[(train_decorator(train), i) for i, train in enumerate(trains)],
            default=None,
        ),
    ]

    choice = inquirer.prompt(q_choice)
    if choice is None or not choice["trains"]:
        print(colored("선택한 열차가 없습니다!", "green", "on_red") + "\n")
        return

    n_trains = len(choice["trains"])

    seat_type = SeatType if is_srt else ReserveOption
    q_options = [
        inquirer.List(
            "type",
            message="선택 유형",
            choices=[
                ("일반실 우선", seat_type.GENERAL_FIRST),
                ("일반실만", seat_type.GENERAL_ONLY),
                ("특실 우선", seat_type.SPECIAL_FIRST),
                ("특실만", seat_type.SPECIAL_ONLY),
            ],
        ),
        inquirer.List(
            "pay",
            message="예매 시 카드 결제",
            choices=[("네", True), ("아니오", False)],
            default=False,
        ),
    ]

    options = inquirer.prompt(q_options)
    if options is None:
        print(colored("예매 정보 입력 중 취소되었습니다", "green", "on_red") + "\n")
        return
    
    pay_now = options.get("pay", False)
    selected_card_alias = None
    if pay_now:
        aliases = list_card_aliases()
        if not aliases:
            print("등록된 카드가 없습니다. 카드 설정 메뉴에서 먼저 등록하세요.")
            return
        
        card_q = [
            inquirer.List(
                "alias",
                message="결제할 카드 선택 (↕:이동, Enter:선택)",
                choices=aliases,
            )
        ]
        answer = inquirer.prompt(card_q)
        if not answer or "alias" not in answer:
            print("카드를 선택하지 않아 예매를 취소합니다.")
            return
        selected_card_alias = answer["alias"]
        
    # =========================================================================
    # [수정된 부분] 설정 완료 후 예약 모드 처리 및 종료 여부 확인
    
    should_shutdown = False

    if is_schedule_mode:
        # 1. 예약 시간 선택 (설정이 끝난 현재 시점 기준)
        scheduled_dt = scheduler.select_schedule_time()
        if not scheduled_dt:
            print("예약 실행이 취소되었습니다.")
            return
        
        # 2. 종료 여부 묻기
        should_shutdown = scheduler.ask_shutdown()

        # 3. 대기
        scheduler.wait_until(scheduled_dt)
        
        # 4. 재로그인
        print("\n🔄 세션 갱신을 위해 재로그인을 시도합니다...")
        try:
            rail = (SRT if rail_type == "SRT" else Korail)(user_id, password, verbose=debug)
            print("✅ 재로그인 성공! 예매를 시작합니다.")
        except Exception as e:
            print(f"❌ 재로그인 실패: {e}")
            return
    # =========================================================================

    def _reserve(train):
        reserve = rail.reserve(train, passengers=passengers, option=options["type"])
        msg = f"{reserve}"
        if hasattr(reserve, "tickets") and reserve.tickets:
            msg += "\n" + "\n".join(map(str, reserve.tickets))

        print(colored(f"\n\n🎫 🎉 예매 성공!!! 🎉 🎫\n{msg}\n", "red", "on_green"))

        if pay_now and not reserve.is_waiting:
            num, pw, bd, exp = get_card_info(selected_card_alias)
            ok = rail.pay_with_card(
                reserve,
                num, pw, bd, exp,
                0,
                "J" if len(bd) == 6 else "S",
            )
            if ok:
                print(colored("\n\n💳 ✨ 결제 성공!!! ✨ 💳\n\n", "green", "on_red"), end="")
                msg += "\n결제 완료"

        tgprintf = get_telegram()
        asyncio.run(tgprintf(msg))
        
        # [추가] 예약 성공 시 종료 옵션이 켜져있으면 컴퓨터 종료
        if should_shutdown:
            scheduler.shutdown_computer()

    # Reservation loop (기존과 동일)
    i_try = 0
    start_time = time.time()
    while True:
        try:
            i_try += 1
            elapsed_time = time.time() - start_time
            hours, remainder = divmod(int(elapsed_time), 3600)
            minutes, seconds = divmod(remainder, 60)
            print(
                f"\r예매 대기 중... {WAITING_BAR[i_try & 3]} {i_try:4d} ({hours:02d}:{minutes:02d}:{seconds:02d}) ",
                end="",
                flush=True,
            )

            trains = rail.search_train(**params)
            for i in choice["trains"]:
                if _is_seat_available(trains[i], options["type"], rail_type):
                    _reserve(trains[i])
                    return
            _sleep()
            
        except KeyboardInterrupt:
            print("\n🛑 예매를 중단합니다. 메인 메뉴로 돌아갑니다.")
            return
        except SRTError as ex:
            msg = ex.msg
            if "정상적인 경로로 접근 부탁드립니다" in msg or isinstance(
                ex, SRTNetFunnelError
            ):
                if debug:
                    print(f"\nException: {ex}\nType: {type(ex)}\nArgs: {ex.args}\nMessage: {msg}")
                rail.clear()
            elif "로그인 후 사용하십시오" in msg:
                if debug:
                    print(f"\nException: {ex}\nType: {type(ex)}\nArgs: {ex.args}\nMessage: {msg}")
                try:
                     rail = (SRT if rail_type == "SRT" else Korail)(user_id, password, verbose=debug)
                except:
                     pass

                if not rail.is_login and not _handle_error(ex):
                    return
            elif not any(
                err in msg
                for err in (
                    "잔여석없음",
                    "사용자가 많아 접속이 원활하지 않습니다",
                    "예약대기 접수가 마감되었습니다",
                    "예약대기자한도수초과",
                )
            ):
                if not _handle_error(ex):
                    return
            _sleep()

        except KorailError as ex:
            msg = ex.msg
            if "Need to Login" in msg:
                try:
                     rail = (SRT if rail_type == "SRT" else Korail)(user_id, password, verbose=debug)
                except:
                     pass
                if not rail.is_login and not _handle_error(ex):
                    return
            elif not any(
                err in msg
                for err in ("Sold out", "잔여석없음", "예약대기자한도수초과")
            ):
                if not _handle_error(ex):
                    return
            _sleep()

        except JSONDecodeError as ex:
            if debug:
                print(f"\nException: {ex}\nType: {type(ex)}\nArgs: {ex.args}\nMessage: {ex.msg}")
            _sleep()
            try:
                 rail = (SRT if rail_type == "SRT" else Korail)(user_id, password, verbose=debug)
            except:
                 pass

        except ConnectionError as ex:
            if not _handle_error(ex, "연결이 끊겼습니다"):
                return
            try:
                 rail = (SRT if rail_type == "SRT" else Korail)(user_id, password, verbose=debug)
            except:
                 pass

        except Exception as ex:
            if debug:
                print("\nUndefined exception")
            if not _handle_error(ex):
                return
            try:
                 rail = (SRT if rail_type == "SRT" else Korail)(user_id, password, verbose=debug)
            except:
                 pass


def _sleep():
    time.sleep(
        gammavariate(RESERVE_INTERVAL_SHAPE, RESERVE_INTERVAL_SCALE)
        + RESERVE_INTERVAL_MIN
    )


def _handle_error(ex, msg=None):
    msg = (
        msg
        or f"\nException: {ex}, Type: {type(ex)}, Message: {ex.msg if hasattr(ex, 'msg') else 'No message attribute'}"
    )
    print(msg)
    tgprintf = get_telegram()
    asyncio.run(tgprintf(msg))
    return inquirer.confirm(message="계속할까요", default=True)


def _is_seat_available(train, seat_type, rail_type):
    if rail_type == "SRT":
        if not train.seat_available():
            return train.reserve_standby_available()
        if seat_type in [SeatType.GENERAL_FIRST, SeatType.SPECIAL_FIRST]:
            return train.seat_available()
        if seat_type == SeatType.GENERAL_ONLY:
            return train.general_seat_available()
        return train.special_seat_available()
    else:
        if not train.has_seat():
            return train.has_waiting_list()
        if seat_type in [ReserveOption.GENERAL_FIRST, ReserveOption.SPECIAL_FIRST]:
            return train.has_seat()
        if seat_type == ReserveOption.GENERAL_ONLY:
            return train.has_general_seat()
        return train.has_special_seat()


def check_reservation(rail_type="SRT", debug=False):
    rail = login(rail_type, debug=debug)

    while True:
        reservations = (
            rail.get_reservations() if rail_type == "SRT" else rail.reservations()
        )
        tickets = [] if rail_type == "SRT" else rail.tickets()

        all_reservations = []
        for t in tickets:
            t.is_ticket = True
            all_reservations.append(t)
        for r in reservations:
            if hasattr(r, "paid") and r.paid:
                r.is_ticket = True
            else:
                r.is_ticket = False
            all_reservations.append(r)

        if not reservations and not tickets:
            print(colored("예약 내역이 없습니다", "green", "on_red") + "\n")
            return

        choices = [
            (str(reservation), i) for i, reservation in enumerate(all_reservations)
        ] + [("텔레그램으로 예매 정보 전송", -2), ("돌아가기", -1)]

        choice = inquirer.list_input(message="예약 취소 (Enter: 결정)", choices=choices)

        # No choice or go back
        if choice in (None, -1):
            return

        # Send reservation info to telegram
        if choice == -2:
            out = []
            if all_reservations:
                out.append("[ 예매 내역 ]")
                for reservation in all_reservations:
                    out.append(f"🚅{reservation}")
                    if rail_type == "SRT":
                        out.extend(map(str, reservation.tickets))

            if out:
                tgprintf = get_telegram()
                asyncio.run(tgprintf("\n".join(out)))
            return

        # If choice is an unpaid reservation, ask to pay or cancel
        if (
            not all_reservations[choice].is_ticket
            and not all_reservations[choice].is_waiting
        ):
            answer = inquirer.list_input(
                message=f"결재 대기 승차권: {all_reservations[choice]}",
                choices=[("결제하기", 1), ("취소하기", 2)],
            )

            if answer == 1:
                if pay_card(rail, all_reservations[choice]):
                    print(
                        colored("\n\n💳 ✨ 결제 성공!!! ✨ 💳\n\n", "green", "on_red"),
                        end="",
                    )
            elif answer == 2:
                rail.cancel(all_reservations[choice])
            return

        # Else
        if inquirer.confirm(
            message=colored("정말 취소하시겠습니까", "green", "on_red")
        ):
            try:
                if all_reservations[choice].is_ticket:
                    rail.refund(all_reservations[choice])
                else:
                    rail.cancel(all_reservations[choice])
            except Exception as err:
                raise err
            return
        
def login_menu(rail_type: RailType, debug: bool=False) -> Optional[str]:
    """SRT/KTX 로그인 설정: 기존 alias 선택 or 새 계정 추가"""
    rail_cls = SRT if rail_type=="SRT" else Korail

    while True:
        # 1) 별명 목록 + 새 계정 추가
        aliases = list_aliases(rail_type)
        choice = inquirer.list_input(
            message=f"{rail_type} 계정 선택",
            choices=aliases + ["➕ 새 계정 추가", "돌아가기"]
        )
        if choice in (None, "돌아가기"):
            return None

        # 2) 새 계정 추가 흐름
        if choice == "➕ 새 계정 추가":
            # 순차 입력
            info = inquirer.prompt([
                inquirer.Text("id", message="아이디"),
                inquirer.Password("pw", message="비밀번호"),
                inquirer.Text("alias", message="별명"),
            ])
            if not info:
                return False
            uid, pwd, alias = info["id"], info["pw"], info["alias"]

            # 로그인 테스트
            try:
                rail_cls(uid, pwd, verbose=debug)
            except Exception as err:
                print(f"로그인 실패: {err}")
                if inquirer.confirm("다시 시도하시겠습니까?", default=True):
                    continue
                return False

            # 저장 및 최상단 노출
            add_account(rail_type, alias, uid, pwd)
            print("✅ 저장 완료!")
            # loop 돌면서 방금 추가한 alias가 제일 앞에 뜹니다.
            continue

        # 3) 기존 alias 선택 → 로그인 시도
        try:
            uid, pwd = get_account_credentials(rail_type, choice)
            rail_cls(uid, pwd, verbose=debug)
            print(f"✅ '{choice}' 계정으로 로그인 성공")
            return choice
        except Exception as err:
            print(f"로그인 오류: {err}")
            return None



if __name__ == "__main__":
    srtgo()
