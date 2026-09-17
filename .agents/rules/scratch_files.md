# Scratch and Test Files

When creating temporary scratch scripts, test files, or bash patch files, the agent MUST NEVER place them directly in the user's project workspace directory, as this clutters the git status and workspace.

Instead, the agent MUST place all temporary scripts and files in the conversation's persistent scratch directory (`<appDataDir>/brain/<conversation-id>/scratch/`).

If the scratch directory is not available, use `/tmp/`.

By doing this, the scripts are kept out of sight, but are still safely saved to the conversation's cache history so they can be recalled if needed without clogging the user's project storage.
