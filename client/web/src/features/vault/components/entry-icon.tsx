import { getServiceBrand } from "@/features/vault/utils/service-icons";

interface EntryIconProps {
  icon?: string;
  issuer: string;
  size?: "sm" | "lg";
}

export function EntryIcon({ icon, issuer, size = "sm" }: EntryIconProps) {
  const isDataUrl = icon?.startsWith("data:");
  const isEmoji = icon && !isDataUrl;

  const imgClass = size === "lg" ? "h-12 w-12 rounded-full" : "h-7 w-7 rounded-full";
  const emojiClass = size === "lg" ? "text-3xl" : "text-lg";

  if (isDataUrl) return <img src={icon} alt="" className={imgClass} />;
  if (isEmoji) return <span className={emojiClass}>{icon}</span>;

  // Try branded service icon
  const brand = getServiceBrand(issuer);
  const dim = size === "lg" ? "h-12 w-12 text-xl" : "h-7 w-7 text-xs";

  if (brand) {
    return (
      <div
        className={`${dim} flex items-center justify-center rounded-full font-bold`}
        style={{ backgroundColor: brand.bg, color: brand.fg }}
      >
        {brand.letter}
      </div>
    );
  }

  // Fallback: muted letter
  const letterClass = size === "lg"
    ? "h-12 w-12 text-xl"
    : "h-7 w-7 text-xs";
  return (
    <div className={`${letterClass} bg-muted text-muted-foreground flex items-center justify-center rounded-full font-bold`}>
      {issuer.charAt(0).toUpperCase()}
    </div>
  );
}
