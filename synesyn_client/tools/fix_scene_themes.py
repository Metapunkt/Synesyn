import sys
import re
from pathlib import Path

# Paths relative to synesyn/synesyn_client
files = [
    "ScenSyn/scenes/main_menu.tscn",
    "ScenSyn/scenes/game_session.tscn",
    "ScenSyn/scenes/chat_system.tscn"
]

# UID for SynesynBase_light.tres
NEW_UID = "uid://yo24nrkueenh"
NEW_PATH = "res://ScenSyn/themes/SynesynBase_light.tres"

replacements = [
    "res://ScenSyn/themes/MaterialThemeBuilder_01_light.tres",
    "res://ScenSyn/themes/MinimalUI/MinimalUI_2.tres",
    "res://ScenSyn/themes/MinimalUI.tres"
]

for fpath in files:
    p = Path(fpath)
    if not p.exists():
        print(f"Skipping {fpath} (not found)")
        continue
    
    txt = p.read_text(encoding="utf-8")
    original = txt
    
    for old_path in replacements:
        # We look for: [ext_resource type="Theme" uid="..." path="old_path" id="..."]
        # We want to replace uid and path.
        pattern = r'(\[ext_resource type="Theme" uid=")([^"]+)(" path=")' + re.escape(old_path) + r'(" id="[^"]+"])'
        
        def sub_fn(match):
            return f'{match.group(1)}{NEW_UID}{match.group(3)}{NEW_PATH}{match.group(4)}'
            
        txt = re.sub(pattern, sub_fn, txt)
    
    if txt != original:
        p.write_text(txt, encoding="utf-8")
        print(f"Updated {fpath}")
    else:
        print(f"No changes needed for {fpath}")
