# Plan: zt-canary

project: zt-canary

A tiny TypeScript library with one exported function greet(name) and one test. Test repo for
zero-touch provisioning.

## G1: greet library

area: greet
depends: seed

Turn the seed package `packages/shared` into the library: it exports one function,
`greet(name)`, that returns `Hello, <name>!`, covered by one test.

### Tasks

- T1: Export greet(name) from packages/shared with one test
  touch: packages/shared/src/**, packages/shared/AGENTS.md, changelog.d/*.md
  size: 30

### Done when

- UC-G1-1: `greet("Ada")` returns `"Hello, Ada!"`, and `greet` is the only export of `@keelstackhq/shared`.
