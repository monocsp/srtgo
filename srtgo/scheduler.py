# srtgo/scheduler.py
from datetime import datetime, timedelta
import time
import inquirer
from termcolor import colored
import os
import platform

def shutdown_computer():
    """운영체제에 맞춰 컴퓨터를 종료합니다."""
    system_name = platform.system()
    
    print(colored("\n💤 예매가 완료되어 10초 뒤 컴퓨터를 종료합니다...", "magenta"))
    print(colored("⚠️  종료를 취소하려면 [Ctrl+C]를 눌러주세요.", "yellow"))

    try:
        # 10초 카운트다운
        for i in range(10, 0, -1):
            print(f"\r⏳ {i}초 뒤 종료됩니다...   ", end='', flush=True)
            time.sleep(1)
        print() # 줄바꿈

    except KeyboardInterrupt:
        print(colored("\n\n🛑 사용자 요청으로 컴퓨터 종료가 취소되었습니다.", "green"))
        return

    # 종료 명령 실행
    if system_name == "Windows":
        os.system("shutdown /s /t 1")
    elif system_name == "Darwin": # Mac (수정됨)
        # Mac에서는 shutdown 명령어 대신 AppleScript를 사용하여 권한 문제 우회
        os.system("osascript -e 'tell application \"System Events\" to shut down'")
    elif system_name == "Linux":
        # 리눅스는 보통 sudo가 필요하지만, 사용자가 설정했을 경우를 대비해 시도
        os.system("shutdown -h now")
    else:
        print("알 수 없는 운영체제라 종료하지 못했습니다.")

def ask_shutdown():
    """예매 완료 후 컴퓨터 종료 여부를 묻습니다."""
    q = [
        inquirer.Confirm(
            "shutdown",
            message="🎉 예매 성공 후 컴퓨터를 자동으로 종료하시겠습니까?",
            default=False
        )
    ]
    ans = inquirer.prompt(q)
    return ans["shutdown"] if ans else False

def select_schedule_time():
    """
    설정이 완료된 시점을 기준으로 예약 시간을 선택합니다.
    """
    now = datetime.now()
    choices = []

    # 1. 상대 시간 옵션 (설정 완료 시점 기준)
    choices.append((f"⏱️  설정 완료 후 1분 뒤 시작 ({ (now + timedelta(minutes=1)).strftime('%H:%M:%S') })", now + timedelta(minutes=1)))
    choices.append((f"⏱️  설정 완료 후 5분 뒤 시작 ({ (now + timedelta(minutes=5)).strftime('%H:%M') })", now + timedelta(minutes=5)))
    choices.append((f"⏱️  설정 완료 후 10분 뒤 시작 ({ (now + timedelta(minutes=10)).strftime('%H:%M') })", now + timedelta(minutes=10)))

    # 2. 절대 시간 옵션 (5분 단위 정각)
    # 현재 시간 기준 다음 5분 단위 찾기
    next_tick_min = (now.minute // 5 + 1) * 5
    next_tick = now.replace(minute=0, second=0, microsecond=0) + timedelta(minutes=next_tick_min)
    
    # 만약 계산된 정각이 현재보다 과거거나 너무 가까우면 보정
    if next_tick <= now:
        next_tick += timedelta(minutes=5)

    end_time = now + timedelta(hours=5)
    
    current_step = next_tick
    while current_step <= end_time:
        label = f"⏰ {current_step.strftime('%H:%M')} (정각/5분 단위)"
        choices.append((label, current_step))
        current_step += timedelta(minutes=5)

    question = [
        inquirer.List(
            "schedule_dt",
            message="[예약 실행] 언제 예매를 시작할까요?",
            choices=choices,
        )
    ]
    
    answer = inquirer.prompt(question)
    return answer["schedule_dt"] if answer else None

def wait_until(target_time):
    """
    target_time이 될 때까지 대기합니다.
    """
    print(colored(f"\n⏰ 예약 모드 가동: {target_time.strftime('%Y-%m-%d %H:%M:%S')}에 예매를 시작합니다.", "yellow"))
    print(colored("⚠️ 컴퓨터를 끄거나 절전 모드로 전환하지 마세요.\n", "red"))

    while True:
        now = datetime.now()
        remaining = target_time - now
        
        if remaining.total_seconds() <= 0:
            print(colored("\n🚀 예약 시간이 되었습니다! 예매를 시작합니다.", "green", "on_red"))
            break

        # 남은 시간 표시
        hours, rem = divmod(int(remaining.total_seconds()), 3600)
        minutes, seconds = divmod(rem, 60)
        time_str = f"{hours:02d}:{minutes:02d}:{seconds:02d}"
        
        print(f"\r⏳ 실행 대기 중... 남은 시간: {time_str}", end="", flush=True)
        time.sleep(1)