import re

with open('lib/core/prompt_system/prompt_template.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. For Hashtag, ViralRewrite, ShotIdeas: they have an OUTPUT FORMAT heading.
# We strip everything from that heading until the closing '''
output_format_headings = [
    r'OUTPUT FORMAT:',
    r'ФОРМАТ ВЫВОДА:',
    r'CHIQISH FORMATI:',
    r'تنسيق الإخراج:',
    r'AUSGABE FORMAT:',
    r'FORMATO DE SALIDA:',
    r'FORMAT DE SORTIE:',
    r'ĐỊNH DẠNG ĐẦU RA:',
    r'FORMAT KELUARAN:'
]

for heading in output_format_headings:
    pattern = r'\n*' + heading + r'[\s\S]*?(?=\'\'\')'
    content = re.sub(pattern, '', content)

# 2. For CommentGenerator: it starts with "Return ONLY a valid JSON object..." and ends with the JSON format or FAIL-SAFE.
# The pattern for CommentGenerator JSON block:
# It starts with "Return ONLY" or something similar. But wait, it has Requirements *after* it in some, and CRITICAL OUTPUT RULES.
# Let's target the exact blocks.
# Let's remove the "Return ONLY a valid JSON... " till "}"
json_block_patterns = [
    r'Return ONLY a valid JSON object with this exact structure:\s*\{\s*\$toneStructure\s*\}',
    r'Вернуть ТОЛЬКО валидный объект JSON с этой точной структурой:\s*\{\s*\$toneStructure\s*\}',
    r'FAQAT bu aniq tuzulishda haqiqiy JSON ob\'ektini qaytaring:\s*\{\s*\$toneStructure\s*\}',
    r'أعد فقط كائن JSON صحيح بهذا الهيكل الدقيق:\s*\{\s*\$toneStructure\s*\}',
    r'Geben Sie nur ein gültiges JSON-Objekt mit dieser genauen Struktur zurück:\s*\{\s*\$toneStructure\s*\}',
    r'Devuelve SOLO un objeto JSON válido con esta estructura exacta:\s*\{\s*\$toneStructure\s*\}',
    r'Retournez UNIQUEMENT un objet JSON valide avec cette structure exacte\s*:\s*\{\s*\$toneStructure\s*\}',
    r'Sirf valid JSON object return karien is exact structure ke saath:\s*\{\s*\$toneStructure\s*\}',
    r'Hanya kembalikan objek JSON yang valid dengan struktur yang tepat ini:\s*\{\s*\$toneStructure\s*\}',
    r'Hanya pulang objek JSON yang sah dengan struktur yang tepat ini:\s*\{\s*\$toneStructure\s*\}',
    r'Retorne APENAS um objeto JSON válido com esta estrutura exata:\s*\{\s*\$toneStructure\s*\}',
    r'Chỉ trả về một đối tượng JSON hợp lệ với cấu trúc chính xác này:\s*\{\s*\$toneStructure\s*\}'
]

for p in json_block_patterns:
    content = re.sub(r'\n*' + p, '', content)

# Remove the CRITICAL OUTPUT RULES block at the end of CommentGenerator cases
critical_rules_headings = [
    r'CRITICAL OUTPUT RULES \(MUST FOLLOW STRICTLY\):',
    r'КРИТИЧЕСКИЕ ПРАВИЛА ВЫВОДА \(СЛЕДУЙТЕ СТРОГО\):',
    r'KRITIK CHIQISH QO\'YLLARI \(QATIY RIOYA QILING\):',
    r'قواعد العملية الحرجة \(اتبع بصرامة\):',
    r'KRITISCHE AUSGANGSREGELN \(STRENG EINHALTEN\):',
    r'REGLAS CRÍTICAS DE SALIDA \(CUMPLIR ESTRICTAMENTE\):',
    r'RÈGLES CRITIQUES DE SORTIE \(RESPECTER STRICTEMENT\) :',
    r'ZAROORI OUTPUT RULES \(STRICTLY FOLLOW KARIEN\):',
    r'PERATURAN OUTPUT KRITIS \(IKUTI DENGAN KETAT\):',
    r'PERATURAN KELUARAN KRITIKAL \(IKUTI DENGAN KETAT\):',
    r'REGRAS DE SAÍDA CRÍTICAS \(CUMPRIR ESTRITAMENTE\):',
    r'QUY TẮC ĐẦU RA TÀI HẠN \(TUÂN THỰ HOÀN TOÀN\):'
]

for heading in critical_rules_headings:
    pattern = r'\n*' + heading + r'[\s\S]*?(?=\'\'\')'
    content = re.sub(pattern, '', content)


with open('lib/core/prompt_system/prompt_template.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print("Done cleaning prompt_template.dart")
