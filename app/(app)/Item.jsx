"use client";

import { useState } from "react";

// A client component per row. Each one is a client module reference in the Flight
// stream, which is what splits the action response into many chunks (the real app
// renders a client card component per folder/deck).
export default function Item({ label, blurb }) {
  const [hot, setHot] = useState(false);
  return (
    <li data-testid="item" onMouseEnter={() => setHot(true)} style={{ opacity: hot ? 0.9 : 1 }}>
      <b>{label}</b> <span style={{ color: "#666" }}>{blurb}</span>
    </li>
  );
}
