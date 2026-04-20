import { cn } from "@/lib/css-utils";

interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  error?: string;
}

export function Input({ label, error, className, id, ...props }: InputProps) {
  return (
    <div>
      {label && (
        <label htmlFor={id} className="mb-1.5 block text-sm font-medium">
          {label}
        </label>
      )}
      <input
        id={id}
        className={cn(
          "border-input bg-background w-full rounded-md border px-3 py-2 text-sm shadow-sm transition-colors",
          "placeholder:text-muted-foreground",
          "focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20",
          "disabled:cursor-not-allowed disabled:opacity-50",
          error && "border-destructive focus:ring-destructive/20",
          className,
        )}
        {...props}
      />
      {error && (
        <p className="text-destructive mt-1.5 text-xs">{error}</p>
      )}
    </div>
  );
}
