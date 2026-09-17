# File Editing Tool Preference

When modifying existing files, the agent MUST prioritize using the native `replace_file_content` tool (the "client edit file" tool) instead of creating bash patch files (e.g., using `cat << 'EOF' > patch.pl && perl patch.pl`). 

The `replace_file_content` tool should always be the default approach for editing files, unless the edit is significantly complex, heavily multi-line across many different disparate sections, or otherwise explicitly requires a bash script/patch fallback.
