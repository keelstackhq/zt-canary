import { expect, test } from "vite-plus/test";
import * as shared from "./index";

// UC-G1-1: greet("Ada") returns "Hello, Ada!", and greet is the package's only export.
test("greet", () => {
  expect(shared.greet("Ada")).toBe("Hello, Ada!");
  expect(Object.keys(shared)).toEqual(["greet"]);
});
