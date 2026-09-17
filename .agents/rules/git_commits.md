# Automatic Git Commits

Whenever code, configuration, or documentation files are created or updated, the agent MUST make a git commit to save and version the progress.

## Guidelines:
1. Stage only the relevant modified or created files (`git add <files>`).
2. Write concise, conventional commit messages (e.g., `feat: ...`, `fix: ...`, `docs: ...`, `refactor: ...`, `chore: ...`).
3. Commit proactively after completing each logical unit of work, feature implementation, or bug fix without waiting for the user to prompt for a commit.
4. Ensure temporary scratch files are cleaned up before committing.
