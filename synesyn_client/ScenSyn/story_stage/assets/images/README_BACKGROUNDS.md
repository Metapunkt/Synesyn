# ScenSyn Background Metadata System

This folder contains background images and their metadata for ScenSyn's dynamic visual presentation system.

## How It Works

The system automatically discovers background images (`.png` files) in this folder and looks for corresponding metadata files (`.json` files) with the same name.

For example:
- `detective_office.png` → `detective_office.json`
- `courthouse_lobby.png` → `courthouse_lobby.json`

## Adding New Backgrounds

1. **Add your background image** (PNG format) to this folder
2. **Create a metadata JSON file** with the same name
3. **Fill in the metadata** following the format below

## Metadata Format

Each background should have a JSON file with this structure:

```json
{
    "description": "A one-sentence description of the location",
    "ai_instructions": "When the AI should use this location",
    "tags": ["keyword1", "keyword2", "keyword3"],
    "mood": "emotional_tone"
}
```

### Field Descriptions

- **`description`** (Required): A clear, descriptive sentence that helps the AI understand what this location looks like and feels like.

- **`ai_instructions`** (Optional but recommended): Specific guidance for the AI about when this location is most appropriate to use in the story.

- **`tags`** (Optional): Array of keywords that help the system match AI descriptions to this location. Include:
  - Indoor/outdoor: `"indoor"`, `"outdoor"`
  - Mood: `"tense"`, `"peaceful"`, `"dramatic"`, `"casual"`
  - Function: `"professional"`, `"social"`, `"private"`, `"public"`
  - Theme: `"legal"`, `"investigation"`, `"romantic"`, `"action"`

- **`mood`** (Optional): Single word describing the overall emotional tone. Examples: `"serious"`, `"welcoming"`, `"mysterious"`, `"focused"`

## Examples

### Detective Office
```json
{
    "description": "A cluttered detective's office with case files scattered across the desk and dim lighting",
    "ai_instructions": "Use for investigation scenes, case discussions, or private detective work",
    "tags": ["indoor", "professional", "investigation", "private"],
    "mood": "serious"
}
```

### Park Bench
```json
{
    "description": "A peaceful park bench surrounded by trees and nature, perfect for quiet conversations",
    "ai_instructions": "Use for heart-to-heart conversations, peaceful moments, or when characters need to think",
    "tags": ["outdoor", "peaceful", "natural", "private"],
    "mood": "peaceful"
}
```

## How the AI Uses This Information

1. **Location Awareness**: The AI knows what backgrounds are available before generating content
2. **Smart Transitions**: The AI can naturally steer the story toward locations you've provided
3. **Automatic Matching**: When the AI mentions locations, the system automatically matches them to your backgrounds
4. **Visual Continuity**: The story and visuals work together seamlessly

## Tips for Best Results

1. **Be Descriptive**: The more detailed your description, the better the AI can match it
2. **Use Clear Instructions**: Specific AI instructions help create more appropriate scene transitions
3. **Include Relevant Tags**: Good tagging improves automatic location detection
4. **Consider Story Flow**: Think about how locations connect to create smooth narrative transitions

## Fallback System

If a character or location is mentioned but no matching background is found, the system will:
1. Use the most similar available background based on tags and description
2. Continue the story without breaking
3. Log the missing background for you to add later

## File Naming

- Use lowercase with underscores: `detective_office.png`
- Avoid spaces and special characters
- Keep names descriptive but concise
- JSON files must exactly match the PNG filename

See `METADATA_EXAMPLE.json` for a comprehensive example with all available options.














