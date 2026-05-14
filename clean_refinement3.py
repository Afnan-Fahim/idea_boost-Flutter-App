import re

with open('lib/core/prompt_system/prompt_template.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# For Retorne APENAS um... we can just use the standard removal
patterns = [
    r'\n*Return ONLY a JSON object \(no markdown, no extra text\):[\s\S]*?(?=\'\'\')',
    r'\n*Kewal JSON return karien:[\s\S]*?(?=\'\'\')',
    r'\n*Верните ТОЛЬКО JSON:[\s\S]*?(?=\'\'\')',
    r'\n*أعد فقط JSON:[\s\S]*?(?=\'\'\')',
    r'\n*Gib nur JSON zurück:[\s\S]*?(?=\'\'\')',
    r'\n*Devuelve solo JSON:[\s\S]*?(?=\'\'\')',
    r'\n*Retournez uniquement JSON:[\s\S]*?(?=\'\'\')',
    r'\n*Kembalikan hanya JSON:[\s\S]*?(?=\'\'\')',
    r'\n*Pulang hanya JSON:[\s\S]*?(?=\'\'\')',
    r'\n*Retorne apenas JSON:[\s\S]*?(?=\'\'\')',
    r'\n*Faqat JSON qaytaring:[\s\S]*?(?=\'\'\')',
    r'\n*Chỉ trả về JSON:[\s\S]*?(?=\'\'\')',
    
    # And there were some leftover "Retorne APENAS um objeto JSON"
    r'\n*Retorne APENAS um objeto JSON válido com esta estrutura exata\. Sem markdown, sem blocos de código:[\s\S]*?(?=\'\'\')',
    r'\n*Retorne APENAS um objeto JSON válido com esta estrutura exata\. Sem markdown, sem blocos de código, sem explicações, sem texto extra:[\s\S]*?(?=\'\'\')'
]

for p in patterns:
    text = re.sub(p, '', text)

with open('lib/core/prompt_system/prompt_template.dart', 'w', encoding='utf-8') as f:
    f.write(text)
