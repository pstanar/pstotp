import { Sun, Moon, SunMoon } from "lucide-react";
import { useTheme } from "@/hooks/use-theme";

export function ModeToggle() {
  const { theme, setTheme } = useTheme();

  const next = () => {
    if (theme === "light") setTheme("dark");
    else if (theme === "dark") setTheme("system");
    else setTheme("light");
  };

  return (
    <button
      onClick={next}
      className="text-muted-foreground hover:text-foreground p-2"
      title={`Theme: ${theme}`}
    >
      {theme === "light" && <Sun className="h-5 w-5" />}
      {theme === "dark" && <Moon className="h-5 w-5" />}
      {theme === "system" && <SunMoon className="h-5 w-5" />}
      <span className="sr-only">Toggle theme</span>
    </button>
  );
}
