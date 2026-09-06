"use client";

import { createContext, useState } from "react";

// The real app wraps the whole authed shell in client providers (theme, toaster).
export const ShellContext = createContext(null);

export default function Providers({ children }) {
  const [state] = useState({ theme: "dark" });
  return <ShellContext.Provider value={state}>{children}</ShellContext.Provider>;
}
