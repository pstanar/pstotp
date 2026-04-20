/**
 * Map of common service issuers to their brand colors and initials.
 * Used when no custom icon is set on an entry.
 */
const SERVICE_BRANDS: Record<string, { bg: string; fg: string; letter?: string }> = {
  google: { bg: "#4285F4", fg: "#fff" },
  github: { bg: "#24292e", fg: "#fff" },
  gitlab: { bg: "#FC6D26", fg: "#fff" },
  microsoft: { bg: "#00A4EF", fg: "#fff" },
  amazon: { bg: "#FF9900", fg: "#111" },
  aws: { bg: "#232F3E", fg: "#FF9900", letter: "A" },
  apple: { bg: "#000", fg: "#fff" },
  facebook: { bg: "#1877F2", fg: "#fff" },
  meta: { bg: "#1877F2", fg: "#fff" },
  twitter: { bg: "#1DA1F2", fg: "#fff" },
  x: { bg: "#000", fg: "#fff" },
  discord: { bg: "#5865F2", fg: "#fff" },
  slack: { bg: "#4A154B", fg: "#fff" },
  dropbox: { bg: "#0061FF", fg: "#fff" },
  reddit: { bg: "#FF4500", fg: "#fff" },
  twitch: { bg: "#9146FF", fg: "#fff" },
  steam: { bg: "#1B2838", fg: "#fff" },
  digitalocean: { bg: "#0080FF", fg: "#fff", letter: "D" },
  cloudflare: { bg: "#F38020", fg: "#fff" },
  heroku: { bg: "#430098", fg: "#fff" },
  stripe: { bg: "#635BFF", fg: "#fff" },
  paypal: { bg: "#003087", fg: "#fff" },
  coinbase: { bg: "#0052FF", fg: "#fff" },
  binance: { bg: "#F0B90B", fg: "#111" },
  kraken: { bg: "#5741D9", fg: "#fff" },
  bitwarden: { bg: "#175DDC", fg: "#fff" },
  "1password": { bg: "#1A8CFF", fg: "#fff", letter: "1" },
  lastpass: { bg: "#D32D27", fg: "#fff" },
  npm: { bg: "#CB3837", fg: "#fff" },
  docker: { bg: "#2496ED", fg: "#fff" },
  linkedin: { bg: "#0A66C2", fg: "#fff" },
  instagram: { bg: "#E4405F", fg: "#fff" },
  snapchat: { bg: "#FFFC00", fg: "#111" },
  tiktok: { bg: "#000", fg: "#fff" },
  spotify: { bg: "#1DB954", fg: "#fff" },
  netflix: { bg: "#E50914", fg: "#fff" },
  protonmail: { bg: "#6D4AFF", fg: "#fff" },
  proton: { bg: "#6D4AFF", fg: "#fff" },
  tutanota: { bg: "#840010", fg: "#fff" },
  zoom: { bg: "#2D8CFF", fg: "#fff" },
  figma: { bg: "#F24E1E", fg: "#fff" },
  notion: { bg: "#000", fg: "#fff" },
  vercel: { bg: "#000", fg: "#fff" },
  netlify: { bg: "#00C7B7", fg: "#111" },
  bitbucket: { bg: "#0052CC", fg: "#fff" },
  jira: { bg: "#0052CC", fg: "#fff" },
  atlassian: { bg: "#0052CC", fg: "#fff" },
  okta: { bg: "#007DC1", fg: "#fff" },
  auth0: { bg: "#EB5424", fg: "#fff" },
  shopify: { bg: "#96BF48", fg: "#fff" },
  wordpress: { bg: "#21759B", fg: "#fff" },
  namecheap: { bg: "#DE3723", fg: "#fff" },
  godaddy: { bg: "#1BDBDB", fg: "#111" },
  ovh: { bg: "#123F6D", fg: "#fff" },
  hetzner: { bg: "#D50C2D", fg: "#fff" },
  linode: { bg: "#00A95C", fg: "#fff" },
  vultr: { bg: "#007BFC", fg: "#fff" },
  epic: { bg: "#2F2D2E", fg: "#fff" },
  ea: { bg: "#000", fg: "#fff" },
  ubisoft: { bg: "#000", fg: "#fff" },
  nintendo: { bg: "#E60012", fg: "#fff" },
  playstation: { bg: "#003791", fg: "#fff" },
  xbox: { bg: "#107C10", fg: "#fff" },
};

export function getServiceBrand(issuer: string): { bg: string; fg: string; letter: string } | null {
  const key = issuer.toLowerCase().replace(/[^a-z0-9]/g, "");
  for (const [name, brand] of Object.entries(SERVICE_BRANDS)) {
    if (key.includes(name) || name.includes(key)) {
      return { ...brand, letter: brand.letter ?? issuer.charAt(0).toUpperCase() };
    }
  }
  return null;
}
