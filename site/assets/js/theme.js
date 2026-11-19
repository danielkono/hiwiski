// Light or dark: the system's until the switch in the header is used, then the
// switch's. The choice goes along to the next page of the site in its address
// (`?theme=dark`) and is taken out of the address again as soon as it is read, so
// a reload starts from the system. Nothing is stored.
// The scenes follow.
(() => {
  const root = document.documentElement;
  const key = 'theme';
  const themes = ['light', 'dark'];

  const params = new URLSearchParams(location.search);
  if (themes.includes(params.get(key))) {
    root.dataset.theme = params.get(key);
    params.delete(key);
    const rest = params.toString();
    history.replaceState(history.state, '', location.pathname + (rest ? '?' + rest : '') + location.hash);
  }

  const system = () => (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
  const current = () => root.dataset.theme || system();

  // Every link to another page of the site carries the switch's choice.
  function carry() {
    for (const link of document.querySelectorAll('a[href]')) {
      const url = new URL(link.getAttribute('href'), location.href);
      if (url.origin !== location.origin || url.pathname === location.pathname) continue;
      if (root.dataset.theme) url.searchParams.set(key, root.dataset.theme);
      else url.searchParams.delete(key);
      link.setAttribute('href', url.pathname + url.search + url.hash);
    }
  }
  document.addEventListener('DOMContentLoaded', carry);

  document.addEventListener('click', (event) => {
    if (!event.target.closest('.theme-toggle')) return;
    root.dataset.theme = current() === 'dark' ? 'light' : 'dark';
    window.hiwiskiScenesTheme?.(root.dataset.theme);
    carry();
  });
})();
