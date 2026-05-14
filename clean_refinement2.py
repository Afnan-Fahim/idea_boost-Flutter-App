import re

with open('lib/core/prompt_system/prompt_template.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    if "_getLanguageEnforcement(" in line:
        # Just close the string since this line was at the end
        new_lines.append("'''\n")
    else:
        new_lines.append(line)

with open('lib/core/prompt_system/prompt_template.dart', 'w', encoding='utf-8') as f:
    f.writelines(new_lines)
