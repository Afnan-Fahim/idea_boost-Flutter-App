import re

with open('lib/core/prompt_system/prompt_template.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# Lines like:
# ⚠️ CRITICAL: refined_steps MUST be PLAIN ARRAY OF STRINGS ["String 1", "String 2"], NEVER objects${_getLanguageEnforcement('en')}'''
# We will just replace everything from "⚠️ " to "_getLanguageEnforcement(.*)}'''" with "'''"
pattern = r'⚠️ .*?\$\{_getLanguageEnforcement\([^)]+\)\}\'\'\''
text = re.sub(pattern, "'''", text)

# Just in case, clean any trailing newlines before '''
text = re.sub(r'\n+\'\'\'', "\n'''", text)

with open('lib/core/prompt_system/prompt_template.dart', 'w', encoding='utf-8') as f:
    f.write(text)
