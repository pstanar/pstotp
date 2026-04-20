import { Outlet, useRouterState } from "@tanstack/react-router";
import { ThemeProvider } from "@/components/theme-provider";
import { useShutdownOnClose } from "@/hooks/use-shutdown-on-close";

export function RootLayout() {
  const path = useRouterState({ select: (s) => s.location.pathname });
  useShutdownOnClose();

  return (
    <ThemeProvider defaultTheme="system">
      <div key={path} className="page-transition">
        <Outlet />
      </div>
    </ThemeProvider>
  );
}
