// The scenes: the first "Try it" on a page loads the
// app's scene build once; every scene started puts a real view of the app where its
// screenshot was. Nothing loads before that click.
(() => {
  const base = document.currentScript?.dataset.base || '/embed/';
  const figures = new Map(); // view id -> figure
  let app = null;
  let loading = null;
  const waiting = [];

  function show(figure) {
    const host = document.createElement('div');
    host.className = 'view';
    figure.querySelector('.frame').append(host);
    figure.classList.add('running');
    // The wheel over a scene is the scene's: at the end of its list the page would
    // otherwise scroll on under the pointer.
    host.addEventListener('wheel', (event) => event.preventDefault(), { passive: false });
    const viewId = app.addView({
      hostElement: host,
      initialData: { scene: figure.dataset.scene, lang: figure.dataset.lang },
    });
    figures.set(viewId, figure);
    figure.dataset.view = viewId;
  }

  function load() {
    loading ??= new Promise((resolve) => {
      window.hiwiskiScenes = {
        base,
        ready(flutterApp) {
          app = flutterApp;
          // The page's theme if its switch was used; the system's otherwise.
          if (document.documentElement.dataset.theme) {
            window.hiwiskiScenesTheme?.(document.documentElement.dataset.theme);
          }
          resolve();
        },
      };
      const script = document.createElement('script');
      script.src = base + 'flutter_bootstrap.js';
      script.async = true;
      document.body.append(script);
    });
    return loading;
  }

  // A scene that left where it began (a task opened, an event) offers the way back
  // beside it: inside it there is no shell to go back through.
  window.hiwiskiScenesMoved = (viewId, away) => {
    figures.get(viewId)?.classList.toggle('away', away);
  };

  document.addEventListener('click', async (event) => {
    const back = event.target.closest('.scene .back');
    if (back) {
      window.hiwiskiScenesHome?.(Number(back.closest('.scene').dataset.view));
      return;
    }
    const button = event.target.closest('.scene .try');
    if (!button) return;
    const figure = button.closest('.scene');
    if (app) return show(figure);
    button.disabled = true;
    button.lastChild.textContent = button.dataset.loading;
    waiting.push(figure);
    await load();
    while (waiting.length) show(waiting.shift());
  });
})();
