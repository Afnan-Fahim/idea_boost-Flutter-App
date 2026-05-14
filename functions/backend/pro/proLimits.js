/**
 * PRO User Daily Limits
 * Spec: PRO SUBSCRIPTION MODEL ORDER
 *
 * Phase 1: Mini (0→20/day) — premium model first
 * Phase 2: Nano (0→80/day) — after mini exhausted
 * Total:   100 AI generations/day for PRO users
 *
 * Hard caps (server-side, hidden): Mini: 20/day, Nano: 80/day
 */

const config = require("../config");

/**
 * Get soft caps for UI display
 * @return {object} - UI-visible limits
 */
function getSoftCaps() {
  return {
    mini: config.PRO_LIMITS.soft_cap_mini,
    nano: config.PRO_LIMITS.soft_cap_nano,
  };
}

/**
 * Get hard caps for server enforcement
 * @return {object} - Hidden server limits
 */
function getHardCaps() {
  return {
    mini: config.PRO_LIMITS.hard_cap_mini,
    nano: config.PRO_LIMITS.hard_cap_nano,
  };
}

/**
 * Check if PRO user exceeded soft cap
 * Used for UI display only
 * @param {object} counters - Daily counters
 * @return {object} - { exceedsSoft: boolean, message?: string }
 */
function checkSoftCap(counters) {
  if (!counters) {
    return {
      exceedsSoft: false,
    };
  }

  const nanoUsed = counters.aiNanoUsedToday || 0;
  const miniUsed = counters.aiMiniUsedToday || 0;
  const miniCap = config.PRO_LIMITS.soft_cap_mini; // 20
  const nanoCap = config.PRO_LIMITS.soft_cap_nano; // 80

  const miniExceeds = miniUsed > miniCap;
  const nanoExceeds = nanoUsed > nanoCap;

  if (miniExceeds || nanoExceeds) {
    const exceededModels = [];
    if (miniExceeds) exceededModels.push(`Mini (${miniUsed}/${miniCap})`);
    if (nanoExceeds) exceededModels.push(`Nano (${nanoUsed}/${nanoCap})`);

    return {
      exceedsSoft: true,
      message: `Soft cap exceeded: ${exceededModels.join(", ")}`,
      exceeded: exceededModels,
    };
  }

  return {
    exceedsSoft: false,
    remaining: {
      mini: miniCap - miniUsed,
      nano: nanoCap - nanoUsed,
    },
  };
}

/**
 * Check if PRO user exceeded hard cap (server enforcement)
 * @param {object} counters - Daily counters
 * @return {object} - { exceedsHard: boolean }
 */
function checkHardCap(counters) {
  if (!counters) {
    return {
      exceedsHard: false,
    };
  }

  const hardCaps = getHardCaps();
  const nanoUsed = counters.aiNanoUsedToday || 0;
  const miniUsed = counters.aiMiniUsedToday || 0;

  // Both caps must be exhausted for total hard cap to trigger
  const miniExceeds = miniUsed >= hardCaps.mini;
  const nanoExceeds = nanoUsed >= hardCaps.nano;

  if (miniExceeds && nanoExceeds) {
    console.warn(
        `⚠️ PRO hard cap reached | Mini: ${miniUsed}/${hardCaps.mini}, ` +
        `Nano: ${nanoUsed}/${hardCaps.nano}`,
    );

    return {
      exceedsHard: true,
      message: "Hard cap reached - AI generation paused until daily reset",
    };
  }

  return {
    exceedsHard: false,
  };
}

/**
 * Check if PRO user can generate AI with the given model
 * @param {object} counters - Daily counters
 * @param {string} model - "nano" or "mini"
 * @return {object} - { canGenerate: boolean, message?: string }
 */
function canGenerateWithModel(counters, model) {
  if (!counters || !model) {
    return {
      canGenerate: false,
      message: "Invalid data",
    };
  }

  const hardCaps = getHardCaps();
  const miniCap = config.PRO_LIMITS.soft_cap_mini; // 20
  const nanoCap = config.PRO_LIMITS.soft_cap_nano; // 80

  const effectiveCap = model === "mini" ?
      Math.min(miniCap, hardCaps.mini) :
      Math.min(nanoCap, hardCaps.nano);

  const used = model === "mini" ?
      (counters.aiMiniUsedToday || 0) :
      (counters.aiNanoUsedToday || 0);

  if (used >= effectiveCap) {
    return {
      canGenerate: false,
      message: `${model.toUpperCase()} limit reached (${used}/${effectiveCap})`,
    };
  }

  const remaining = effectiveCap - used;

  return {
    canGenerate: true,
    remaining,
    cap: effectiveCap,
  };
}

/**
 * Determine which model a PRO user should use based on phased allocation
 * PRO Phased Flow:
 *   Phase 1 (mini): Mini model first (0→20/day)
 *   Phase 2 (nano): Nano model after mini exhausted (0→80/day)
 *   Phase 3 (exhausted): Both exhausted — total 100/day
 * @param {object} counters - Daily counters
 * @return {object} - { phase, model, remaining }
 */
function getProModelPhase(counters) {
  const miniCap = config.PRO_LIMITS.soft_cap_mini; // 20
  const nanoCap = config.PRO_LIMITS.soft_cap_nano; // 80

  if (!counters) {
    return {phase: "mini", model: "mini", remaining: miniCap};
  }

  const nanoUsed = counters.aiNanoUsedToday || 0;
  const miniUsed = counters.aiMiniUsedToday || 0;

  // Phase 1: Mini available (0→20)
  if (miniUsed < miniCap) {
    return {phase: "mini", model: "mini", remaining: miniCap - miniUsed};
  }

  // Phase 2: Nano available after mini exhausted (0→80)
  if (nanoUsed < nanoCap) {
    return {phase: "nano", model: "nano", remaining: nanoCap - nanoUsed};
  }

  // Phase 3: All exhausted (100 total reached)
  return {phase: "exhausted", model: null, remaining: 0};
}

/**
 * Get PRO daily usage status
 * @param {object} counters - Daily counters
 * @return {object} - Complete PRO status with phase info
 */
function getProDailyStatus(counters) {
  if (!counters) {
    return null;
  }

  const nanoUsed = counters.aiNanoUsedToday || 0;
  const miniUsed = counters.aiMiniUsedToday || 0;
  const miniCap = config.PRO_LIMITS.soft_cap_mini; // 20
  const nanoCap = config.PRO_LIMITS.soft_cap_nano; // 80
  const hardCaps = getHardCaps();

  const phase = getProModelPhase(counters);

  return {
    mini: {
      used: miniUsed,
      softCap: miniCap,
      hardCap: hardCaps.mini,
      capExceeded: miniUsed >= miniCap,
      hardCapExceeded: miniUsed >= hardCaps.mini,
      remaining: Math.max(0, miniCap - miniUsed),
    },
    nano: {
      used: nanoUsed,
      softCap: nanoCap,
      hardCap: hardCaps.nano,
      capExceeded: nanoUsed >= nanoCap,
      hardCapExceeded: nanoUsed >= hardCaps.nano,
      remaining: Math.max(0, nanoCap - nanoUsed),
    },
    phase: phase.phase,
    currentModel: phase.model,
    totalUsed: miniUsed + nanoUsed,
    totalCap: miniCap + nanoCap, // 100
    totalHardCapExceeded: miniUsed >= hardCaps.mini && nanoUsed >= hardCaps.nano,
  };
}

module.exports = {
  getSoftCaps,
  getHardCaps,
  checkSoftCap,
  checkHardCap,
  canGenerateWithModel,
  getProModelPhase,
  getProDailyStatus,
};
