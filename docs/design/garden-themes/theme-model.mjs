// Executable proposal contract, deliberately not imported by the application.
export const themes = [
  {
    id: 'meadow-dawn', name: 'Meadow Dawn', bird: 'Skylark', unlockDays: 0,
    background: 'Soft sunrise, rolling meadow and seed heads',
    palette: { canvas: '#F7F4EF', surface: '#FFFFFF', text: '#242424', muted: '#5C5C5C', accent: '#2F6F4E', onAccent: '#FFFFFF', sky: '#E8EEE0', ground: '#D3DFC3', plant: '#2F6F4E', bloom: '#A04758', bird: '#775334', wing: '#EDC995', detail: '#242424' },
  },
  {
    id: 'zen-garden', name: 'Zen Garden', bird: 'Wren', unlockDays: 0,
    background: 'Raked sand, smooth stones and a quiet maple',
    palette: { canvas: '#F2F0E8', surface: '#FFFFFF', text: '#292D29', muted: '#535B52', accent: '#4C6043', onAccent: '#FFFFFF', sky: '#E4E8DE', ground: '#DDD5C0', plant: '#4C6043', bloom: '#AA573C', bird: '#73513E', wing: '#D8AD83', detail: '#292D29' },
  },
  {
    id: 'night-garden', name: 'Night Garden', bird: 'Nightingale', unlockDays: 0,
    background: 'Moonlit silhouettes and still, scattered fireflies',
    palette: { canvas: '#17232D', surface: '#22313C', text: '#F2F4F0', muted: '#C0CBCD', accent: '#B5D9B2', onAccent: '#17232D', sky: '#263A4A', ground: '#344C46', plant: '#B5D9B2', bloom: '#E5B7CA', bird: '#D7AF8C', wing: '#785544', detail: '#17232D' },
  },
  {
    id: 'rain-forest', name: 'Rain Forest', bird: 'Hummingbird', unlockDays: 0,
    background: 'Broad leaves, layered canopy and still raindrops',
    palette: { canvas: '#EEF4EC', surface: '#FFFFFF', text: '#203329', muted: '#4D6053', accent: '#256044', onAccent: '#FFFFFF', sky: '#D8EADD', ground: '#BBD4BD', plant: '#256044', bloom: '#A63B50', bird: '#256044', wing: '#9CBF6D', detail: '#203329' },
  },
  {
    id: 'desert-bloom', name: 'Desert Bloom', bird: 'Finch', unlockDays: 0,
    background: 'Terracotta dunes, a flowering cactus and warm light',
    palette: { canvas: '#FBF1E4', surface: '#FFFFFF', text: '#3D3028', muted: '#685546', accent: '#884328', onAccent: '#FFFFFF', sky: '#F1DFC4', ground: '#DBB48F', plant: '#526B3D', bloom: '#AB3F55', bird: '#A14F34', wing: '#EDC181', detail: '#3D3028' },
  },
  {
    id: 'seasonal', name: 'Seasonal', bird: 'Skylark', unlockDays: 0,
    background: 'A four-season garden; autumn shown, every season stays selectable',
    palette: { canvas: '#FAF1E6', surface: '#FFFFFF', text: '#352D26', muted: '#655747', accent: '#7D4529', onAccent: '#FFFFFF', sky: '#F3DFC3', ground: '#DBBD88', plant: '#657442', bloom: '#A54530', bird: '#775334', wing: '#EDC995', detail: '#352D26' },
  },
];

export const seasonalVariants = ['spring', 'summer', 'autumn', 'winter'];

export function contrastRatio(foreground, background) {
  const luminance = hex => {
    if (!/^#[0-9A-F]{6}$/i.test(hex)) throw new TypeError('Expected an opaque six-digit color');
    const channels = hex.slice(1).match(/../g).map(part => parseInt(part, 16) / 255)
      .map(value => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
    return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
  };
  const a = luminance(foreground), b = luminance(background);
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}

export function resolveThemeAccess({ practiceDays, unlockedThemeIds = [] }) {
  if (!Array.isArray(practiceDays) || !Array.isArray(unlockedThemeIds)) {
    throw new TypeError('Practice days and retained unlocks must be arrays');
  }
  for (const day of practiceDays) {
    if (typeof day !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(day)
      || !Number.isFinite(Date.parse(`${day}T00:00:00Z`))
      || new Date(`${day}T00:00:00Z`).toISOString().slice(0, 10) !== day) {
      throw new TypeError('Expected a real ISO practice date');
    }
  }
  for (const id of unlockedThemeIds) {
    if (!themes.some(theme => theme.id === id)) throw new TypeError(`Unknown theme: ${id}`);
  }
  return themes.map(theme => theme.id);
}

export function celebrationPolicy({
  appReducedMotion = false, osReducedMotion = false,
  celebrationEnabled = true, soundEnabled = false,
} = {}) {
  for (const value of [appReducedMotion, osReducedMotion, celebrationEnabled, soundEnabled]) {
    if (typeof value !== 'boolean') throw new TypeError('Celebration preferences must be boolean');
  }
  const reduced = appReducedMotion || osReducedMotion;
  return {
    flight: celebrationEnabled && !reduced,
    durationMs: celebrationEnabled && !reduced ? 1000 : 0,
    staticBird: true,
    statusText: 'A little practice, a little growth.',
    sound: celebrationEnabled && soundEnabled,
    ambientMotion: false,
  };
}
