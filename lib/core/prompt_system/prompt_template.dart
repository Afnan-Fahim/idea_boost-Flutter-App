/// lib/core/prompt_system/prompt_template.dart
///
/// Base template class and specific generators for each of the 6 generators.
/// Templates handle generator-specific prompt construction logic ONLY.
///
/// WHAT TEMPLATES OWN:
///   • Generator-specific expert role & context (translated per language)
///   • Generator-specific requirements (e.g., "5 comments per tone", "25-35 hashtags")
///   • Content-specific parameters (toneStructure, selectedDescriptions, etc.)
///
/// WHAT TEMPLATES DO NOT OWN (handled by PromptBuilder ranks):
///   • Language enforcement ("MUST BE IN X LANGUAGE") → Rank 1
///   • Platform optimization → Rank 2
///   • Tone guidance → Rank 3
///   • Locale/cultural context → Rank 4
///   • Domain/audience relevance → Rank 5
///   • JSON output format → Rank 6
///
/// NOTE: Rank 1 language enforcement is handled by PromptBuilder in prompt_handler.dart.
/// Templates must NOT call _buildLanguageEnforcement() — it is injected globally.
///
/// LANGUAGE STRATEGY (Apr 2026):
///   All requirement/instruction text inside each generator template is now
///   written in the target language so the LLM receives a fully native prompt
///   instead of an English body with a tacked-on enforcement block.
///   This eliminates the primary cause of language drift.

import 'package:flutter/foundation.dart';

import 'models/prompt_context.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SHARED LANGUAGE UTILITIES
// ─────────────────────────────────────────────────────────────────────────────

/// All supported language codes.
const _supportedLanguages = {
  'en',
  'ru',
  'uz',
  'ar',
  'de',
  'es',
  'fr',
  'hi',
  'id',
  'ms',
  'pt',
  'vi',
};

/// Returns [lang] if supported, otherwise falls back to 'en'.
String _resolvedLang(String lang) =>
    _supportedLanguages.contains(lang) ? lang : 'en';

// ─────────────────────────────────────────────────────────────────────────────
// RANK 1 · LANGUAGE ENFORCEMENT BLOCK
//
// Appended to the END of every prompt so it carries maximum recency weight.
// Explicitly names both the language AND the script to prevent the model
// from compromising into transliteration (e.g. writing Russian words in
// Latin characters like "Vsegda budite gotovыi" instead of Cyrillic).
//
// Design decisions:
//   • Placed LAST — recency is the strongest positioning signal for LLMs
//   • Names the native script explicitly — "Russian" alone is ambiguous;
//     "Cyrillic script" is not
//   • States the rule twice — once as a constraint, once as a final reminder
//   • Distinguishes JSON keys (stay English) from JSON values (must be native)
//   • English and Latin-only languages skip script enforcement entirely
// ─────────────────────────────────────────────────────────────────────────────

/// Full human-readable language names for use in enforcement text.
const Map<String, String> _languageNames = {
  'en': 'English',
  'ru': 'Russian',
  'uz': 'Uzbek',
  'ar': 'Arabic',
  'de': 'German',
  'es': 'Spanish',
  'fr': 'French',
  'hi': 'Hindi',
  'id': 'Indonesian',
  'ms': 'Malay',
  'pt': 'Portuguese',
  'vi': 'Vietnamese',
};

/// Script metadata per language.
/// [name] is shown in enforcement text. [nativeExample] anchors the model
/// to the correct writing system by showing a native word.
class _ScriptInfo {
  final String name;
  final String nativeExample;
  const _ScriptInfo({required this.name, required this.nativeExample});
}

const Map<String, _ScriptInfo> _scriptInfo = {
  // No special enforcement for English (model default)
  'en': _ScriptInfo(name: 'Latin', nativeExample: ''),

  // Cyrillic — highest risk of transliteration drift
  'ru': _ScriptInfo(name: 'Cyrillic', nativeExample: 'Например: «Привет мир»'),

  // Uzbek uses Latin officially since 1993, but model may switch to Cyrillic
  'uz': _ScriptInfo(
    name: 'Latin (Uzbek)',
    nativeExample: "Masalan: «Salom dunyo»",
  ),

  // Arabic script — RTL, high risk of falling back to transliteration
  'ar': _ScriptInfo(name: 'Arabic', nativeExample: 'مثال: «مرحبا بالعالم»'),

  // Devanagari — high risk of Hinglish/transliteration drift
  'hi': _ScriptInfo(
    name: 'Devanagari',
    nativeExample: 'उदाहरण: «नमस्ते दुनिया»',
  ),

  // Vietnamese Latin has unique diacritics that models sometimes drop
  'vi': _ScriptInfo(
    name: 'Latin (Vietnamese with diacritics)',
    nativeExample: 'Ví dụ: «Xin chào thế giới»',
  ),

  // These use standard Latin — no script enforcement needed,
  // only language naming is sufficient
  'de': _ScriptInfo(name: 'Latin', nativeExample: ''),
  'es': _ScriptInfo(name: 'Latin', nativeExample: ''),
  'fr': _ScriptInfo(name: 'Latin', nativeExample: ''),
  'pt': _ScriptInfo(name: 'Latin', nativeExample: ''),
  'id': _ScriptInfo(name: 'Latin', nativeExample: ''),
  'ms': _ScriptInfo(name: 'Latin', nativeExample: ''),
};

/// Languages that need explicit script + no-transliteration enforcement.
/// Latin-standard European/Asian languages (de, es, fr, pt, id, ms) do not.
bool _needsScriptEnforcement(String lang) =>
    const {'ru', 'ar', 'hi', 'vi', 'uz'}.contains(lang);

