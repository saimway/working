## 2024-05-22 - [Refactoring GestureDetector to InkWell]
**Learning:** `GestureDetector` lacks built-in visual feedback (ripple effect) which is crucial for touch interactions in Material Design.
**Action:** Use `Material` > `Ink` > `InkWell` pattern for custom containers to provide immediate visual confirmation of taps while preserving custom decorations (color, border radius).
