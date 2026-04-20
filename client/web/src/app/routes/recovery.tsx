import { createFileRoute } from "@tanstack/react-router";
import { RecoveryPage } from "@/features/recovery/components/recovery-page";

export const Route = createFileRoute("/recovery")({
  component: RecoveryPage,
});
