# Contributing to AgentBox

Thank you for your interest in contributing to AgentBox! This document provides guidelines for contributing.

## 🔐 Security First

AgentBox prioritizes security above all else. All contributions must maintain or enhance security posture.

### Security Review Checklist

Before submitting a PR, ensure:

- [ ] No secrets or credentials in code
- [ ] All secrets use encrypted storage (age)
- [ ] No new network egress without explicit allowlist
- [ ] Audit logging for all sensitive operations
- [ ] No privilege escalation paths
- [ ] Dependencies vetted for known vulnerabilities
- [ ] Tests pass in isolated VM environment

## 🐛 Reporting Security Vulnerabilities

**DO NOT** create public GitHub issues for security vulnerabilities.

Instead:
1. Use [GitHub Security Advisories](https://github.com/travis-burmaster/agentbox/security/advisories/new)
2. Or email: security@[domain] (response within 48 hours)

## 📝 How to Contribute

### 1. Fork & Clone

```bash
git clone https://github.com/travis-burmaster/agentbox.git
cd agentbox
```

### 2. Create a Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/bug-description
```

### 3. Make Changes

Follow these guidelines:

**Code Style:**
- Use 2 spaces for indentation
- Follow existing patterns in the codebase
- Add comments for complex logic
- Keep functions small and focused

**Commit Messages:**
```
type: Brief description (50 chars max)

Longer explanation if needed (wrap at 72 chars)

- Bullet points for multiple changes
- Reference issues with #123

Breaking Change: Yes/No
Security Impact: Yes/No
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `security`: Security improvement
- `docs`: Documentation
- `refactor`: Code restructuring
- `test`: Test additions
- `chore`: Maintenance

### 4. Test Your Changes

```bash
# Build Docker image
docker build -t agentbox-test .

# Run tests
docker run -it agentbox-test npm test

# Manual testing
docker run -it agentbox-test bash
```

### 5. Submit Pull Request

**PR Title:**
```
[Type] Brief description
```

**PR Description Template:**
```markdown
## Changes

Describe what changed and why.

## Testing

How did you test this?

## Security Impact

- [ ] No security impact
- [ ] Enhances security (describe)
- [ ] Requires security review (explain)

## Breaking Changes

- [ ] No breaking changes
- [ ] Breaking changes (list and migration path)

## Checklist

- [ ] Tests pass
- [ ] Documentation updated
- [ ] CHANGELOG.md updated
- [ ] No secrets in commits
- [ ] Security review complete
```

## 🎯 Areas We Need Help With

### High Priority
- [ ] Vagrant VM configurations (macOS, Linux, Windows)
- [ ] SELinux/AppArmor security profiles
- [ ] Network firewall rule automation
- [ ] HSM integration for key storage
- [ ] Automated compliance reporting

### Medium Priority
- [ ] Documentation improvements
- [ ] Example configurations
- [ ] Integration tests
- [ ] Performance benchmarks
- [ ] Cross-platform compatibility

### Low Priority
- [ ] UI/UX improvements
- [ ] Additional language support
- [ ] Community tools and utilities

## 📚 Development Setup

### Prerequisites

- Node.js 20+
- Docker
- age encryption tool
- Git

### Local Development

```bash
# Install dependencies
npm install

# Build from source
npm run build

# Link for local testing
npm link

# Run locally
agentbox init
agentbox gateway start
```

### Testing

```bash
# Unit tests
npm test

# Integration tests
npm run test:integration

# Security tests
npm run test:security

# All tests
npm run test:all
```

## 🧪 Testing Guidelines

### Unit Tests
- Test individual functions in isolation
- Mock external dependencies
- 80%+ code coverage

### Integration Tests
- Test full workflows end-to-end
- Use isolated test VMs
- Clean up resources after tests

### Security Tests
- Test secret encryption/decryption
- Verify firewall rules
- Check for privilege escalation
- Audit log validation

## 📖 Documentation

### Code Documentation
- Add JSDoc comments for all public APIs
- Include examples in comments
- Document edge cases and gotchas

### User Documentation
- Update README.md for user-facing changes
- Add guides in docs/ for complex features
- Include screenshots/examples where helpful

## 🤝 Code of Conduct

### Our Standards

- **Be respectful**: Treat everyone with respect
- **Be constructive**: Focus on solutions, not blame
- **Be collaborative**: We're all learning together
- **Be secure**: Security is everyone's responsibility

### Unacceptable Behavior

- Harassment, discrimination, or personal attacks
- Publishing others' private information
- Trolling, insulting, or derogatory comments
- Other conduct harmful to the community

## 📜 License

By contributing, you agree that your contributions will be licensed under the MIT License.

## ❓ Questions?

- **General questions**: [GitHub Discussions](https://github.com/travis-burmaster/agentbox/discussions)
- **Bug reports**: [GitHub Issues](https://github.com/travis-burmaster/agentbox/issues)
- **Security issues**: [Security Advisories](https://github.com/travis-burmaster/agentbox/security/advisories/new)

## 🙏 Thank You!

Every contribution helps make AgentBox more secure and accessible. We appreciate your time and effort!

---

**Note on OpenClaw Attribution:**
When contributing features derived from OpenClaw, please maintain attribution in code comments and documentation. This respects the open-source origins of the project.
