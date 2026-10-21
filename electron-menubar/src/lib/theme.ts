export function followSystemTheme(
  media = window.matchMedia('(prefers-color-scheme: dark)'),
  root = document.documentElement
): () => void {
  const update = () => root.classList.toggle('dark', media.matches);
  update();
  media.addEventListener('change', update);
  return () => media.removeEventListener('change', update);
}
