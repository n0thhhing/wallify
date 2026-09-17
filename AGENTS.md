# Agent Rules & Instructions

This repository contains operational rules and guidelines for AI agents working on Wallify.
Agents must strictly follow all rules defined here and in `.agents/rules/`.

## 1. File Editing
- Use the native `replace_file_content` tool as the default method for file edits.
- Never write ad-hoc bash patch scripts (`patch.pl`, `sed`, `perl`) for modifying existing code.
- Detailed rule: [`.agents/rules/editing.md`](.agents/rules/editing.md)

## 2. Automatic Git Commits
- Whenever code, configuration, or documentation files are created or updated, automatically create a git commit to save progress.
- Stage only relevant files (`git add <files>`), write concise conventional commit messages (`feat:`, `fix:`, `docs:`, `chore:`), and do not wait for the user to ask for a commit.
- Detailed rule: [`.agents/rules/git_commits.md`](.agents/rules/git_commits.md)

## 3. Scratch Files
- Never write temporary test scripts or scratch files directly into the repository root.
- Clean up any temporary files before completing tasks.
- Detailed rule: [`.agents/rules/scratch_files.md`](.agents/rules/scratch_files.md)