/// Builds the Rank 1 language enforcement block.
/// Returns an empty string for English (no enforcement needed).
/// Must be called as the LAST element of every prompt string.
String _buildLanguageEnforcement(String language) {
  final lang = _resolvedLang(language);

  // English is the model default — no enforcement block needed
  if (lang == 'en') return '';

  final langName = _languageNames[lang]!;
  final script = _scriptInfo[lang]!;

  final scriptClause = _needsScriptEnforcement(lang)
      ? '\n- Write exclusively in ${script.name} script. '
            'NEVER use Latin/romanized transliteration. '
            '${script.nativeExample}'
      : '';

  return '''

⚠️ LANGUAGE ENFORCEMENT (RANK 1 — HIGHEST PRIORITY) ⚠️
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ABSOLUTE REQUIREMENT — overrides ALL other instructions:
- ALL output text values MUST be written in $langName ONLY$scriptClause
- Do NOT mix languages. Do NOT substitute English words for $langName words.
- Do NOT transliterate. Do NOT romanize. Use native $langName characters only.
- JSON field KEYS stay in English. JSON field VALUES must be in $langName.
- This rule applies to EVERY string value in the JSON response without exception.

FINAL REMINDER: Respond with all content in $langName (native $langName script only).
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━''';
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED ROLE INTROS
// Per-generator, per-language expert role intro.
// Shape: { generatorKey: { languageCode: roleIntroString } }
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, Map<String, String>> _roleIntros = {
  // ── Comment Generator ────────────────────────────────────────────────────
  'comment': {
    'en': 'Generate engaging social media comments for this content:',
    'ru':
        'Создайте привлекательные комментарии в социальных сетях для этого контента:',
    'uz': 'Ijtimoiy media uchun jozibador izohlarni yozing bu kontent uchun:',
    'ar': 'أنشئ تعليقات الوسائط الاجتماعية الجذابة لهذا المحتوى:',
    'de':
        'Erstellen Sie ansprechende Social-Media-Kommentare für diesen Inhalt:',
    'es': 'Crea comentarios atractivos de redes sociales para este contenido:',
    'fr':
        'Créez des commentaires de médias sociaux engageants pour ce contenu :',
    'hi': 'इस कंटेंट के लिए आकर्षक सोशल मीडिया कमेंट बनाएं:',
    'id': 'Buat komentar media sosial yang menarik untuk konten ini:',
    'ms': 'Buat ulasan media sosial yang menarik untuk kandungan ini:',
    'pt': 'Crie comentários de mídias sociais envolventes para este conteúdo:',
    'vi': 'Tạo bình luận truyền thông xã hội hấp dẫn cho nội dung này:',
  },

  // ── Hashtag Generator ────────────────────────────────────────────────────
  'hashtag': {
    'en':
        'You are a social media hashtag expert. Generate highly effective hashtags for the following content.',
    'ru':
        'Вы эксперт по хештегам в социальных сетях. Создавайте высокоэффективные хештеги для следующего контента.',
    'uz':
        "Siz ijtimoiy media xeshtegi eksprti siz. Berilgan kontent uchun juda ta'sirchan xashteglari yarating.",
    'ar':
        'أنت خبير هاشتاج وسائل التواصل الاجتماعي. قم بإنشاء علامات تجزئة فعالة جداً للمحتوى التالي.',
    'de':
        'Sie sind ein Social-Media-Hashtag-Experte. Generieren Sie hocheffektive Hashtags für den folgenden Inhalt.',
    'es':
        'Eres un experto en hashtags de redes sociales. Genera hashtags altamente efectivos para el siguiente contenido.',
    'fr':
        'Vous êtes un expert en hashtags de médias sociaux. Générez des hashtags hautement efficaces pour le contenu suivant.',
    'hi':
        'Tum social media hashtag expert ho. Neeche diye gaye content ke liye highly effective hashtags banao.',
    'id':
        'Anda adalah ahli hashtag media sosial. Hasilkan hashtag yang sangat efektif untuk konten berikut.',
    'ms':
        'Anda adalah pakar hashtag media sosial. Hasilkan hashtag yang sangat berkesan untuk kandungan berikut.',
    'pt':
        'Você é um especialista em hashtags de mídia social. Gere hashtags altamente eficazes para o seguinte conteúdo.',
    'vi':
        'Bạn là chuyên gia hashtag truyền thông xã hội. Tạo hashtag cực kỳ hiệu quả cho nội dung sau.',
  },

  // ── Viral Rewrite ────────────────────────────────────────────────────────
  'viral_rewrite': {
    'en':
        'You are a viral social media expert. Rewrite the given content to make it highly engaging, shareable, and viral on Instagram, TikTok, Twitter/X, and Facebook.',
    'ru':
        'Вы эксперт по вирусному контенту социальных сетей. Переделайте данный контент, чтобы сделать его привлекательным, общедоступным и вирусным на Instagram, TikTok, Twitter/X и Facebook.',
    'uz':
        "Siz ijtimoiy media uchun viral kontent bo'yicha ekspert siz. Berilgan kontentni o'zgartiring, shunda u juda jozibador va viral bo'ladi Instagram, TikTok, Twitter/X va Facebook uchun.",
    'ar':
        'أنت خبير في المحتوى الفيروسي على وسائل التواصل الاجتماعي. أعد كتابة المحتوى المعطى ليكون جذاباً وقابلاً للمشاركة وفيروسياً على Instagram و TikTok و Twitter/X و Facebook.',
    'de':
        'Sie sind Experte für Viral-Inhalte in den sozialen Medien. Schreiben Sie den angegebenen Inhalt um, um ihn auf Instagram, TikTok, Twitter/X und Facebook ansprechend, teilbar und viral zu gestalten.',
    'es':
        'Eres experto en contenido viral en redes sociales. Reescribe el contenido dado para hacerlo muy atractivo, compartible y viral en Instagram, TikTok, Twitter/X y Facebook.',
    'fr':
        "Vous êtes expert en contenu viral sur les réseaux sociaux. Réécrivez le contenu donné pour le rendre très attrayant, partageable et viral sur Instagram, TikTok, Twitter/X et Facebook.",
    'hi':
        'Tum viral social media expert ho. Neeche diye gaye content ko highly engaging, shareable, aur viral banane ke liye fir se likho Instagram, TikTok, Twitter/X, aur Facebook par.',
    'id':
        'Anda adalah ahli konten viral di media sosial. Tulis ulang konten yang diberikan agar sangat menarik, dapat dibagikan, dan viral di Instagram, TikTok, Twitter/X, dan Facebook.',
    'ms':
        'Anda adalah pakar konten viral di media sosial. Tulis semula kandungan yang diberikan untuk menjadikannya sangat menarik, boleh berkongsi, dan viral di Instagram, TikTok, Twitter/X, dan Facebook.',
    'pt':
        'Você é especialista em conteúdo viral em redes sociais. Reescreva o conteúdo fornecido para torná-lo muito atrativo, compartilhável e viral em Instagram, TikTok, Twitter/X e Facebook.',
    'vi':
        'Bạn là chuyên gia nội dung viral trên mạng xã hội. Viết lại nội dung được cung cấp để làm cho nó rất hấp dẫn, có thể chia sẻ và viral trên Instagram, TikTok, Twitter/X và Facebook.',
  },

  // ── Shot Ideas ───────────────────────────────────────────────────────────
  'shot_ideas': {
    'en':
        'You are a professional cinematographer and viral content creator. Generate creative and effective shot ideas for the following content concept.',
    'ru':
        'Вы профессиональный кинематограф и создатель вирусного контента. Создайте творческие и эффективные идеи кадров для следующей концепции контента.',
    'uz':
        'Siz professional kino yozuvchi va viral kontent yaratuvchisiz. Berilgan kontent kontseptsiyasi uchun ijodiy va samarali shot ideyalarini yarating.',
    'ar':
        'أنت عالم سينما احترافي ومنشئ محتوى فيروسي. إنشاء أفكار لقطات إبداعية وفعالة لمفهوم المحتوى التالي.',
    'de':
        'Sie sind ein professioneller Kameramann und viraler Content-Creator. Generieren Sie kreative und effektive Shotideen für das folgende Content-Konzept.',
    'es':
        'Eres un camarógrafo profesional y creador de contenido viral. Genera las mejores ideas de tomas para el siguiente concepto de contenido.',
    'fr':
        'Vous êtes directeur de la photographie professionnel et créateur de contenu viral. Générez des idées de plans créatives et efficaces pour le concept de contenu suivant.',
    'hi':
        'Tum professional cinematographer aur viral content creator ho. Neeche diye gaye content concept ke liye creative aur effective shot ideas banao.',
    'id':
        'Anda adalah sinematografer profesional dan pembuat konten viral. Hasilkan ide pemotretan kreatif dan efektif untuk konsep konten berikut.',
    'ms':
        'Anda adalah seorang sinematografer profesional dan pencipta kandungan viral. Janakan idea menggambar kreatif dan berkesan untuk konsep kandungan berikut.',
    'pt':
        'Você é um cinegrafista profissional e criador de conteúdo viral. Gere ideias de tiro criativas e eficazes para o seguinte conceito de conteúdo.',
    'vi':
        'Bạn là một nhà quay phim chuyên nghiệp và người tạo nội dung viral. Tạo ý tưởng chụp ảnh sáng tạo và hiệu quả cho khái niệm nội dung sau.',
  },

  // ── Idea Refinement ──────────────────────────────────────────────────────
  'refinement': {
    'en':
        'You are an expert viral content strategist. Enhance and refine this video idea to maximize virality and engagement.',
    'ru':
        'Вы эксперт по созданию вирусного контента. Улучшите эту идею видео, чтобы максимально увеличить вовлечённость.',
    'uz':
        "Siz viral kontent bo'yicha ekspert siz. Ushbu video g'oyani yanada qiziqarli va ommabop qiling.",
    'ar':
        'أنت خبير في المحتوى الفيروسي. قم بتحسين فكرة الفيديو لزيادة التفاعل والانتشار.',
    'de':
        'Du bist ein Experte für virale Inhalte. Optimiere diese Videoidee für maximale Reichweite und Engagement.',
    'es':
        'Eres experto en contenido viral. Mejora esta idea para hacerla más atractiva y envolvente.',
    'fr':
        "Vous êtes expert en contenu viral. Améliorez cette idée pour maximiser l'engagement et la portée.",
    'hi':
        'Tum viral content expert ho. Maximum engagement ke liye is video idea ko improve karo.',
    'id':
        'Anda adalah ahli konten viral. Tingkatkan ide video ini untuk engagement maksimal.',
    'ms':
        'Anda adalah pakar konten viral. Tingkatkan idea video ini untuk engagement maksimal.',
    'pt':
        'Você é especialista em conteúdo viral. Melhore essa ideia de vídeo para máximo engagement.',
    'vi':
        'Bạn là chuyên gia nội dung viral. Cải thiện ý tưởng video này để tăng engagement tối đa.',
  },

  // ── Script Generator ─────────────────────────────────────────────────────
  'script': {
    'en':
        'You are a professional video script writer. Generate a creative and engaging video script for the following idea.',
    'ru':
        'Вы профессиональный сценарист видео. Напишите творческий и увлекательный сценарий видео для следующей идеи.',
    'uz':
        "Siz professional video senariy yozuvchisiz. Quyidagi g'oya uchun ijodiy va qiziqarli video senariy yozing.",
    'ar':
        'أنت كاتب سيناريو فيديو محترف. اكتب سيناريو فيديو إبداعياً وجذاباً للفكرة التالية.',
    'de':
        'Sie sind ein professioneller Videoskript-Autor. Schreiben Sie ein kreatives und ansprechendes Videoskript für die folgende Idee.',
    'es':
        'Eres un guionista de video profesional. Escribe un guión de video creativo y atractivo para la siguiente idea.',
    'fr':
        'Vous êtes un scénariste vidéo professionnel. Rédigez un scénario vidéo créatif et engageant pour l\'idée suivante.',
    'hi':
        'Tum professional video script writer ho. Neeche diye gaye idea ke liye creative aur engaging video script likho.',
    'id':
        'Anda adalah penulis skrip video profesional. Tulis skrip video yang kreatif dan menarik untuk ide berikut.',
    'ms':
        'Anda adalah penulis skrip video profesional. Tulis skrip video yang kreatif dan menarik untuk idea berikut.',
    'pt':
        'Você é um roteirista de vídeo profissional. Escreva um roteiro de vídeo criativo e envolvente para a seguinte ideia.',
    'vi':
        'Bạn là một nhà viết kịch bản video chuyên nghiệp. Viết kịch bản video sáng tạo và hấp dẫn cho ý tưởng sau.',
  },
};

/// Retrieve a localised role intro string for a given generator + language.
/// Falls back to English if the language is unsupported.
String _getRoleIntro(String generatorKey, String language) {
  final lang = _resolvedLang(language);
  return _roleIntros[generatorKey]?[lang] ?? _roleIntros[generatorKey]!['en']!;
}

// ─────────────────────────────────────────────────────────────────────────────
// LOCALISED REQUIREMENT LABELS
//
// Every generator's "Requirements:" block is now translated so the LLM
// receives fully native instructions — not an English body with a
// language-enforcement bolt-on. This is the primary fix for language drift.
// ─────────────────────────────────────────────────────────────────────────────

// ── Script requirements ───────────────────────────────────────────────────────
const Map<String, Map<String, String>> _scriptLabels = {
  'en': {
    'baseIdea': '📝 Base Idea/Request:',
    'instructions':
        'Generate a well-structured script with clear sections (hook, voiceover, shots, CTA).',
    'noNested':
        '- Do NOT wrap output in nested objects like {"script": {...}} or {"sections": {...}}',
    'flatArrays':
        '- voiceover and shots MUST be flat JSON arrays of plain strings',
    'hashtagArray':
        '- hashtags MUST be a JSON array of hashtag strings (e.g. ["#tag1", "#tag2"])',
  },
  'ru': {
    'baseIdea': '📝 Базовая идея/запрос:',
    'instructions':
        'Создайте хорошо структурированный сценарий с чёткими разделами (крюк, закадровый текст, кадры, призыв к действию).',
    'noNested':
        '- НЕ оборачивайте вывод во вложенные объекты вроде {"script": {...}} или {"sections": {...}}',
    'flatArrays':
        '- voiceover и shots ДОЛЖНЫ быть плоскими JSON-массивами обычных строк',
    'hashtagArray':
        '- hashtags ДОЛЖНЫ быть JSON-массивом строк хештегов (например ["#tag1", "#tag2"])',
  },
  'uz': {
    'baseIdea': '📝 Asosiy g\'oya/so\'rov:',
    'instructions':
        "Aniq bo'limlari (hook, ovozli matn, kadrlar, harakat chaqiruvi) bo'lgan yaxshi tuzilgan senariy yarating.",
    'noNested':
        '- Natijani {"script": {...}} yoki {"sections": {...}} kabi ichki obyektlarga O\'RAMANG',
    'flatArrays':
        '- voiceover va shots oddiy satrlarning tekis JSON massivlari BO\'LISHI KERAK',
    'hashtagArray':
        '- hashtags xeshteg satrlari JSON massivi BO\'LISHI KERAK (masalan ["#tag1", "#tag2"])',
  },
  'ar': {
    'baseIdea': '📝 الفكرة الأساسية/الطلب:',
    'instructions':
        'أنشئ سيناريو منظماً جيداً بأقسام واضحة (خطاف، تعليق صوتي، لقطات، دعوة للعمل).',
    'noNested':
        '- لا تُغلّف الناتج في كائنات متداخلة مثل {"script": {...}} أو {"sections": {...}}',
    'flatArrays':
        '- يجب أن تكون voiceover و shots مصفوفات JSON مسطحة من السلاسل البسيطة',
    'hashtagArray':
        '- يجب أن تكون hashtags مصفوفة JSON من سلاسل الوسوم (مثلاً ["#tag1", "#tag2"])',
  },
  'de': {
    'baseIdea': '📝 Grundidee/Anfrage:',
    'instructions':
        'Erstellen Sie ein gut strukturiertes Skript mit klaren Abschnitten (Hook, Voiceover, Shots, CTA).',
    'noNested':
        '- Kein Output in verschachtelten Objekten wie {"script": {...}} oder {"sections": {...}}',
    'flatArrays':
        '- voiceover und shots MÜSSEN flache JSON-Arrays einfacher Strings sein',
    'hashtagArray':
        '- hashtags MUSS ein JSON-Array von Hashtag-Strings sein (z.B. ["#tag1", "#tag2"])',
  },
  'es': {
    'baseIdea': '📝 Idea base/Solicitud:',
    'instructions':
        'Genera un guión bien estructurado con secciones claras (gancho, narración, planos, CTA).',
    'noNested':
        '- NO envuelvas la salida en objetos anidados como {"script": {...}} o {"sections": {...}}',
    'flatArrays':
        '- voiceover y shots DEBEN ser arrays JSON planos de strings simples',
    'hashtagArray':
        '- hashtags DEBE ser un array JSON de strings de hashtags (ej. ["#tag1", "#tag2"])',
  },
  'fr': {
    'baseIdea': '📝 Idée de base/Demande :',
    'instructions':
        'Générez un script bien structuré avec des sections claires (accroche, voix off, plans, CTA).',
    'noNested':
        '- Ne PAS envelopper la sortie dans des objets imbriqués comme {"script": {...}} ou {"sections": {...}}',
    'flatArrays':
        '- voiceover et shots DOIVENT être des tableaux JSON plats de chaînes simples',
    'hashtagArray':
        '- hashtags DOIT être un tableau JSON de chaînes de hashtags (ex. ["#tag1", "#tag2"])',
  },
  'hi': {
    'baseIdea': '📝 Base idea/request:',
    'instructions':
        'Clear sections (hook, voiceover, shots, CTA) ke saath ek well-structured script banao.',
    'noNested':
        '- Output ko {"script": {...}} ya {"sections": {...}} jaise nested object mein mat daalo',
    'flatArrays':
        '- Voiceover aur shots simple strings ke flat JSON arrays hone chahiye',
    'hashtagArray':
        '- Hashtags ek JSON array hona chahiye hashtag strings ka (jaise ["#tag1", "#tag2"])',
  },
  'id': {
    'baseIdea': '📝 Ide Dasar/Permintaan:',
    'instructions':
        'Buat skrip terstruktur dengan bagian yang jelas (hook, voiceover, shots, CTA).',
    'noNested':
        '- JANGAN bungkus output dalam objek bersarang seperti {"script": {...}} atau {"sections": {...}}',
    'flatArrays':
        '- voiceover dan shots HARUS berupa array JSON datar dari string biasa',
    'hashtagArray':
        '- hashtags HARUS berupa array JSON dari string hashtag (mis. ["#tag1", "#tag2"])',
  },
  'ms': {
    'baseIdea': '📝 Idea Asas/Permintaan:',
    'instructions':
        'Buat skrip berstruktur dengan bahagian yang jelas (hook, voiceover, shots, CTA).',
    'noNested':
        '- JANGAN bungkus output dalam objek bersarang seperti {"script": {...}} atau {"sections": {...}}',
    'flatArrays':
        '- voiceover dan shots MESTI berupa array JSON rata dari string biasa',
    'hashtagArray':
        '- hashtags MESTI berupa array JSON dari string hashtag (cth. ["#tag1", "#tag2"])',
  },
  'pt': {
    'baseIdea': '📝 Ideia base/Solicitação:',
    'instructions':
        'Gere um roteiro bem estruturado com seções claras (gancho, narração, planos, CTA).',
    'noNested':
        '- NÃO envolva a saída em objetos aninhados como {"script": {...}} ou {"sections": {...}}',
    'flatArrays':
        '- voiceover e shots DEVEM ser arrays JSON planos de strings simples',
    'hashtagArray':
        '- hashtags DEVE ser um array JSON de strings de hashtags (ex. ["#tag1", "#tag2"])',
  },
  'vi': {
    'baseIdea': '📝 Ý tưởng cơ bản/Yêu cầu:',
    'instructions':
        'Tạo kịch bản có cấu trúc tốt với các phần rõ ràng (hook, voiceover, shots, CTA).',
    'noNested':
        '- KHÔNG bọc đầu ra trong các đối tượng lồng nhau như {"script": {...}} hoặc {"sections": {...}}',
    'flatArrays':
        '- voiceover và shots PHẢI là các mảng JSON phẳng của các chuỗi đơn giản',
    'hashtagArray':
        '- hashtags PHẢI là một mảng JSON các chuỗi hashtag (vd. ["#tag1", "#tag2"])',
  },
};

// ── Script length / variation labels ─────────────────────────────────────────
const Map<String, Map<String, String>> _scriptLengthLabels = {
  'en': {
    'superShort':
        '📏 LENGTH: SUPER SHORT (15-second video)\n'
        '⚠️ STRICT LIMITS — violating ANY of these = FAILURE:\n'
        '- hook: MAX 8 words, one punchy sentence\n'
        '- voiceover: EXACTLY 2 lines (NOT 3, NOT 4 — only 2), each under 12 words\n'
        '- shots: EXACTLY 4 shot descriptions\n'
        '- cta: MAX 5 words\n'
        '- hashtags: 3 hashtags only\n'
        '- TOTAL OUTPUT: 40-70 words. Ultra-compressed. Every word must earn its place.',
    'full':
        '📏 LENGTH: FULL (120+ second video)\n'
        '⚠️ STRICT MINIMUMS — too short = FAILURE:\n'
        '- hook: 12-20 words, detailed and curiosity-driven\n'
        '- voiceover: EXACTLY 10 lines, each 5-10 words with rich detail\n'
        '- shots: 5-6 detailed shot descriptions with camera angles\n'
        '- cta: 10-15 words, compelling and specific\n'
        '- hashtags: 5-8 hashtags\n'
        '- TOTAL OUTPUT: 300-500 words. Comprehensive, thorough, in-depth breakdown.',
    'short':
        '📏 LENGTH: SHORT (45-60 second video)\n'
        '⚠️ STRICT LIMITS:\n'
        '- hook: 8-12 words, one strong sentence\n'
        '- voiceover: EXACTLY 4 lines (NOT 2, NOT 5 — only 4), each 10-15 words\n'
        '- shots: 3-4 shot descriptions\n'
        '- cta: 6-10 words\n'
        '- hashtags: 4-5 hashtags\n'
        '- TOTAL OUTPUT: 120-200 words. Balanced, clear, concise.',
    'comedic':
        '🎭 VARIATION: Comedic — Use humor, puns, exaggeration, and funny twists throughout',
    'dramatic':
        '🎭 VARIATION: Dramatic — Build tension, emotional intensity, cliffhanger moments',
    'motivational':
        '🎭 VARIATION: Motivational — Uplifting, inspiring, empowering language',
    'default': '🎭 VARIATION: Default — Neutral, clear, straightforward tone',
  },
  'ru': {
    'superShort':
        '📏 ДЛИНА: Очень короткая — создайте РОВНО 2 строки закадрового текста максимум',
    'full': '📏 ДЛИНА: Полная — создайте РОВНО 10 строк закадрового текста',
    'short':
        '📏 ДЛИНА: Короткая — создайте РОВНО 4 строки закадрового текста максимум',
    'comedic': '🎭 ВАРИАЦИЯ: Комедийная — сделайте юмористической и смешной',
    'dramatic':
        '🎭 ВАРИАЦИЯ: Драматическая — сделайте насыщенной и эмоциональной',
    'motivational': '🎭 ВАРИАЦИЯ: Мотивационная — сделайте вдохновляющей',
    'default': '🎭 ВАРИАЦИЯ: По умолчанию — сохраняйте нейтральный тон',
  },
  'uz': {
    'superShort':
        "📏 UZUNLIK: Juda qisqa — maksimum 2 ta ovozli matn qatori yarating",
    'full': "📏 UZUNLIK: To'liq — 10 ta ovozli matn qatori yarating",
    'short': "📏 UZUNLIK: Qisqa — maksimum 4 ta ovozli matn qatori yarating",
    'comedic': "🎭 VARIATSIYA: Komediya — uni kulgili va hazilkash qiling",
    'dramatic': "🎭 VARIATSIYA: Dramatik — uni shiddatli va hissiy qiling",
    'motivational': "🎭 VARIATSIYA: Motivatsion — uni ilhomlantiruvchi qiling",
    'default': "🎭 VARIATSIYA: Standart — neytral va sodda qiling",
  },
  'ar': {
    'superShort':
        '📏 الطول: قصير جداً — أنشئ 2 أسطر تعليق صوتي بالضبط كحد أقصى',
    'full': '📏 الطول: كامل — أنشئ 10 أسطر تعليق صوتي بالضبط',
    'short': '📏 الطول: قصير — أنشئ 4 أسطر تعليق صوتي بالضبط كحد أقصى',
    'comedic': '🎭 التنوع: كوميدي — اجعله مضحكاً وفكاهياً',
    'dramatic': '🎭 التنوع: دراما — اجعله مكثفاً وعاطفياً',
    'motivational': '🎭 التنوع: تحفيزي — اجعله ملهماً',
    'default': '🎭 التنوع: افتراضي — اجعله محايداً ومباشراً',
  },
  'de': {
    'superShort':
        '📏 LÄNGE: S ehr kurz – Generieren Sie GENAU 2 Voiceover-Zeilen maximal',
    'full': '📏 LÄNGE: Vollständig – Generieren Sie GENAU 10 Voiceover-Zeilen',
    'short': '📏 LÄNGE: Kurz – Generieren Sie GENAU 4 Voiceover-Zeilen maximal',
    'comedic': '🎭 VARIATION: Komisch – Machen Sie es humorvoll und lustig',
    'dramatic':
        '🎭 VARIATION: Dramatisch – Machen Sie es intensiv und emotional',
    'motivational': '🎭 VARIATION: Motivierend – Machen Sie es inspirierend',
    'default': '🎭 VARIATION: Standard – Neutral und geradlinig halten',
  },
  'es': {
    'superShort':
        '📏 LONGITUD: Muy corto — Genera EXACTAMENTE 2 líneas de narración como máximo',
    'full': '📏 LONGITUD: Completo — Genera EXACTAMENTE 10 líneas de narración',
    'short':
        '📏 LONGITUD: Corto — Genera EXACTAMENTE 4 líneas de narración como máximo',
    'comedic': '🎭 VARIACIÓN: Cómico — Hazlo humorístico y divertido',
    'dramatic': '🎭 VARIACIÓN: Dramático — Hazlo intenso y emocional',
    'motivational': '🎭 VARIACIÓN: Motivacional — Hazlo inspirador',
    'default': '🎭 VARIACIÓN: Por defecto — Mantenerlo neutro y directo',
  },
  'fr': {
    'superShort':
        '📏 LONGUEUR : Très court — Générez EXACTEMENT 2 lignes de voix off maximum',
    'full': '📏 LONGUEUR : Complet — Générez EXACTEMENT 10 lignes de voix off',
    'short':
        '📏 LONGUEUR : Court — Générez EXACTEMENT 4 lignes de voix off maximum',
    'comedic': '🎭 VARIATION : Comique — Rendez-le humoristique et drôle',
    'dramatic': '🎭 VARIATION : Dramatique — Rendez-le intense et émotionnel',
    'motivational': '🎭 VARIATION : Motivant — Rendez-le inspirant',
    'default': '🎭 VARIATION : Par défaut — Gardez-le neutre et direct',
  },
  'hi': {
    'superShort':
        '📏 LENGTH: BAHUT CHHOTI (15-second video)\n'
        '⚠️ STRICT LIMITS — inme se koi bhi todna = FAILURE:\n'
        '- hook: MAX 8 shabd, ek punchy sentence\n'
        '- voiceover: SIRF 2 lines (3 nahi, 4 nahi — sirf 2), har ek 12 shabd se kam\n'
        '- shots: SIRF 4 shot descriptions\n'
        '- cta: MAX 5 shabd\n'
        '- hashtags: SIRF 3 hashtags\n'
        '- TOTAL OUTPUT: 40-70 shabd. Ultra-compressed.',
    'full':
        '📏 LENGTH: FULL (120+ second video)\n'
        '⚠️ STRICT MINIMUMS — bahut chhota = FAILURE:\n'
        '- hook: 12-20 shabd, detailed aur curiosity-driven\n'
        '- voiceover: EXACTLY 10 lines, har ek 5-10 shabd rich detail ke saath\n'
        '- shots: 5-6 detailed shot descriptions camera angles ke saath\n'
        '- cta: 10-15 shabd, compelling aur specific\n'
        '- hashtags: 5-8 hashtags\n'
        '- TOTAL OUTPUT: 300-500 shabd. Comprehensive, thorough, in-depth.',
    'short':
        '📏 LENGTH: SHORT (45-60 second video)\n'
        '⚠️ STRICT LIMITS:\n'
        '- hook: 8-12 shabd, ek strong sentence\n'
        '- voiceover: EXACTLY 4 lines (2 nahi, 5 nahi — sirf 4), har ek 10-15 shabd\n'
        '- shots: 3-4 shot descriptions\n'
        '- cta: 6-10 shabd\n'
        '- hashtags: 4-5 hashtags\n'
        '- TOTAL OUTPUT: 120-200 shabd. Balanced, clear, concise.',
    'comedic':
        '🎭 VARIATION: Comedic — Humor, puns, exaggeration, aur funny twists use karo',
    'dramatic':
        '🎭 VARIATION: Dramatic — Tension build karo, emotional intensity, cliffhanger moments',
    'motivational':
        '🎭 VARIATION: Motivational — Uplifting, inspiring, empowering language',
    'default': '🎭 VARIATION: Default — Neutral, clear, straightforward tone',
  },
  'id': {
    'superShort':
        '📏 PANJANG: Sangat Pendek — Buat TEPAT 2 baris voiceover maksimum',
    'full': '📏 PANJANG: Penuh — Buat TEPAT 10 baris voiceover',
    'short': '📏 PANJANG: Pendek — Buat TEPAT 4 baris voiceover maksimum',
    'comedic': '🎭 VARIASI: Komedi — Buat lucu dan menghibur',
    'dramatic': '🎭 VARIASI: Dramatis — Buat intens dan emosional',
    'motivational': '🎭 VARIASI: Motivasi — Buat menginspirasi',
    'default': '🎭 VARIASI: Default — Jaga tetap netral dan langsung',
  },
  'ms': {
    'superShort':
        '📏 PANJANG: Sangat Pendek — Buat TEPAT 2 baris voiceover maksimum',
    'full': '📏 PANJANG: Penuh — Buat TEPAT 10 baris voiceover',
    'short': '📏 PANJANG: Pendek — Buat TEPAT 4 baris voiceover maksimum',
    'comedic': '🎭 VARIASI: Komedi — Jadikan lucu dan menghibur',
    'dramatic': '🎭 VARIASI: Dramatik — Jadikan intens dan emosional',
    'motivational': '🎭 VARIASI: Motivasi — Jadikan menginspirasi',
    'default': '🎭 VARIASI: Lalai — Kekalkan neutral dan terus',
  },
  'pt': {
    'superShort':
        '📏 COMPRIMENTO: Muito curto — Gere EXATAMENTE 2 linhas de narração no máximo',
    'full': '📏 COMPRIMENTO: Completo — Gere EXATAMENTE 10 linhas de narração',
    'short':
        '📏 COMPRIMENTO: Curto — Gere EXATAMENTE 4 linhas de narração no máximo',
    'comedic': '🎭 VARIAÇÃO: Cômico — Torne-o humorístico e engraçado',
    'dramatic': '🎭 VARIAÇÃO: Dramático — Torne-o intenso e emocional',
    'motivational': '🎭 VARIAÇÃO: Motivacional — Torne-o inspirador',
    'default': '🎭 VARIAÇÃO: Padrão — Mantenha neutro e direto',
  },
  'vi': {
    'superShort': '📏 ĐỘ DÀI: Rất ngắn — Tạo ĐÚNG 2 dòng voiceover tối đa',
    'full': '📏 ĐỘ DÀI: Đầy đủ — Tạo ĐÚNG 10 dòng voiceover',
    'short': '📏 ĐỘ DÀI: Ngắn — Tạo ĐÚNG 4 dòng voiceover tối đa',
    'comedic': '🎭 BIẾN THỂ: Hài hước — Làm cho nó vui nhộn và buồn cười',
    'dramatic': '🎭 BIẾN THỂ: Kịch tính — Làm cho nó căng thẳng và cảm xúc',
    'motivational': '🎭 BIẾN THỂ: Truyền cảm hứng — Làm cho nó inspiring',
    'default': '🎭 BIẾN THỂ: Mặc định — Giữ trung lập và thẳng thắn',
  },
};

// ── Comment requirements ──────────────────────────────────────────────────────
const Map<String, Map<String, String>> _commentLabels = {
  'en': {
    'requirements': 'Requirements:',
    'relevance': '- All comments must be relevant to:',
    'authentic':
        '- Make comments authentic, engaging, and suitable for Instagram, TikTok, YouTube',
    'exactly5': '- For EACH selected tone key, return EXACTLY 5 comments',
    'mustArray':
        '- Each tone value MUST be a JSON array of 5 strings — NOT a single string',
    'noNumber': '- Do NOT number comments (no "1.", "2." prefixes)',
    'onlyKeys': '- Use ONLY these tone keys — no extras:',
    'exactShape': 'EXACT JSON SHAPE:',
    'toneGuidance': 'Tone guidance:',
  },
  'ru': {
    'requirements': 'Требования:',
    'relevance': '- Все комментарии должны быть релевантны:',
    'authentic':
        '- Комментарии должны быть аутентичными, привлекательными и подходящими для Instagram, TikTok, YouTube',
    'exactly5': '- Для КАЖДОГО выбранного тона верните РОВНО 5 комментариев',
    'mustArray':
        '- Каждый тон ДОЛЖЕН быть JSON-массивом из 5 строк — НЕ одной строкой',
    'noNumber': '- НЕ нумеруйте комментарии (без префиксов "1.", "2.")',
    'onlyKeys': '- Используйте ТОЛЬКО эти ключи тона — без лишних:',
    'exactShape': 'ТОЧНАЯ СТРУКТУРА JSON:',
    'toneGuidance': 'Руководство по тону:',
  },
  'uz': {
    'requirements': 'Talablar:',
    'relevance': '- Barcha izohlar quyidagiga tegishli bo\'lishi kerak:',
    'authentic':
        '- Izohlarni Instagram, TikTok, YouTube uchun haqiqiy, qiziqarli va mos qiling',
    'exactly5': '- Har bir tanlangan ohang kaliti uchun 5 ta izoh qaytaring',
    'mustArray':
        '- Har bir ohang qiymati 5 ta satrning JSON massivi BO\'LISHI KERAK — bitta satr emas',
    'noNumber': '- Izohlarni raqamlaMang ("1.", "2." prefikslarsiz)',
    'onlyKeys': '- Faqat shu ohang kalitlarini ishlating — qo\'shimchalarsiz:',
    'exactShape': 'ANIQ JSON SHAKLI:',
    'toneGuidance': 'Ohang bo\'yicha ko\'rsatmalar:',
  },
  'ar': {
    'requirements': 'المتطلبات:',
    'relevance': '- يجب أن تكون جميع التعليقات ذات صلة بـ:',
    'authentic':
        '- اجعل التعليقات أصيلة وجذابة ومناسبة لـ Instagram وTikTok وYouTube',
    'exactly5': '- لكل مفتاح نبرة مختار، أعد 5 تعليقات بالضبط',
    'mustArray':
        '- يجب أن تكون كل قيمة نبرة مصفوفة JSON من 5 سلاسل — ليس سلسلة واحدة',
    'noNumber': '- لا تُرقِّم التعليقات (بدون بادئات "1." أو "2.")',
    'onlyKeys': '- استخدم هذه المفاتيح فقط — بدون إضافات:',
    'exactShape': 'الشكل الدقيق لـ JSON:',
    'toneGuidance': 'إرشادات النبرة:',
  },
  'de': {
    'requirements': 'Anforderungen:',
    'relevance': '- Alle Kommentare müssen relevant sein zu:',
    'authentic':
        '- Kommentare authentisch, ansprechend und geeignet für Instagram, TikTok, YouTube machen',
    'exactly5':
        '- Für JEDEN gewählten Ton-Schlüssel GENAU 5 Kommentare zurückgeben',
    'mustArray':
        '- Jeder Ton-Wert MUSS ein JSON-Array aus 5 Strings sein — KEIN einzelner String',
    'noNumber': '- Kommentare NICHT nummerieren (keine "1.", "2."-Präfixe)',
    'onlyKeys': '- NUR diese Ton-Schlüssel verwenden — keine Extras:',
    'exactShape': 'EXAKTE JSON-STRUKTUR:',
    'toneGuidance': 'Ton-Leitfaden:',
  },
  'es': {
    'requirements': 'Requisitos:',
    'relevance': '- Todos los comentarios deben ser relevantes para:',
    'authentic':
        '- Hacer los comentarios auténticos, atractivos y adecuados para Instagram, TikTok, YouTube',
    'exactly5':
        '- Para CADA clave de tono seleccionada, devolver EXACTAMENTE 5 comentarios',
    'mustArray':
        '- Cada valor de tono DEBE ser un array JSON de 5 strings — NO un string único',
    'noNumber': '- NO numerar comentarios (sin prefijos "1.", "2.")',
    'onlyKeys': '- Usar SOLO estas claves de tono — sin extras:',
    'exactShape': 'FORMA EXACTA DEL JSON:',
    'toneGuidance': 'Guía de tono:',
  },
  'fr': {
    'requirements': 'Exigences :',
    'relevance': '- Tous les commentaires doivent être pertinents pour :',
    'authentic':
        '- Rendre les commentaires authentiques, engageants et adaptés à Instagram, TikTok, YouTube',
    'exactly5':
        '- Pour CHAQUE clé de ton sélectionnée, retourner EXACTEMENT 5 commentaires',
    'mustArray':
        '- Chaque valeur de ton DOIT être un tableau JSON de 5 chaînes — PAS une seule chaîne',
    'noNumber':
        '- Ne PAS numéroter les commentaires (sans préfixes "1.", "2.")',
    'onlyKeys': '- Utiliser UNIQUEMENT ces clés de ton — sans extras :',
    'exactShape': 'FORMAT JSON EXACT :',
    'toneGuidance': 'Guide de ton :',
  },
  'hi': {
    'requirements': 'Requirements:',
    'relevance': '- Saare comments is se relevant hone chahiye:',
    'authentic':
        '- Comments ko Instagram, TikTok, YouTube ke liye authentic, engaging aur suitable banao',
    'exactly5': '- Har selected tone key ke liye 5 comments return karo',
    'mustArray':
        '- Har tone value 5 strings ka JSON array hona chahiye — single string nahi',
    'noNumber': '- Comments ko number na karo ("1.", "2." prefix use na karo)',
    'onlyKeys': '- Sirf ye tone keys use karo — extra nahi:',
    'exactShape': 'Exact JSON shape:',
    'toneGuidance': 'Tone guidance:',
  },
  'id': {
    'requirements': 'Persyaratan:',
    'relevance': '- Semua komentar harus relevan dengan:',
    'authentic':
        '- Buat komentar autentik, menarik, dan cocok untuk Instagram, TikTok, YouTube',
    'exactly5':
        '- Untuk SETIAP kunci nada yang dipilih, kembalikan TEPAT 5 komentar',
    'mustArray':
        '- Setiap nilai nada HARUS berupa array JSON 5 string — BUKAN string tunggal',
    'noNumber': '- JANGAN nomori komentar (tanpa awalan "1.", "2.")',
    'onlyKeys': '- Gunakan HANYA kunci nada ini — tanpa tambahan:',
    'exactShape': 'BENTUK JSON TEPAT:',
    'toneGuidance': 'Panduan nada:',
  },
  'ms': {
    'requirements': 'Keperluan:',
    'relevance': '- Semua ulasan mesti relevan dengan:',
    'authentic':
        '- Buat ulasan yang autentik, menarik, dan sesuai untuk Instagram, TikTok, YouTube',
    'exactly5':
        '- Untuk SETIAP kunci nada yang dipilih, kembalikan TEPAT 5 ulasan',
    'mustArray':
        '- Setiap nilai nada MESTI berupa array JSON 5 string — BUKAN string tunggal',
    'noNumber': '- JANGAN nombori ulasan (tanpa awalan "1.", "2.")',
    'onlyKeys': '- Gunakan HANYA kunci nada ini — tanpa tambahan:',
    'exactShape': 'BENTUK JSON TEPAT:',
    'toneGuidance': 'Panduan nada:',
  },
  'pt': {
    'requirements': 'Requisitos:',
    'relevance': '- Todos os comentários devem ser relevantes para:',
    'authentic':
        '- Tornar os comentários autênticos, envolventes e adequados para Instagram, TikTok, YouTube',
    'exactly5':
        '- Para CADA chave de tom selecionada, retornar EXATAMENTE 5 comentários',
    'mustArray':
        '- Cada valor de tom DEVE ser um array JSON de 5 strings — NÃO uma string única',
    'noNumber': '- NÃO numerar comentários (sem prefixos "1.", "2.")',
    'onlyKeys': '- Usar APENAS essas chaves de tom — sem extras:',
    'exactShape': 'FORMA EXATA DO JSON:',
    'toneGuidance': 'Guia de tom:',
  },
  'vi': {
    'requirements': 'Yêu cầu:',
    'relevance': '- Tất cả bình luận phải liên quan đến:',
    'authentic':
        '- Làm cho bình luận xác thực, hấp dẫn và phù hợp với Instagram, TikTok, YouTube',
    'exactly5': '- Với MỖI khóa tông được chọn, trả về ĐÚNG 5 bình luận',
    'mustArray':
        '- Mỗi giá trị tông PHẢI là một mảng JSON 5 chuỗi — KHÔNG phải chuỗi đơn',
    'noNumber': '- KHÔNG đánh số bình luận (không có tiền tố "1.", "2.")',
    'onlyKeys': '- Chỉ sử dụng các khóa tông này — không có thêm:',
    'exactShape': 'DẠNG JSON CHÍNH XÁC:',
    'toneGuidance': 'Hướng dẫn tông:',
  },
};

// ── Hashtag requirements ──────────────────────────────────────────────────────
const Map<String, Map<String, String>> _hashtagLabels = {
  'en': {
    'content': 'Content:',
    'requirements': 'Requirements:',
    'count': '- Generate 25-35 relevant hashtags, each starting with #',
    'mood': '- Ensure they match the content mood and topic',
    'different': '- Generate DIFFERENT hashtags from the previous generation',
    'continuous':
        '- The "hashtags" field value MUST be ONE continuous space-separated string',
    'noComma':
        '- Do NOT use commas, newlines, or numbered lists between hashtags',
    'noExtra': '- Do NOT add explanatory text outside the JSON',
  },
  'ru': {
    'content': 'Контент:',
    'requirements': 'Требования:',
    'count': '- Создайте 25-35 релевантных хештегов, каждый начинается с #',
    'mood': '- Убедитесь, что они соответствуют настроению и теме контента',
    'different': '- Создайте ДРУГИЕ хештеги, отличные от предыдущей генерации',
    'continuous':
        '- Значение поля "hashtags" ДОЛЖНО быть ОДНОЙ непрерывной строкой с пробелами',
    'noComma':
        '- НЕ используйте запятые, переносы строк или нумерованные списки между хештегами',
    'noExtra': '- НЕ добавляйте пояснительный текст вне JSON',
  },
  'uz': {
    'content': 'Kontent:',
    'requirements': 'Talablar:',
    'count':
        '- 25-35 ta tegishli xeshteg yarating, har biri # bilan boshlanadi',
    'mood': '- Ular kontent kayfiyati va mavzusiga mos kelishi kerak',
    'different': '- Oldingi generatsiyadan BOSHQA xeshteglар yarating',
    'continuous':
        '- "hashtags" maydoni qiymati bo\'sh joy bilan ajratilgan BITTA uzluksiz satr bo\'lishi kerak',
    'noComma':
        '- Xeshtegler o\'rtasida vergul, yangi qator yoki raqamli ro\'yxatlardan FOYDALANMANG',
    'noExtra': '- JSON tashqarisiga tushuntirish matni QOSHIMANG',
  },
  'ar': {
    'content': 'المحتوى:',
    'requirements': 'المتطلبات:',
    'count': '- أنشئ 25-35 وسماً ذا صلة، كل منها يبدأ بـ #',
    'mood': '- تأكد من مطابقتها لمزاج المحتوى وموضوعه',
    'different': '- أنشئ وسوماً مختلفة عن التوليد السابق',
    'continuous':
        '- يجب أن تكون قيمة حقل "hashtags" سلسلة واحدة مستمرة مفصولة بمسافات',
    'noComma':
        '- لا تستخدم الفواصل أو الأسطر الجديدة أو القوائم المرقمة بين الوسوم',
    'noExtra': '- لا تضف نصاً توضيحياً خارج JSON',
  },
  'de': {
    'content': 'Inhalt:',
    'requirements': 'Anforderungen:',
    'count': '- 25-35 relevante Hashtags generieren, jeder beginnt mit #',
    'mood':
        '- Sicherstellen, dass sie zur Stimmung und zum Thema des Inhalts passen',
    'different':
        '- ANDERE Hashtags als bei der vorherigen Generierung erstellen',
    'continuous':
        '- Der Wert des Feldes "hashtags" MUSS ein EINZIGER kontinuierlicher, durch Leerzeichen getrennter String sein',
    'noComma':
        '- KEINE Kommas, Zeilenumbrüche oder nummerierte Listen zwischen Hashtags verwenden',
    'noExtra': '- KEINEN erklärenden Text außerhalb des JSON hinzufügen',
  },
  'es': {
    'content': 'Contenido:',
    'requirements': 'Requisitos:',
    'count': '- Generar 25-35 hashtags relevantes, cada uno comenzando con #',
    'mood':
        '- Asegurarse de que coincidan con el estado de ánimo y tema del contenido',
    'different': '- Generar hashtags DIFERENTES a la generación anterior',
    'continuous':
        '- El valor del campo "hashtags" DEBE ser UNA cadena continua separada por espacios',
    'noComma':
        '- NO usar comas, saltos de línea o listas numeradas entre hashtags',
    'noExtra': '- NO agregar texto explicativo fuera del JSON',
  },
  'fr': {
    'content': 'Contenu :',
    'requirements': 'Exigences :',
    'count': '- Générer 25-35 hashtags pertinents, chacun commençant par #',
    'mood':
        '- S\'assurer qu\'ils correspondent à l\'ambiance et au sujet du contenu',
    'different':
        '- Générer des hashtags DIFFÉRENTS de la génération précédente',
    'continuous':
        '- La valeur du champ "hashtags" DOIT être UNE chaîne continue séparée par des espaces',
    'noComma':
        '- Ne PAS utiliser de virgules, sauts de ligne ou listes numérotées entre les hashtags',
    'noExtra': '- Ne PAS ajouter de texte explicatif en dehors du JSON',
  },
  'hi': {
    'content': 'Content:',
    'requirements': 'Requirements:',
    'count': '- 25-35 relevant hashtags banao, har ek # se start ho',
    'mood': '- Ensure karo ke ye content ke mood aur topic se match karein',
    'different': '- Previous generation se different hashtags banao',
    'continuous':
        '- "hashtags" field ki value ek continuous space-separated string honi chahiye',
    'noComma':
        '- Hashtags ke beech commas, newlines ya numbered lists ka use na karo',
    'noExtra': '- JSON ke bahar koi explanatory text add na karo',
  },
  'id': {
    'content': 'Konten:',
    'requirements': 'Persyaratan:',
    'count':
        '- Buat 25-35 hashtag yang relevan, masing-masing dimulai dengan #',
    'mood': '- Pastikan cocok dengan suasana dan topik konten',
    'different': '- Buat hashtag BERBEDA dari generasi sebelumnya',
    'continuous':
        '- Nilai field "hashtags" HARUS berupa SATU string berkelanjutan yang dipisah spasi',
    'noComma':
        '- JANGAN gunakan koma, baris baru, atau daftar bernomor antara hashtag',
    'noExtra': '- JANGAN tambahkan teks penjelasan di luar JSON',
  },
  'ms': {
    'content': 'Kandungan:',
    'requirements': 'Keperluan:',
    'count':
        '- Jana 25-35 hashtag yang relevan, masing-masing bermula dengan #',
    'mood': '- Pastikan ia sepadan dengan suasana dan topik kandungan',
    'different': '- Jana hashtag BERBEZA daripada generasi sebelumnya',
    'continuous':
        '- Nilai field "hashtags" MESTI berupa SATU string berterusan yang dipisah ruang',
    'noComma':
        '- JANGAN gunakan koma, baris baru, atau senarai bernombor antara hashtag',
    'noExtra': '- JANGAN tambah teks penjelasan di luar JSON',
  },
  'pt': {
    'content': 'Conteúdo:',
    'requirements': 'Requisitos:',
    'count': '- Gerar 25-35 hashtags relevantes, cada um começando com #',
    'mood': '- Garantir que correspondam ao humor e tópico do conteúdo',
    'different': '- Gerar hashtags DIFERENTES da geração anterior',
    'continuous':
        '- O valor do campo "hashtags" DEVE ser UMA string contínua separada por espaços',
    'noComma':
        '- NÃO usar vírgulas, quebras de linha ou listas numeradas entre hashtags',
    'noExtra': '- NÃO adicionar texto explicativo fora do JSON',
  },
  'vi': {
    'content': 'Nội dung:',
    'requirements': 'Yêu cầu:',
    'count': '- Tạo 25-35 hashtag có liên quan, mỗi cái bắt đầu bằng #',
    'mood': '- Đảm bảo chúng phù hợp với tâm trạng và chủ đề nội dung',
    'different': '- Tạo hashtag KHÁC với lần tạo trước',
    'continuous':
        '- Giá trị trường "hashtags" PHẢI là MỘT chuỗi liên tục phân cách bằng dấu cách',
    'noComma':
        '- KHÔNG dùng dấu phẩy, xuống dòng hoặc danh sách có số giữa các hashtag',
    'noExtra': '- KHÔNG thêm văn bản giải thích ngoài JSON',
  },
};

// ── Viral Rewrite requirements ────────────────────────────────────────────────
const Map<String, Map<String, String>> _viralRewriteLabels = {
  'en': {
    'original': 'Original content:',
    'requirements': 'Requirements:',
    'punchy': '- Rewrite in 2-4 punchy sentences',
    'applyTones': '- Apply these tones:',
    'flatJson':
        '- Return a FLAT JSON object with exactly these keys: text, emotional_hook, hashtag, call_to_action',
    'noBraces': '- Do NOT embed braces {} inside any field value',
    'hook': '- emotional_hook: one short curiosity/emotion hook line',
    'hashtagLine': '- hashtag: one line with 3-6 hashtags separated by spaces',
    'cta': '- call_to_action: one clear engagement sentence',
  },
  'ru': {
    'original': 'Оригинальный контент:',
    'requirements': 'Требования:',
    'punchy': '- Перепишите в 2-4 динамичных предложения',
    'applyTones': '- Применяйте эти тона:',
    'flatJson':
        '- Верните ПЛОСКИЙ JSON-объект с ровно этими ключами: text, emotional_hook, hashtag, call_to_action',
    'noBraces': '- НЕ вставляйте фигурные скобки {} внутри значений полей',
    'hook':
        '- emotional_hook: одна короткая строка-крюк для любопытства/эмоций',
    'hashtagLine': '- hashtag: одна строка с 3-6 хештегами через пробел',
    'cta': '- call_to_action: одно чёткое предложение для вовлечения',
  },
  'uz': {
    'original': 'Asl kontent:',
    'requirements': 'Talablar:',
    'punchy': '- 2-4 ta ta\'sirchan jumlada qayta yozing',
    'applyTones': '- Ushbu ohanglarni qo\'llang:',
    'flatJson':
        '- Aniq shu kalitlar bilan TEKIS JSON obyekti qaytaring: text, emotional_hook, hashtag, call_to_action',
    'noBraces': '- Maydon qiymatlariga {} qavslarini QISTIRMANG',
    'hook': '- emotional_hook: qiziquvchanlik/his uchun bitta qisqa hook satr',
    'hashtagLine':
        '- hashtag: bo\'sh joy bilan ajratilgan 3-6 xeshteg bilan bir qator',
    'cta': '- call_to_action: bitta aniq jalb etish jumla',
  },
  'ar': {
    'original': 'المحتوى الأصلي:',
    'requirements': 'المتطلبات:',
    'punchy': '- أعد الكتابة في 2-4 جمل موجزة ومؤثرة',
    'applyTones': '- طبّق هذه النبرات:',
    'flatJson':
        '- أعد كائن JSON مسطحاً بهذه المفاتيح بالضبط: text, emotional_hook, hashtag, call_to_action',
    'noBraces': '- لا تُدمج الأقواس {} داخل أي قيمة حقل',
    'hook': '- emotional_hook: سطر واحد قصير للفضول/العاطفة',
    'hashtagLine': '- hashtag: سطر واحد بـ 3-6 وسوم مفصولة بمسافات',
    'cta': '- call_to_action: جملة واضحة واحدة للتفاعل',
  },
  'de': {
    'original': 'Originalinhalt:',
    'requirements': 'Anforderungen:',
    'punchy': '- In 2-4 prägnante Sätze umschreiben',
    'applyTones': '- Diese Töne anwenden:',
    'flatJson':
        '- Ein FLACHES JSON-Objekt mit genau diesen Schlüsseln zurückgeben: text, emotional_hook, hashtag, call_to_action',
    'noBraces': '- KEINE geschweifte Klammern {} in Feldwerte einbetten',
    'hook': '- emotional_hook: eine kurze Neugier-/Emotions-Hook-Zeile',
    'hashtagLine':
        '- hashtag: eine Zeile mit 3-6 Hashtags, durch Leerzeichen getrennt',
    'cta': '- call_to_action: ein klarer Engagement-Satz',
  },
  'es': {
    'original': 'Contenido original:',
    'requirements': 'Requisitos:',
    'punchy': '- Reescribir en 2-4 oraciones impactantes',
    'applyTones': '- Aplicar estos tonos:',
    'flatJson':
        '- Devolver un objeto JSON PLANO con exactamente estas claves: text, emotional_hook, hashtag, call_to_action',
    'noBraces': '- NO insertar llaves {} dentro de ningún valor de campo',
    'hook': '- emotional_hook: una línea corta de gancho de curiosidad/emoción',
    'hashtagLine':
        '- hashtag: una línea con 3-6 hashtags separados por espacios',
    'cta': '- call_to_action: una oración clara de participación',
  },
  'fr': {
    'original': 'Contenu original :',
    'requirements': 'Exigences :',
    'punchy': '- Réécrire en 2-4 phrases percutantes',
    'applyTones': '- Appliquer ces tons :',
    'flatJson':
        '- Retourner un objet JSON PLAT avec exactement ces clés : text, emotional_hook, hashtag, call_to_action',
    'noBraces': '- Ne PAS incorporer d\'accolades {} dans les valeurs de champ',
    'hook': '- emotional_hook : une courte ligne d\'accroche curiosité/émotion',
    'hashtagLine':
        '- hashtag : une ligne avec 3-6 hashtags séparés par des espaces',
    'cta': '- call_to_action : une phrase d\'engagement claire',
  },
  'hi': {
    'original': 'Original content:',
    'requirements': 'Requirements:',
    'punchy': '- 2-4 impactful sentences mein rewrite karo',
    'applyTones': '- In tones ko apply karo:',
    'flatJson':
        '- In keys ke saath ek FLAT JSON object return karo: text, emotional_hook, hashtag, call_to_action',
    'noBraces': '- Kisi bhi field value ke andar {} braces mat daalo',
    'hook': '- emotional_hook: curiosity/feeling ke liye ek short hook line',
    'hashtagLine': '- hashtag: spaces se separated 3-6 hashtags ki ek line',
    'cta': '- call_to_action: ek clear engagement sentence',
  },
  'id': {
    'original': 'Konten asli:',
    'requirements': 'Persyaratan:',
    'punchy': '- Tulis ulang dalam 2-4 kalimat yang tajam',
    'applyTones': '- Terapkan nada-nada ini:',
    'flatJson':
        '- Kembalikan objek JSON DATAR dengan kunci persis ini: text, emotional_hook, hashtag, call_to_action',
    'noBraces':
        '- JANGAN sisipkan kurung kurawal {} di dalam nilai field mana pun',
    'hook':
        '- emotional_hook: satu baris hook keingintahuan/emosi yang singkat',
    'hashtagLine': '- hashtag: satu baris dengan 3-6 hashtag dipisah spasi',
    'cta': '- call_to_action: satu kalimat keterlibatan yang jelas',
  },
  'ms': {
    'original': 'Kandungan asal:',
    'requirements': 'Keperluan:',
    'punchy': '- Tulis semula dalam 2-4 ayat yang tajam',
    'applyTones': '- Gunakan nada-nada ini:',
    'flatJson':
        '- Kembalikan objek JSON RATA dengan kunci tepat ini: text, emotional_hook, hashtag, call_to_action',
    'noBraces': '- JANGAN sisipkan pendakap {} di dalam mana-mana nilai field',
    'hook':
        '- emotional_hook: satu baris hook keingintahuan/emosi yang ringkas',
    'hashtagLine': '- hashtag: satu baris dengan 3-6 hashtag dipisah ruang',
    'cta': '- call_to_action: satu ayat penglibatan yang jelas',
  },
  'pt': {
    'original': 'Conteúdo original:',
    'requirements': 'Requisitos:',
    'punchy': '- Reescrever em 2-4 frases impactantes',
    'applyTones': '- Aplicar estes tons:',
    'flatJson':
        '- Retornar um objeto JSON PLANO com exatamente estas chaves: text, emotional_hook, hashtag, call_to_action',
    'noBraces': '- NÃO inserir chaves {} dentro de nenhum valor de campo',
    'hook': '- emotional_hook: uma linha curta de gancho de curiosidade/emoção',
    'hashtagLine':
        '- hashtag: uma linha com 3-6 hashtags separados por espaços',
    'cta': '- call_to_action: uma frase clara de engajamento',
  },
  'vi': {
    'original': 'Nội dung gốc:',
    'requirements': 'Yêu cầu:',
    'punchy': '- Viết lại trong 2-4 câu mạnh mẽ',
    'applyTones': '- Áp dụng các tông này:',
    'flatJson':
        '- Trả về một đối tượng JSON PHẲNG với chính xác các khóa này: text, emotional_hook, hashtag, call_to_action',
    'noBraces': '- KHÔNG nhúng dấu ngoặc nhọn {} vào bất kỳ giá trị trường nào',
    'hook': '- emotional_hook: một dòng hook tò mò/cảm xúc ngắn',
    'hashtagLine':
        '- hashtag: một dòng với 3-6 hashtag phân cách bằng dấu cách',
    'cta': '- call_to_action: một câu tương tác rõ ràng',
  },
};

// ── Shot Ideas requirements ───────────────────────────────────────────────────
const Map<String, Map<String, String>> _shotIdeasLabels = {
  'en': {
    'concept': 'Content Concept:',
    'requirements': 'Requirements:',
    'count': '- Create 8-10 specific, actionable shot ideas',
    'applyTones': '- Apply these tones:',
    'timing':
        '- Include timing (e.g. "0-3s") and shot style (e.g. "close-up", "wide shot") for each',
    'variety':
        '- Include variety: hook, tension builders, reveals, and CTA shots',
    'format':
        '- Each shot idea MUST be a single plain string in this format:\n  **N. Title**: Description. Timing: X-Ys. Shot style: style',
    'noNested':
        '- Do NOT use nested objects or JSON key:value syntax inside any string item',
    'mustArray': '- shot_ideas MUST be a JSON array of 8-10 plain strings',
  },
  'ru': {
    'concept': 'Концепция контента:',
    'requirements': 'Требования:',
    'count': '- Создайте 8-10 конкретных, actionable идей кадров',
    'applyTones': '- Применяйте эти тона:',
    'timing':
        '- Укажите тайминг (например "0-3с") и стиль кадра (например "крупный план", "общий план") для каждого',
    'variety':
        '- Включите разнообразие: крюк, нагнетание, раскрытие и кадры призыва к действию',
    'format':
        '- Каждая идея кадра ДОЛЖНА быть одной обычной строкой в формате:\n  **N. Название**: Описание. Тайминг: X-Yс. Стиль кадра: стиль',
    'noNested':
        '- НЕ используйте вложенные объекты или синтаксис JSON key:value внутри строк',
    'mustArray': '- shot_ideas ДОЛЖЕН быть JSON-массивом из 8-10 обычных строк',
  },
  'uz': {
    'concept': 'Kontent kontseptsiyasi:',
    'requirements': 'Talablar:',
    'count': '- 8-10 ta aniq, amaliy shot ideyalari yarating',
    'applyTones': '- Ushbu ohanglarni qo\'llang:',
    'timing':
        '- Har biri uchun vaqt (masalan "0-3s") va shot uslubini (masalan "yaqin plan", "keng plan") kiriting',
    'variety':
        '- Xilma-xillikni kiriting: hook, taranggullik, kashfiyot va CTA shotlar',
    'format':
        '- Har bir shot ideyasi ushbu formatda bitta oddiy satr BO\'LISHI KERAK:\n  **N. Sarlavha**: Tavsif. Vaqt: X-Ys. Shot uslubi: uslub',
    'noNested':
        '- Satr elementlari ichida ichki obyektlar yoki JSON key:value sintaksisidan FOYDALANMANG',
    'mustArray':
        '- shot_ideas 8-10 ta oddiy satrlarning JSON massivi BO\'LISHI KERAK',
  },
  'ar': {
    'concept': 'مفهوم المحتوى:',
    'requirements': 'المتطلبات:',
    'count': '- أنشئ 8-10 أفكار لقطات محددة وقابلة للتنفيذ',
    'applyTones': '- طبّق هذه النبرات:',
    'timing':
        '- أدرج التوقيت (مثل "0-3ث") وأسلوب اللقطة (مثل "لقطة مقربة"، "لقطة واسعة") لكل منها',
    'variety': '- أدرج التنوع: خطاف، بناء توتر، كشف، ولقطات دعوة للعمل',
    'format':
        '- يجب أن تكون كل فكرة لقطة سلسلة نصية واحدة بهذا التنسيق:\n  **N. العنوان**: الوصف. التوقيت: X-Yث. أسلوب اللقطة: الأسلوب',
    'noNested':
        '- لا تستخدم كائنات متداخلة أو صيغة JSON key:value داخل أي عنصر نصي',
    'mustArray': '- يجب أن تكون shot_ideas مصفوفة JSON من 8-10 سلاسل عادية',
  },
  'de': {
    'concept': 'Inhaltskonzept:',
    'requirements': 'Anforderungen:',
    'count': '- 8-10 spezifische, umsetzbare Shot-Ideen erstellen',
    'applyTones': '- Diese Töne anwenden:',
    'timing':
        '- Für jeden Shot Timing (z.B. "0-3s") und Shot-Stil (z.B. "Nahaufnahme", "Weitwinkel") angeben',
    'variety':
        '- Abwechslung einschließen: Hook, Spannungsaufbau, Enthüllung und CTA-Shots',
    'format':
        '- Jede Shot-Idee MUSS ein einzelner einfacher String in diesem Format sein:\n  **N. Titel**: Beschreibung. Timing: X-Ys. Shot-Stil: Stil',
    'noNested':
        '- KEINE verschachtelten Objekte oder JSON key:value Syntax innerhalb von String-Elementen',
    'mustArray':
        '- shot_ideas MUSS ein JSON-Array aus 8-10 einfachen Strings sein',
  },
  'es': {
    'concept': 'Concepto de contenido:',
    'requirements': 'Requisitos:',
    'count': '- Crear 8-10 ideas de tomas específicas y accionables',
    'applyTones': '- Aplicar estos tonos:',
    'timing':
        '- Incluir el tiempo (ej. "0-3s") y el estilo de toma (ej. "primer plano", "plano general") para cada uno',
    'variety':
        '- Incluir variedad: gancho, generadores de tensión, revelaciones y tomas de CTA',
    'format':
        '- Cada idea de toma DEBE ser una cadena de texto simple en este formato:\n  **N. Título**: Descripción. Tiempo: X-Ys. Estilo de toma: estilo',
    'noNested':
        '- NO usar objetos anidados ni sintaxis JSON key:value dentro de cadenas',
    'mustArray': '- shot_ideas DEBE ser un array JSON de 8-10 strings simples',
  },
  'fr': {
    'concept': 'Concept de contenu :',
    'requirements': 'Exigences :',
    'count': '- Créer 8-10 idées de plans spécifiques et réalisables',
    'applyTones': '- Appliquer ces tons :',
    'timing':
        '- Inclure le timing (ex. "0-3s") et le style de plan (ex. "gros plan", "plan large") pour chacun',
    'variety':
        '- Inclure de la variété : accroche, montée en tension, révélations et plans CTA',
    'format':
        '- Chaque idée de plan DOIT être une chaîne simple dans ce format :\n  **N. Titre** : Description. Timing : X-Ys. Style de plan : style',
    'noNested':
        '- Ne PAS utiliser d\'objets imbriqués ou de syntaxe JSON key:value dans les chaînes',
    'mustArray':
        '- shot_ideas DOIT être un tableau JSON de 8-10 chaînes simples',
  },
  'hi': {
    'concept': 'Content Concept:',
    'requirements': 'Requirements:',
    'count': '- 8-10 specific, actionable shot ideas banao',
    'applyTones': '- In tones ko apply karo:',
    'timing':
        '- Har ek ke liye timing (jaise "0-3s") aur shot style (jaise "close-up", "wide shot") include karo',
    'variety':
        '- Variety include karo: hook, tension builders, reveals aur CTA shots',
    'format':
        '- Har shot idea is format mein ek plain string honi chahiye:\n  **N. Title**: Description. Timing: X-Ys. Shot style: style',
    'noNested':
        '- String items ke andar nested objects ya JSON key:value syntax ka use na karo',
    'mustArray': '- shot_ideas 8-10 plain strings ka JSON array hona chahiye',
  },
  'id': {
    'concept': 'Konsep Konten:',
    'requirements': 'Persyaratan:',
    'count': '- Buat 8-10 ide shot yang spesifik dan dapat dieksekusi',
    'applyTones': '- Terapkan nada-nada ini:',
    'timing':
        '- Sertakan timing (mis. "0-3d") dan gaya shot (mis. "close-up", "wide shot") untuk setiap shot',
    'variety':
        '- Sertakan variasi: hook, pembangun ketegangan, pengungkapan, dan shot CTA',
    'format':
        '- Setiap ide shot HARUS berupa string sederhana tunggal dalam format ini:\n  **N. Judul**: Deskripsi. Timing: X-Yd. Gaya shot: gaya',
    'noNested':
        '- JANGAN gunakan objek bersarang atau sintaks JSON key:value di dalam item string',
    'mustArray':
        '- shot_ideas HARUS berupa array JSON dari 8-10 string sederhana',
  },
  'ms': {
    'concept': 'Konsep Kandungan:',
    'requirements': 'Keperluan:',
    'count': '- Buat 8-10 idea shot yang spesifik dan boleh dilaksanakan',
    'applyTones': '- Gunakan nada-nada ini:',
    'timing':
        '- Sertakan masa (mis. "0-3s") dan gaya shot (mis. "close-up", "wide shot") untuk setiap shot',
    'variety':
        '- Sertakan variasi: hook, pembina ketegangan, pendedahan, dan shot CTA',
    'format':
        '- Setiap idea shot MESTI berupa string tunggal mudah dalam format ini:\n  **N. Tajuk**: Penerangan. Masa: X-Ys. Gaya shot: gaya',
    'noNested':
        '- JANGAN gunakan objek bersarang atau sintaks JSON key:value dalam item string',
    'mustArray': '- shot_ideas MESTI berupa array JSON dari 8-10 string mudah',
  },
  'pt': {
    'concept': 'Conceito de conteúdo:',
    'requirements': 'Requisitos:',
    'count': '- Criar 8-10 ideias de planos específicas e acionáveis',
    'applyTones': '- Aplicar estes tons:',
    'timing':
        '- Incluir o tempo (ex. "0-3s") e o estilo de plano (ex. "close-up", "plano aberto") para cada um',
    'variety':
        '- Incluir variedade: gancho, geradores de tensão, revelações e planos de CTA',
    'format':
        '- Cada ideia de plano DEVE ser uma string simples neste formato:\n  **N. Título**: Descrição. Tempo: X-Ys. Estilo de plano: estilo',
    'noNested':
        '- NÃO usar objetos aninhados ou sintaxe JSON key:value dentro de strings',
    'mustArray': '- shot_ideas DEVE ser um array JSON de 8-10 strings simples',
  },
  'vi': {
    'concept': 'Khái niệm nội dung:',
    'requirements': 'Yêu cầu:',
    'count': '- Tạo 8-10 ý tưởng cảnh quay cụ thể và có thể thực hiện',
    'applyTones': '- Áp dụng các tông này:',
    'timing':
        '- Bao gồm thời gian (vd. "0-3g") và phong cách quay (vd. "cận cảnh", "toàn cảnh") cho mỗi cảnh',
    'variety':
        '- Bao gồm sự đa dạng: hook, tạo căng thẳng, tiết lộ và cảnh CTA',
    'format':
        '- Mỗi ý tưởng cảnh quay PHẢI là một chuỗi đơn giản trong định dạng này:\n  **N. Tiêu đề**: Mô tả. Thời gian: X-Yg. Phong cách quay: phong cách',
    'noNested':
        '- KHÔNG dùng đối tượng lồng nhau hoặc cú pháp JSON key:value trong các mục chuỗi',
    'mustArray': '- shot_ideas PHẢI là một mảng JSON gồm 8-10 chuỗi đơn giản',
  },
};

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: get label map for a given language
// ─────────────────────────────────────────────────────────────────────────────

Map<String, String> _getLabels(
  Map<String, Map<String, String>> labelMap,
  String language,
) {
  final lang = _resolvedLang(language);
  return labelMap[lang] ?? labelMap['en']!;
}

// ─────────────────────────────────────────────────────────────────────────────
// BASE CLASS
// ─────────────────────────────────────────────────────────────────────────────

/// Base class for all prompt templates.
abstract class PromptTemplate {
  /// Build the base prompt for this generator type.
  /// Implementations should focus on core generation logic only.
  String buildBasePrompt(PromptContext context);

  /// Get template name for logging.
  String get templateName;
}

// ─────────────────────────────────────────────────────────────────────────────
// GENERATOR 1 · SCRIPT GENERATOR
// ─────────────────────────────────────────────────────────────────────────────

class ScriptGeneratorTemplate implements PromptTemplate {
  @override
  String get templateName => 'ScriptGenerator';

  @override
  String buildBasePrompt(PromptContext context) {
    final language = context.language;
    final request = context.userPrompt;
    final length = context.parameters?['length'] ?? 'short';
    final variation = context.parameters?['variation'] ?? 'default';

    final r = _getLabels(_scriptLabels, language);
    final l = _getLabels(_scriptLengthLabels, language);

    return '''${_getRoleIntro('script', language)}

${r['baseIdea']}
$request

${r['instructions']}
${r['noNested']}
${r['flatArrays']}
${r['hashtagArray']}

${_getLengthLabel(l, length)}
${_getVariationLabel(l, variation)}''';
  }

  String _getLengthLabel(Map<String, String> l, String length) =>
      switch (length) {
        'super_short' => l['superShort']!,
        'full' => l['full']!,
        _ => l['short']!,
      };

  String _getVariationLabel(Map<String, String> l, String variation) =>
      switch (variation) {
        'comedic' => l['comedic']!,
        'dramatic' => l['dramatic']!,
        'motivational' => l['motivational']!,
        _ => l['default']!,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// GENERATOR 2 · COMMENT GENERATOR
// ─────────────────────────────────────────────────────────────────────────────

class CommentGeneratorTemplate implements PromptTemplate {
  @override
  String get templateName => 'CommentGenerator';

  // Canonical tone descriptions — single source of truth.
  static const Map<String, String> _toneDescriptions = {
    'friendly': 'Friendly comments should be warm and casual',
    'engaging_question':
        'Engaging comments should encourage conversation and interaction',
    'humorous': 'Humorous comments should be witty and appropriate',
    'supportive': 'Supportive comments should be motivational and positive',
    'thought_provoking':
        'Thought-provoking comments should inspire reflection and deep thinking',
    'hate_to_art':
        'Hate-to-art comments should cleverly transform negativity and hate into elegant, artistic, and witty responses — turning shade into poetry, roasts into masterpieces, and criticism into creative gold',
  };

  @override
  String buildBasePrompt(PromptContext context) {
    final language = context.language;
    final basePrompt = context.userPrompt;

    final selectedTones =
        (context.parameters?['selectedTones'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        ['friendly'];

    final toneStructure = selectedTones
        .map(
          (t) =>
              '"$t": ["comment 1", "comment 2", "comment 3", "comment 4", "comment 5"]',
        )
        .join(',\n');

    final selectedDescriptions = selectedTones
        .map((t) => '- ${_toneDescriptions[t] ?? t}')
        .join('\n');

    debugPrint('🌍 CommentGeneratorTemplate: language=$language');

    final r = _getLabels(_commentLabels, language);

    return '''${_getRoleIntro('comment', language)} "$basePrompt"

${r['requirements']}
${r['relevance']} "$basePrompt"
${r['authentic']}
${r['exactly5']}
${r['mustArray']}
${r['noNumber']}
${r['onlyKeys']}

${r['exactShape']}
{
$toneStructure
}

${r['toneGuidance']}
$selectedDescriptions''';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GENERATOR 3 · HASHTAG GENERATOR
// ─────────────────────────────────────────────────────────────────────────────

class HashtagGeneratorTemplate implements PromptTemplate {
  @override
  String get templateName => 'HashtagGenerator';

  @override
  String buildBasePrompt(PromptContext context) {
    final language = context.language;
    final userInput = context.userPrompt;
    final isDifferent = context.parameters?['isDifferent'] as bool? ?? false;

    debugPrint('🌍 HashtagGeneratorTemplate: language=$language');

    final r = _getLabels(_hashtagLabels, language);

    final differentLine = isDifferent ? '\n${r['different']}' : '';

    return '''${_getRoleIntro('hashtag', language)}

${r['content']}
"$userInput"

${r['requirements']}
${r['count']}
${r['mood']}$differentLine
${r['continuous']}
${r['noComma']}
${r['noExtra']}''';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GENERATOR 4 · VIRAL REWRITE
// ─────────────────────────────────────────────────────────────────────────────

class ViralRewriteTemplate implements PromptTemplate {
  @override
  String get templateName => 'ViralRewrite';

  @override
  String buildBasePrompt(PromptContext context) {
    final language = context.language;
    final userInput = context.userPrompt;
    final selectedToneDescriptions =
        (context.parameters?['selectedToneDescriptions'] as String?) ??
        'engaging, relatable';

    debugPrint('🌍 ViralRewriteTemplate: language=$language');

    final r = _getLabels(_viralRewriteLabels, language);

    return '''${_getRoleIntro('viral_rewrite', language)}

${r['original']}
"$userInput"

${r['requirements']}
${r['punchy']}
${r['applyTones']} $selectedToneDescriptions
${r['flatJson']}
${r['noBraces']}
${r['hook']}
${r['hashtagLine']}
${r['cta']}''';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GENERATOR 5 · SHOT IDEAS
// ─────────────────────────────────────────────────────────────────────────────

class ShotIdeasTemplate implements PromptTemplate {
  @override
  String get templateName => 'ShotIdeas';

  @override
  String buildBasePrompt(PromptContext context) {
    final language = context.language;
    final userInput = context.userPrompt;
    final selectedToneDescriptions =
        (context.parameters?['selectedToneDescriptions'] as String?) ??
        'warm and approachable, funny and entertaining';

    debugPrint('🌍 ShotIdeasTemplate: language=$language');

    final r = _getLabels(_shotIdeasLabels, language);

    // Build extra language enforcement for Shot Ideas
    final langName = _languageNames[_resolvedLang(language)]!;
    final langEnforcement =
        '''

⚠️ CRITICAL LANGUAGE REQUIREMENT:
- All shot ideas MUST be generated in $langName language ONLY
- NO English words or mixed language allowed
- Every shot title, description, and timing must be in $langName
- This is non-negotiable - pure $langName only''';

    return '''${_getRoleIntro('shot_ideas', language)}

${r['concept']}
"$userInput"

${r['requirements']}
${r['count']}
${r['applyTones']} $selectedToneDescriptions
${r['timing']}
${r['variety']}
${r['format']}
${r['noNested']}
${r['mustArray']}$langEnforcement''';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GENERATOR 6 · IDEA REFINEMENT
// ─────────────────────────────────────────────────────────────────────────────

class RefinementTemplate implements PromptTemplate {
  @override
  String get templateName => 'IdeaRefinement';

  @override
  String buildBasePrompt(PromptContext context) {
    final lines = context.userPrompt.split('\n');
    final title = lines.first;
    final description = lines.length > 1 ? lines.skip(1).join('\n') : '';

    final stepsValue = context.parameters?['steps'];
    final steps = switch (stepsValue) {
      List s => s.join(', '),
      String s => s,
      Map m => m.toString(),
      _ => '',
    };

    final ctaValue = context.parameters?['cta'];
    final cta = switch (ctaValue) {
      String s => s,
      Map m => m.toString(),
      _ => '',
    };

    final length = context.parameters?['length'] is String
        ? context.parameters!['length'] as String
        : 'short';
    final variation = context.parameters?['variation'] is String
        ? context.parameters!['variation'] as String
        : 'default';
    final emotion = context.parameters?['emotion'] is String
        ? context.parameters!['emotion'] as String
        : 'neutral';
    final platform = context.platform ?? 'reels';
    final language = context.language;

    debugPrint(
      '📊 RefinementTemplate: length=$length | variation=$variation | emotion=$emotion | lang=$language',
    );

    final roleIntro = _getRoleIntro('refinement', language);
    final labels = _getFieldLabels(language);
    final lengthGuide = _getLengthGuide(length, language);
    final variationGuide = _getVariationGuide(variation, language);
    final emotionGuide = _getEmotionGuide(emotion, language);
    final platformGuide = _getPlatformGuide(platform, language);

    return '''$roleIntro

${labels['currentIdea']}:
${labels['title']}: $title
${labels['description']}: $description
${labels['steps']}: $steps
CTA: $cta

${labels['guidelines']}:
- $lengthGuide
- $variationGuide
- $emotionGuide
- $platformGuide

${labels['strictReqs']}:
- ${labels['noEmpty']}
- ${labels['allFilled']}
- refined_steps ${labels['must5Steps']}
- ${labels['eachSpecific']}
- ${labels['qualityAbove']}

${labels['returnJson']}''';
  }

  // ── Field labels ─────────────────────────────────────────────────────────

  static const Map<String, Map<String, String>> _fieldLabelsMap = {
    'en': {
      'currentIdea': 'Current Idea',
      'title': 'Title',
      'description': 'Description',
      'steps': 'Steps',
      'guidelines': 'Guidelines',
      'strictReqs': 'STRICT REQUIREMENTS',
      'noEmpty': 'NEVER return empty fields or null values',
      'allFilled': 'All fields MUST be filled with relevant text',
      'must5Steps': 'MUST contain 5 steps, each minimum 10 words',
      'eachSpecific': 'Each step must be specific and actionable',
      'qualityAbove': 'Overall quality must exceed the original idea',
      'returnJson': 'Return ONLY a JSON object (no markdown, no extra text)',
      'exTitle': 'An improved, more compelling title',
      'exDesc': 'A description that enhances virality and engagement',
      'exStep': 'Step',
      'exCta': 'A more compelling call-to-action',
    },
    'ru': {
      'currentIdea': 'Текущая идея',
      'title': 'Заголовок',
      'description': 'Описание',
      'steps': 'Шаги',
      'guidelines': 'Руководство',
      'strictReqs': 'СТРОГИЕ ТРЕБОВАНИЯ',
      'noEmpty': 'НИКОГДА не возвращайте пустые поля или значения null',
      'allFilled':
          'Все поля ОБЯЗАТЕЛЬНО должны быть заполнены релевантным текстом',
      'must5Steps': 'ДОЛЖЕН содержать 5 шагов, каждый min 10 слов',
      'eachSpecific': 'Каждый шаг должен быть конкретным и практичным',
      'qualityAbove': 'Общее качество ВЫШЕ чем исходная идея',
      'returnJson': 'Верните ТОЛЬКО JSON',
      'exTitle': 'Улучшенный заголовок, более привлекательный',
      'exDesc': 'Описание, которое повышает вирусность и вовлеченность',
      'exStep': 'Шаг',
      'exCta': 'Более привлекательный призыв к действию',
    },
    'uz': {
      'currentIdea': "Joriy g'oya",
      'title': 'Sarlavha',
      'description': 'Tavsif',
      'steps': 'Qadamlar',
      'guidelines': "Ko'rsatmalar",
      'strictReqs': 'QATIY TALABLAR',
      'noEmpty': "HECH QACHON bo'sh maydonlarni qaytarmang",
      'allFilled': "Barcha maydonlar MUTLAQO to'ldirilgan bo'lishi kerak",
      'must5Steps': "5 ta qadamni o'z ichiga olishi kerak, har biri 10+ so'z",
      'eachSpecific': "Har bir qadami aniq va amaliy bo'lishi kerak",
      'qualityAbove': "Umumiy sifat asliy g'oyadan YUQORI bo'lishi kerak",
      'returnJson': 'Faqat JSON qaytaring',
      'exTitle': 'Yaxshilangan sarlavha',
      'exDesc': "Tavsif ko'proq viral xususiyati bilan",
      'exStep': 'Qadami',
      'exCta': "Ko'proq jozibador harakatlantirish",
    },
    'ar': {
      'currentIdea': 'الفكرة الحالية',
      'title': 'العنوان',
      'description': 'الوصف',
      'steps': 'الخطوات',
      'guidelines': 'الإرشادات',
      'strictReqs': 'متطلبات صارمة',
      'noEmpty': 'لا تعد أبدًا حقولاً فارغة أو null',
      'allFilled': 'يجب ملء جميع الحقول بنص ذا صلة',
      'must5Steps': 'يجب أن يحتوي على 5 خطوات، كل منها 10+ كلمات',
      'eachSpecific': 'كل خطوة يجب أن تكون محددة وعملية',
      'qualityAbove': 'الجودة الإجمالية أعلى من الفكرة الأصلية',
      'returnJson': 'أعد فقط JSON',
      'exTitle': 'عنوان محسّن أكثر جاذبية',
      'exDesc': 'وصف أكثر فيروسية وتفاعلاً',
      'exStep': 'خطوة',
      'exCta': 'دعوة أقوى للعمل',
    },
    'de': {
      'currentIdea': 'Aktuelle Idee',
      'title': 'Titel',
      'description': 'Beschreibung',
      'steps': 'Schritte',
      'guidelines': 'Richtlinien',
      'strictReqs': 'STRIKTE ANFORDERUNGEN',
      'noEmpty': 'Geben Sie NIEMALS leere Felder zurück',
      'allFilled': 'Alle Felder MÜSSEN mit relevanten Texten gefüllt sein',
      'must5Steps': 'muss 5 Schritte enthalten, jeder mindestens 10 Wörter',
      'eachSpecific': 'Jeder Schritt muss konkret und praktisch sein',
      'qualityAbove': 'Gesamtqualität muss über der Originalidee liegen',
      'returnJson': 'Gib nur JSON zurück',
      'exTitle': 'Verbesserter Titel, ansprechender',
      'exDesc': 'Beschreibung mit höherer Viralität',
      'exStep': 'Schritt',
      'exCta': 'Stärkerer Call-to-Action',
    },
    'es': {
      'currentIdea': 'Idea actual',
      'title': 'Título',
      'description': 'Descripción',
      'steps': 'Pasos',
      'guidelines': 'Guía',
      'strictReqs': 'REQUISITOS ESTRICTOS',
      'noEmpty': 'NUNCA devolver campos vacíos',
      'allFilled': 'Todos los campos DEBEN estar llenos de texto relevante',
      'must5Steps': 'debe contener 5 pasos, cada uno 10+ palabras',
      'eachSpecific': 'Cada paso debe ser específico y práctico',
      'qualityAbove': 'La calidad general debe superar la idea original',
      'returnJson': 'Devuelve solo JSON',
      'exTitle': 'Título mejorado, más atractivo',
      'exDesc': 'Descripción con mayor viralidad',
      'exStep': 'Paso',
      'exCta': 'Llamada a la acción más convincente',
    },
    'fr': {
      'currentIdea': 'Idée actuelle',
      'title': 'Titre',
      'description': 'Description',
      'steps': 'Étapes',
      'guidelines': 'Guide',
      'strictReqs': 'EXIGENCES STRICTES',
      'noEmpty': 'NE JAMAIS retourner de champs vides',
      'allFilled': 'Tous les champs DOIVENT être remplis de texte pertinent',
      'must5Steps': 'doit contenir 5 étapes, chacune 10+ mots',
      'eachSpecific': 'Chaque étape doit être spécifique et pratique',
      'qualityAbove': "La qualité globale doit dépasser l'idée originale",
      'returnJson': 'Retournez uniquement JSON',
      'exTitle': 'Titre amélioré, plus attrayant',
      'exDesc': 'Description avec plus de viralité',
      'exStep': 'Étape',
      'exCta': "Appel à l'action plus convaincant",
    },
    'hi': {
      'currentIdea': 'Current idea',
      'title': 'Title',
      'description': 'Description',
      'steps': 'Steps',
      'guidelines': 'Guidelines',
      'strictReqs': 'Strict requirements',
      'noEmpty': 'Kabhi bhi empty field return na karein',
      'allFilled': 'Saari fields relevant text se filled honi chahiye',
      'must5Steps': 'Ismein 5 steps hone chahiye, har ek 10+ shabd',
      'eachSpecific': 'Har step specific aur practical hona chahiye',
      'qualityAbove': 'Overall quality original idea se better honi chahiye',
      'returnJson': 'Sirf JSON return karein',
      'exTitle': 'Better, zyada engaging title',
      'exDesc': 'Virality aur engagement badhane wala description',
      'exStep': 'Step',
      'exCta': 'Zyada engaging call-to-action',
    },
    'id': {
      'currentIdea': 'Ide saat ini',
      'title': 'Judul',
      'description': 'Deskripsi',
      'steps': 'Langkah',
      'guidelines': 'Panduan',
      'strictReqs': 'PERSYARATAN KETAT',
      'noEmpty': 'JANGAN PERNAH kembalikan field kosong',
      'allFilled': 'Semua field HARUS diisi dengan teks relevan',
      'must5Steps': 'harus berisi 5 langkah, masing-masing 10+ kata',
      'eachSpecific': 'Setiap langkah harus spesifik dan praktis',
      'qualityAbove': 'Kualitas keseluruhan harus melebihi ide asli',
      'returnJson': 'Kembalikan hanya JSON',
      'exTitle': 'Judul yang ditingkatkan',
      'exDesc': 'Deskripsi dengan viralitas lebih tinggi',
      'exStep': 'Langkah',
      'exCta': 'Call-to-action yang lebih kuat',
    },
    'ms': {
      'currentIdea': 'Idea semasa',
      'title': 'Tajuk',
      'description': 'Penerangan',
      'steps': 'Langkah',
      'guidelines': 'Panduan',
      'strictReqs': 'KEPERLUAN KETAT',
      'noEmpty': 'JANGAN PULANG field kosong',
      'allFilled': 'Semua field MESTI diisi dengan teks relevan',
      'must5Steps': 'harus mengandungi 5 langkah, masing-masing 10+ perkataan',
      'eachSpecific': 'Setiap langkah harus spesifik dan praktikal',
      'qualityAbove': 'Kualiti keseluruhan harus melebihi idea asal',
      'returnJson': 'Pulang hanya JSON',
      'exTitle': 'Tajuk yang dipertingkat',
      'exDesc': 'Penerangan dengan viraliti lebih tinggi',
      'exStep': 'Langkah',
      'exCta': 'Seruan bertindak yang lebih kuat',
    },
    'pt': {
      'currentIdea': 'Ideia atual',
      'title': 'Título',
      'description': 'Descrição',
      'steps': 'Etapas',
      'guidelines': 'Diretrizes',
      'strictReqs': 'REQUISITOS RIGOROSOS',
      'noEmpty': 'NUNCA retorne campos vazios',
      'allFilled': 'Todos os campos DEVEM ser preenchidos com texto relevante',
      'must5Steps': 'deve conter 5 etapas, cada uma com 10+ palavras',
      'eachSpecific': 'Cada etapa deve ser específica e prática',
      'qualityAbove': 'A qualidade geral deve superar a ideia original',
      'returnJson': 'Retorne apenas JSON',
      'exTitle': 'Título melhorado, mais atraente',
      'exDesc': 'Descrição com maior viralidade',
      'exStep': 'Etapa',
      'exCta': 'Chamada à ação mais convincente',
    },
    'vi': {
      'currentIdea': 'Ý tưởng hiện tại',
      'title': 'Tiêu đề',
      'description': 'Mô tả',
      'steps': 'Bước',
      'guidelines': 'Hướng dẫn',
      'strictReqs': 'YÊU CẦU NGHIÊM NGẶT',
      'noEmpty': 'KHÔNG BAO GIỜ trả về các trường trống',
      'allFilled': 'Tất cả các trường PHẢI được điền bằng văn bản có liên quan',
      'must5Steps': 'phải chứa 5 bước, mỗi bước 10+ từ',
      'eachSpecific': 'Mỗi bước phải cụ thể và thực tế',
      'qualityAbove': 'Chất lượng tổng thể phải vượt quá ý tưởng gốc',
      'returnJson': 'Chỉ trả về JSON',
      'exTitle': 'Tiêu đề cải thiện, hấp dẫn hơn',
      'exDesc': 'Mô tả có viralité cao hơn',
      'exStep': 'Bước',
      'exCta': 'Lời kêu gọi hành động thuyết phục hơn',
    },
  };

  Map<String, String> _getFieldLabels(String language) {
    final lang = _resolvedLang(language);
    return _fieldLabelsMap[lang] ?? _fieldLabelsMap['en']!;
  }

  // ── Refinement-specific guides (12 languages) ─────────────────────────────

  static const Map<String, Map<String, String>> _lengthGuides = {
    'en': {
      'super_short':
          '📏 SUPER_SHORT LENGTH (15-20 second format):\n'
          '- Title: MAX 8 words\n'
          '- Description: MAX 30 words, 1 sentence only\n'
          '- Steps: 2 steps ONLY (not 3, not 5, exactly 2)\n'
          '- CTA: MAX 5 words\n'
          '- TOTAL OUTPUT: 50-80 words MAX. Ultra-compressed, punchy, minimal.',
      'full':
          '📏 FULL LENGTH (120+ second format):\n'
          '- Title: 8-15 words, detailed and specific\n'
          '- Description: 100-150 words, multiple paragraphs\n'
          '- Steps: ALL 5 steps detailed (minimum 15 words EACH)\n'
          '- CTA: 8-12 words, compelling\n'
          '- TOTAL OUTPUT: 400-600 words. Comprehensive, thorough, in-depth breakdown.',
      'short':
          '📏 SHORT LENGTH (45-60 second format):\n'
          '- Title: 6-10 words, engaging\n'
          '- Description: 50-80 words, 2-3 sentences\n'
          '- Steps: 4 steps (NOT 2, NOT 5, exactly 4) minimum 10 words EACH\n'
          '- CTA: 6-8 words\n'
          '- TOTAL OUTPUT: 150-250 words. Balanced, clear, concise.',
    },
    'ru': {
      'super_short':
          '📏 ОЧЕНЬ КОРОТКИЙ (формат 15-20 секунд):\n'
          '- Заголовок: МАКС 8 слов\n'
          '- Описание: МАКС 30 слов, только 1 предложение\n'
          '- Шаги: ТОЛЬКО 2 шага (не 3, не 5, ровно 2)\n'
          '- CTA: МАКС 5 слов\n'
          '- ИТОГО: 50-80 слов МАКС. Ультракомпактно, ёмко, минимально.',
      'full':
          '📏 ПОЛНЫЙ (формат 120+ секунд):\n'
          '- Заголовок: 8-15 слов, подробный и конкретный\n'
          '- Описание: 100-150 слов, несколько абзацев\n'
          '- Шаги: ВСЕ 5 шагов детально (минимум 15 слов КАЖДЫЙ)\n'
          '- CTA: 8-12 слов, убедительно\n'
          '- ИТОГО: 400-600 слов. Всестороннее, тщательное, глубокое.',
      'short':
          '📏 КОРОТКИЙ (формат 45-60 секунд):\n'
          '- Заголовок: 6-10 слов, увлекательный\n'
          '- Описание: 50-80 слов, 2-3 предложения\n'
          '- Шаги: 4 шага (НЕ 2, НЕ 5, ровно 4) минимум 10 слов КАЖДЫЙ\n'
          '- CTA: 6-8 слов\n'
          '- ИТОГО: 150-250 слов. Сбалансировано, чётко, лаконично.',
    },
    'uz': {
      'super_short':
          "📏 JUDA QISQA (15-20 soniyalik format):\n"
          "- Sarlavha: MAKS 8 so'z\n"
          "- Tavsif: MAKS 30 so'z, faqat 1 jumla\n"
          "- Qadamlar: FAQAT 2 qadam (3 emas, 5 emas, aynan 2)\n"
          "- CTA: MAKS 5 so'z\n"
          "- JAMI: 50-80 so'z MAKS. Ultra-ixcham, ta'sirchan, minimal.",
      'full':
          "📏 TO'LIQ (120+ soniyalik format):\n"
          "- Sarlavha: 8-15 so'z, batafsil va aniq\n"
          "- Tavsif: 100-150 so'z, bir necha paragraf\n"
          "- Qadamlar: BARCHA 5 qadam batafsil (har biri kamida 15 so'z)\n"
          "- CTA: 8-12 so'z, ta'sirchan\n"
          "- JAMI: 400-600 so'z. Keng qamrovli, puxta, chuqur.",
      'short':
          "📏 QISQA (45-60 soniyalik format):\n"
          "- Sarlavha: 6-10 so'z, qiziqarli\n"
          "- Tavsif: 50-80 so'z, 2-3 jumla\n"
          "- Qadamlar: 4 qadam (2 emas, 5 emas, aynan 4) har biri kamida 10 so'z\n"
          "- CTA: 6-8 so'z\n"
          "- JAMI: 150-250 so'z. Muvozanatli, aniq, ixcham.",
    },
    'ar': {
      'super_short':
          '📏 قصير جداً (تنسيق 15-20 ثانية):\n'
          '- العنوان: 8 كلمات كحد أقصى\n'
          '- الوصف: 30 كلمة كحد أقصى، جملة واحدة فقط\n'
          '- الخطوات: خطوتان فقط (ليس 3، ليس 5، بالضبط 2)\n'
          '- CTA: 5 كلمات كحد أقصى\n'
          '- المجموع: 50-80 كلمة كحد أقصى. مضغوط للغاية، مؤثر، بسيط.',
      'full':
          '📏 كامل (تنسيق 120+ ثانية):\n'
          '- العنوان: 8-15 كلمة، مفصّل ومحدد\n'
          '- الوصف: 100-150 كلمة، فقرات متعددة\n'
          '- الخطوات: جميع الخطوات الخمس مفصّلة (15 كلمة لكل منها كحد أدنى)\n'
          '- CTA: 8-12 كلمة، مقنع\n'
          '- المجموع: 400-600 كلمة. شامل، دقيق، معمّق.',
      'short':
          '📏 قصير (تنسيق 45-60 ثانية):\n'
          '- العنوان: 6-10 كلمات، جذاب\n'
          '- الوصف: 50-80 كلمة، 2-3 جمل\n'
          '- الخطوات: 4 خطوات (ليس 2، ليس 5، بالضبط 4) 10 كلمات لكل منها كحد أدنى\n'
          '- CTA: 6-8 كلمات\n'
          '- المجموع: 150-250 كلمة. متوازن، واضح، موجز.',
    },
    'de': {
      'super_short':
          '📏 SEHR KURZ (15-20-Sekunden-Format):\n'
          '- Titel: MAX 8 Wörter\n'
          '- Beschreibung: MAX 30 Wörter, nur 1 Satz\n'
          '- Schritte: NUR 2 Schritte (nicht 3, nicht 5, genau 2)\n'
          '- CTA: MAX 5 Wörter\n'
          '- GESAMT: 50-80 Wörter MAX. Ultrakompakt, prägnant, minimal.',
      'full':
          '📏 VOLLSTÄNDIG (120+-Sekunden-Format):\n'
          '- Titel: 8-15 Wörter, detailliert und spezifisch\n'
          '- Beschreibung: 100-150 Wörter, mehrere Absätze\n'
          '- Schritte: ALLE 5 Schritte detailliert (mindestens 15 Wörter JEDER)\n'
          '- CTA: 8-12 Wörter, überzeugend\n'
          '- GESAMT: 400-600 Wörter. Umfassend, gründlich, tiefgehend.',
      'short':
          '📏 KURZ (45-60-Sekunden-Format):\n'
          '- Titel: 6-10 Wörter, ansprechend\n'
          '- Beschreibung: 50-80 Wörter, 2-3 Sätze\n'
          '- Schritte: 4 Schritte (NICHT 2, NICHT 5, genau 4) mindestens 10 Wörter JEDER\n'
          '- CTA: 6-8 Wörter\n'
          '- GESAMT: 150-250 Wörter. Ausgewogen, klar, prägnant.',
    },
    'es': {
      'super_short':
          '📏 MUY CORTO (formato de 15-20 segundos):\n'
          '- Título: MÁX 8 palabras\n'
          '- Descripción: MÁX 30 palabras, solo 1 oración\n'
          '- Pasos: SOLO 2 pasos (no 3, no 5, exactamente 2)\n'
          '- CTA: MÁX 5 palabras\n'
          '- TOTAL: 50-80 palabras MÁX. Ultra-comprimido, contundente, mínimo.',
      'full':
          '📏 COMPLETO (formato de 120+ segundos):\n'
          '- Título: 8-15 palabras, detallado y específico\n'
          '- Descripción: 100-150 palabras, múltiples párrafos\n'
          '- Pasos: TODOS 5 pasos detallados (mínimo 15 palabras CADA UNO)\n'
          '- CTA: 8-12 palabras, convincente\n'
          '- TOTAL: 400-600 palabras. Completo, exhaustivo, profundo.',
      'short':
          '📏 CORTO (formato de 45-60 segundos):\n'
          '- Título: 6-10 palabras, atractivo\n'
          '- Descripción: 50-80 palabras, 2-3 oraciones\n'
          '- Pasos: 4 pasos (NO 2, NO 5, exactamente 4) mínimo 10 palabras CADA UNO\n'
          '- CTA: 6-8 palabras\n'
          '- TOTAL: 150-250 palabras. Equilibrado, claro, conciso.',
    },
    'fr': {
      'super_short':
          '📏 TRÈS COURT (format 15-20 secondes) :\n'
          '- Titre : MAX 8 mots\n'
          '- Description : MAX 30 mots, 1 phrase seulement\n'
          '- Étapes : SEULEMENT 2 étapes (pas 3, pas 5, exactement 2)\n'
          '- CTA : MAX 5 mots\n'
          '- TOTAL : 50-80 mots MAX. Ultra-compressé, percutant, minimal.',
      'full':
          '📏 COMPLET (format 120+ secondes) :\n'
          '- Titre : 8-15 mots, détaillé et spécifique\n'
          '- Description : 100-150 mots, plusieurs paragraphes\n'
          '- Étapes : TOUTES 5 étapes détaillées (minimum 15 mots CHACUNE)\n'
          '- CTA : 8-12 mots, convaincant\n'
          '- TOTAL : 400-600 mots. Complet, approfondi, exhaustif.',
      'short':
          '📏 COURT (format 45-60 secondes) :\n'
          '- Titre : 6-10 mots, engageant\n'
          '- Description : 50-80 mots, 2-3 phrases\n'
          '- Étapes : 4 étapes (PAS 2, PAS 5, exactement 4) minimum 10 mots CHACUNE\n'
          '- CTA : 6-8 mots\n'
          '- TOTAL : 150-250 mots. Équilibré, clair, concis.',
    },
    'hi': {
      'super_short':
          '📏 Bahut chhoti length (15-20 second ka format):\n'
          '- Title: maximum 8 shabd\n'
          '- Description: maximum 30 shabd, sirf 1 sentence\n'
          '- Steps: sirf 2 steps (3 nahi, 5 nahi, bilkul 2)\n'
          '- CTA: maximum 5 shabd\n'
          '- Total: maximum 50-80 shabd. Ultra-compressed, impactful, minimal.',
      'full':
          '📏 Full length (120+ second ka format):\n'
          '- Title: 8-15 shabd, detailed aur specific\n'
          '- Description: 100-150 shabd, multiple paragraphs\n'
          '- Steps: saare 5 steps detailed (har ek mein kam se kam 15 shabd)\n'
          '- CTA: 8-12 shabd, compelling\n'
          '- Total: 400-600 shabd. Comprehensive, deep, detailed.',
      'short':
          '📏 Short length (45-60 second ka format):\n'
          '- Title: 6-10 shabd, engaging\n'
          '- Description: 50-80 shabd, 2-3 sentences\n'
          '- Steps: 4 steps (2 nahi, 5 nahi, bilkul 4) har ek mein kam se kam 10 shabd\n'
          '- CTA: 6-8 shabd\n'
          '- Total: 150-250 shabd. Balanced, clear, concise.',
    },
    'id': {
      'super_short':
          '📏 SANGAT PENDEK (format 15-20 detik):\n'
          '- Judul: MAKS 8 kata\n'
          '- Deskripsi: MAKS 30 kata, hanya 1 kalimat\n'
          '- Langkah: HANYA 2 langkah (bukan 3, bukan 5, tepat 2)\n'
          '- CTA: MAKS 5 kata\n'
          '- TOTAL: 50-80 kata MAKS. Ultra-padat, tajam, minimal.',
      'full':
          '📏 PENUH (format 120+ detik):\n'
          '- Judul: 8-15 kata, detail dan spesifik\n'
          '- Deskripsi: 100-150 kata, beberapa paragraf\n'
          '- Langkah: SEMUA 5 langkah detail (minimum 15 kata MASING-MASING)\n'
          '- CTA: 8-12 kata, meyakinkan\n'
          '- TOTAL: 400-600 kata. Komprehensif, mendalam.',
      'short':
          '📏 PENDEK (format 45-60 detik):\n'
          '- Judul: 6-10 kata, menarik\n'
          '- Deskripsi: 50-80 kata, 2-3 kalimat\n'
          '- Langkah: 4 langkah (BUKAN 2, BUKAN 5, tepat 4) minimum 10 kata MASING-MASING\n'
          '- CTA: 6-8 kata\n'
          '- TOTAL: 150-250 kata. Seimbang, jelas, ringkas.',
    },
    'ms': {
      'super_short':
          '📏 SANGAT PENDEK (format 15-20 saat):\n'
          '- Tajuk: MAKS 8 patah perkataan\n'
          '- Penerangan: MAKS 30 patah perkataan, hanya 1 ayat\n'
          '- Langkah: HANYA 2 langkah (bukan 3, bukan 5, tepat 2)\n'
          '- CTA: MAKS 5 patah perkataan\n'
          '- JUMLAH: 50-80 patah perkataan MAKS. Ultra-padat, tajam, minimal.',
      'full':
          '📏 PENUH (format 120+ saat):\n'
          '- Tajuk: 8-15 patah perkataan, terperinci dan spesifik\n'
          '- Penerangan: 100-150 patah perkataan, beberapa perenggan\n'
          '- Langkah: SEMUA 5 langkah terperinci (minimum 15 patah perkataan SETIAP SATU)\n'
          '- CTA: 8-12 patah perkataan, meyakinkan\n'
          '- JUMLAH: 400-600 patah perkataan. Menyeluruh, mendalam.',
      'short':
          '📏 PENDEK (format 45-60 saat):\n'
          '- Tajuk: 6-10 patah perkataan, menarik\n'
          '- Penerangan: 50-80 patah perkataan, 2-3 ayat\n'
          '- Langkah: 4 langkah (BUKAN 2, BUKAN 5, tepat 4) minimum 10 patah perkataan SETIAP SATU\n'
          '- CTA: 6-8 patah perkataan\n'
          '- JUMLAH: 150-250 patah perkataan. Seimbang, jelas, ringkas.',
    },
    'pt': {
      'super_short':
          '📏 MUITO CURTO (formato de 15-20 segundos):\n'
          '- Título: MÁX 8 palavras\n'
          '- Descrição: MÁX 30 palavras, apenas 1 frase\n'
          '- Etapas: APENAS 2 etapas (não 3, não 5, exatamente 2)\n'
          '- CTA: MÁX 5 palavras\n'
          '- TOTAL: 50-80 palavras MÁX. Ultra-comprimido, impactante, mínimo.',
      'full':
          '📏 COMPLETO (formato de 120+ segundos):\n'
          '- Título: 8-15 palavras, detalhado e específico\n'
          '- Descrição: 100-150 palavras, múltiplos parágrafos\n'
          '- Etapas: TODAS 5 etapas detalhadas (mínimo 15 palavras CADA)\n'
          '- CTA: 8-12 palavras, convincente\n'
          '- TOTAL: 400-600 palavras. Abrangente, completo, aprofundado.',
      'short':
          '📏 CURTO (formato de 45-60 segundos):\n'
          '- Título: 6-10 palavras, envolvente\n'
          '- Descrição: 50-80 palavras, 2-3 frases\n'
          '- Etapas: 4 etapas (NÃO 2, NÃO 5, exatamente 4) mínimo 10 palavras CADA\n'
          '- CTA: 6-8 palavras\n'
          '- TOTAL: 150-250 palavras. Equilibrado, claro, conciso.',
    },
    'vi': {
      'super_short':
          '📏 RẤT NGẮN (định dạng 15-20 giây):\n'
          '- Tiêu đề: TỐI ĐA 8 từ\n'
          '- Mô tả: TỐI ĐA 30 từ, chỉ 1 câu\n'
          '- Bước: CHỈ 2 bước (không phải 3, không phải 5, đúng 2)\n'
          '- CTA: TỐI ĐA 5 từ\n'
          '- TỔNG: 50-80 từ TỐI ĐA. Siêu nén, mạnh mẽ, tối giản.',
      'full':
          '📏 ĐẦY ĐỦ (định dạng 120+ giây):\n'
          '- Tiêu đề: 8-15 từ, chi tiết và cụ thể\n'
          '- Mô tả: 100-150 từ, nhiều đoạn văn\n'
          '- Bước: TẤT CẢ 5 bước chi tiết (tối thiểu 15 từ MỖI bước)\n'
          '- CTA: 8-12 từ, thuyết phục\n'
          '- TỔNG: 400-600 từ. Toàn diện, kỹ lưỡng, sâu sắc.',
      'short':
          '📏 NGẮN (định dạng 45-60 giây):\n'
          '- Tiêu đề: 6-10 từ, hấp dẫn\n'
          '- Mô tả: 50-80 từ, 2-3 câu\n'
          '- Bước: 4 bước (KHÔNG phải 2, KHÔNG phải 5, đúng 4) tối thiểu 10 từ MỖI bước\n'
          '- CTA: 6-8 từ\n'
          '- TỔNG: 150-250 từ. Cân bằng, rõ ràng, súc tích.',
    },
  };

  static const Map<String, Map<String, String>> _variationGuides = {
    'en': {
      'comedy':
          '🎭 VARIATION: Comedy/Humor Style\n'
          '- Heavy use of word play, puns, jokes\n'
          '- Exaggerated reactions and funny moments\n'
          '- Unexpected twists that surprise audience\n'
          '- Make people laugh out loud',
      'dramatic':
          '🎭 VARIATION: Dramatic/Suspense Style\n'
          '- Build tension gradually from start\n'
          '- Include cliffhanger moments\n'
          '- Emotional intensity throughout\n'
          '- Gripping narrative arc',
      'romantic':
          '🎭 VARIATION: Romantic/Emotional Style\n'
          '- Heart-warming moments\n'
          '- Love and connection themes\n'
          '- Emotional storytelling\n'
          '- Touching and relatable scenes',
      'school':
          '🎭 VARIATION: School/Educational Style\n'
          '- Student and teacher interactions\n'
          '- School setting scenarios\n'
          '- Learning moments\n'
          '- Relatable student experiences',
      'npc':
          '🎭 VARIATION: NPC/Game Character Style\n'
          '- Robotic, repetitive behaviors\n'
          '- Glitchy movement patterns\n'
          '- Meme-style actions\n'
          '- Over-the-top character voice',
      'default':
          '🎭 VARIATION: Standard Engaging Style\n'
          '- Direct and clear messaging\n'
          '- Relatable content\n'
          '- Natural storytelling\n'
          '- Standard viral format',
    },
    'ru': {
      'comedy':
          '🎭 ВАРИАЦИЯ: Комедийный стиль\n'
          '- Активное использование игры слов, каламбуров, шуток\n'
          '- Преувеличенные реакции и смешные моменты\n'
          '- Неожиданные повороты, удивляющие зрителей\n'
          '- Заставить людей громко смеяться',
      'dramatic':
          '🎭 ВАРИАЦИЯ: Драматический/Напряжённый стиль\n'
          '- Постепенное нагнетание напряжения с самого начала\n'
          '- Включение захватывающих моментов\n'
          '- Эмоциональная насыщенность на протяжении всего\n'
          '- Захватывающая нарративная дуга',
      'romantic':
          '🎭 ВАРИАЦИЯ: Романтический/Эмоциональный стиль\n'
          '- Трогательные моменты\n'
          '- Темы любви и связи\n'
          '- Эмоциональное повествование\n'
          '- Трогающие и близкие зрителю сцены',
      'school':
          '🎭 ВАРИАЦИЯ: Школьный/Образовательный стиль\n'
          '- Взаимодействие учеников и учителей\n'
          '- Школьные сценарии\n'
          '- Моменты обучения\n'
          '- Близкие ученикам ситуации',
      'npc':
          '🎭 ВАРИАЦИЯ: Стиль NPC/Игрового персонажа\n'
          '- Роботизированное, повторяющееся поведение\n'
          '- Глитчевые паттерны движения\n'
          '- Мем-стайл действия\n'
          '- Утрированный голос персонажа',
      'default':
          '🎭 ВАРИАЦИЯ: Стандартный увлекательный стиль\n'
          '- Прямые и чёткие сообщения\n'
          '- Близкий контент\n'
          '- Естественное повествование\n'
          '- Стандартный вирусный формат',
    },
    'uz': {
      'comedy':
          "🎭 VARIATSIYA: Komediya uslubi\n"
          "- So'z o'yinlari, qofiyalar, hazillardan keng foydalanish\n"
          "- Mubolag'ali reaksiyalar va kulgili momentlar\n"
          "- Auditoriyani hayron qoldiruvchi kutilmagan burilishlar\n"
          "- Odamlarni baland ovozda kuldirib yuborish",
      'dramatic':
          "🎭 VARIATSIYA: Dramatik/Suspens uslubi\n"
          "- Boshidanoq asta-sekin taranggullik qurib borish\n"
          "- Klikhenger momentlarini kiritish\n"
          "- Davomida hissiy intensivlik\n"
          "- Qiziqarli narrativ yoy",
      'romantic':
          "🎭 VARIATSIYA: Romantik/Hissiy uslub\n"
          "- Yurakni isituvchi momentlar\n"
          "- Muhabbat va bog'liqlik mavzulari\n"
          "- Hissiy hikoya qilish\n"
          "- Teginuvchi va tanish sahnalar",
      'school':
          "🎭 VARIATSIYA: Maktab/Ta'lim uslubi\n"
          "- O'quvchi va o'qituvchi o'zaro ta'siri\n"
          "- Maktab muhiti stsenariylari\n"
          "- O'rganish momentlari\n"
          "- O'quvchilarga yaqin tajribalar",
      'npc':
          "🎭 VARIATSIYA: NPC/O'yin qahramoni uslubi\n"
          "- Robotsimon, takrorlovchi xulq-atvor\n"
          "- Glitch harakatlanish naqshlari\n"
          "- Mem uslubidagi harakatlar\n"
          "- Mubolag'ali qahramon ovozi",
      'default':
          "🎭 VARIATSIYA: Standart qiziqarli uslub\n"
          "- To'g'ridan-to'g'ri va aniq xabarlar\n"
          "- Tanish kontent\n"
          "- Tabiiy hikoya qilish\n"
          "- Standart viral format",
    },
    'ar': {
      'comedy':
          '🎭 التنوع: أسلوب كوميدي/فكاهي\n'
          '- استخدام مكثف للعب الألفاظ والتورية والنكات\n'
          '- ردود فعل مبالغ فيها ولحظات مضحكة\n'
          '- مفاجآت غير متوقعة تدهش الجمهور\n'
          '- جعل الناس يضحكون بصوت عالٍ',
      'dramatic':
          '🎭 التنوع: أسلوب درامي/مشوق\n'
          '- بناء التوتر تدريجياً من البداية\n'
          '- تضمين لحظات مثيرة للشوق\n'
          '- كثافة عاطفية طوال المقطع\n'
          '- قوس سردي مثير',
      'romantic':
          '🎭 التنوع: أسلوب رومانسي/عاطفي\n'
          '- لحظات تدفئ القلب\n'
          '- موضوعات الحب والتواصل\n'
          '- سرد قصصي عاطفي\n'
          '- مشاهد مؤثرة وقريبة من القلب',
      'school':
          '🎭 التنوع: أسلوب مدرسي/تعليمي\n'
          '- تفاعلات الطلاب والمعلمين\n'
          '- سيناريوهات البيئة المدرسية\n'
          '- لحظات التعلم\n'
          '- تجارب الطلاب المألوفة',
      'npc':
          '🎭 التنوع: أسلوب شخصية NPC/الألعاب\n'
          '- سلوكيات آلية ومتكررة\n'
          '- أنماط حركة متقطعة\n'
          '- أفعال بأسلوب الميمز\n'
          '- صوت شخصية مبالغ فيه',
      'default':
          '🎭 التنوع: أسلوب جذاب قياسي\n'
          '- رسائل مباشرة وواضحة\n'
          '- محتوى قريب من الجمهور\n'
          '- سرد قصصي طبيعي\n'
          '- تنسيق فيروسي قياسي',
    },
    'de': {
      'comedy':
          '🎭 VARIATION: Komödien-/Humor-Stil\n'
          '- Starke Nutzung von Wortspielen, Witzen\n'
          '- Übertriebene Reaktionen und lustige Momente\n'
          '- Unerwartete Wendungen, die das Publikum überraschen\n'
          '- Menschen zum Lachen bringen',
      'dramatic':
          '🎭 VARIATION: Dramatischer/Spannungsgeladener Stil\n'
          '- Spannung von Anfang an graduell aufbauen\n'
          '- Cliffhanger-Momente einbeziehen\n'
          '- Emotionale Intensität durchgehend\n'
          '- Fesselnder Narrativbogen',
      'romantic':
          '🎭 VARIATION: Romantischer/Emotionaler Stil\n'
          '- Herzerwärmende Momente\n'
          '- Liebe und Verbindungs-Themen\n'
          '- Emotionales Geschichtenerzählen\n'
          '- Berührende und nachvollziehbare Szenen',
      'school':
          '🎭 VARIATION: Schul-/Bildungsstil\n'
          '- Schüler-Lehrer-Interaktionen\n'
          '- Schulumgebungsszenarien\n'
          '- Lernmomente\n'
          '- Nachvollziehbare Schülererfahrungen',
      'npc':
          '🎭 VARIATION: NPC-/Spielcharakter-Stil\n'
          '- Roboterhafte, repetitive Verhaltensweisen\n'
          '- Glitchy Bewegungsmuster\n'
          '- Meme-artige Aktionen\n'
          '- Übertriebene Charakterstimme',
      'default':
          '🎭 VARIATION: Standard Engagierender Stil\n'
          '- Direkte und klare Botschaften\n'
          '- Nachvollziehbarer Inhalt\n'
          '- Natürliches Geschichtenerzählen\n'
          '- Standard virales Format',
    },
    'es': {
      'comedy':
          '🎭 VARIACIÓN: Estilo Comedia/Humor\n'
          '- Uso intensivo de juegos de palabras, chistes\n'
          '- Reacciones exageradas y momentos divertidos\n'
          '- Giros inesperados que sorprendan al público\n'
          '- Hacer que la gente se ría a carcajadas',
      'dramatic':
          '🎭 VARIACIÓN: Estilo Dramático/Suspenso\n'
          '- Construir tensión gradualmente desde el inicio\n'
          '- Incluir momentos de clímax\n'
          '- Intensidad emocional a lo largo\n'
          '- Arco narrativo apasionante',
      'romantic':
          '🎭 VARIACIÓN: Estilo Romántico/Emocional\n'
          '- Momentos que calientan el corazón\n'
          '- Temas de amor y conexión\n'
          '- Narrativa emocional\n'
          '- Escenas conmovedoras y cercanas',
      'school':
          '🎭 VARIACIÓN: Estilo Escolar/Educativo\n'
          '- Interacciones entre estudiantes y profesores\n'
          '- Escenarios en entorno escolar\n'
          '- Momentos de aprendizaje\n'
          '- Experiencias identificables de estudiantes',
      'npc':
          '🎭 VARIACIÓN: Estilo Personaje NPC/Videojuego\n'
          '- Comportamientos robóticos y repetitivos\n'
          '- Patrones de movimiento con glitches\n'
          '- Acciones estilo meme\n'
          '- Voz de personaje exagerada',
      'default':
          '🎭 VARIACIÓN: Estilo Atractivo Estándar\n'
          '- Mensajes directos y claros\n'
          '- Contenido cercano al público\n'
          '- Narrativa natural\n'
          '- Formato viral estándar',
    },
    'fr': {
      'comedy':
          '🎭 VARIATION : Style Comédie/Humour\n'
          '- Utilisation intensive des jeux de mots, calembours, blagues\n'
          '- Réactions exagérées et moments drôles\n'
          '- Rebondissements inattendus qui surprennent\n'
          '- Faire rire le public aux éclats',
      'dramatic':
          '🎭 VARIATION : Style Dramatique/Suspense\n'
          '- Construire la tension graduellement depuis le début\n'
          '- Inclure des moments de cliffhanger\n'
          '- Intensité émotionnelle tout au long\n'
          '- Arc narratif captivant',
      'romantic':
          '🎭 VARIATION : Style Romantique/Émotionnel\n'
          '- Moments qui réchauffent le cœur\n'
          '- Thèmes d\'amour et de connexion\n'
          '- Narration émotionnelle\n'
          '- Scènes touchantes et attachantes',
      'school':
          '🎭 VARIATION : Style Scolaire/Éducatif\n'
          '- Interactions élèves-professeurs\n'
          '- Scénarios en milieu scolaire\n'
          '- Moments d\'apprentissage\n'
          '- Expériences d\'élèves identifiables',
      'npc':
          '🎭 VARIATION : Style Personnage NPC/Jeu\n'
          '- Comportements robotiques et répétitifs\n'
          '- Patterns de mouvement glitchés\n'
          '- Actions style mème\n'
          '- Voix de personnage exagérée',
      'default':
          '🎭 VARIATION : Style Engageant Standard\n'
          '- Messages directs et clairs\n'
          '- Contenu accessible\n'
          '- Narration naturelle\n'
          '- Format viral standard',
    },
    'hi': {
      'comedy':
          '🎭 Variation: Comedy/Humor Style\n'
          '- Word play, puns, jokes ka zyada use\n'
          '- Exaggerated reactions aur funny moments\n'
          '- Unexpected twists jo audience ko surprise karein\n'
          '- Logon ko zor se hasaaye',
      'dramatic':
          '🎭 Variation: Dramatic/Suspense Style\n'
          '- Shuru se dheere-dheere tension build karein\n'
          '- Cliffhanger moments include karein\n'
          '- Poore mein emotional intensity\n'
          '- Gripping narrative arc',
      'romantic':
          '🎭 Variation: Romantic/Emotional Style\n'
          '- Dil ko chhoo lene wale moments\n'
          '- Pyaar aur connection ke themes\n'
          '- Emotional storytelling\n'
          '- Touching aur relatable scenes',
      'school':
          '🎭 Variation: School/Educational Style\n'
          '- Student aur teacher interactions\n'
          '- School setting scenarios\n'
          '- Learning moments\n'
          '- Relatable student experiences',
      'npc':
          '🎭 Variation: NPC/Game Character Style\n'
          '- Robotic, repetitive behaviors\n'
          '- Glitchy movement patterns\n'
          '- Meme-style actions\n'
          '- Over-the-top character voice',
      'default':
          '🎭 Variation: Standard Engaging Style\n'
          '- Direct aur clear messaging\n'
          '- Relatable content\n'
          '- Natural storytelling\n'
          '- Standard viral format',
    },
    'id': {
      'comedy':
          '🎭 VARIASI: Gaya Komedi/Humor\n'
          '- Banyak menggunakan permainan kata, plesetan, lelucon\n'
          '- Reaksi berlebihan dan momen lucu\n'
          '- Kejutan yang mengejutkan penonton\n'
          '- Membuat orang tertawa terbahak-bahak',
      'dramatic':
          '🎭 VARIASI: Gaya Dramatis/Suspense\n'
          '- Membangun ketegangan secara bertahap dari awal\n'
          '- Momen cliffhanger\n'
          '- Intensitas emosional sepanjang video\n'
          '- Busur narasi yang memikat',
      'romantic':
          '🎭 VARIASI: Gaya Romantis/Emosional\n'
          '- Momen yang menghangatkan hati\n'
          '- Tema cinta dan koneksi\n'
          '- Cerita emosional\n'
          '- Adegan yang menyentuh dan relatable',
      'school':
          '🎭 VARIASI: Gaya Sekolah/Pendidikan\n'
          '- Interaksi siswa dan guru\n'
          '- Skenario lingkungan sekolah\n'
          '- Momen belajar\n'
          '- Pengalaman siswa yang relatable',
      'npc':
          '🎭 VARIASI: Gaya Karakter NPC/Game\n'
          '- Perilaku robotik dan repetitif\n'
          '- Pola gerakan glitchy\n'
          '- Aksi gaya meme\n'
          '- Suara karakter yang berlebihan',
      'default':
          '🎭 VARIASI: Gaya Menarik Standar\n'
          '- Pesan langsung dan jelas\n'
          '- Konten yang relatable\n'
          '- Cerita yang natural\n'
          '- Format viral standar',
    },
    'ms': {
      'comedy':
          '🎭 VARIASI: Gaya Komedi/Humor\n'
          '- Banyak menggunakan permainan kata, jenaka\n'
          '- Reaksi berlebihan dan momen lucu\n'
          '- Kejutan yang mengejutkan penonton\n'
          '- Menjadikan orang ketawa terbahak-bahak',
      'dramatic':
          '🎭 VARIASI: Gaya Dramatik/Suspense\n'
          '- Bina ketegangan secara beransur-ansur dari awal\n'
          '- Momen cliffhanger\n'
          '- Intensiti emosi sepanjang video\n'
          '- Busur naratif yang memikat',
      'romantic':
          '🎭 VARIASI: Gaya Romantik/Emosional\n'
          '- Momen yang menghangatkan hati\n'
          '- Tema cinta dan hubungan\n'
          '- Penceritaan emosional\n'
          '- Adegan yang menyentuh dan relatable',
      'school':
          '🎭 VARIASI: Gaya Sekolah/Pendidikan\n'
          '- Interaksi pelajar dan guru\n'
          '- Senario persekitaran sekolah\n'
          '- Momen pembelajaran\n'
          '- Pengalaman pelajar yang relatable',
      'npc':
          '🎭 VARIASI: Gaya Watak NPC/Permainan\n'
          '- Tingkah laku robotik dan berulang\n'
          '- Corak pergerakan glitchy\n'
          '- Aksi gaya meme\n'
          '- Suara watak yang berlebihan',
      'default':
          '🎭 VARIASI: Gaya Menarik Standard\n'
          '- Mesej langsung dan jelas\n'
          '- Kandungan yang relatable\n'
          '- Penceritaan yang semula jadi\n'
          '- Format viral standard',
    },
    'pt': {
      'comedy':
          '🎭 VARIAÇÃO: Estilo Comédia/Humor\n'
          '- Uso intensivo de jogos de palavras, piadas\n'
          '- Reações exageradas e momentos engraçados\n'
          '- Reviravoltas inesperadas que surpreendem\n'
          '- Fazer as pessoas rir alto',
      'dramatic':
          '🎭 VARIAÇÃO: Estilo Dramático/Suspense\n'
          '- Construir tensão gradualmente desde o início\n'
          '- Incluir momentos de cliffhanger\n'
          '- Intensidade emocional ao longo\n'
          '- Arco narrativo envolvente',
      'romantic':
          '🎭 VARIAÇÃO: Estilo Romântico/Emocional\n'
          '- Momentos que aquecem o coração\n'
          '- Temas de amor e conexão\n'
          '- Narrativa emocional\n'
          '- Cenas tocantes e identificáveis',
      'school':
          '🎭 VARIAÇÃO: Estilo Escolar/Educativo\n'
          '- Interações entre alunos e professores\n'
          '- Cenários em ambiente escolar\n'
          '- Momentos de aprendizagem\n'
          '- Experiências identificáveis de alunos',
      'npc':
          '🎭 VARIAÇÃO: Estilo Personagem NPC/Jogo\n'
          '- Comportamentos robóticos e repetitivos\n'
          '- Padrões de movimento com glitch\n'
          '- Ações estilo meme\n'
          '- Voz de personagem exagerada',
      'default':
          '🎭 VARIAÇÃO: Estilo Envolvente Padrão\n'
          '- Mensagens diretas e claras\n'
          '- Conteúdo próximo do público\n'
          '- Narrativa natural\n'
          '- Formato viral padrão',
    },
    'vi': {
      'comedy':
          '🎭 BIẾN THỂ: Phong cách Hài hước/Vui vẻ\n'
          '- Sử dụng nhiều chơi chữ, câu đùa, trò hề\n'
          '- Phản ứng phóng đại và những khoảnh khắc buồn cười\n'
          '- Những bước ngoặt bất ngờ làm khán giả ngạc nhiên\n'
          '- Làm mọi người cười lớn',
      'dramatic':
          '🎭 BIẾN THỂ: Phong cách Kịch tính/Hồi hộp\n'
          '- Tạo căng thẳng dần dần từ đầu\n'
          '- Bao gồm những khoảnh khắc cliff-hanger\n'
          '- Cường độ cảm xúc xuyên suốt\n'
          '- Cung truyện kể cuốn hút',
      'romantic':
          '🎭 BIẾN THỂ: Phong cách Lãng mạn/Cảm xúc\n'
          '- Những khoảnh khắc ấm lòng\n'
          '- Chủ đề tình yêu và kết nối\n'
          '- Kể chuyện cảm xúc\n'
          '- Những cảnh chạm đến lòng người',
      'school':
          '🎭 BIẾN THỂ: Phong cách Trường học/Giáo dục\n'
          '- Tương tác giữa học sinh và giáo viên\n'
          '- Kịch bản môi trường học đường\n'
          '- Những khoảnh khắc học tập\n'
          '- Trải nghiệm học sinh gần gũi',
      'npc':
          '🎭 BIẾN THỂ: Phong cách Nhân vật NPC/Game\n'
          '- Hành vi máy móc, lặp đi lặp lại\n'
          '- Chuyển động bị lỗi\n'
          '- Hành động kiểu meme\n'
          '- Giọng nhân vật phóng đại',
      'default':
          '🎭 BIẾN THỂ: Phong cách Hấp dẫn Tiêu chuẩn\n'
          '- Thông điệp trực tiếp và rõ ràng\n'
          '- Nội dung gần gũi\n'
          '- Kể chuyện tự nhiên\n'
          '- Định dạng viral tiêu chuẩn',
    },
  };

  static const Map<String, Map<String, String>> _emotionGuides = {
    'en': {
      'funny':
          '😄 EMOTION: Funny/Humorous Tone\n'
          '- Light-hearted energy throughout\n'
          '- Joyful and playful\n'
          '- Laugh-inducing content\n'
          '- Positive, entertaining delivery',
      'panic':
          '😰 EMOTION: Panic/Urgent Tone\n'
          '- Create FOMO (fear of missing out)\n'
          '- High energy, fast-paced\n'
          '- Urgent, intense delivery\n'
          '- Action-compelling messaging',
      'calm':
          '😌 EMOTION: Calm/Serene Tone\n'
          '- Soothing and meditative\n'
          '- Peaceful energy\n'
          '- Relaxing delivery\n'
          '- Zen-like contentment',
      'overacting':
          '🎬 EMOTION: Overacting/Dramatic Tone\n'
          '- Exaggerated emotions\n'
          '- Over-the-top delivery\n'
          '- Theatrical expressions\n'
          '- Hyperbolized reactions',
      'cinematic':
          '🎥 EMOTION: Cinematic/Epic Tone\n'
          '- Movie-trailer style energy\n'
          '- Grand, impressive feeling\n'
          '- Epic production quality sense\n'
          '- Premium, high-impact messaging',
      'neutral':
          '➡️ EMOTION: Neutral/Professional Tone\n'
          '- Balanced delivery\n'
          '- Professional and clear\n'
          '- Factual presentation\n'
          '- Straightforward messaging',
    },
    'ru': {
      'funny':
          '😄 ЭМОЦИЯ: Весёлый/Юмористический тон\n'
          '- Лёгкая энергия на протяжении всего\n'
          '- Радостно и игриво\n'
          '- Контент, вызывающий смех\n'
          '- Позитивная, развлекательная подача',
      'panic':
          '😰 ЭМОЦИЯ: Паника/Срочный тон\n'
          '- Создать FOMO (страх упустить)\n'
          '- Высокая энергия, быстрый темп\n'
          '- Срочная, интенсивная подача\n'
          '- Сообщения, побуждающие к действию',
      'calm':
          '😌 ЭМОЦИЯ: Спокойный/Умиротворённый тон\n'
          '- Успокаивающий и медитативный\n'
          '- Умиротворённая энергия\n'
          '- Расслабляющая подача\n'
          '- Дзен-подобное удовлетворение',
      'overacting':
          '🎬 ЭМОЦИЯ: Переигрывание/Драматический тон\n'
          '- Преувеличенные эмоции\n'
          '- Чрезмерная подача\n'
          '- Театральные выражения\n'
          '- Гиперболизированные реакции',
      'cinematic':
          '🎥 ЭМОЦИЯ: Кинематографический/Эпический тон\n'
          '- Энергия в стиле трейлера\n'
          '- Грандиозное, впечатляющее ощущение\n'
          '- Ощущение эпического качества производства\n'
          '- Премиум, высокоэффективные сообщения',
      'neutral':
          '➡️ ЭМОЦИЯ: Нейтральный/Профессиональный тон\n'
          '- Сбалансированная подача\n'
          '- Профессионально и чётко\n'
          '- Фактическая презентация\n'
          '- Прямые сообщения',
    },
    'uz': {
      'funny':
          "😄 HIS: Kulgili/Hazilomuz ohang\n"
          "- Davomida yengil energiya\n"
          "- Quvnoq va o'yinbop\n"
          "- Kulgi qo'zg'atuvchi kontent\n"
          "- Ijobiy, ko'ngilochar taqdimot",
      'panic':
          "😰 HIS: Vahima/Shoshilinch ohang\n"
          "- FOMO (o'tkazib yuborish qo'rquvi) yaratish\n"
          "- Yuqori energiya, tez sur'at\n"
          "- Shoshilinch, kuchli taqdimot\n"
          "- Harakat qilishga undovchi xabarlar",
      'calm':
          "😌 HIS: Tinch/Xotirjam ohang\n"
          "- Tinchlantiruivchi va meditativ\n"
          "- Osoyishta energiya\n"
          "- Rivojlantiruivchi taqdimot\n"
          "- Zen-ga o'xshash qoniqish",
      'overacting':
          "🎬 HIS: Haddan tashqari/Dramatik ohang\n"
          "- Mubolag'ali his-tuyg'ular\n"
          "- Haddan tashqari taqdimot\n"
          "- Teatral iboralar\n"
          "- Giperbola reaktsiyalar",
      'cinematic':
          "🎥 HIS: Kinematografik/Epik ohang\n"
          "- Film treyleri uslubidagi energiya\n"
          "- Ulug'vor, hayratlanarli his\n"
          "- Epik ishlab chiqarish sifati hissi\n"
          "- Premium, yuqori ta'sirchan xabarlar",
      'neutral':
          "➡️ HIS: Neytral/Professional ohang\n"
          "- Muvozanatli taqdimot\n"
          "- Professional va aniq\n"
          "- Faktik taqdimot\n"
          "- To'g'ridan-to'g'ri xabarlar",
    },
    'ar': {
      'funny':
          '😄 العاطفة: نبرة مضحكة/فكاهية\n'
          '- طاقة خفيفة طوال المقطع\n'
          '- مبهج ومرح\n'
          '- محتوى يثير الضحك\n'
          '- تقديم إيجابي وترفيهي',
      'panic':
          '😰 العاطفة: نبرة ذعر/عاجلة\n'
          '- إنشاء FOMO (الخوف من التفويت)\n'
          '- طاقة عالية، وتيرة سريعة\n'
          '- تقديم عاجل ومكثف\n'
          '- رسائل تدفع للعمل',
      'calm':
          '😌 العاطفة: نبرة هادئة/رزينة\n'
          '- مهدئ وتأملي\n'
          '- طاقة سلمية\n'
          '- تقديم مريح\n'
          '- رضا شبيه بالزن',
      'overacting':
          '🎬 العاطفة: نبرة مبالغة/دراماتيكية\n'
          '- عواطف مبالغ فيها\n'
          '- تقديم مفرط\n'
          '- تعابير مسرحية\n'
          '- ردود فعل مبالغ فيها',
      'cinematic':
          '🎥 العاطفة: نبرة سينمائية/ملحمية\n'
          '- طاقة بأسلوب إعلانات الأفلام\n'
          '- إحساس رائع ومثير للإعجاب\n'
          '- إحساس بجودة إنتاج ملحمية\n'
          '- رسائل متميزة وعالية التأثير',
      'neutral':
          '➡️ العاطفة: نبرة محايدة/احترافية\n'
          '- تقديم متوازن\n'
          '- احترافي وواضح\n'
          '- عرض حقائقي\n'
          '- رسائل مباشرة',
    },
    'de': {
      'funny':
          '😄 EMOTION: Lustiger/Humorvoller Ton\n'
          '- Leichte Energie durchgehend\n'
          '- Freudig und verspielt\n'
          '- Zum Lachen anregender Inhalt\n'
          '- Positive, unterhaltsame Darbietung',
      'panic':
          '😰 EMOTION: Panik-/Dringlichkeitston\n'
          '- FOMO erzeugen (Angst, etwas zu verpassen)\n'
          '- Hohe Energie, schnelles Tempo\n'
          '- Dringende, intensive Darbietung\n'
          '- Zum Handeln auffordernde Botschaften',
      'calm':
          '😌 EMOTION: Ruhiger/Gelassener Ton\n'
          '- Beruhigend und meditativ\n'
          '- Friedliche Energie\n'
          '- Entspannende Darbietung\n'
          '- Zen-artiger Zufriedenheit',
      'overacting':
          '🎬 EMOTION: Übertriebener/Dramatischer Ton\n'
          '- Übertriebene Emotionen\n'
          '- Excessive Darbietung\n'
          '- Theatralische Ausdrücke\n'
          '- Hyperbolisierte Reaktionen',
      'cinematic':
          '🎥 EMOTION: Cineastischer/Epischer Ton\n'
          '- Filmtrailer-artige Energie\n'
          '- Grandioser, beeindruckender Eindruck\n'
          '- Gefühl epischer Produktionsqualität\n'
          '- Premium, wirkungsstarke Botschaften',
      'neutral':
          '➡️ EMOTION: Neutraler/Professioneller Ton\n'
          '- Ausgeglichene Darbietung\n'
          '- Professionell und klar\n'
          '- Sachliche Präsentation\n'
          '- Direkte Botschaften',
    },
    'es': {
      'funny':
          '😄 EMOCIÓN: Tono Divertido/Humorístico\n'
          '- Energía desenfadada en todo momento\n'
          '- Alegre y juguetón\n'
          '- Contenido que provoca risas\n'
          '- Presentación positiva y entretenida',
      'panic':
          '😰 EMOCIÓN: Tono de Pánico/Urgencia\n'
          '- Crear FOMO (miedo a perderse algo)\n'
          '- Alta energía, ritmo rápido\n'
          '- Presentación urgente e intensa\n'
          '- Mensajes que impulsan a la acción',
      'calm':
          '😌 EMOCIÓN: Tono Calmado/Sereno\n'
          '- Relajante y meditativo\n'
          '- Energía tranquila\n'
          '- Presentación relajada\n'
          '- Satisfacción tipo zen',
      'overacting':
          '🎬 EMOCIÓN: Tono de Sobreactuación/Dramático\n'
          '- Emociones exageradas\n'
          '- Presentación exagerada\n'
          '- Expresiones teatrales\n'
          '- Reacciones hiperbólicas',
      'cinematic':
          '🎥 EMOCIÓN: Tono Cinematográfico/Épico\n'
          '- Energía estilo tráiler de película\n'
          '- Sensación grandiosa e impresionante\n'
          '- Calidad de producción épica\n'
          '- Mensajes premium de alto impacto',
      'neutral':
          '➡️ EMOCIÓN: Tono Neutro/Profesional\n'
          '- Presentación equilibrada\n'
          '- Profesional y claro\n'
          '- Presentación factual\n'
          '- Mensajes directos',
    },
    'fr': {
      'funny':
          '😄 ÉMOTION : Ton Drôle/Humoristique\n'
          '- Énergie légère tout au long\n'
          '- Joyeux et enjoué\n'
          '- Contenu qui provoque le rire\n'
          '- Présentation positive et divertissante',
      'panic':
          '😰 ÉMOTION : Ton Panique/Urgent\n'
          '- Créer du FOMO (peur de rater quelque chose)\n'
          '- Haute énergie, rythme rapide\n'
          '- Présentation urgente et intense\n'
          '- Messages qui poussent à l\'action',
      'calm':
          '😌 ÉMOTION : Ton Calme/Serein\n'
          '- Apaisant et méditatif\n'
          '- Énergie paisible\n'
          '- Présentation relaxante\n'
          '- Sérénité zen',
      'overacting':
          '🎬 ÉMOTION : Ton Surjoué/Dramatique\n'
          '- Émotions exagérées\n'
          '- Présentation excessive\n'
          '- Expressions théâtrales\n'
          '- Réactions hyperboliques',
      'cinematic':
          '🎥 ÉMOTION : Ton Cinématographique/Épique\n'
          '- Énergie style bande-annonce\n'
          '- Sensation grandiose et impressionnante\n'
          '- Qualité de production épique\n'
          '- Messages premium à fort impact',
      'neutral':
          '➡️ ÉMOTION : Ton Neutre/Professionnel\n'
          '- Présentation équilibrée\n'
          '- Professionnel et clair\n'
          '- Présentation factuelle\n'
          '- Messages directs',
    },
    'hi': {
      'funny':
          '😄 Bhavna: Funny/Humorous Tone\n'
          '- Poore mein light-hearted energy\n'
          '- Khush aur playful vibe\n'
          '- Hasaane wala content\n'
          '- Positive, entertaining delivery',
      'panic':
          '😰 Bhavna: Panic/Urgent Tone\n'
          '- FOMO (fear of missing out) create karo\n'
          '- High energy, fast-paced\n'
          '- Urgent, intense delivery\n'
          '- Action lene par majboor kare',
      'calm':
          '😌 Bhavna: Calm/Serene Tone\n'
          '- Soothing aur meditative\n'
          '- Shaant aur peaceful energy\n'
          '- Relaxing delivery\n'
          '- Zen jaisi sukoon wali feeling',
      'overacting':
          '🎬 Bhavna: Overacting/Dramatic Tone\n'
          '- Exaggerated emotions\n'
          '- Over-the-top delivery\n'
          '- Theatrical expressions\n'
          '- Hyperbolized reactions',
      'cinematic':
          '🎥 Bhavna: Cinematic/Epic Tone\n'
          '- Movie-trailer jaisi energy\n'
          '- Grand aur impressive feel\n'
          '- Epic production wali vibe\n'
          '- Premium, high-impact messaging',
      'neutral':
          '➡️ Bhavna: Neutral/Professional Tone\n'
          '- Balanced delivery\n'
          '- Professional aur clear\n'
          '- Factual presentation\n'
          '- Seedha aur straightforward messaging',
    },
    'id': {
      'funny':
          '😄 EMOSI: Nada Lucu/Humoris\n'
          '- Energi ringan sepanjang video\n'
          '- Gembira dan playful\n'
          '- Konten yang memancing tawa\n'
          '- Penyampaian positif dan menghibur',
      'panic':
          '😰 EMOSI: Nada Panik/Mendesak\n'
          '- Ciptakan FOMO (takut ketinggalan)\n'
          '- Energi tinggi, tempo cepat\n'
          '- Penyampaian mendesak dan intens\n'
          '- Pesan yang mendorong tindakan',
      'calm':
          '😌 EMOSI: Nada Tenang/Damai\n'
          '- Menenangkan dan meditatif\n'
          '- Energi yang damai\n'
          '- Penyampaian yang santai\n'
          '- Kepuasan seperti zen',
      'overacting':
          '🎬 EMOSI: Nada Berlebihan/Dramatis\n'
          '- Emosi yang dilebih-lebihkan\n'
          '- Penyampaian berlebihan\n'
          '- Ekspresi teatrikal\n'
          '- Reaksi yang hiperbolis',
      'cinematic':
          '🎥 EMOSI: Nada Sinematik/Epik\n'
          '- Energi gaya trailer film\n'
          '- Perasaan megah dan mengesankan\n'
          '- Kualitas produksi epik\n'
          '- Pesan premium berdampak tinggi',
      'neutral':
          '➡️ EMOSI: Nada Netral/Profesional\n'
          '- Penyampaian yang seimbang\n'
          '- Profesional dan jelas\n'
          '- Presentasi faktual\n'
          '- Pesan yang lugas',
    },
    'ms': {
      'funny':
          '😄 EMOSI: Nada Lucu/Humoris\n'
          '- Tenaga ringan sepanjang video\n'
          '- Gembira dan playful\n'
          '- Kandungan yang memancing ketawa\n'
          '- Penyampaian positif dan menghiburkan',
      'panic':
          '😰 EMOSI: Nada Panik/Mendesak\n'
          '- Cipta FOMO (takut ketinggalan)\n'
          '- Tenaga tinggi, tempo cepat\n'
          '- Penyampaian mendesak dan intens\n'
          '- Mesej yang mendorong tindakan',
      'calm':
          '😌 EMOSI: Nada Tenang/Damai\n'
          '- Menenangkan dan meditatif\n'
          '- Tenaga yang aman\n'
          '- Penyampaian yang santai\n'
          '- Kepuasan seperti zen',
      'overacting':
          '🎬 EMOSI: Nada Berlebihan/Dramatik\n'
          '- Emosi yang dilebih-lebihkan\n'
          '- Penyampaian berlebihan\n'
          '- Ekspresi teatrikal\n'
          '- Reaksi yang hiperbola',
      'cinematic':
          '🎥 EMOSI: Nada Sinematik/Epik\n'
          '- Tenaga gaya treler filem\n'
          '- Perasaan megah dan mengesankan\n'
          '- Kualiti produksi epik\n'
          '- Mesej premium berimpak tinggi',
      'neutral':
          '➡️ EMOSI: Nada Neutral/Profesional\n'
          '- Penyampaian yang seimbang\n'
          '- Profesional dan jelas\n'
          '- Pembentangan faktual\n'
          '- Mesej yang terus terang',
    },
    'pt': {
      'funny':
          '😄 EMOÇÃO: Tom Divertido/Humorístico\n'
          '- Energia descontraída em todo momento\n'
          '- Alegre e brincalhão\n'
          '- Conteúdo que provoca gargalhadas\n'
          '- Apresentação positiva e divertida',
      'panic':
          '😰 EMOÇÃO: Tom de Pânico/Urgência\n'
          '- Criar FOMO (medo de perder algo)\n'
          '- Alta energia, ritmo acelerado\n'
          '- Apresentação urgente e intensa\n'
          '- Mensagens que impulsionam a ação',
      'calm':
          '😌 EMOÇÃO: Tom Calmo/Sereno\n'
          '- Tranquilizador e meditativo\n'
          '- Energia pacífica\n'
          '- Apresentação relaxante\n'
          '- Satisfação zen',
      'overacting':
          '🎬 EMOÇÃO: Tom de Exagero/Dramático\n'
          '- Emoções exageradas\n'
          '- Apresentação excessiva\n'
          '- Expressões teatrais\n'
          '- Reações hiperbólicas',
      'cinematic':
          '🎥 EMOÇÃO: Tom Cinematográfico/Épico\n'
          '- Energia estilo trailer de filme\n'
          '- Sensação grandiosa e impressionante\n'
          '- Qualidade de produção épica\n'
          '- Mensagens premium de alto impacto',
      'neutral':
          '➡️ EMOÇÃO: Tom Neutro/Profissional\n'
          '- Apresentação equilibrada\n'
          '- Profissional e claro\n'
          '- Apresentação factual\n'
          '- Mensagens diretas',
    },
    'vi': {
      'funny':
          '😄 CẢM XÚC: Tông Vui vẻ/Hài hước\n'
          '- Năng lượng nhẹ nhàng xuyên suốt\n'
          '- Vui vẻ và tinh nghịch\n'
          '- Nội dung gây cười\n'
          '- Trình bày tích cực, giải trí',
      'panic':
          '😰 CẢM XÚC: Tông Hoảng loạn/Khẩn cấp\n'
          '- Tạo FOMO (sợ bỏ lỡ)\n'
          '- Năng lượng cao, nhịp độ nhanh\n'
          '- Trình bày khẩn cấp, mãnh liệt\n'
          '- Thông điệp thúc đẩy hành động',
      'calm':
          '😌 CẢM XÚC: Tông Bình tĩnh/Thanh thản\n'
          '- Êm dịu và thiền định\n'
          '- Năng lượng bình hòa\n'
          '- Trình bày thư giãn\n'
          '- Sự hài lòng kiểu thiền',
      'overacting':
          '🎬 CẢM XÚC: Tông Phóng đại/Kịch tính\n'
          '- Cảm xúc phóng đại\n'
          '- Trình bày quá mức\n'
          '- Biểu hiện kịch tính\n'
          '- Phản ứng cường điệu',
      'cinematic':
          '🎥 CẢM XÚC: Tông Điện ảnh/Hùng tráng\n'
          '- Năng lượng kiểu trailer phim\n'
          '- Cảm giác hoành tráng, ấn tượng\n'
          '- Chất lượng sản xuất sử thi\n'
          '- Thông điệp cao cấp, tác động mạnh',
      'neutral':
          '➡️ CẢM XÚC: Tông Trung lập/Chuyên nghiệp\n'
          '- Trình bày cân bằng\n'
          '- Chuyên nghiệp và rõ ràng\n'
          '- Trình bày khách quan\n'
          '- Thông điệp thẳng thắn',
    },
  };

  static const Map<String, Map<String, String>> _platformGuides = {
    'en': {
      'tiktok':
          '📱 PLATFORM: TikTok Format\n'
          '- Hook in first 2 seconds\n'
          '- Use trending sounds\n'
          '- Fast cuts and transitions\n'
          '- Stitches and duets compatible\n'
          '- Maximize watch time',
      'shorts':
          '📱 PLATFORM: YouTube Shorts Format\n'
          '- Searchable keywords in title\n'
          '- Thumbnail-worthy moments\n'
          '- Educational value\n'
          '- Discoverable content\n'
          '- High retention hooks',
      'reels':
          '📱 PLATFORM: Instagram Reels Format\n'
          '- Aesthetic and visually appealing\n'
          '- Shareable format\n'
          '- Story-driven narrative\n'
          '- Caption-integrated\n'
          '- Engagement-focused',
    },
    'ru': {
      'tiktok':
          '📱 ПЛАТФОРМА: Формат TikTok\n'
          '- Крюк в первые 2 секунды\n'
          '- Использовать трендовые звуки\n'
          '- Быстрые склейки и переходы\n'
          '- Совместимость со Stitch и Duet\n'
          '- Максимизировать время просмотра',
      'shorts':
          '📱 ПЛАТФОРМА: Формат YouTube Shorts\n'
          '- Поисковые ключевые слова в названии\n'
          '- Эффектные моменты для превью\n'
          '- Образовательная ценность\n'
          '- Обнаруживаемый контент\n'
          '- Высокие удержания',
      'reels':
          '📱 ПЛАТФОРМА: Формат Instagram Reels\n'
          '- Эстетичный и визуально привлекательный\n'
          '- Формат для распространения\n'
          '- Нарратив, основанный на истории\n'
          '- Интеграция с подписями\n'
          '- Фокус на вовлечённость',
    },
    'uz': {
      'tiktok':
          "📱 PLATFORMA: TikTok Formati\n"
          "- Birinchi 2 soniyada hook\n"
          "- Trend ovozlardan foydalanish\n"
          "- Tez kesimlar va o'tishlar\n"
          "- Stitch va Duet bilan moslik\n"
          "- Ko'rish vaqtini maksimallash",
      'shorts':
          "📱 PLATFORMA: YouTube Shorts Formati\n"
          "- Sarlavhada qidiruv kalit so'zlari\n"
          "- Thumbnail uchun yaxshi momentlar\n"
          "- Ta'limiy qiymat\n"
          "- Kashfetilishi mumkin kontent\n"
          "- Yuqori ushlab turish hooklari",
      'reels':
          "📱 PLATFORMA: Instagram Reels Formati\n"
          "- Estetik va vizual jozibador\n"
          "- Ulashish uchun format\n"
          "- Hikoyaga asoslangan narrativ\n"
          "- Sarlavha bilan integratsiya\n"
          "- Jalb etishga yo'naltirilgan",
    },
    'ar': {
      'tiktok':
          '📱 المنصة: تنسيق TikTok\n'
          '- الخطاف في أول 2 ثانية\n'
          '- استخدام الأصوات الرائجة\n'
          '- مقاطع وانتقالات سريعة\n'
          '- متوافق مع Stitch وDuet\n'
          '- تعظيم وقت المشاهدة',
      'shorts':
          '📱 المنصة: تنسيق YouTube Shorts\n'
          '- كلمات مفتاحية قابلة للبحث في العنوان\n'
          '- لحظات مناسبة للصورة المصغرة\n'
          '- قيمة تعليمية\n'
          '- محتوى قابل للاكتشاف\n'
          '- خطافات احتجاز عالية',
      'reels':
          '📱 المنصة: تنسيق Instagram Reels\n'
          '- جمالي وجذاب بصرياً\n'
          '- تنسيق قابل للمشاركة\n'
          '- سرد قائم على القصة\n'
          '- متكامل مع التعليق\n'
          '- مركّز على التفاعل',
    },
    'de': {
      'tiktok':
          '📱 PLATTFORM: TikTok-Format\n'
          '- Hook in den ersten 2 Sekunden\n'
          '- Trending Sounds verwenden\n'
          '- Schnelle Schnitte und Übergänge\n'
          '- Stitch und Duet kompatibel\n'
          '- Wiedergabezeit maximieren',
      'shorts':
          '📱 PLATTFORM: YouTube Shorts-Format\n'
          '- Durchsuchbare Keywords im Titel\n'
          '- Thumbnail-würdige Momente\n'
          '- Bildungswert\n'
          '- Entdeckbarer Inhalt\n'
          '- Hohe Retention-Hooks',
      'reels':
          '📱 PLATTFORM: Instagram Reels-Format\n'
          '- Ästhetisch und visuell ansprechend\n'
          '- Teilbares Format\n'
          '- Geschichtengetriebenes Narrativ\n'
          '- Caption-integriert\n'
          '- Engagement-fokussiert',
    },
    'es': {
      'tiktok':
          '📱 PLATAFORMA: Formato TikTok\n'
          '- Gancho en los primeros 2 segundos\n'
          '- Usar sonidos trending\n'
          '- Cortes y transiciones rápidas\n'
          '- Compatible con Stitch y Duet\n'
          '- Maximizar el tiempo de visualización',
      'shorts':
          '📱 PLATAFORMA: Formato YouTube Shorts\n'
          '- Palabras clave buscables en el título\n'
          '- Momentos dignos de miniatura\n'
          '- Valor educativo\n'
          '- Contenido descubrible\n'
          '- Ganchos de alta retención',
      'reels':
          '📱 PLATAFORMA: Formato Instagram Reels\n'
          '- Estético y visualmente atractivo\n'
          '- Formato compartible\n'
          '- Narrativa orientada a historias\n'
          '- Integrado con caption\n'
          '- Enfocado en engagement',
    },
    'fr': {
      'tiktok':
          '📱 PLATEFORME : Format TikTok\n'
          '- Accroche dans les 2 premières secondes\n'
          '- Utiliser des sons tendance\n'
          '- Coupes et transitions rapides\n'
          '- Compatible Stitch et Duet\n'
          '- Maximiser le temps de visionnage',
      'shorts':
          '📱 PLATEFORME : Format YouTube Shorts\n'
          '- Mots-clés recherchables dans le titre\n'
          '- Moments dignes de miniature\n'
          '- Valeur éducative\n'
          '- Contenu découvrable\n'
          '- Accroches à haute rétention',
      'reels':
          '📱 PLATEFORME : Format Instagram Reels\n'
          '- Esthétique et visuellement attrayant\n'
          '- Format partageable\n'
          '- Narration axée sur l\'histoire\n'
          '- Intégré aux légendes\n'
          '- Centré sur l\'engagement',
    },
    'hi': {
      'tiktok':
          '📱 PLATFORM: TikTok Format\n'
          '- पहले 2 सेकंड में Hook\n'
          '- Trending sounds का उपयोग\n'
          '- Fast cuts और transitions\n'
          '- Stitches और duets compatible\n'
          '- Watch time maximize करें',
      'shorts':
          '📱 PLATFORM: YouTube Shorts Format\n'
          '- Title में searchable keywords\n'
          '- Thumbnail-worthy moments\n'
          '- Educational value\n'
          '- Discoverable content\n'
          '- High retention hooks',
      'reels':
          '📱 PLATFORM: Instagram Reels Format\n'
          '- Aesthetic और visually appealing\n'
          '- Shareable format\n'
          '- Story-driven narrative\n'
          '- Caption-integrated\n'
          '- Engagement-focused',
    },
    'id': {
      'tiktok':
          '📱 PLATFORM: Format TikTok\n'
          '- Hook dalam 2 detik pertama\n'
          '- Gunakan suara trending\n'
          '- Potongan dan transisi cepat\n'
          '- Kompatibel dengan Stitch dan Duet\n'
          '- Maksimalkan waktu tonton',
      'shorts':
          '📱 PLATFORM: Format YouTube Shorts\n'
          '- Kata kunci yang dapat dicari di judul\n'
          '- Momen layak thumbnail\n'
          '- Nilai edukatif\n'
          '- Konten yang dapat ditemukan\n'
          '- Hook retensi tinggi',
      'reels':
          '📱 PLATFORM: Format Instagram Reels\n'
          '- Estetis dan menarik secara visual\n'
          '- Format yang dapat dibagikan\n'
          '- Narasi berbasis cerita\n'
          '- Terintegrasi dengan caption\n'
          '- Berfokus pada engagement',
    },
    'ms': {
      'tiktok':
          '📱 PLATFORM: Format TikTok\n'
          '- Hook dalam 2 saat pertama\n'
          '- Gunakan bunyi trending\n'
          '- Potongan dan peralihan pantas\n'
          '- Serasi dengan Stitch dan Duet\n'
          '- Maksimumkan masa tontonan',
      'shorts':
          '📱 PLATFORM: Format YouTube Shorts\n'
          '- Kata kunci boleh cari dalam tajuk\n'
          '- Momen layak thumbnail\n'
          '- Nilai pendidikan\n'
          '- Kandungan boleh ditemui\n'
          '- Hook pengekalan tinggi',
      'reels':
          '📱 PLATFORM: Format Instagram Reels\n'
          '- Estetik dan menarik secara visual\n'
          '- Format boleh dikongsi\n'
          '- Naratif berasaskan cerita\n'
          '- Bersepadu dengan caption\n'
          '- Fokus pada penglibatan',
    },
    'pt': {
      'tiktok':
          '📱 PLATAFORMA: Formato TikTok\n'
          '- Gancho nos primeiros 2 segundos\n'
          '- Usar sons em tendência\n'
          '- Cortes e transições rápidas\n'
          '- Compatível com Stitch e Duet\n'
          '- Maximizar o tempo de exibição',
      'shorts':
          '📱 PLATAFORMA: Formato YouTube Shorts\n'
          '- Palavras-chave pesquisáveis no título\n'
          '- Momentos dignos de miniatura\n'
          '- Valor educativo\n'
          '- Conteúdo descobrível\n'
          '- Ganchos de alta retenção',
      'reels':
          '📱 PLATAFORMA: Formato Instagram Reels\n'
          '- Estético e visualmente atraente\n'
          '- Formato compartilhável\n'
          '- Narrativa orientada a histórias\n'
          '- Integrado com legenda\n'
          '- Focado em engajamento',
    },
    'vi': {
      'tiktok':
          '📱 NỀN TẢNG: Định dạng TikTok\n'
          '- Hook trong 2 giây đầu\n'
          '- Sử dụng âm thanh trending\n'
          '- Cắt và chuyển cảnh nhanh\n'
          '- Tương thích với Stitch và Duet\n'
          '- Tối đa hóa thời gian xem',
      'shorts':
          '📱 NỀN TẢNG: Định dạng YouTube Shorts\n'
          '- Từ khóa có thể tìm kiếm trong tiêu đề\n'
          '- Những khoảnh khắc xứng đáng làm thumbnail\n'
          '- Giá trị giáo dục\n'
          '- Nội dung có thể khám phá\n'
          '- Hook giữ chân cao',
      'reels':
          '📱 NỀN TẢNG: Định dạng Instagram Reels\n'
          '- Thẩm mỹ và hấp dẫn về mặt hình ảnh\n'
          '- Định dạng có thể chia sẻ\n'
          '- Tường thuật dựa trên câu chuyện\n'
          '- Tích hợp caption\n'
          '- Tập trung vào engagement',
    },
  };

  String _getLengthGuide(String length, String language) {
    final lang = _resolvedLang(language);
    final guides = _lengthGuides[lang] ?? _lengthGuides['en']!;
    return guides[length] ?? guides['short']!;
  }

  String _getVariationGuide(String variation, String language) {
    final lang = _resolvedLang(language);
    final guides = _variationGuides[lang] ?? _variationGuides['en']!;
    return guides[variation] ?? guides['default']!;
  }

  String _getEmotionGuide(String emotion, String language) {
    final lang = _resolvedLang(language);
    final guides = _emotionGuides[lang] ?? _emotionGuides['en']!;
    return guides[emotion] ?? guides['neutral']!;
  }

  String _getPlatformGuide(String platform, String language) {
    final lang = _resolvedLang(language);
    final guides = _platformGuides[lang] ?? _platformGuides['en']!;
    return guides[platform] ?? guides['reels']!;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DEFAULT GENERATOR (FALLBACK)
// ─────────────────────────────────────────────────────────────────────────────

class DefaultPromptTemplate implements PromptTemplate {
  @override
  String get templateName => 'DefaultTemplate';

  @override
  String buildBasePrompt(PromptContext context) {
    return '''Generate creative content based on:

📝 Request:
${context.userPrompt}

🎯 Default Generator

Create content that:
- Is relevant to the request
- Is high quality and engaging
- Follows best practices${_buildLanguageEnforcement(context.language)}''';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UTILITY · TEMPLATE FACTORY
// ─────────────────────────────────────────────────────────────────────────────

/// Selects the correct template based on generator type string.
class PromptTemplateFactory {
  static PromptTemplate createTemplate(String generatorType) {
    return switch (generatorType.toLowerCase()) {
      'script' => ScriptGeneratorTemplate(),
      'comment' => CommentGeneratorTemplate(),
      'hashtag' => HashtagGeneratorTemplate(),
      'viral_rewrite' => ViralRewriteTemplate(),
      'shot_ideas' => ShotIdeasTemplate(),
      'refinement' => RefinementTemplate(),
      _ => DefaultPromptTemplate(),
    };
  }

  static List<String> getAvailableGenerators() => const [
    'script',
    'comment',
    'hashtag',
    'viral_rewrite',
    'shot_ideas',
    'refinement',
  ];
}
