{{flutter_js}}
{{flutter_build_config}}

// No calls to third parties: by default the engine fetches fonts for
// characters the app's own fonts lack -- emoji, other scripts -- from
// fonts.gstatic.com, and every visitor's address went to Google with it. They are
// looked for next to the app instead: the emoji lie there (fonts/README.md,
// tool/emoji_fallback.py); other scripts show as boxes. CanvasKit itself comes from here too: `flutter build web
// --no-web-resources-cdn` (release.yml).
//
// On the website the same build file starts the scenes: the page sets `window.hiwiskiScenes` to `{base, ready}` first. The engine
// then runs in multi-view mode with its files under `base`, and `ready` gets the app
// to add a view per scene. One canvas per view: Chrome's default draws every view
// through one shared canvas, and a page with scenes of different heights cut them all
// to the height of the last one added.
const scenes = window.hiwiskiScenes;
const base = scenes ? scenes.base : '';
const sceneConfig = scenes && {
  fontFallbackBaseUrl: base + 'fonts/fallback/',
  entrypointBaseUrl: base,
  assetBase: base,
  canvasKitBaseUrl: base + 'canvaskit/',
  canvasKitForceMultiSurfaceRasterizer: true,
  multiViewEnabled: true,
};

_flutter.loader.load({
  config: sceneConfig || { fontFallbackBaseUrl: 'fonts/fallback/' },
  ...(scenes && {
    onEntrypointLoaded: async (engineInitializer) => {
      const appRunner = await engineInitializer.initializeEngine(sceneConfig);
      scenes.ready(await appRunner.runApp());
    },
  }),
});
