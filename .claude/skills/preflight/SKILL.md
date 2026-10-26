---
name: preflight
description: Checks a TabWindo change before it's merged. It formats, builds, tests and lints, then runs Claude's code review and security review locally, guided by REVIEW.md. Use when asked to preflight, to check a branch, or to review before a merge or a pull request.
allowed-tools: Bash(swift build *), Bash(swift test *), Bash(xcrun swift format *), Bash(git status *), Bash(git diff *), Bash(git log *)
---

# Preflight

Checks this branch before it's merged. Everything runs on this Mac with the user's Claude subscription: no
GitHub Action, no API key.

1. **Format.** Run `xcrun swift format --in-place --recursive Sources Tests Package.swift`, then
   `git status --short`. Name any files it changed. Don't commit them.
2. **Build.** Run `swift build`. Note any warnings in files this branch changed.
3. **Test.** Run `swift test`.
4. **Lint.** Run `xcrun swift format lint --strict --recursive Sources Tests Package.swift`.
5. **Review.** Read `REVIEW.md`. Run the `code-review` skill at `high` effort on this branch's changes since
   `main`, plus any uncommitted ones. Then run the `security-review` skill; it diffs against `origin/HEAD`, so
   without an `origin` remote say so and skip it. Never use `ultra`: it runs in the cloud. Keep only the findings
   REVIEW.md asks for, reported its way.
6. **Report.** One line per check (pass or fail, with the first error), then the review findings, most severe
   first, or "No issues found."

When a step fails, carry on with the steps that don't depend on it: tests need the build, but the lint and the
review don't. Fix nothing unless the user asks.
