import { createFileRoute, redirect } from "@tanstack/react-router";

export const Route = createFileRoute("/_authenticated/devices")({
  beforeLoad: () => {
    throw redirect({ to: "/settings" });
  },
});
