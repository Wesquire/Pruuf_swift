-- Migration: 021_break_edge_cases.sql
-- Purpose: Break Edge Cases (Section 7.3)
-- Created: 2026-01-19
--
-- Edge Cases Implemented:
-- EC-7.1: Prevent overlapping breaks with error "You already have a break during this period"
-- EC-7.2: If break starts today, immediately set status='active', today's ping becomes 'on_break'
-- EC-7.3: If break ends today, tomorrow's ping reverts to 'pending'
-- EC-7.4: Connection pause during break applies both statuses; no pings generated
-- EC-7.5: Warn for breaks longer than 1 year: "Breaks longer than 1 year may affect your account"

-- ============================================================================
-- EC-7.1: PREVENT OVERLAPPING BREAKS
-- Function to check if a proposed break overlaps with any existing active/scheduled breaks
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_break_overlap(
    p_sender_id UUID,
    p_start_date DATE,
    p_end_date DATE,
    p_exclude_break_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
    v_overlap_count INTEGER;
BEGIN
    -- Two date ranges [A, B] and [C, D] overlap if A <= D AND C <= B
    SELECT COUNT(*) INTO v_overlap_count
    FROM breaks b
    WHERE b.sender_id = p_sender_id
      AND b.status IN ('scheduled', 'active')
      AND b.start_date <= p_end_date
      AND b.end_date >= p_start_date
      AND (p_exclude_break_id IS NULL OR b.id != p_exclude_break_id);

    RETURN v_overlap_count > 0;
END;
$$;

COMMENT ON FUNCTION public.check_break_overlap IS 'EC-7.1: Checks if a proposed break date range overlaps with existing breaks for a sender';

-- ============================================================================
-- EC-7.2: SAME-DAY BREAK ACTIVATION
-- Function to determine if a break should start as active or scheduled
-- and mark today''s pings as on_break if needed
-- ============================================================================

CREATE OR REPLACE FUNCTION public.determine_break_initial_status(p_start_date DATE)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
BEGIN
    -- EC-7.2: If break starts today or earlier, status should be 'active'
    IF p_start_date <= CURRENT_DATE THEN
        RETURN 'active';
    ELSE
        RETURN 'scheduled';
    END IF;
END;
$$;

COMMENT ON FUNCTION public.determine_break_initial_status IS 'EC-7.2: Determines if a break should start as active (today) or scheduled (future)';

-- Function to mark today's pending pings as on_break when break is created/activated
CREATE OR REPLACE FUNCTION public.mark_todays_pings_on_break(p_sender_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_updated_count INTEGER;
BEGIN
    -- EC-7.2: Update all pending pings for today to 'on_break'
    UPDATE pings
    SET status = 'on_break',
        completion_method = 'auto_break'
    WHERE sender_id = p_sender_id
      AND status = 'pending'
      AND scheduled_time >= CURRENT_DATE
      AND scheduled_time < (CURRENT_DATE + INTERVAL '1 day');

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    RETURN v_updated_count;
END;
$$;

COMMENT ON FUNCTION public.mark_todays_pings_on_break IS 'EC-7.2: Marks all pending pings for today as on_break when a break starts';

-- ============================================================================
-- EC-7.3: BREAK END DATE HANDLING
-- The generate_daily_pings function handles this automatically:
-- - isSenderOnBreak() checks if date is within break range (start_date <= date <= end_date)
-- - When break ends today, tomorrow is outside range, so new ping = 'pending'
-- No additional function needed - documenting the logic here
-- ============================================================================

-- Documentation function (no-op, just for documentation purposes)
CREATE OR REPLACE FUNCTION public.break_end_date_logic_documentation()
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT 'EC-7.3: Break End Date Handling' || E'\n' ||
           '- When generate_daily_pings runs, it calls isSenderOnBreak(breaks, date)' || E'\n' ||
           '- isSenderOnBreak checks: date >= break.start_date AND date <= break.end_date' || E'\n' ||
           '- If break ends today: today = on_break, tomorrow = pending (outside range)' || E'\n' ||
           '- No manual reversion needed - handled automatically by daily ping generation' || E'\n' ||
           '- update_break_statuses() cron job (5 min past midnight) marks ended breaks as completed';
$$;

COMMENT ON FUNCTION public.break_end_date_logic_documentation IS 'EC-7.3: Documentation of how break end dates affect ping generation';

-- ============================================================================
-- EC-7.4: CONNECTION PAUSE DURING BREAK
-- When a connection is paused, no pings are generated regardless of break status
-- The generate_daily_pings function filters: .eq("status", "active")
-- Paused connections are excluded from ping generation entirely
-- ============================================================================

-- Function to check if pings should be generated for a connection
-- Returns FALSE if connection is paused (EC-7.4)
CREATE OR REPLACE FUNCTION public.should_generate_ping_for_connection(p_connection_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
    v_connection_status TEXT;
BEGIN
    -- EC-7.4: Only generate pings for active connections
    -- Paused connections get no pings, regardless of break status
    SELECT status INTO v_connection_status
    FROM connections
    WHERE id = p_connection_id;

    RETURN COALESCE(v_connection_status = 'active', FALSE);
END;
$$;

COMMENT ON FUNCTION public.should_generate_ping_for_connection IS 'EC-7.4: Checks if connection is active (returns FALSE if paused - no pings generated during pause)';

-- ============================================================================
-- EC-7.5: LONG BREAK WARNING
-- Breaks longer than 365 days trigger a warning message
-- This is handled client-side in BreakService.validateBreakDates()
-- Adding database function for completeness
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_break_duration_warning(p_start_date DATE, p_end_date DATE)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_days_between INTEGER;
BEGIN
    v_days_between := p_end_date - p_start_date;

    -- EC-7.5: Warn if break is longer than 365 days (1 year)
    IF v_days_between > 365 THEN
        RETURN 'Breaks longer than 1 year may affect your account';
    END IF;

    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.check_break_duration_warning IS 'EC-7.5: Returns warning message if break duration exceeds 1 year (365 days)';

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION public.check_break_overlap(UUID, DATE, DATE, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.determine_break_initial_status(DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_todays_pings_on_break(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.break_end_date_logic_documentation() TO authenticated;
GRANT EXECUTE ON FUNCTION public.should_generate_ping_for_connection(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.check_break_duration_warning(DATE, DATE) TO authenticated;

-- ============================================================================
-- SUMMARY OF EDGE CASES
-- ============================================================================

-- EC-7.1: Overlapping breaks prevention
--   - check_break_overlap() function validates before insert
--   - Client-side: BreakService.hasOverlappingBreak()
--   - Error message: "You already have a break during this period"

-- EC-7.2: Same-day break activation
--   - determine_break_initial_status() returns 'active' for today or past dates
--   - mark_todays_pings_on_break() updates pending pings to 'on_break'
--   - Client-side: BreakService.scheduleBreak() checks and calls markTodaysPingsAsOnBreak()

-- EC-7.3: Break end date handling
--   - No special function needed - handled by generate_daily_pings
--   - isSenderOnBreak() date range check excludes dates after end_date
--   - Tomorrow's ping automatically becomes 'pending' when break ends today

-- EC-7.4: Connection pause during break
--   - generate_daily_pings filters: .eq("status", "active")
--   - should_generate_ping_for_connection() returns FALSE for paused connections
--   - Paused connections get NO pings regardless of break status

-- EC-7.5: Long break warning
--   - check_break_duration_warning() returns warning for breaks > 365 days
--   - Client-side: BreakService.validateBreakDates() includes warning in result
--   - UI: ScheduleBreakView displays orange warning banner
