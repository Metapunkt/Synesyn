import re
from pathlib import Path

# Paths relative to CWD (synesyn/synesyn_client)
files = [
    "ScenSyn/scenes/game_session.tscn",
    "ScenSyn/scenes/main_menu.tscn",
    "ScenSyn/scenes/chat_system.tscn"
]

# Patterns to remove theme overrides
patterns = [
    r'^\s*theme_override_colors/[^=]+ = .*\n',
    r'^\s*theme_override_fonts/[^=]+ = .*\n',
    r'^\s*theme_override_styles/[^=]+ = .*\n',
    r'^\s*theme_override_font_sizes/[^=]+ = .*\n',
    r'^\s*theme_override_constants/[^=]+ = .*\n',
]

for fpath in files:
    p = Path(fpath)
    if not p.exists():
        print(f"Skipping {fpath} (not found)")
        continue
    
    txt = p.read_text(encoding="utf-8")
    original_lines = txt.splitlines(keepends=True)
    new_lines = []
    
    removed_count = 0
    
    for line in original_lines:
        is_override = False
        for pat in patterns:
            if re.match(pat, line):
                is_override = True
                removed_count += 1
                break
        if not is_override:
            new_lines.append(line)
            
    if removed_count > 0:
        p.write_text("".join(new_lines), encoding="utf-8")
        print(f"Removed {removed_count} overrides from {fpath}")
    else:
        print(f"No overrides found in {fpath}")
