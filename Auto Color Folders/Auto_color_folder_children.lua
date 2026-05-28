-- @description Auto color tracks from selected folder parents when moved into a folder
-- @author Vahe / Codex
-- @version 1.0
-- @about
--   Select one or more folder tracks, then run this as a background script.
--   When enabled, existing children of the selected folders take the folder
--   parent track color. After that, tracks also update when moved into one of
--   the selected folders or moved from one selected folder to another.
--   New tracks created inside an enabled folder automatically inherit that
--   folder's color.
--   If the folder parent has no custom color, the child track color is cleared.

local SCRIPT_NAME = "Auto color tracks from selected folder parents"

local _, _, section_id, command_id = reaper.get_action_context()

if reaper.set_action_options then
  reaper.set_action_options(1)
end

local EXT_SECTION = "AutoColorFolderChildren"
local TOKEN_KEY = "active_token"

local previous_parents = {}
local previous_parent_colors = {}
local selected_folder_guids = {}
local current_project = reaper.EnumProjects(-1, "")
local token = ""

local function set_toolbar_state(state)
  if command_id and command_id ~= 0 then
    reaper.SetToggleCommandState(section_id, command_id, state)
    reaper.RefreshToolbar2(section_id, command_id)
  end
end

local function is_current_instance()
  return reaper.GetExtState(EXT_SECTION, TOKEN_KEY) == token
end

local function track_guid(track)
  return reaper.GetTrackGUID(track)
end

local function parent_guid(parent)
  if parent then
    return track_guid(parent)
  end

  return ""
end

local function color_from_parent(track, parent)
  local color = reaper.GetTrackColor(parent)

  if reaper.GetTrackColor(track) ~= color then
    reaper.SetTrackColor(track, color)
    return true
  end

  return false
end

local function refresh_track_colors()
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
end

local function is_folder_track(track)
  return reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1
end

local function store_selected_folders()
  local selected_folder_count = 0
  local selected_track_count = reaper.CountSelectedTracks(0)

  for i = 0, selected_track_count - 1 do
    local track = reaper.GetSelectedTrack(0, i)

    if is_folder_track(track) then
      selected_folder_guids[track_guid(track)] = true
      selected_folder_count = selected_folder_count + 1
    end
  end

  return selected_folder_count
end

local function is_selected_folder(parent)
  return parent and selected_folder_guids[track_guid(parent)] == true
end

local function build_snapshot_and_color_changes(apply_changes)
  local next_parents = {}
  local next_parent_colors = {}
  local changed = false
  local track_count = reaper.CountTracks(0)

  for i = 0, track_count - 1 do
    local track = reaper.GetTrack(0, i)
    local guid = track_guid(track)
    local parent = reaper.GetParentTrack(track)
    local current_parent_guid = parent_guid(parent)

    next_parents[guid] = current_parent_guid

    if is_selected_folder(parent) then
      local parent_color = reaper.GetTrackColor(parent)
      next_parent_colors[current_parent_guid] = parent_color

      local was_seen_before = previous_parents[guid] ~= nil
      local parent_changed = was_seen_before and previous_parents[guid] ~= current_parent_guid
      local is_new_track_inside_selected_folder = not was_seen_before
      local parent_color_changed = previous_parent_colors[current_parent_guid] ~= nil
        and previous_parent_colors[current_parent_guid] ~= parent_color
      local color_mismatch = reaper.GetTrackColor(track) ~= parent_color
      local should_color_track = parent_changed
        or is_new_track_inside_selected_folder
        or parent_color_changed
        or color_mismatch

      if apply_changes and should_color_track then
        changed = color_from_parent(track, parent) or changed
      end
    end
  end

  previous_parents = next_parents
  previous_parent_colors = next_parent_colors

  return changed
end

local function loop()
  if not is_current_instance() then
    return
  end

  local active_project = reaper.EnumProjects(-1, "")
  if active_project ~= current_project then
    current_project = active_project
    build_snapshot_and_color_changes(false)
    reaper.defer(loop)
    return
  end

  local changed = build_snapshot_and_color_changes(true)

  if changed then
    refresh_track_colors()
  end

  reaper.defer(loop)
end

local function cleanup()
  if is_current_instance() then
    reaper.DeleteExtState(EXT_SECTION, TOKEN_KEY, false)
  end

  set_toolbar_state(0)
end

if store_selected_folders() == 0 then
  reaper.MB("Select at least one folder track before enabling this script.", SCRIPT_NAME, 0)
  return
end

set_toolbar_state(1)
reaper.atexit(cleanup)

token = tostring(reaper.time_precise()) .. ":" .. tostring(math.random())
reaper.SetExtState(EXT_SECTION, TOKEN_KEY, token, false)

if build_snapshot_and_color_changes(true) then
  refresh_track_colors()
end

reaper.defer(loop)
