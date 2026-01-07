# Contributing to Radish

Thank you for your interest in contributing to Radish! This document provides guidelines for contributing to the project.

## Code of Conduct

Be respectful, inclusive, and constructive. We're all here to build better tools for autonomous coding.

## How to Contribute

### Reporting Bugs

1. Check existing issues to avoid duplicates
2. Use the bug report template
3. Include:
   - Radish version (`./radish.sh --version`)
   - OS and bash version
   - Steps to reproduce
   - Expected vs actual behavior
   - Relevant logs from `logs/` directory

### Suggesting Features

1. Check existing issues and discussions
2. Open a new issue with the "feature request" label
3. Describe:
   - The problem you're solving
   - Your proposed solution
   - Alternative approaches considered

### Submitting Code

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Test thoroughly
5. Commit with clear messages
6. Push to your fork
7. Open a Pull Request

## Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/radish.git
cd radish

# Make scripts executable
chmod +x radish.sh scripts/*.sh

# Run tests (when available)
./tests/run_tests.sh
```

## Code Style

### Bash Scripts

- Use `set -euo pipefail` at the top
- Quote variables: `"${var}"` not `$var`
- Use `[[ ]]` for tests, not `[ ]`
- Add comments for non-obvious logic
- Keep functions focused and small
- Use meaningful variable names

### YAML Configuration

- Use 2-space indentation
- Add comments for each section
- Keep related options grouped

### Documentation

- Update README.md for user-facing changes
- Add inline comments for complex code
- Include examples where helpful

## Testing

Before submitting:

1. Test with a real autonomous coding session
2. Verify all guardrails work as expected
3. Check that logs are generated correctly
4. Test rollback scenarios

## Pull Request Guidelines

- Keep PRs focused on a single change
- Update documentation if needed
- Add tests for new features
- Ensure all existing tests pass
- Write a clear PR description

## Release Process

1. Update version in `radish.sh`
2. Update `prd.json`
3. Add entry to `progress.txt`
4. Create GitHub release with changelog

## Questions?

- Open a GitHub Discussion
- Email: kai@longarcstudios.com

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for helping make autonomous coding safer!

— Long Arc Studios
