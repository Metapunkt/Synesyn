#!/usr/bin/env python3
"""
Material Theme Builder (Material 3) JSON -> Godot Theme .tres (text resource)

Treat the Material JSON as a token source, then emit a small set of project-specific theme variants:
- Base: default UI surfaces (chat, main session)
- Utility: overlays/config panels (hamburger/settings, services panel, dialogs)
- Console: text-heavy diagnostics/log panes (monospace)

Usage (run from synesyn/synesyn_client):
  python tools/material_theme_builder_json_to_tres.py ^
    --input tools/material_theme_reference/material-theme_01.json ^
    --outdir ScenSyn/themes ^
    --basename Synesyn ^
    --variants base utility console ^
    --schemes light dark ^
    --ui_font tools/fonts/Noto_Sans/static/NotoSans-Regular.ttf ^
    --ui_font_bold tools/fonts/Noto_Sans/static/NotoSans-SemiBold.ttf ^
    --mono_font tools/fonts/Roboto_Mono/static/RobotoMono-Regular.ttf
"""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Tuple, Optional, List


Color = Tuple[float, float, float, float]  # r,g,b,a in 0..1


def clamp01(x: float) -> float:
    return max(0.0, min(1.0, x))


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def mix(c1: Color, c2: Color, t: float) -> Color:
    t = clamp01(t)
    return (
        lerp(c1[0], c2[0], t),
        lerp(c1[1], c2[1], t),
        lerp(c1[2], c2[2], t),
        lerp(c1[3], c2[3], t),
    )


def hsl_saturation(c: Color) -> float:
    """Approx saturation in HSL space (0..1). Used to avoid tinting with near-neutral tokens."""
    r, g, b, _a = c
    mx = max(r, g, b)
    mn = min(r, g, b)
    d = mx - mn
    if d <= 1e-8:
        return 0.0
    l = (mx + mn) / 2.0
    denom = 1.0 - abs(2.0 * l - 1.0)
    if denom <= 1e-8:
        return 0.0
    return d / denom


def with_alpha(c: Color, a: float) -> Color:
    return (c[0], c[1], c[2], clamp01(a))


def palette_color(palettes: Dict, palette_name: str, step: int, fallback: Color) -> Color:
    """
    Material Theme Builder export includes palettes like:
      palettes.neutral["98"] = "#FDF8F6"
      palettes["neutral-variant"]["80"] = "#CAC6C3"
    """
    if not isinstance(palettes, dict):
        return fallback
    pal = palettes.get(palette_name)
    if not isinstance(pal, dict):
        return fallback
    v = pal.get(str(step))
    if isinstance(v, str):
        try:
            return parse_hex_color(v)
        except Exception:
            return fallback
    return fallback


def parse_hex_color(s: str) -> Color:
    t = s.strip()
    if t.startswith("#"):
        t = t[1:]
    if len(t) == 6:
        r = int(t[0:2], 16) / 255.0
        g = int(t[2:4], 16) / 255.0
        b = int(t[4:6], 16) / 255.0
        return (r, g, b, 1.0)
    if len(t) == 8:
        # AARRGGBB (Material token exports commonly use this elsewhere)
        a = int(t[0:2], 16) / 255.0
        r = int(t[2:4], 16) / 255.0
        g = int(t[4:6], 16) / 255.0
        b = int(t[6:8], 16) / 255.0
        return (r, g, b, a)
    raise ValueError(f"Unsupported color hex: {s}")


def godot_color(c: Color) -> str:
    # Godot writes a lot of decimals; 6dp is plenty and stable.
    return f"Color({c[0]:.6f}, {c[1]:.6f}, {c[2]:.6f}, {c[3]:.6f})"


@dataclass(frozen=True)
class StyleBoxFlatDef:
    bg: Color
    border: Optional[Color] = None
    border_w: int = 0
    radius: int = 0
    shadow_color: Optional[Color] = None
    shadow_size: int = 0
    shadow_offset: Tuple[float, float] = (0.0, 0.0)
    anti_aliasing: bool = True
    # left, top, right, bottom
    content_margin: Tuple[float, float, float, float] = (10.0, 6.0, 10.0, 6.0)


def emit_stylebox_flat(sb_id: int, sb: StyleBoxFlatDef) -> str:
    lines: List[str] = []
    lines.append(f'[sub_resource type="StyleBoxFlat" id="{sb_id}"]')
    l, t, r, b = sb.content_margin
    lines.append(f"content_margin_left = {l}")
    lines.append(f"content_margin_top = {t}")
    lines.append(f"content_margin_right = {r}")
    lines.append(f"content_margin_bottom = {b}")
    lines.append(f"bg_color = {godot_color(sb.bg)}")
    if sb.border and sb.border_w > 0:
        lines.append(f"border_width_left = {sb.border_w}")
        lines.append(f"border_width_top = {sb.border_w}")
        lines.append(f"border_width_right = {sb.border_w}")
        lines.append(f"border_width_bottom = {sb.border_w}")
        lines.append(f"border_color = {godot_color(sb.border)}")
    if sb.radius > 0:
        lines.append(f"corner_radius_top_left = {sb.radius}")
        lines.append(f"corner_radius_top_right = {sb.radius}")
        lines.append(f"corner_radius_bottom_right = {sb.radius}")
        lines.append(f"corner_radius_bottom_left = {sb.radius}")
    if sb.shadow_color and sb.shadow_size > 0:
        lines.append(f"shadow_color = {godot_color(sb.shadow_color)}")
        lines.append(f"shadow_size = {sb.shadow_size}")
        if sb.shadow_offset != (0.0, 0.0):
             lines.append(f"shadow_offset = Vector2({sb.shadow_offset[0]}, {sb.shadow_offset[1]})")
    if not sb.anti_aliasing:
        lines.append("anti_aliasing = false")
    return "\n".join(lines) + "\n"


