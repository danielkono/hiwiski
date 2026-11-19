// The search page: Pagefind's interface over the index built with the site. It reads
// the page's language and searches only the pages in it. Nothing leaves the browser.
window.addEventListener('DOMContentLoaded', () => {
  if (typeof PagefindUI === 'undefined') return;
  new PagefindUI({ element: '#search', showSubResults: true, resetStyles: false });
});
