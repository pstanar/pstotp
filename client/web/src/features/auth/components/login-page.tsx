import { useState } from "react";
import { LoginForm } from "./login-form";
import { RegisterForm } from "./register-form";
import { AnimatedLogo } from "@/components/animated-logo";

export function LoginPage() {
  const [isRegistering, setIsRegistering] = useState(false);

  return (
    <div className="flex min-h-screen items-center justify-center px-4 py-12">
      <div className="w-full max-w-sm space-y-8">
        <div className="text-center">
          <AnimatedLogo size={48} className="mx-auto mb-4" />
          <h1 className="text-3xl font-bold tracking-tight">PsTotp</h1>
          <p className="text-muted-foreground mt-1 text-sm">
            {isRegistering ? "Create your account" : "Sign in to your vault"}
          </p>
        </div>

        <div className="border-border bg-card rounded-xl border p-6 shadow-sm">
          {isRegistering ? (
            <RegisterForm onSwitchToLogin={() => setIsRegistering(false)} />
          ) : (
            <LoginForm onSwitchToRegister={() => setIsRegistering(true)} />
          )}
        </div>
      </div>
    </div>
  );
}