@dataclass(frozen=True)
class ExtFont:
    res_path: str
    type_name: str = "FontFile"


def emit_ext_resources(fonts: Dict[str, ExtFont]) -> Tuple[str, Dict[str, int]]:
    """
    Returns:
      - ext_resource block string
      - mapping of key->ext_resource_id
    """
    lines: List[str] = []
    mapping: Dict[str, int] = {}
    next_id = 1
    for key, ext in fonts.items():
        mapping[key] = next_id
        lines.append(f'[ext_resource type="{ext.type_name}" path="{ext.res_path}" id="{next_id}"]')
        next_id += 1
    return ("\n".join(lines) + ("\n\n" if lines else "")), mapping


def get_token(scheme: Dict, key: str) -> Optional[Color]:
    v = scheme.get(key)
    if isinstance(v, str):
        return parse_hex_color(v)
    if isinstance(v, dict):
        for k in ("value", "$value", "hex", "color"):
            vv = v.get(k)
            if isinstance(vv, str):
                return parse_hex_color(vv)
    return None


def build_theme_text(
    scheme: Dict,
    *,
    scheme_name: str,
    variant: str,
    corner_radius: int,
    fonts: Dict[str, ExtFont],
    palettes: Dict,
) -> str:
    # Core tokens + sensible fallbacks.
    primary = get_token(scheme, "primary") or (0.26, 0.52, 0.96, 1.0)
    on_primary = get_token(scheme, "onPrimary") or (1.0, 1.0, 1.0, 1.0)
    primary_container = get_token(scheme, "primaryContainer") or mix(primary, (1, 1, 1, 1), 0.75)
    on_primary_container = get_token(scheme, "onPrimaryContainer") or on_primary
    secondary = get_token(scheme, "secondary") or mix(primary, (1, 1, 1, 1), 0.25)
    tertiary = get_token(scheme, "tertiary") or secondary

    surface = get_token(scheme, "surface") or get_token(scheme, "background") or (0.1, 0.1, 0.1, 1.0)
    on_surface = get_token(scheme, "onSurface") or get_token(scheme, "onBackground") or (1.0, 1.0, 1.0, 1.0)

    surface_variant = get_token(scheme, "surfaceVariant") or mix(surface, on_surface, 0.12)
    on_surface_variant = get_token(scheme, "onSurfaceVariant") or mix(on_surface, surface, 0.35)

    outline = get_token(scheme, "outline") or with_alpha(on_surface, 0.30)
    outline_variant = get_token(scheme, "outlineVariant") or with_alpha(on_surface, 0.18)

    # Accent color for subtle tints: if primary is near-neutral, fall back to tertiary/secondary.
    accent = primary
    if hsl_saturation(accent) < 0.18:
        accent = tertiary if hsl_saturation(tertiary) >= 0.18 else secondary
    if hsl_saturation(accent) < 0.10:
        # Cool charcoal accent (requested #4A4A4A)
        accent = (0.290, 0.290, 0.290, 1.0)  # #4A4A4A

    # Material "inverse" tokens are perfect for "dark chrome on light canvas" dashboards.
    inverse_surface = get_token(scheme, "inverseSurface") or mix(surface, on_surface, 0.85)
    inverse_on_surface = get_token(scheme, "inverseOnSurface") or mix(on_surface, surface, 0.85)

    # Prefer surfaceContainer for panels if present.
    surface_container = (
        get_token(scheme, "surfaceContainer")
        or get_token(scheme, "surfaceContainerLow")
        or get_token(scheme, "surfaceContainerHigh")
        or surface
    )
    surface_container_high = (
        get_token(scheme, "surfaceContainerHigh")
        or get_token(scheme, "surfaceContainerHighest")
        or surface_container
    )
    surface_container_low = (
        get_token(scheme, "surfaceContainerLow")
        or get_token(scheme, "surfaceContainerLowest")
        or surface_container
    )

    # Option A (neutral + calm): use the export's neutral palettes rather than hue steering.
    scheme_name = scheme_name.lower().strip()
    is_light = scheme_name.startswith("light")

    # Canvas + surfaces (choose stable neutral ladder)
    if is_light:
        # User preference: pure white canvas (avoid warm/pink off-whites like #FFFBFF).
        WHITE: Color = (1.0, 1.0, 1.0, 1.0)
        INK: Color = (0.0, 0.0, 0.0, 1.0)
        surface_n = WHITE
        surface_container_n = WHITE
        surface_container_low_n = WHITE
        surface_container_high_n = WHITE

        # Use neutral grays for fields and separators to avoid color cast.
        surface_variant_n = mix(WHITE, INK, 0.015)  # ~#FBFBFB (avoid "printed gray paper")
        outline_n = with_alpha(INK, 0.28)          # crisper lines
        outline_variant_n = with_alpha(INK, 0.18)  # separators
    else:
        surface_n = palette_color(palettes, "neutral", 10, surface)
        surface_variant_n = palette_color(palettes, "neutral", 20, surface_variant)
        surface_container_n = palette_color(palettes, "neutral", 15, surface_container)
        surface_container_low_n = palette_color(palettes, "neutral", 10, surface_container_low)
        surface_container_high_n = palette_color(palettes, "neutral", 20, surface_container_high)
        outline_n = palette_color(palettes, "neutral-variant", 60, outline)
        outline_variant_n = palette_color(palettes, "neutral-variant", 50, outline_variant)

    # Chrome ladder (neutral charcoal steps; avoid mixing to prevent odd casts)
    if is_light:
        chrome_bg = palette_color(palettes, "neutral", 20, inverse_surface)
        chrome_bg_soft = palette_color(palettes, "neutral", 25, mix(inverse_surface, (1, 1, 1, 1), 0.10))
        chrome_sel = palette_color(palettes, "neutral", 30, mix(inverse_surface, inverse_on_surface, 0.12))
        chrome_sel_focus = palette_color(palettes, "neutral", 35, mix(inverse_surface, inverse_on_surface, 0.18))
        chrome_text = palette_color(palettes, "neutral", 95, inverse_on_surface)
    else:
        chrome_bg = palette_color(palettes, "neutral", 90, inverse_surface)
        chrome_bg_soft = palette_color(palettes, "neutral", 80, mix(inverse_surface, (0, 0, 0, 1), 0.10))
        chrome_sel = palette_color(palettes, "neutral", 70, mix(inverse_surface, inverse_on_surface, 0.12))
        chrome_sel_focus = palette_color(palettes, "neutral", 60, mix(inverse_surface, inverse_on_surface, 0.18))
        chrome_text = palette_color(palettes, "neutral", 10, inverse_on_surface)

    variant = variant.lower().strip()
    if variant not in ("base", "utility", "console", "tools"):
        raise ValueError(f"Unknown variant: {variant}")

    if variant == "utility":
        panel_bg = surface_container_high_n
        panel_border = outline_n
        border_w = 1
        radius = max(6, corner_radius - 2)
        button_kind = "outlined"
        density = "dense"
    elif variant == "tools":
        # “Dark chrome on light canvas” — for dashboards like Synesyn Tools / SynPunkt.
        panel_bg = surface_container_n
        panel_border = outline_n
        border_w = 1
        radius = max(8, corner_radius - 2)
        button_kind = "chrome"
        density = "dense"
    else:
        panel_bg = surface_container_n
        # Crisper separation improves legibility on warm/light backgrounds.
        panel_border = outline_n
        border_w = 1
        radius = corner_radius
        # Outlined-by-default reads more "minimal" while staying earthy (less tinted fill everywhere).
        button_kind = "outlined"
        density = "normal"

    # StyleBoxes (assign stable ids)
    SB_PANEL = 1
    SB_BTN_NORMAL = 2
    SB_BTN_HOVER = 3
    SB_BTN_PRESSED = 4
    SB_BTN_DISABLED = 5
    SB_BTN_FOCUS = 6
    SB_LE_NORMAL = 7
    SB_LE_FOCUS = 8
    SB_LE_READONLY = 9
    SB_POPUP_PANEL = 10
    SB_POPUP_HOVER = 11
    SB_TAB_FG = 12
    SB_TAB_BG = 13
    SB_TREE_BG = 14
    SB_TREE_SELECTED = 15
    SB_TREE_SELECTED_FOCUS = 16
    SB_TEXTEDIT_NORMAL = 17
    SB_TEXTEDIT_FOCUS = 18
    SB_TEXTEDIT_READONLY = 19
    SB_SCROLL = 20
    SB_SCROLL_FOCUS = 21
    SB_GRABBER = 22
    SB_GRABBER_HOVER = 23
    SB_GRABBER_PRESSED = 24
    SB_CHROME_PANEL = 25
    SB_CHROME_PANEL_SOFT = 26
    SB_CHROME_SELECTED = 27
    SB_CHROME_SELECTED_FOCUS = 28

    # Use clearer borders for readability; reserve outlineVariant for subtler separators.
    field_border = outline_variant_n
    tab_line = outline_variant_n

    styleboxes: Dict[int, StyleBoxFlatDef] = {
        # Default panels: keep crisp (no shadow) to avoid "low ink / haze" when many nested panels exist.
        SB_PANEL: StyleBoxFlatDef(
            bg=panel_bg,
            border=panel_border,
            border_w=border_w,
            radius=radius,
            content_margin=(12, 12, 12, 12),
        ),

        SB_LE_NORMAL: StyleBoxFlatDef(bg=surface_variant_n, border=field_border, border_w=1, radius=radius, content_margin=(10, 8, 10, 8)),
        SB_LE_FOCUS: StyleBoxFlatDef(bg=surface_variant_n, border=primary, border_w=2, radius=radius, content_margin=(10, 8, 10, 8)),
        SB_LE_READONLY: StyleBoxFlatDef(bg=mix(surface_variant_n, surface_n, 0.25), border=field_border, border_w=1, radius=radius, content_margin=(10, 8, 10, 8)),

        # Popups/menus: subtle elevation feels tactile without washing the whole UI.
        SB_POPUP_PANEL: StyleBoxFlatDef(
            bg=panel_bg,
            border=panel_border,
            border_w=border_w,
            radius=radius,
            shadow_color=with_alpha((0.0, 0.0, 0.0, 1.0), 0.12) if is_light else None,
            shadow_size=1 if is_light else 0,
            shadow_offset=(0, 1) if is_light else (0, 0),
            content_margin=(8, 8, 8, 8),
        ),
        SB_POPUP_HOVER: StyleBoxFlatDef(bg=surface_variant_n, radius=0, content_margin=(8, 4, 8, 4)),

        # Tabs (flat): tint active/bg tabs so they match the accent language (not just gray).
        SB_TAB_FG: StyleBoxFlatDef(
            bg=mix(panel_bg, accent, 0.25) if is_light else panel_bg,
            border=accent if is_light else tab_line,
            border_w=1,
            radius=0,
            anti_aliasing=False,
            content_margin=(10, 6, 10, 6)
        ),
        SB_TAB_BG: StyleBoxFlatDef(
            bg=mix(panel_bg, accent, 0.10) if is_light else surface_variant_n,
            border=with_alpha(accent, 0.40) if is_light else tab_line,
            border_w=1,
            radius=0,
            anti_aliasing=False,
            content_margin=(10, 6, 10, 6)
        ),

        SB_TREE_BG: StyleBoxFlatDef(bg=panel_bg, border=outline_variant_n, border_w=1, radius=radius, content_margin=(12, 12, 12, 12)),
        SB_TREE_SELECTED: StyleBoxFlatDef(bg=with_alpha(primary, 0.30), radius=0, content_margin=(0, 0, 0, 0)),
        SB_TREE_SELECTED_FOCUS: StyleBoxFlatDef(bg=with_alpha(primary, 0.35), radius=0, content_margin=(0, 0, 0, 0)),

        SB_TEXTEDIT_NORMAL: StyleBoxFlatDef(bg=with_alpha(panel_bg, 0.0), border=field_border, border_w=1, radius=radius, content_margin=(10, 10, 10, 10)),
        SB_TEXTEDIT_FOCUS: StyleBoxFlatDef(bg=with_alpha(panel_bg, 0.0), border=primary, border_w=2, radius=radius, content_margin=(10, 10, 10, 10)),
        SB_TEXTEDIT_READONLY: StyleBoxFlatDef(bg=with_alpha(panel_bg, 0.0), border=field_border, border_w=1, radius=radius, content_margin=(10, 10, 10, 10)),

        SB_SCROLL: StyleBoxFlatDef(bg=with_alpha(surface_variant_n, 0.65), border=outline_variant_n, border_w=1, radius=6, content_margin=(4, 4, 4, 4)),
        SB_SCROLL_FOCUS: StyleBoxFlatDef(bg=with_alpha(surface_variant, 0.65), border=primary, border_w=2, radius=6, content_margin=(4, 4, 4, 4)),
        SB_GRABBER: StyleBoxFlatDef(bg=with_alpha(on_surface_variant, 0.35), radius=6, content_margin=(0, 0, 0, 0)),
        SB_GRABBER_HOVER: StyleBoxFlatDef(bg=with_alpha(on_surface_variant, 0.50), radius=6, content_margin=(0, 0, 0, 0)),
        SB_GRABBER_PRESSED: StyleBoxFlatDef(bg=with_alpha(on_surface_variant, 0.65), radius=6, content_margin=(0, 0, 0, 0)),

        # Chrome panels (used by tools variant)
        SB_CHROME_PANEL: StyleBoxFlatDef(
            bg=chrome_bg,
            border=with_alpha(chrome_text, 0.22),
            border_w=1,
            radius=0,
            content_margin=(10, 6, 10, 6),
        ),
        SB_CHROME_PANEL_SOFT: StyleBoxFlatDef(
            bg=chrome_bg_soft,
            border=with_alpha(chrome_text, 0.16),
            border_w=1,
            radius=0,
            content_margin=(10, 6, 10, 6),
        ),
        SB_CHROME_SELECTED: StyleBoxFlatDef(
            bg=chrome_sel,
            radius=0,
            content_margin=(0, 0, 0, 0),
        ),
        SB_CHROME_SELECTED_FOCUS: StyleBoxFlatDef(
            bg=chrome_sel_focus,
            radius=0,
            content_margin=(0, 0, 0, 0),
        ),
    }

    # Buttons (tonal/outlined/chrome): avoids dark-mode "primary == white" glare for this export.
    if button_kind == "tonal":
        btn_bg = primary_container
        btn_fg = on_primary_container
        btn_hover_bg = mix(primary_container, on_primary_container, 0.06)
        btn_pressed_bg = mix(primary_container, (0, 0, 0, 1), 0.10)
        btn_border = None
        btn_border_w = 0
        btn_focus_border = primary
    else:
        if button_kind == "chrome":
            btn_bg = chrome_bg
            btn_fg = chrome_text
            btn_hover_bg = chrome_bg_soft
            btn_pressed_bg = chrome_sel
            btn_border = with_alpha(chrome_text, 0.22)
            btn_border_w = 1
            btn_focus_border = primary
        else:
            # Stronger tint so buttons feel like solid objects, not dirty paper.
            # Tint mix increased to 0.25 to make the charcoal color visible.
            btn_bg = mix(panel_bg, accent, 0.25) if is_light else panel_bg
            # Text: Use pure INK (black) for maximum contrast, no mixing with gray accent.
            btn_fg = INK if is_light else primary
            btn_hover_bg = mix(panel_bg, accent, 0.35) if is_light else mix(panel_bg, primary, 0.06)
            btn_pressed_bg = mix(panel_bg, accent, 0.45) if is_light else mix(panel_bg, primary, 0.10)
            btn_border = accent if is_light else outline
            btn_border_w = 1
            btn_focus_border = primary

    btn_margins = (14, 8, 14, 8) if density == "normal" else (12, 7, 12, 7)
    # Buttons: sharper, darker shadow for crisp definition.
    # Normal state now has shadow (per user request). Offset increased to (0, 2).
    btn_shadow_c = with_alpha((0.0, 0.0, 0.0, 1.0), 0.30) if is_light else None
    btn_shadow_s = 1 if is_light else 0
    btn_shadow_o = (0, 2) if is_light else (0, 0)
    
    styleboxes[SB_BTN_NORMAL] = StyleBoxFlatDef(bg=btn_bg, border=btn_border, border_w=btn_border_w, radius=radius, shadow_color=btn_shadow_c, shadow_size=btn_shadow_s, shadow_offset=btn_shadow_o, content_margin=btn_margins)
    styleboxes[SB_BTN_HOVER] = StyleBoxFlatDef(bg=btn_hover_bg, border=btn_border, border_w=btn_border_w, radius=radius, shadow_color=btn_shadow_c, shadow_size=btn_shadow_s, shadow_offset=btn_shadow_o, content_margin=btn_margins)
    styleboxes[SB_BTN_PRESSED] = StyleBoxFlatDef(bg=btn_pressed_bg, border=btn_border, border_w=btn_border_w, radius=radius, content_margin=btn_margins)
    styleboxes[SB_BTN_DISABLED] = StyleBoxFlatDef(bg=with_alpha(surface_variant, 0.65), border=btn_border, border_w=btn_border_w, radius=radius, content_margin=btn_margins)
    styleboxes[SB_BTN_FOCUS] = StyleBoxFlatDef(bg=btn_bg, border=btn_focus_border, border_w=2, radius=radius, content_margin=btn_margins)

    subresource_chunks = [emit_stylebox_flat(i, styleboxes[i]).rstrip() for i in sorted(styleboxes.keys())]
    ext_block, ext_ids = emit_ext_resources(fonts)
    load_steps = 1 + len(styleboxes) + len(ext_ids)

    # Theme properties (match naming style found in ScenSyn/themes/MinimalUI.tres)
    resource_lines: List[str] = []
    resource_lines.append("[resource]")

    # Fonts
    if variant == "console":
        resource_lines.append(f'default_font = ExtResource("{ext_ids["mono"]}")')
    else:
        resource_lines.append(f'default_font = ExtResource("{ext_ids["ui"]}")')

    # Default sizing: boost readability on dense screens.
    base_size = 14 if variant not in ("utility", "tools") else 13
    console_size = 13

    # Label / RichTextLabel (do NOT make all labels bold; it destroys hierarchy)
    resource_lines.append(f"Label/colors/font_color = {godot_color(on_surface)}")
    resource_lines.append(f"Label/font_sizes/font_size = {base_size}")
    resource_lines.append(f"RichTextLabel/colors/default_color = {godot_color(on_surface)}")
    resource_lines.append(f"RichTextLabel/font_sizes/normal_font_size = {base_size}")

    # Panel / PanelContainer / Window (dialogs)
    resource_lines.append(f'Panel/styles/panel = SubResource("{SB_PANEL}")')
    resource_lines.append(f'PanelContainer/styles/panel = SubResource("{SB_PANEL}")')
    resource_lines.append(f'Window/styles/panel = SubResource("{SB_PANEL}")')

    # Button
    resource_lines.append(f'Button/styles/normal = SubResource("{SB_BTN_NORMAL}")')
    resource_lines.append(f'Button/styles/hover = SubResource("{SB_BTN_HOVER}")')
    resource_lines.append(f'Button/styles/pressed = SubResource("{SB_BTN_PRESSED}")')
    resource_lines.append(f'Button/styles/disabled = SubResource("{SB_BTN_DISABLED}")')
    resource_lines.append(f'Button/styles/focus = SubResource("{SB_BTN_FOCUS}")')
    resource_lines.append(f"Button/colors/font_color = {godot_color(btn_fg)}")
    resource_lines.append(f"Button/colors/font_color_hover = {godot_color(btn_fg)}")
    resource_lines.append(f"Button/colors/font_color_pressed = {godot_color(btn_fg)}")
    resource_lines.append(f"Button/colors/font_color_disabled = {godot_color(with_alpha(on_surface, 0.35))}")
    resource_lines.append(f'Button/fonts/font = ExtResource("{ext_ids["ui_bold"]}")')
    resource_lines.append(f"Button/font_sizes/font_size = {base_size}")

    # OptionButton (roughly like a button)
    resource_lines.append(f'OptionButton/styles/normal = SubResource("{SB_BTN_NORMAL}")')
    resource_lines.append(f'OptionButton/styles/hover = SubResource("{SB_BTN_HOVER}")')
    resource_lines.append(f'OptionButton/styles/pressed = SubResource("{SB_BTN_PRESSED}")')
    resource_lines.append(f'OptionButton/styles/disabled = SubResource("{SB_BTN_DISABLED}")')
    resource_lines.append(f'OptionButton/styles/focus = SubResource("{SB_BTN_FOCUS}")')
    resource_lines.append(f"OptionButton/colors/font_color = {godot_color(btn_fg)}")
    resource_lines.append(f"OptionButton/colors/font_color_hover = {godot_color(btn_fg)}")
    resource_lines.append(f"OptionButton/colors/font_color_pressed = {godot_color(btn_fg)}")
    resource_lines.append(f"OptionButton/colors/font_color_disabled = {godot_color(with_alpha(on_surface, 0.35))}")
    resource_lines.append(f'OptionButton/fonts/font = ExtResource("{ext_ids["ui_bold"]}")')
    resource_lines.append(f"OptionButton/font_sizes/font_size = {base_size}")

    # CheckButton / CheckBox (settings)
    resource_lines.append(f"CheckButton/colors/font_color = {godot_color(on_surface)}")
    resource_lines.append(f"CheckButton/colors/font_color_disabled = {godot_color(with_alpha(on_surface, 0.35))}")
    resource_lines.append(f"CheckButton/colors/font_color_hover = {godot_color(on_surface)}")
    resource_lines.append(f"CheckButton/colors/font_color_pressed = {godot_color(on_surface)}")
    resource_lines.append(f"CheckBox/colors/font_color = {godot_color(on_surface)}")
    resource_lines.append(f"CheckBox/colors/font_color_disabled = {godot_color(with_alpha(on_surface, 0.35))}")
    resource_lines.append(f"CheckBox/colors/font_color_hover = {godot_color(on_surface)}")
    resource_lines.append(f"CheckBox/colors/font_color_pressed = {godot_color(on_surface)}")
    resource_lines.append(f"CheckButton/font_sizes/font_size = {base_size}")
    resource_lines.append(f"CheckBox/font_sizes/font_size = {base_size}")

    # LineEdit
    resource_lines.append(f'LineEdit/styles/normal = SubResource("{SB_LE_NORMAL}")')
    resource_lines.append(f'LineEdit/styles/focus = SubResource("{SB_LE_FOCUS}")')
    resource_lines.append(f'LineEdit/styles/read_only = SubResource("{SB_LE_READONLY}")')
    resource_lines.append(f"LineEdit/colors/font_color = {godot_color(on_surface)}")
    resource_lines.append(f"LineEdit/colors/font_color_uneditable = {godot_color(with_alpha(on_surface, 0.55))}")
    # Placeholder should be clearly readable but secondary.
    resource_lines.append(f"LineEdit/colors/font_placeholder_color = {godot_color(with_alpha(on_surface_variant, 0.70))}")
    resource_lines.append(f"LineEdit/colors/cursor_color = {godot_color(primary)}")
    resource_lines.append(f"LineEdit/colors/selection_color = {godot_color(with_alpha(primary, 0.35))}")
    resource_lines.append(f"LineEdit/colors/font_color_selected = {godot_color(on_primary)}")
    resource_lines.append(f"LineEdit/font_sizes/font_size = {base_size}")

    # TextEdit
    resource_lines.append(f'TextEdit/styles/normal = SubResource("{SB_TEXTEDIT_NORMAL}")')
    resource_lines.append(f'TextEdit/styles/focus = SubResource("{SB_TEXTEDIT_FOCUS}")')
    resource_lines.append(f'TextEdit/styles/read_only = SubResource("{SB_TEXTEDIT_READONLY}")')
    resource_lines.append(f"TextEdit/colors/font_color = {godot_color(on_surface)}")
    resource_lines.append(f"TextEdit/colors/font_color_readonly = {godot_color(with_alpha(on_surface, 0.6))}")
    resource_lines.append(f"TextEdit/colors/selection_color = {godot_color(with_alpha(primary, 0.35))}")
    resource_lines.append(f"TextEdit/colors/caret_color = {godot_color(primary)}")
    resource_lines.append(f"TextEdit/font_sizes/font_size = {console_size if variant == 'console' else base_size}")
    resource_lines.append("TextEdit/constants/line_spacing = 4")
    # Force a solid background (removes “mystery gradients” from transparent defaults).
    textedit_bg = surface_container_low_n if variant != "utility" else surface_container_n
    resource_lines.append(f"TextEdit/colors/background_color = {godot_color(textedit_bg)}")
    if variant == "console":
        resource_lines.append(f'TextEdit/fonts/font = ExtResource("{ext_ids["mono"]}")')

    # ItemList (SynPunkt lists)
    if variant == "tools":
        resource_lines.append(f"ItemList/colors/font_color = {godot_color(inverse_on_surface)}")
        resource_lines.append(f"ItemList/colors/font_selected_color = {godot_color((1.0, 1.0, 1.0, 1.0))}")
        resource_lines.append(f"ItemList/font_sizes/font_size = {base_size}")
        resource_lines.append(f'ItemList/styles/panel = SubResource("{SB_CHROME_PANEL}")')
        resource_lines.append(f'ItemList/styles/selected = SubResource("{SB_CHROME_SELECTED}")')
        resource_lines.append(f'ItemList/styles/selected_focus = SubResource("{SB_CHROME_SELECTED_FOCUS}")')
    else:
        resource_lines.append(f"ItemList/colors/font_color = {godot_color(on_surface)}")
        resource_lines.append(f"ItemList/colors/font_selected_color = {godot_color(on_surface)}")
        resource_lines.append(f"ItemList/font_sizes/font_size = {base_size}")
        resource_lines.append(f'ItemList/styles/panel = SubResource("{SB_PANEL}")')
        # Best-effort selection styleboxes (safe if ignored by engine/theme type)
        resource_lines.append(f'ItemList/styles/selected = SubResource("{SB_TREE_SELECTED}")')
        resource_lines.append(f'ItemList/styles/selected_focus = SubResource("{SB_TREE_SELECTED_FOCUS}")')

    # PopupMenu
    resource_lines.append(f'PopupMenu/styles/panel = SubResource("{SB_POPUP_PANEL}")')
    resource_lines.append(f'PopupMenu/styles/hover = SubResource("{SB_POPUP_HOVER}")')
    resource_lines.append(f"PopupMenu/colors/font_color = {godot_color(on_surface)}")
    resource_lines.append(f"PopupMenu/colors/font_color_hover = {godot_color(on_surface)}")
    resource_lines.append(f"PopupMenu/colors/font_color_disabled = {godot_color(with_alpha(on_surface, 0.35))}")
    resource_lines.append(f"PopupMenu/colors/font_color_accel = {godot_color(with_alpha(on_surface_variant, 0.9))}")
    resource_lines.append(f"PopupMenu/colors/font_color_separator = {godot_color(with_alpha(on_surface_variant, 0.9))}")
    resource_lines.append("PopupMenu/constants/hseparation = 8")
    resource_lines.append("PopupMenu/constants/vseparation = 6")

    # TabContainer
    # Tools: no enclosing panel behind the tab strip (keeps the top row crisp and non-pill).
    resource_lines.append(f'TabContainer/styles/panel = SubResource("0")' if variant == "tools" else f'TabContainer/styles/panel = SubResource("{SB_PANEL}")')
    if variant == "tools":
        resource_lines.append(f'TabContainer/styles/tab_fg = SubResource("{SB_CHROME_PANEL}")')
        resource_lines.append(f'TabContainer/styles/tab_bg = SubResource("{SB_CHROME_PANEL_SOFT}")')
        resource_lines.append(f"TabContainer/colors/font_color_fg = {godot_color(inverse_on_surface)}")
        resource_lines.append(f"TabContainer/colors/font_color_bg = {godot_color(with_alpha(inverse_on_surface, 0.85))}")
        # Compatibility keys (some UI uses selected/unselected naming)
        resource_lines.append(f"TabContainer/colors/font_selected_color = {godot_color(inverse_on_surface)}")
        resource_lines.append(f"TabContainer/colors/font_unselected_color = {godot_color(with_alpha(inverse_on_surface, 0.75))}")
        resource_lines.append(f'TabContainer/styles/tab_selected = SubResource("{SB_CHROME_PANEL}")')
        resource_lines.append(f'TabContainer/styles/tab_unselected = SubResource("{SB_CHROME_PANEL_SOFT}")')
    else:
        resource_lines.append(f'TabContainer/styles/tab_fg = SubResource("{SB_TAB_FG}")')
        resource_lines.append(f'TabContainer/styles/tab_bg = SubResource("{SB_TAB_BG}")')
        resource_lines.append(f"TabContainer/colors/font_color_fg = {godot_color(on_surface)}")
        resource_lines.append(f"TabContainer/colors/font_color_bg = {godot_color(with_alpha(on_surface_variant, 0.9))}")
        resource_lines.append(f"TabContainer/colors/font_selected_color = {godot_color(on_surface)}")
        resource_lines.append(f"TabContainer/colors/font_unselected_color = {godot_color(with_alpha(on_surface, 0.70))}")
        resource_lines.append(f'TabContainer/styles/tab_selected = SubResource("{SB_TAB_FG}")')
        resource_lines.append(f'TabContainer/styles/tab_unselected = SubResource("{SB_TAB_BG}")')
    resource_lines.append(f"TabContainer/colors/font_color_disabled = {godot_color(with_alpha(on_surface, 0.35))}")
    resource_lines.append(f'TabContainer/fonts/font = ExtResource("{ext_ids["ui_bold"]}")')
    resource_lines.append(f"TabContainer/font_sizes/font_size = {base_size}")
    # Spacing defaults (reduces cramped nested tabs)
    resource_lines.append("TabContainer/constants/hseparation = 4")
    resource_lines.append("TabContainer/constants/side_margin = 8")
    resource_lines.append("TabContainer/constants/top_margin = 24")

    # Tree
    resource_lines.append(f'Tree/styles/bg = SubResource("{SB_TREE_BG}")')
    resource_lines.append(f'Tree/styles/selected = SubResource("{SB_TREE_SELECTED}")')
    resource_lines.append(f'Tree/styles/selected_focus = SubResource("{SB_TREE_SELECTED_FOCUS}")')
    resource_lines.append(f"Tree/colors/font_color = {godot_color(on_surface)}")
    resource_lines.append(f"Tree/colors/font_color_selected = {godot_color(on_surface)}")
    resource_lines.append(f"Tree/colors/guide_color = {godot_color(with_alpha(outline_variant, 0.5))}")
    resource_lines.append(f"Tree/colors/relationship_line_color = {godot_color(with_alpha(outline, 0.65))}")

    # Scroll bars
    for cls in ("HScrollBar", "VScrollBar"):
        resource_lines.append(f'{cls}/styles/scroll = SubResource("{SB_SCROLL}")')
        resource_lines.append(f'{cls}/styles/scroll_focus = SubResource("{SB_SCROLL_FOCUS}")')
        resource_lines.append(f'{cls}/styles/grabber = SubResource("{SB_GRABBER}")')
        resource_lines.append(f'{cls}/styles/grabber_highlight = SubResource("{SB_GRABBER_HOVER}")')
        resource_lines.append(f'{cls}/styles/grabber_pressed = SubResource("{SB_GRABBER_PRESSED}")')

    header = f'[gd_resource type="Theme" load_steps={load_steps} format=3]'
    return "\n\n".join([header, ext_block.rstrip(), "\n\n".join(subresource_chunks), "\n".join(resource_lines)]) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--basename", default="Synesyn")
    ap.add_argument("--schemes", nargs="+", default=["light", "dark"])
    ap.add_argument("--variants", nargs="+", default=["base", "utility"])
    ap.add_argument("--corner_radius", type=int, default=10)
    ap.add_argument("--ui_font", default="tools/fonts/Noto_Sans/static/NotoSans-Regular.ttf")
    ap.add_argument("--ui_font_bold", default="tools/fonts/Noto_Sans/static/NotoSans-SemiBold.ttf")
    ap.add_argument("--mono_font", default="tools/fonts/Roboto_Mono/static/RobotoMono-Regular.ttf")
    args = ap.parse_args()

    in_path = Path(args.input)
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    data = json.loads(in_path.read_text(encoding="utf-8"))
    schemes = data.get("schemes", {})
    palettes = data.get("palettes", {})
    if not isinstance(schemes, dict):
        raise SystemExit("Expected JSON.schemes to be an object")

    def as_res(path_str: str) -> str:
        pth = Path(path_str)
        if pth.is_absolute():
            try:
                rel = pth.relative_to(Path.cwd())
                return "res://" + rel.as_posix()
            except Exception:
                return path_str
        return "res://" + pth.as_posix().replace("\\", "/")

    fonts = {
        "ui": ExtFont(as_res(args.ui_font)),
        "ui_bold": ExtFont(as_res(args.ui_font_bold)),
        "mono": ExtFont(as_res(args.mono_font)),
    }

    written: List[Path] = []
    for variant in args.variants:
        for scheme_name in args.schemes:
            scheme = schemes.get(scheme_name)
            if not isinstance(scheme, dict):
                raise SystemExit(f"Scheme '{scheme_name}' not found in JSON.schemes")
            tres = build_theme_text(
                scheme,
                scheme_name=scheme_name,
                variant=variant,
                corner_radius=args.corner_radius,
                fonts=fonts,
                palettes=palettes,
            )
            out_path = outdir / f"{args.basename}{variant.capitalize()}_{scheme_name}.tres"
            out_path.write_text(tres, encoding="utf-8", newline="\n")
            written.append(out_path)

    print("Wrote:")
    for p in written:
        print(f"  {p.as_posix()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


