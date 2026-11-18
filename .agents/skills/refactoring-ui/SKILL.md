---
name: refactoring-ui
description: Professional minimalist UI/UX design guidelines based on Refactoring UI by Adam Wathan & Steve Schoger. Use whenever designing, refactoring, or polishing user interfaces, layouts, typography, color palettes, and desktop/web tool components.
---

# Refactoring UI - Minimalist Design System

This skill embeds the practical, tactical design rules from **Refactoring UI** (by Adam Wathan & Steve Schoger) adapted for Flutter desktop and modern Web applications.

---

## Core Philosophy: Design Like a Pro, Not an Artist

1. **Start in Greyscale (单色先行)**
   - Design the layout, typography, contrast, and spacing purely in monochrome (black, white, neutral zinc/slate grays) before introducing any accent color.
   - Accent color should be reserved for **1-2 primary focal actions** (e.g. Primary CTA, key active tab indicator).

2. **Hierarchy by Size, Weight, and Opacity (而非堆砌颜色)**
   - Primary heading: `fontSize: 13-14`, `FontWeight.w600`, opacity `0.9-1.0`.
   - Secondary content/labels: `fontSize: 11-12`, `FontWeight.w500`, opacity `0.7-0.8`.
   - Tertiary captions/meta: `fontSize: 10-10.5`, `FontWeight.w400`, opacity `0.45-0.55`.
   - Avoid creating multiple colorful badges for secondary attributes. Use subtle typography instead.

3. **1px Micro Borders over Heavy Shadows (精细微边框)**
   - Dark theme surface:
     - Root background: `#121214` or `#0F0F11`
     - Card background: `#18181B` (Zinc-900) or `#1A1A1E`
     - Card border: `Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.0)`
     - Divider / Separator: `Colors.white.withValues(alpha: 0.06)`
   - Avoid thick outlines, heavy drop shadows, or high-saturation gradient cards.

4. **Double Down on Whitespace (留白呼吸感)**
   - Use strict spacing scale: `4px` (tight), `8px` (compact), `12px` (standard), `16px` (comfortable), `20-24px` (spacious).
   - Card inner padding: `12-14px` horizontal, `10-12px` vertical.
   - Elements inside a card should breathe with at least `8-10px` gap between distinct rows.

5. **Progressive Disclosure (渐进式披露，杜绝信息轰炸)**
   - **Default State**: Show only the current status, clean summary, and primary trigger.
   - **Expanded State**: Detailed technical parameters, API keys, or raw configurations are collapsed by default or only shown when explicitly configuring.
   - **Hover on Demand**: Secondary utility buttons (copy, delete, refresh) should be subtle or reveal on hover.

6. **Micro Status Indicators (以点代面)**
   - Avoid large, loud, saturated warning banners for ordinary states.
   - Use a `6px` solid status circle + small pill badge (`padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2)`):
     - Online / Healthy: Emerald Green (`#10B981`) with 12% alpha background.
     - Warning / Syncing: Amber / Warm Orange with 12% alpha background.
     - Inactive / Offline: Neutral Slate Gray with 10% alpha background.

7. **Buttons & Inputs (克制精致)**
   - Primary Button: Accent color background, white text, height `28-32px`, radius `6px`.
   - Secondary Button: Transparent background, `1px` subtle border (`Colors.white12`), neutral text.
   - Text Inputs: Background slightly darker than card (`#141416`), border `Colors.white10`, subtle focus glow `accentColor.withValues(alpha: 0.4)`.

---

## Application Checklist for PodQuick

When refactoring Flutter desktop or Vue web components:
- [ ] Is the page visually calm and de-cluttered?
- [ ] Are redundant colorful banners removed in favor of concise micro-pills?
- [ ] Is there enough breathing space between sections (`SizedBox(height: 12-14)`)?
- [ ] Are borders thin (`1px`) and semi-transparent (`alpha: 0.06 - 0.08`)?
- [ ] Are buttons compact (`26-30px` height) with crisp typography (`11-12px`)?
- [ ] Is technical noise (long URLs, IDs, secret tokens) either masked or monospaced and demoted?
