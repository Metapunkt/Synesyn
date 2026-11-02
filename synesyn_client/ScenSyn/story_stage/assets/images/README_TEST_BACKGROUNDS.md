# Test Background Images

## Missing Background Images

The following JSON metadata files exist but need corresponding PNG images:

- `test_room.json` → **needs** `test_room.png`

## How to Add Background Images

1. Create or find appropriate background images in PNG format
2. Name them to match the existing JSON files
3. Place them in this folder (`assets/images/`)
4. The system will automatically discover and use them

## Current Status

The dynamic background system is fully implemented and will work as soon as the actual PNG files are added. The JSON metadata is already configured.

## Testing

You can test the system by:
1. Adding a `test_room.png` file to this folder
2. Running the story_stage scene
3. Using AI responses that mention "test room" or similar keywords
4. The background should change automatically

## Fallback Behavior

If PNG files are missing, the system will:
- Continue to work without breaking
- Log warnings about missing images
- Use the current background (usually title_screen.png)
- Still track available backgrounds in AI prompts














