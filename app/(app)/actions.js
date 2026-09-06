"use server";

import { cookies } from "next/headers";
import { revalidatePath } from "next/cache";

export async function setSortAction(formData) {
  const sort = formData.get("sort") === "desc" ? "desc" : "asc";
  const store = await cookies();
  store.set("sort", sort, { path: "/", sameSite: "lax" });
  revalidatePath("/");
}
