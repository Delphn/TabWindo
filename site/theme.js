// Runs before the page paints, so a visitor's saved light or dark choice shows from the first frame.
// Without one, the page follows the Mac: styles.css sets color-scheme to "light dark".
try {
  const saved = localStorage.getItem('tabwindo-theme');
  if (saved === 'light' || saved === 'dark') document.documentElement.dataset.theme = saved;
} catch {
  // Storage blocked (private browsing, strict settings): follow the Mac.
}
