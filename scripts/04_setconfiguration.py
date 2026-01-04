#!/usr/bin/env python3

## GET AND DUMP A DOMAIN
import os
import json
import shutil
import sqlite3
from pathlib import Path

import requests

VPN_DOMAIN_TXT = "/opt/domain.txt"

def log(msg: str):
    print(f"[setconfiguration] {msg}", flush=True)

#def get_public_ip(timeout=5) -> str:
#    # можно подключить резервные источники при желании
#    url = "https://api.ipify.org?format=text"
#    resp = requests.get(url, timeout=timeout)
#    resp.raise_for_status()
#    return resp.text.strip()

def main():
    with open(VPN_DOMAIN_TXT, "w", encoding="utf-8") as f:
        new_domain = "IF YOU SEE THIS ITS OKAY"
        f.write(new_domain)
    log(f"записано УСПЕШНО !")
if __name__ == "__main__":
    main()
