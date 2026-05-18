import { useEffect, useState } from "react";
import { useToast } from "@/hooks/use-toast";
import {
  getServerSettings,
  setRegistrationEnabled,
  type AdminServerSettings,
} from "@/features/admin/api/admin-api";

/**
 * Runtime-toggleable server settings exposed only to admins. Lives in
 * the admin page, never in appsettings — single source of truth so
 * operators can flip behaviour without a server restart and get an
 * audit-log entry for free.
 */
export function SettingsSection() {
  const [settings, setSettings] = useState<AdminServerSettings | null>(null);
  const [busy, setBusy] = useState(false);
  const { toast } = useToast();

  useEffect(() => {
    void getServerSettings()
      .then(setSettings)
      .catch(() => toast("Failed to load server settings", "error"));
  }, [toast]);

  const toggleRegistration = async (next: boolean) => {
    setBusy(true);
    try {
      const updated = await setRegistrationEnabled(next);
      setSettings(updated);
      toast(`Registration ${next ? "enabled" : "disabled"}`, "success");
    } catch (err) {
      toast(err instanceof Error ? err.message : "Toggle failed", "error");
    } finally {
      setBusy(false);
    }
  };

  if (settings === null) return null;

  return (
    <section className="border-border rounded-lg border bg-card p-5 shadow-sm">
      <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
        Server settings
      </h3>
      <div className="flex items-center justify-between gap-4">
        <div>
          <div className="text-sm font-medium">User registration</div>
          <p className="mt-0.5 text-xs text-muted-foreground">
            When off, <code className="font-mono">/auth/register/begin</code>{" "}
            returns 403 and no new users can self-register. Existing users are
            unaffected. Last changed{" "}
            {new Date(settings.updatedAt).toLocaleString()}.
          </p>
        </div>
        <label className="inline-flex cursor-pointer items-center gap-2">
          <input
            type="checkbox"
            checked={settings.registrationEnabled}
            disabled={busy}
            onChange={(e) => void toggleRegistration(e.target.checked)}
            className="border-input h-4 w-4 rounded border accent-primary"
          />
          <span className="text-sm">
            {settings.registrationEnabled ? "Enabled" : "Disabled"}
          </span>
        </label>
      </div>
    </section>
  );
}
