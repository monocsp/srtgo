import json
from pathlib import Path
from typing import List, Tuple
import keyring

# 카드 별칭 관리 파일
CARDS_FILE = Path(__file__).parent / "payment_nickname.json"


def load_cards() -> List[str]:
    """
    저장된 카드 별칭(alias) 목록을 로드합니다.
    파일이 없으면 빈 리스트로 초기화 후 반환합니다.
    """
    if not CARDS_FILE.exists():
        CARDS_FILE.write_text("[]", encoding="utf-8")
        return []
    data = json.loads(CARDS_FILE.read_text(encoding="utf-8"))
    return data  # List[str]


def save_cards(aliases: List[str]) -> None:
    """
    카드 별칭 목록을 JSON 파일로 저장합니다.
    """
    CARDS_FILE.parent.mkdir(parents=True, exist_ok=True)
    CARDS_FILE.write_text(json.dumps(aliases, ensure_ascii=False, indent=2), encoding="utf-8")


def list_card_aliases() -> List[str]:
    """
    현재 등록된 모든 카드 별칭을 반환합니다.
    """
    return load_cards()


def add_card(alias: str, number: str, password: str, birthday: str, expire: str) -> None:
    """
    새로운 카드를 등록합니다.
    1. keyring 에 민감 정보 저장
    2. alias 를 JSON 최상단에 추가
    """
    service = f"srtgo-card-{alias}"
    # keyring 저장
    keyring.set_password(service, "number", number)
    keyring.set_password(service, "password", password)
    keyring.set_password(service, "birthday", birthday)
    keyring.set_password(service, "expire", expire)

    # JSON alias 저장
    aliases = load_cards()
    if alias in aliases:
        raise ValueError(f"Alias '{alias}' already exists.")
    aliases.insert(0, alias)
    save_cards(aliases)


def remove_card(alias: str) -> None:
    """
    카드 등록 취소(삭제) 처리합니다.
    1. keyring 에서 정보 삭제
    2. JSON 에서 alias 제거
    """
    service = f"srtgo-card-{alias}"
    # keyring 삭제
    for key in ("number", "password", "birthday", "expire"):
        try:
            keyring.delete_password(service, key)
        except Exception:
            pass

    # JSON alias 업데이트
    aliases = load_cards()
    filtered = [a for a in aliases if a != alias]
    save_cards(filtered)


def get_card_credentials(alias: str) -> Tuple[str, str, str, str]:
    """
    alias 에 해당하는 카드 정보(number, password, birthday, expire)를 반환합니다.
    """
    service = f"srtgo-card-{alias}"
    number = keyring.get_password(service, "number")
    password = keyring.get_password(service, "password")
    birthday = keyring.get_password(service, "birthday")
    expire = keyring.get_password(service, "expire")
    if None in (number, password, birthday, expire):
        raise KeyError(f"Incomplete card info for alias '{alias}'")
    return number, password, birthday, expire
