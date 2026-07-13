# Commit Style

This repository uses Conventional Commits.

## Format

```text
type(scope): description
```

## Types

- `feat`: new functionality
- `fix`: bug fix
- `docs`: documentation
- `refactor`: internal restructuring
- `test`: tests and fixtures
- `chore`: maintenance and repository tooling
- `perf`: performance improvement
- `ci`: continuous integration
- `build`: build or packaging changes

## Common scopes

- `audit`
- `vm`
- `kernel`
- `storage`
- `network`
- `backup`
- `migration`
- `lib`
- `standards`
- `docs`
- `repo`

## Examples

```text
feat(audit): add Proxmox host audit
fix(audit): classify mixed disk buses correctly
docs(howto): document IDE to SCSI migration
refactor(lib): extract shared output functions
test(vm): add legacy disk fixtures
chore(repo): standardize directory layout
```

## Rules

- use imperative language;
- keep the subject concise;
- do not end the subject with a period;
- keep unrelated changes in separate commits;
- explain important reasons in the commit body.
