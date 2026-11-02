# ReadyMade Troubleshooting Guide

This guide covers the most common problems you might encounter while working with ReadyMade's Edit Session workflow.

## 1. UI Resizing Issues
**Symptom**: The left panel or tasks tab refuses to resize or content overlaps.
**Fix**:
1. Make sure you're running the latest commit – layout fixes landed in 5.2.3.
2. Press **F5** (Refresh Dashboard) to reload the scene layout.
3. If the splitter still misbehaves, delete your `user://` settings file to reset saved split offsets.

## 2. Lazy-Loading Doesn't Trigger
**Symptom**: Large documents (>100 KB) load completely instead of streaming chunks.
**Fix**:
1. Confirm **Lazy Loading** is enabled in **Settings → Performance**.
2. Check the console for "`is_large_document = false`" – if you see this, the file size was below the threshold.
3. Raise the **Lazy Loading Threshold** or split the file manually.

## 3. "Context window too large" Errors
**Symptom**: AI requests fail with token-limit warnings.
**Fix**:
1. Lower `max_context_tokens` in **Settings → AI → Context Budget**.
2. Switch **Context Mode** to **Single Document**.
3. Disable rich relationships if not needed.

## 4. Missing Dependencies
**Symptom**: ReadyMade fails to start, complaining about missing addons.
**Fix**:
1. Ensure the `Metapunkt`, `LimboAI`, `SynTree`, and `Godot` addons are all present in `addons/`.
2. Re-run the Godot import process if files were moved.

## 5. Export Buttons Do Nothing
**Symptom**: Clicking **Export** buttons shows no dialog.
**Fix**:
1. You might be in **Headless** or **No-Window** mode – file dialogs require windowed execution.
2. Check Project → Project Settings → Display → Window to ensure a main window is configured.

## 6. Still Stuck?
• Join the GitHub Discussions board and search for your issue.
• Open a new topic with logs (found in `readymade/logs/`). 