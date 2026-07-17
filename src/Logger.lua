-- =========================================================
-- FS25_ProStaffCoOp - Logger
-- =========================================================
-- Author: TisonK
-- Greppable by "[ProStaff]".
-- =========================================================

PSLogger = {}
PSLogger.PREFIX = "[ProStaff] "
PSLogger.debugEnabled = false

function PSLogger.info(msg, ...)
    if select("#", ...) > 0 then Logging.info(PSLogger.PREFIX .. msg, ...)
    else Logging.info(PSLogger.PREFIX .. msg) end
end
function PSLogger.warning(msg, ...)
    if select("#", ...) > 0 then Logging.warning(PSLogger.PREFIX .. msg, ...)
    else Logging.warning(PSLogger.PREFIX .. msg) end
end
function PSLogger.error(msg, ...)
    if select("#", ...) > 0 then Logging.error(PSLogger.PREFIX .. msg, ...)
    else Logging.error(PSLogger.PREFIX .. msg) end
end
function PSLogger.debug(msg, ...)
    if not PSLogger.debugEnabled then return end
    if select("#", ...) > 0 then Logging.info(PSLogger.PREFIX .. "[debug] " .. msg, ...)
    else Logging.info(PSLogger.PREFIX .. "[debug] " .. msg) end
end
