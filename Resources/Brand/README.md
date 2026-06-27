# Comet Brand Assets

This folder contains first-party SVG assets for Comet documentation, GitHub surfaces, and app resources.

## Files

- `icon-gradient.svg`: primary icon for README, social previews, and app branding
- `icon-black.svg`: single-color mark for light backgrounds
- `icon-white.svg`: single-color mark for dark backgrounds
- `logo-mark.svg`: stacked mark with text
- `logo-text.svg`: wordmark text

Use relative paths from repository docs when possible. For example:

```html
<img src="Resources/Brand/icon-gradient.svg" alt="Comet logo" width="112">
```

The playground app keeps its runtime image asset in `Examples/CometPlayground/App/Assets.xcassets/CometIcon.imageset` and its app icon in `Examples/CometPlayground/App/Assets.xcassets/AppIcon.appiconset`.
