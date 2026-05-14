/**
 * Backend Configuration & Remote Config Defaults
 * Source of Truth: FINAL MONETIZATION SPEC v1
 *
 * All limits are configurable via Firebase Remote Config
 * These are fallback defaults if Remote Config is unavailable
 */

module.exports = {
  // ════════════════════════════════════════════════════════════════
  // REGION TIER MAPPING (Anti-VPN: use lowest tier if mismatch)
  // ════════════════════════════════════════════════════════════════
  TIER_1_COUNTRIES: [
    // North America
    "US", "CA",
    // Oceania
    "AU", "NZ",
    // UK & Ireland
    "GB", "IE",
    // Western Europe
    "DE", "FR", "IT", "ES", "NL", "BE", "AT", "CH", "SE", "NO", "DK",
    // Southern Europe
    "PT", "GR",
    // Northern Europe
    "FI", "LU",
    // East Asia (Developed)
    "JP", "KR", "SG", "HK", "TW",
  ],
  TIER_2_COUNTRIES: [
    // LATAM
    "BR", "MX", "AR", "CL", "CO", "PE", "VE", "EC", "BO", "PY", "UY", "CR", "PA", "GT", "HN", "SV", "NI",
    // MENA
    "AE", "SA", "KW", "QA", "BH", "OM", "JO", "IL",
    // Eastern Europe & Balkans
    "TR", "PL", "CZ", "HU", "RO", "BG", "HR", "RS", "BA", "ME", "SK", "SI", "MD",
    // Caribbean
    "CU", "DO", "JM", "TT",
    // Central Asia (Developed)
    "KZ",
    // Additional Middle-Income
    "TH", "MY", "BN",
    // North Africa
    "EG", "MA", "TN", "DZ", "LY",
    // Middle East
    "LB", "SY", "IQ", "IR", "AF",
  ],
  TIER_3_COUNTRIES: [
    // South Asia
    "IN", "PK", "BD", "LK", "NP", "BT", "MV",
    // Southeast Asia
    "PH", "ID", "VN", "MM", "LA", "KH",
    // Sub-Saharan Africa
    "ZA", "NG", "KE", "GH", "ET", "TZ", "UG", "RW", "ZW", "MW", "ZM", "MZ",
    "BW", "NA", "SL", "LR", "CI", "SN", "GM", "GN", "CM", "GA", "CG", "CD",
    "AO", "MG", "SC", "DJ", "ER", "SO", "SD", "SS",
    // CIS (Former Soviet)
    "RU", "UA", "BY", "UZ", "TM", "KG", "TJ", "AM", "AZ", "GE",
    // Central America & Caribbean Low-Income
    "HT", "BZ",
    // Pacific Islands
    "PG", "FJ", "SB", "VU", "KI", "TO", "WS", "FM", "MH", "PW",
    // Other Low-Income Countries
    "YE", "PS", "LY", "MR", "WF", "RE", "MU", "KM",
  ],

  // ════════════════════════════════════════════════════════════════
  // AI OUTPUT TOKEN LIMITS (Max Response Length - Server-Side Enforced)
  // ════════════════════════════════════════════════════════════════
  TOKEN_LIMITS: {
    // ⚠️ IMPORTANT: These limits account for JSON structure overhead
    // The API will truncate at this token boundary, potentially mid-word
    // Higher limits = more complete JSON structures before truncation
    tier1_free: 1000, // Tier-1 non-PRO / rewarded (increased from 800)
    tier1_pro: 2000, // Tier-1 PRO users (increased from 1600)
    tier2: 800, // Tier-2 (rewarded only, increased from 600)
    tier3: 600, // Tier-3 (rewarded only, increased from 400)
  },

  // ════════════════════════════════════════════════════════════════
  // TRIAL LIMITS (One-Time Only per Device)
  // ════════════════════════════════════════════════════════════════
  TRIAL: {
    tier1: 2, // Tier-1: 2 free AI generations
    tier2: 1, // Tier-2: 1 free AI generation
    tier3: 0, // Tier-3: No trial
  },

  // ════════════════════════════════════════════════════════════════
  // DAILY AI GENERATION LIMITS (non-PRO Users)
  // ════════════════════════════════════════════════════════════════
  DAILY_AI_LIMITS: {
    tier1: 4, // Tier-1: 4 AI/day (rewarded only)
    tier2: 3, // Tier-2: 3 AI/day (rewarded only)
    tier3: 3, // Tier-3: 3 AI/day (rewarded only)
  },

  // ════════════════════════════════════════════════════════════════
  // REWARDED ADS LIMITS (non-PRO Users)
  // ════════════════════════════════════════════════════════════════
  REWARDED_ADS: {
    tier1: {
      max_per_day: 2, // Max 2 rewarded ads/day
      ai_per_reward: 2, // 1 ad = 2 AI generations
      immediate_consumption: false, // Can store unlocks
    },
    tier2: {
      max_per_day: 3, // Max 3 rewarded ads/day
      ai_per_reward: 1, // 1 ad = 1 AI generation
      immediate_consumption: false, // Can store unlocks
    },
    tier3: {
      max_per_day: 3, // Max 3 rewarded ads/day
      ai_per_reward: 1, // 1 ad = 1 AI generation (every gen requires ad)
      immediate_consumption: true, // MUST watch ad before EACH generation
    },
  },

  // ════════════════════════════════════════════════════════════════
  // PRO SUBSCRIPTION LIMITS (Tier-1 ONLY)
  // ════════════════════════════════════════════════════════════════
  PRO_LIMITS: {
    soft_cap_mini: 20, // Phase 1: 20 mini/day (premium model first)
    hard_cap_mini: 20, // Server hard cap: 20 mini/day
    soft_cap_nano: 80, // Phase 2: 80 nano/day (after mini exhausted)
    hard_cap_nano: 80, // Server hard cap: 80 nano/day
    // Total: 100 AI generations/day for PRO users
  },

  // ════════════════════════════════════════════════════════════════
  // CONTEXT & INPUT SIZE LIMITS (Cost Safety)
  // ════════════════════════════════════════════════════════════════
  CONTEXT_LIMITS: {
    max_context_messages: 10, // Last 10 messages in history
    max_user_input_chars: 2000, // Max 2000 chars per user input
  },

  // ════════════════════════════════════════════════════════════════
  // ABUSE DETECTION THRESHOLDS
  // ════════════════════════════════════════════════════════════════
  ABUSE_DETECTION: {
    high_frequency_window_minutes: 5, // Time window for frequency check
    high_frequency_threshold: 10, // Requests in 5 min = abuse
    high_similarity_threshold: 0.85, // Cosine similarity >= 0.85 = abuse
    session_duration_warning_minutes: 30, // Session > 30 min = watch
  },

  // ════════════════════════════════════════════════════════════════
  // ADMOB FAILSAFE MODE
  // ════════════════════════════════════════════════════════════════
  FAILSAFE: {
    fill_rate_threshold: 0.60, // If fill rate < 60% → disable ads
    fill_rate_check_window_minutes: 30, // Check over 30 min window
    disable_tier2_ads: true, // Disable Tier-2 ads in failsafe
    disable_tier3_ads: true, // Disable Tier-3 ads in failsafe
    keep_tier1_pro: true, // Tier-1 PRO unaffected
  },

  // ════════════════════════════════════════════════════════════════
  // FIRESTORE COLLECTION & FIELDS (Schema Validation)
  // ════════════════════════════════════════════════════════════════
  FIRESTORE: {
    USERS_COLLECTION: "users",
    REQUIRED_FIELDS: [
      "regionTier", // "tier1" | "tier2" | "tier3"
      "hasUsedTrial", // boolean
      "trialKey", // string (device fingerprint)
      "aiNanoUsedToday", // number
      "aiMiniUsedToday", // number
      "rewardedAdsWatchedToday", // number
      "dailyResetAt", // timestamp
      "activeRewardTokens", // object (reward tokens storage)
      "regionTierAppVersion", // string (app version for tier caching)
    ],
  },

  // ════════════════════════════════════════════════════════════════
  // AI MODEL ROUTING (per FINAL MONETIZATION SPEC v1)
  // Uses Groq API models - equivalent to spec intent:
  // - nano/default ≈ gpt-4.1-nano → llama-3.1-8b-instant (small, fast, cheap)
  // - mini/premium ≈ gpt-4.1-mini → llama-3.1-70b-versatile (larger, better quality)
  // ════════════════════════════════════════════════════════════════
  AI_MODELS: {
    default: "llama-3.1-8b-instant", // Groq nano-equivalent: fast, cost-effective
    premium: "llama-3.1-70b-versatile", // Groq premium-equivalent: better quality
  },

  // ════════════════════════════════════════════════════════════════
  // ANALYTICS EVENTS (Firebase Analytics)
  // ════════════════════════════════════════════════════════════════
  ANALYTICS_EVENTS: {
    TRIAL_STARTED: "trial_started",
    TRIAL_COMPLETED: "trial_completed",
    REWARDED_WATCHED: "rewarded_watched",
    AI_GENERATION_SUCCESS: "ai_generation_success",
    AI_GENERATION_BLOCKED_LIMIT: "ai_generation_blocked_limit",
    PRO_UPGRADE_CLICKED: "pro_upgrade_clicked",
    PRO_SUBSCRIPTION_STARTED: "pro_subscription_started",
    // AdMob/Reward Pipeline Events (8 new events per spec K)
    REWARDED_AD_REQUESTED: "rewarded_ad_requested",
    REWARDED_AD_LOADED: "rewarded_ad_loaded",
    REWARDED_AD_FAILED: "rewarded_ad_failed",
    REWARDED_AD_REWARDED: "rewarded_ad_rewarded",
    REWARDED_AD_BLOCKED_LIMIT: "rewarded_ad_blocked_limit",
    REWARD_CLAIM_SENT: "reward_claim_sent",
    REWARD_CLAIM_APPROVED: "reward_claim_approved",
    REWARD_CLAIM_DENIED: "reward_claim_denied",
  },

  // ════════════════════════════════════════════════════════════════
  // ERROR MESSAGES
  // ════════════════════════════════════════════════════════════════
  MESSAGES: {
    LIMIT_REACHED_TIER1: "You've reached today's AI limit. Come back tomorrow or upgrade to PRO.",
    LIMIT_REACHED_TIER2_3: "You've reached today's limit. Come back tomorrow.",
    NO_TRIAL: "Trial not available. Watch an ad to unlock AI generation.",
    PRO_NOT_AVAILABLE: "This feature is currently available in selected regions.",
    TRIAL_ALREADY_USED: "You've already used your free trial on this device.",
  },

  // ════════════════════════════════════════════════════════════════
  // DAILY RESET SCHEDULE (GMT+5 / Asia/Karachi)
  // ════════════════════════════════════════════════════════════════
  DAILY_RESET: {
    timezone: "Asia/Karachi",
    schedule: "0 0 * * *", // 12:00 AM every day
  },
};
