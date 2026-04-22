import { useState, useEffect } from "react";
import { Link, useNavigate } from "@tanstack/react-router";
import { ArrowLeft, User, Monitor, FileText, ShieldCheck } from "lucide-react";
import { useAuthStore } from "@/stores/useAuthStore";
import { useSettingsStore, LOCK_TIMEOUT_OPTIONS } from "@/stores/useSettingsStore";
import { ModeToggle } from "@/components/mode-toggle";
import { ChangePasswordForm } from "./change-password-form";
import { RecoveryManagement } from "./recovery-management";
import { WebAuthnManagement } from "@/features/webauthn/components/webauthn-management";
import { DevicesPanel } from "@/features/devices/components/devices-panel";
import { AuditPanel } from "@/features/audit/components/audit-panel";
import { AdminPage } from "@/features/admin/components/admin-page";
import { ImportExport } from "./import-export";

type Tab = "account" | "devices" | "audit" | "admin";

interface TabDef {
  id: Tab;
  label: string;
  icon: typeof User;
  adminOnly?: boolean;
}

const allTabs: TabDef[] = [
  { id: "account", label: "Account", icon: User },
  { id: "devices", label: "Devices", icon: Monitor },
  { id: "audit", label: "Audit", icon: FileText },
  { id: "admin", label: "Admin", icon: ShieldCheck, adminOnly: true },
];

export function SettingsPage() {
  const [activeTab, setActiveTab] = useState<Tab>("account");
  const email = useAuthStore((s) => s.email);
  const isAdmin = useAuthStore((s) => s.isAdmin);
  const navigate = useNavigate();

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape" && !(e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement)) {
        void navigate({ to: "/" });
      }
    };
    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [navigate]);

  const tabs = allTabs.filter((t) => !t.adminOnly || isAdmin);

  return (
    <div className="mx-auto max-w-2xl px-4 py-6">
      <header className="mb-6 flex items-center gap-3">
        <Link to="/" className="text-muted-foreground hover:text-foreground">
          <ArrowLeft className="h-5 w-5" />
        </Link>
        <h1 className="text-xl font-bold">Settings</h1>
      </header>

      {/* Tabs */}
      <div className="border-border mb-6 flex flex-wrap border-b">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={`flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium border-b-2 -mb-px transition-colors ${
              activeTab === tab.id
                ? "border-primary text-foreground"
                : "border-transparent text-muted-foreground hover:text-foreground"
            }`}
          >
            <tab.icon className="h-4 w-4" />
            {tab.label}
          </button>
        ))}
      </div>

      {/* Tab content */}
      {activeTab === "account" && (
        <div className="space-y-5">
          <section className="border-border rounded-lg border bg-card p-5 shadow-sm">
            <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">Profile</h3>
            <div className="space-y-3">
              <div>
                <label className="text-sm font-medium">Email</label>
                <p className="text-muted-foreground mt-0.5 text-sm">{email}</p>
              </div>
              <div>
                <label className="text-sm font-medium">Theme</label>
                <div className="mt-1 flex items-center gap-2">
                  <ModeToggle />
                  <span className="text-muted-foreground text-sm">Click to cycle: Light / Dark / System</span>
                </div>
              </div>
            </div>
          </section>

          <section className="border-border rounded-lg border bg-card p-5 shadow-sm">
            <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">Display</h3>
            <ShowNextCodeSetting />
          </section>

          <section className="border-border rounded-lg border bg-card p-5 shadow-sm">
            <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">Security</h3>
            <div className="space-y-4">
              <div>
                <label className="text-sm font-medium">Change Password</label>
                <div className="mt-2">
                  <ChangePasswordForm />
                </div>
              </div>
              <WebAuthnManagement />
              <RecoveryManagement />
              <ImportExport />
              <AutoLockSetting />
            </div>
          </section>
        </div>
      )}

      {activeTab === "devices" && <DevicesPanel />}

      {activeTab === "audit" && <AuditPanel />}

      {activeTab === "admin" && <AdminPage />}

      <p className="mt-8 text-center text-xs text-muted-foreground">
        {import.meta.env.VITE_APP_VERSION || "dev"}
      </p>
    </div>
  );
}

function ShowNextCodeSetting() {
  const showNextCode = useSettingsStore((s) => s.showNextCode);
  const setShowNextCode = useSettingsStore((s) => s.setShowNextCode);
  return (
    <label className="flex cursor-pointer items-start gap-3">
      <input
        type="checkbox"
        checked={showNextCode}
        onChange={(e) => setShowNextCode(e.target.checked)}
        className="border-input mt-0.5 h-4 w-4 rounded border accent-primary"
      />
      <span className="text-sm">
        <span className="font-medium">Show upcoming code</span>
        <span className="text-muted-foreground mt-0.5 block">
          In the last 10 seconds, preview the next code; copying in the last 3 seconds hands you the fresh one.
        </span>
      </span>
    </label>
  );
}

function AutoLockSetting() {
  const lockTimeoutMs = useSettingsStore((s) => s.lockTimeoutMs);
  const setLockTimeoutMs = useSettingsStore((s) => s.setLockTimeoutMs);
  return (
    <div>
      <label htmlFor="auto-lock-select" className="text-sm font-medium">
        Auto-lock
      </label>
      <p className="text-muted-foreground mt-0.5 text-sm">
        Lock the vault after this long without activity.
      </p>
      <select
        id="auto-lock-select"
        value={lockTimeoutMs}
        onChange={(e) => setLockTimeoutMs(Number(e.target.value))}
        className="border-input bg-background mt-2 rounded-md border px-3 py-1.5 text-sm"
      >
        {LOCK_TIMEOUT_OPTIONS.map((opt) => (
          <option key={opt.ms} value={opt.ms}>
            {opt.label}
          </option>
        ))}
      </select>
    </div>
  );
}
