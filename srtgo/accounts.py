import json
from pathlib import Path
from dataclasses import dataclass
from typing import List, Tuple

@dataclass
class Account:
    """
    사용자 계정 정보를 담는 데이터 클래스
    alias: 별칭
    user_id: 로그인에 사용할 아이디
    password: 로그인 비밀번호
    """
    alias: str
    user_id: str
    password: str


def _get_file_path(rail_type: str) -> Path:
    """
    rail_type 에 따라 JSON 파일 경로를 반환합니다.
    rail_type: 'SRT' 또는 'KTX'
    파일명: srt_login.json 또는 ktx_login.json
    """
    filename = f"{rail_type.lower()}_login.json"
    return Path(__file__).parent / filename


def load_accounts(rail_type: str) -> List[Account]:
    """
    저장된 계정 목록을 로드합니다.
    파일이 없으면 빈 리스트를 반환하고 새로운 파일을 생성합니다.
    """
    path = _get_file_path(rail_type)
    if not path.exists():
        path.write_text("[]", encoding="utf-8")
        return []

    data = json.loads(path.read_text(encoding="utf-8"))
    return [Account(**item) for item in data]


def save_accounts(rail_type: str, accounts: List[Account]) -> None:
    """
    계정 리스트를 JSON 파일로 저장합니다.
    파일이 없으면 자동 생성됩니다.
    """
    path = _get_file_path(rail_type)
    path.parent.mkdir(parents=True, exist_ok=True)
    data = [acc.__dict__ for acc in accounts]
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def list_aliases(rail_type: str) -> List[str]:
    """
    rail_type 에 저장된 모든 alias(별명) 목록을 반환합니다.
    """
    return [acc.alias for acc in load_accounts(rail_type)]


def add_account(rail_type: str, alias: str, user_id: str, password: str) -> None:
    """
    새로운 계정을 추가하고 JSON 파일에 저장합니다.
    중복 alias가 있으면 ValueError 발생.
    추가된 계정은 목록의 최상단에 위치합니다.
    """
    accounts = load_accounts(rail_type)
    if any(acc.alias == alias for acc in accounts):
        raise ValueError(f"Alias '{alias}' already exists for '{rail_type}'")
    accounts.insert(0, Account(alias=alias, user_id=user_id, password=password))
    save_accounts(rail_type, accounts)


def get_account_credentials(rail_type: str, alias: str) -> Tuple[str, str]:
    """
    alias 에 해당하는 (user_id, password) 튜플을 반환합니다.
    해당 alias가 없으면 KeyError 발생.
    """
    accounts = load_accounts(rail_type)
    for acc in accounts:
        if acc.alias == alias:
            return acc.user_id, acc.password
    raise KeyError(f"Alias '{alias}' not found for '{rail_type}'")


def remove_account(rail_type: str, alias: str) -> None:
    """
    저장된 계정을 삭제하고 JSON 파일을 업데이트합니다.
    """
    accounts = load_accounts(rail_type)
    filtered = [acc for acc in accounts if acc.alias != alias]
    save_accounts(rail_type, filtered)