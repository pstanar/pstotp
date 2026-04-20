import { createRouter } from "@tanstack/react-router";
import { routeTree } from "./routeTree.gen";
import { basePath } from "@/lib/base-path";

export const router = createRouter({
  routeTree,
  basepath: basePath || undefined,
});

declare module "@tanstack/react-router" {
  interface Register {
    router: typeof router;
  }
}
