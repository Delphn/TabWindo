// The light/dark switch and the switcher demo. The page reads fine without this script; it only adds them.

const root = document.documentElement;
const themeButtons = document.querySelectorAll('[data-theme-choice]');

function showTheme(choice) {
  for (const button of themeButtons) {
    button.setAttribute('aria-pressed', String(button.dataset.themeChoice === choice));
  }
}

// "auto" follows the Mac; "light" and "dark" stick, for this browser only.
function setTheme(choice) {
  if (choice === 'auto') delete root.dataset.theme;
  else root.dataset.theme = choice;
  try {
    if (choice === 'auto') localStorage.removeItem('tabwindo-theme');
    else localStorage.setItem('tabwindo-theme', choice);
  } catch {
    // Storage blocked: the choice lasts until the page closes.
  }
  showTheme(choice);
}

for (const button of themeButtons) {
  button.addEventListener('click', () => setTheme(button.dataset.themeChoice));
}
showTheme(root.dataset.theme ?? 'auto');
document.querySelector('.theme')?.removeAttribute('hidden');

// The demo: Tab and Shift move through the windows, Return "switches", a click picks one.
const tiles = [...document.querySelectorAll('.tile')];
const caption = document.querySelector('.caption');
const hint = caption?.textContent ?? '';
let selected = Math.max(0, tiles.findIndex((tile) => tile.getAttribute('aria-pressed') === 'true'));

function select(index) {
  selected = (index + tiles.length) % tiles.length;
  tiles.forEach((tile, i) => tile.setAttribute('aria-pressed', String(i === selected)));
  if (caption) caption.textContent = hint;
}

tiles.forEach((tile, i) => tile.addEventListener('click', () => select(i)));
document.querySelector('[data-key="next"]')?.addEventListener('click', () => select(selected + 1));
document.querySelector('[data-key="previous"]')?.addEventListener('click', () => select(selected - 1));
document.querySelector('[data-key="switch"]')?.addEventListener('click', () => {
  const title = tiles[selected]?.querySelector('.tile-title')?.textContent;
  if (caption && title) caption.textContent = `Switched to “${title}”. It’s in front now.`;
});
document.querySelector('.keys')?.removeAttribute('hidden');
