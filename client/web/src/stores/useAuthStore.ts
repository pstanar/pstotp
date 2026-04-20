import { create } from "zustand";
import { persist, createJSONStorage } from "zustand/middleware";

interface AuthState {
  isAuthenticated: boolean;
  userId: string | null;
  email: string | null;
  deviceId: string | null;
  deviceStatus: string | null;
  role: string | null;
  isAdmin: boolean;
}

interface AuthActions {
  login: (state: Omit<AuthState, "isAuthenticated" | "isAdmin">) => void;
  logout: () => void;
}

interface AuthStore extends AuthState, AuthActions {}

const initialState: AuthState = {
  isAuthenticated: false,
  userId: null,
  email: null,
  deviceId: null,
  deviceStatus: null,
  role: null,
  isAdmin: false,
};

export const useAuthStore = create<AuthStore>()(
  persist(
    (set) => ({
      ...initialState,
      login: (state) =>
        set({
          isAuthenticated: true,
          isAdmin: state.role === "Admin",
          ...state,
        }),
      logout: () => set(initialState),
    }),
    {
      name: "pstotp-auth",
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({
        userId: state.userId,
        email: state.email,
        deviceId: state.deviceId,
        role: state.role,
      }),
    },
  ),
);
