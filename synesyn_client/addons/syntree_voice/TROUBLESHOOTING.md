# SynTree Voice Service Troubleshooting Guide

This document provides a step-by-step guide to diagnosing and fixing communication issues between the Godot project and the Python-based voice synthesis server.

## Problem: No Voice Audio, No Errors, or "Nothing Happening"

This is the most common and difficult issue. It typically occurs after changes have been made to the server or client configuration. The root cause is almost always a mismatch between the server address the Python server is *using* and the address the Godot client is *trying to connect to*.

### Step-by-Step Diagnosis

Follow these steps in order.

#### 1. Check the Python Server Address

First, confirm exactly where the Python server is running.

-   Open `syntree-voice-service/voice_server.py`.
-   Go to the very bottom of the file.
-   Look for the `uvicorn.run(...)` line. It will look like this:
    ```python
    if __name__ == "__main__":
        uvicorn.run(app, host="0.0.0.0", port=8000)
    ```
-   Note the `host` and `port`. This is the **correct address** that the Godot client must use. In the example above, it's `http://0.0.0.0:8000`. (Note: Godot usually connects to `127.0.0.1` when the server is `0.0.0.0`).

#### 2. Check the Godot Client Configuration (The Critical Step)

The Godot client has its URL configured in multiple places. One of them acts as the ultimate source of truth and overrides the others.

-   **The Main Culprit: `VoiceServiceManager`**
    -   Open `addons/syntree_voice/scripts/services/voice_service_manager.gd`.
    -   Near the top, find the `voice_service_url` variable:
        ```gdscript
        var voice_service_url: String = "http://127.0.0.1:8000"
        ```
    -   **This is the most important setting.** This script is an autoload, and it forces the URL onto the actual HTTP client when the game starts.
    -   **Action:** Ensure this URL matches the host and port from Step 1.

-   **The Other Configuration Files (Check these too)**
    -   While the Manager is the usual cause, it's good practice to ensure consistency. Check the following files and update the URL if necessary:
        1.  `addons/syntree_voice/scripts/services/voice_client.gd` (check the `service_url` variable).
        2.  `project.godot` (check for `syntree_voice/service_url` under the `[global]` or a plugin section).

#### 3. Verify the Health Check Logic

A more subtle error we found was a mismatch in the "health check" status message.

-   **Server-Side:** In `syntree-voice-service/voice_server.py`, the `/health` endpoint returns `{"status": "ok"}`.
-   **Client-Side:** In `addons/syntree_voice/scripts/services/voice_client.gd`, the `_handle_successful_response` function must check for this exact string.
    ```gdscript
    if response_data.has("status"):
        if response_data.status == "ok": // This must be "ok"
            _update_service_status(true)
    ```
-   **Action:** If the client never reports "VoiceClient: Service is healthy" in the Godot output log, this mismatch is the likely cause. Ensure the status string is identical on both sides.

### Summary

To fix a connection issue:

1.  Find the **real address** from the `uvicorn.run` line in `voice_server.py`.
2.  Set that **exact address** in the `voice_service_url` variable inside `addons/syntree_voice/scripts/services/voice_service_manager.gd`.
3.  Restart both the Python server and the Godot project.

This process should reliably resolve any communication failures. 