# Contributing to SwiftCoderTUI

Thanks for your interest in contributing.

## Before You Start

- Search existing issues and pull requests before opening a new one.
- For large changes, open an issue first to discuss direction.
- Keep pull requests focused and reviewable.

## Development Setup

Requirements:

- Swift 6.3.1+
- macOS 15+

Build and test:

```bash
swift build
swift test
```

Run the example app:

```bash
swift run Example
```

## Branching and Commits

- Create a branch from main.
- Use clear commit messages in imperative mood.
- Keep unrelated changes out of the same pull request.

Example commit message style:

- renderer: fix footer repaint on resize
- autocomplete: guard slash-command submenu refresh
- tests: add regression for diff renderer reset

## Coding Guidelines

- Follow existing naming and style conventions in the project.
- Prefer small, composable changes over large rewrites.
- Preserve public API compatibility unless the change explicitly targets a breaking release.
- Add concise comments only where logic is not obvious.

## Tests

- Add or update tests for any behavior change.
- Prefer deterministic tests using VirtualTerminal where possible.
- Include regression tests for bug fixes.

A change is ready when:

- swift build passes
- swift test passes
- Relevant tests for your change are included

## Pull Request Checklist

Please include in your PR description:

- Summary of the change
- Motivation and expected behavior
- Any trade-offs or known limitations
- Test coverage details

If your change affects terminal rendering or interaction behavior, include:

- Before/after notes
- Terminal/environment used for validation

## Reporting Bugs

When opening a bug report, include:

- Steps to reproduce
- Expected result
- Actual result
- Swift version and macOS version
- Minimal reproducible input when possible

## Security Issues

Please do not report security vulnerabilities in public issues. See SECURITY.md for private reporting instructions.

## License

By contributing, you agree that your contributions are licensed under this repository's MIT License.
