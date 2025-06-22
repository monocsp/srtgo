import json
from pathlib import Path
from dataclasses import dataclass
from typing import Dict, List, Tuple
import keyring

# 파일 경로: 사용자 홈 디렉터리 아래 숨김 JSON 파일로 계정 정보를 저장합니다.
ACCOUNTS_FILE = Path.home() / ".srtgo_accounts.json"
# keyring 서비스 이름 접두사
SERVICE_PREFIX = "srtgo"

@dataclass
class Account:
    alias: str
    rail_type: str
    user_id: str


def load_accounts() -> Dict[str, List[Account]]:
    """
    저장된 모든 계정을 불러옵니다.
    반환 형식: { "SRT": [Account, ...], "KTX": [Account, ...] }
    """
    if not ACCOUNTS_FILE.exists():
        return {"SRT": [], "KTX": []}
    data = json.loads(ACCOUNTS_FILE.read_text(encoding='utf-8'))
    accounts: Dict[str, List[Account]] = {"SRT": [], "KTX": []}
    for rail in ("SRT", "KTX"):
        for item in data.get(rail, []):
            accounts[rail].append(
                Account(
                    alias=item["alias"],
                    rail_type=rail,
                    user_id=item["user_id"]
                )
            )
    return accounts


def save_accounts(accounts: Dict[str, List[Account]]) -> None:
    """
    메모리 상의 계정 리스트를 JSON 파일로 저장합니다.
    """
    data = {}
    for rail_type, lst in accounts.items():
        data[rail_type] = [
            {"alias": acc.alias, "user_id": acc.user_id}
            for acc in lst
        ]
    ACCOUNTS_FILE.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')


def list_accounts(rail_type: str) -> List[str]:
    """
    특정 철도(SRT 또는 KTX)에 저장된 계정 별명(aliases) 목록을 반환합니다.
    """
    accounts = load_accounts()
    return [acc.alias for acc in accounts.get(rail_type, [])]


def add_account(rail_type: str, alias: str, user_id: str, password: str) -> None:
    """
    새로운 계정을 추가합니다.
    1. JSON 파일에 alias 및 user_id를 저장
    2. keyring에 비밀번호를 저장

    rail_type: "SRT" 또는 "KTX"
    alias: 계정 별명(고유해야 함)
    user_id: 로그인용 아이디(멤버십 번호, 이메일 등)
    password: 로그인 비밀번호
    """
    accounts = load_accounts()
    if rail_type not in accounts:
        accounts[rail_type] = []
    # 중복 별명 방지
    if any(acc.alias == alias for acc in accounts[rail_type]):
        raise ValueError(f"Alias '{alias}' already exists for '{rail_type}'")
    # JSON에 저장
    accounts[rail_type].append(Account(alias=alias, rail_type=rail_type, user_id=user_id))
    save_accounts(accounts)
    # keyring에 비밀번호 저장
    service_name = f"{SERVICE_PREFIX}-{rail_type}"
    keyring.set_password(service_name, alias, password)


def get_account_credentials(rail_type: str, alias: str) -> Tuple[str, str]:
    """
    alias로 저장된 계정의 (user_id, password) 튜플을 반환합니다.
    """
    accounts = load_accounts().get(rail_type, [])
    for acc in accounts:
        if acc.alias == alias:
            service_name = f"{SERVICE_PREFIX}-{rail_type}"
            pwd = keyring.get_password(service_name, alias)
            if pwd is None:
                raise KeyError(f"Password not found for alias '{alias}'")
            return acc.user_id, pwd
    raise KeyError(f"Alias '{alias}' not found for '{rail_type}'")


def remove_account(rail_type: str, alias: str) -> None:
    """
    저장된 계정을 삭제합니다.
    JSON과 keyring에서 모두 해당 항목을 제거합니다.
    """
    accounts = load_accounts()
    if rail_type not in accounts:
        return
    new_list = [acc for acc in accounts[rail_type] if acc.alias != alias]
    accounts[rail_type] = new_list
    save_accounts(accounts)
    service_name = f"{SERVICE_PREFIX}-{rail_type}"
    keyring.delete_password(service_name, alias)
