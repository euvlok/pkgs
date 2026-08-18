#!/usr/bin/env bash
# shellcheck shell=bash

set -Eeuo pipefail
shopt -s inherit_errexit

if [[ -n "${YT_DLP_SCRIPT_PATH:-}" ]]; then
  PATH="${YT_DLP_SCRIPT_PATH}:${PATH}"
  export PATH
  hash -r
fi

readonly PROGRAM_NAME="${YT_DLP_SCRIPT_NAME:-${0##*/}}"

# User-facing policy lives here. Adding a format or browser location should be
# a data change; the control flow below consumes these declarations.
readonly DEFAULT_CRF=26
readonly MIN_CRF=0
readonly MAX_CRF=51
readonly MAX_FILENAME_LENGTH=220
readonly MAX_VIDEO_HEIGHT=1080
readonly AUDIO_QUALITY=0
readonly COMPRESSION_VIDEO_CODEC=libx264
readonly COMPRESSION_PRESET=slow
readonly COMPRESSION_AUDIO_CODEC=copy
readonly COMPRESSION_OUTPUT_EXTENSION=mp4
readonly OUTPUT_ID_TEMPLATE='%(display_id)s'
readonly METADATA_ERROR_LINE_LIMIT=3
readonly DEFAULT_BROWSER_COOKIE_MODE=auto
readonly DISABLED_BROWSER_COOKIE_MODE=none
readonly UPLOAD_DATE_TIME_SUFFIX=0000
readonly MAX_TIME_COMPONENTS=3
readonly FRACTIONAL_SECOND_DIGITS=3
readonly SECONDS_PER_MINUTE=60
readonly MILLISECONDS_PER_SECOND=1000
readonly MILLISECONDS_PER_MINUTE=$((SECONDS_PER_MINUTE * MILLISECONDS_PER_SECOND))
readonly TIME_ENDPOINT_PATTERN='^-?[0-9]+(:[0-9]+){0,2}([.][0-9]+)?$'
readonly UPLOAD_DATE_PATTERN='^[0-9]{8}$'
readonly METADATA_PRINT_TEMPLATE='%(.{duration,upload_date})j'
readonly METADATA_PRINT_WHEN=video

# Fields: CLI name, base format, requires time range, supports compression,
# force precise video cuts.
declare -ar FORMAT_SPECS=(
  $'mp4\tmp4\tfalse\ttrue\tfalse'
  $'mp3\tmp3\tfalse\tfalse\tfalse'
  $'m4a\tm4a\tfalse\tfalse\tfalse'
  $'mp4-cut\tmp4\ttrue\ttrue\ttrue'
  $'mp3-cut\tmp3\ttrue\tfalse\tfalse'
  $'m4a-cut\tm4a\ttrue\tfalse\tfalse'
)

# These arrays are referenced indirectly through FORMAT_ARGUMENT_ARRAY.
# shellcheck disable=SC2034
declare -ar FORMAT_ARGS_MP4=(
  --preset-alias mp4
  --format-sort "res:${MAX_VIDEO_HEIGHT}"
)

# shellcheck disable=SC2034
declare -ar FORMAT_ARGS_MP3=(
  --preset-alias mp3
  --audio-quality "$AUDIO_QUALITY"
  --embed-thumbnail
)

# shellcheck disable=SC2034
declare -ar FORMAT_ARGS_M4A=(
  --format 'ba[acodec^=mp4a]/ba/b'
  --extract-audio
  --audio-format m4a
  --audio-quality "$AUDIO_QUALITY"
  --embed-thumbnail
)

declare -Ar FORMAT_ARGUMENT_ARRAY=(
  [mp4]=FORMAT_ARGS_MP4
  [mp3]=FORMAT_ARGS_MP3
  [m4a]=FORMAT_ARGS_M4A
)

declare -ar YT_DLP_BASE_ARGS=(
  --ignore-config
  --no-playlist
)

declare -ar DOWNLOAD_BEHAVIOR_ARGS=(
  --trim-filenames "$MAX_FILENAME_LENGTH"
)

declare -ar DOWNLOAD_FINAL_ARGS=(
  --embed-metadata
  --console-title
)

declare -ar FFMPEG_BASE_ARGS=(
  -nostdin
  -hide_banner
)

declare -ar COMPRESSION_ARGS=(
  -map 0:v:0
  -map '0:a?'
  -map_metadata 0
  -c:v "$COMPRESSION_VIDEO_CODEC"
  -preset "$COMPRESSION_PRESET"
  -c:a "$COMPRESSION_AUDIO_CODEC"
  -movflags +faststart
  -n
)

# Fields: root key, yt-dlp browser, display label, relative browser-data path.
# The path is only used to detect installed browsers. yt-dlp itself selects the
# newest profile and cookie database.
declare -ar BROWSER_PROFILE_SPECS=(
  $'config\tchrome\tGoogle Chrome\tgoogle-chrome'
  $'config\tchromium\tChromium\tchromium'
  $'config\tbrave\tBrave\tBraveSoftware/Brave-Browser'
  $'config\tedge\tMicrosoft Edge\tmicrosoft-edge'
  $'config\tfirefox\tFirefox\tmozilla/firefox'
  $'config\tvivaldi\tVivaldi\tvivaldi'
  $'config\topera\tOpera\topera'
  $'home\tchrome\tGoogle Chrome\tLibrary/Application Support/Google/Chrome'
  $'home\tchromium\tChromium\tLibrary/Application Support/Chromium'
  $'home\tbrave\tBrave\tLibrary/Application Support/BraveSoftware/Brave-Browser'
  $'home\tedge\tMicrosoft Edge\tLibrary/Application Support/Microsoft Edge'
  $'home\tfirefox\tFirefox\tLibrary/Application Support/Firefox/Profiles'
  $'home\tfirefox\tFirefox\t.mozilla/firefox'
  $'home\tsafari\tSafari\tLibrary/Cookies/Cookies.binarycookies'
  $'home\tsafari\tSafari\tLibrary/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies'
  $'home\tvivaldi\tVivaldi\tLibrary/Application Support/Vivaldi'
  $'home\topera\tOpera\tLibrary/Application Support/com.operasoftware.Opera'
)

declare -ar COOKIE_PASSTHROUGH_OPTIONS=(
  --cookies
  --no-cookies
  --cookies-from-browser
  --no-cookies-from-browser
)

readonly COLOR_ERROR=$'\033[1;31m'
readonly COLOR_INFO=$'\033[1;34m'
readonly COLOR_SUCCESS=$'\033[1;32m'
readonly COLOR_WARNING=$'\033[1;33m'
readonly COLOR_RESET=$'\033[0m'

log_error() {
  printf '%s[error]%s %s\n' "$COLOR_ERROR" "$COLOR_RESET" "$*" >&2
}

log_info() {
  printf '%s[info]%s %s\n' "$COLOR_INFO" "$COLOR_RESET" "$*"
}

log_success() {
  printf '%s[success]%s %s\n' "$COLOR_SUCCESS" "$COLOR_RESET" "$*"
}

log_warning() {
  printf '%s[warning]%s %s\n' "$COLOR_WARNING" "$COLOR_RESET" "$*" >&2
}

die() {
  log_error "$*"
  exit 1
}

TEMP_PATHS=()

cleanup_temp_paths() {
  ((${#TEMP_PATHS[@]} == 0)) && return 0
  rm -rf -- "${TEMP_PATHS[@]}"
}

trap cleanup_temp_paths EXIT

make_temp_file() {
  local -n output_ref=$1
  local path

  path=$(mktemp)
  TEMP_PATHS+=("$path")
  output_ref=$path
}

make_temp_dir() {
  local -n output_ref=$1
  local path

  path=$(mktemp -d)
  TEMP_PATHS+=("$path")
  output_ref=$path
}

join_by() {
  local separator=$1
  local value
  shift

  (($# > 0)) || return 0
  printf '%s' "$1"
  shift
  for value in "$@"; do
    printf '%s%s' "$separator" "$value"
  done
}

supported_formats() {
  local spec name _base_format _requires_time_range _supports_compression _force_precise_cuts
  local -a names=()

  for spec in "${FORMAT_SPECS[@]}"; do
    IFS=$'\t' read -r \
      name _base_format _requires_time_range _supports_compression _force_precise_cuts <<<"$spec"
    names+=("$name")
  done
  join_by ', ' "${names[@]}"
}

usage() {
  cat <<EOF
Usage:
  $PROGRAM_NAME FORMAT URL [TIME_RANGE] [--compress] [--crf CRF] [--no-browser-cookies] [--browser-cookies SPEC] [-- YT_DLP_ARGS...]

Formats:
  $(supported_formats)

Time ranges:
  START-END, -END, or START-. Timestamps may be seconds or HH:MM:SS;
  negative timestamps are relative to the end of the video.

Examples:
  $PROGRAM_NAME mp4 'https://example.invalid/watch?v=id'
  $PROGRAM_NAME mp3-cut 'https://example.invalid/watch?v=id' 30-60
  $PROGRAM_NAME mp4 'https://example.invalid/watch?v=id' --no-browser-cookies
  $PROGRAM_NAME mp4 'https://example.invalid/watch?v=id' --browser-cookies 'chromium:/path/to/Profile'
  $PROGRAM_NAME mp4 'https://example.invalid/watch?v=id' -- --cookies-from-browser firefox
EOF
}

read_format_spec() {
  local requested_format=$1
  local -n base_format_ref=$2
  local -n requires_time_range_ref=$3
  local -n supports_compression_ref=$4
  local -n force_precise_cuts_ref=$5
  local spec declared_name declared_base_format declared_requires_time_range
  local declared_supports_compression declared_force_precise_cuts

  for spec in "${FORMAT_SPECS[@]}"; do
    IFS=$'\t' read -r \
      declared_name declared_base_format declared_requires_time_range \
      declared_supports_compression declared_force_precise_cuts <<<"$spec"
    [[ "$declared_name" == "$requested_format" ]] || continue
    # Assigned through nameref output parameters.
    # shellcheck disable=SC2034
    base_format_ref=$declared_base_format
    # shellcheck disable=SC2034
    requires_time_range_ref=$declared_requires_time_range
    # shellcheck disable=SC2034
    supports_compression_ref=$declared_supports_compression
    # shellcheck disable=SC2034
    force_precise_cuts_ref=$declared_force_precise_cuts
    return 0
  done
  return 1
}

is_unsigned_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

is_valid_crf() {
  is_unsigned_integer "$1" && (($1 >= MIN_CRF && $1 <= MAX_CRF))
}

append_format_args() {
  local destination_name=$1
  local base_format=$2
  local source_name=${FORMAT_ARGUMENT_ARRAY[$base_format]:-}
  local -n destination_ref=$destination_name

  [[ -n "$source_name" ]] || die "No download arguments declared for format '$base_format'."
  local -n source_ref=$source_name
  destination_ref+=("${source_ref[@]}")
}

resolve_browser_root() {
  local root_key=$1
  local config_home=$2
  local home=$3
  local -n output_ref=$4

  case "$root_key" in
    config) output_ref=$config_home ;;
    home) output_ref=$home ;;
    *) die "Unknown browser profile root key '$root_key'." ;;
  esac
}

discover_browser_cookie_candidates() {
  local xdg_config_home=${XDG_CONFIG_HOME:-}
  local home=${HOME:-}
  local config_home=''
  local spec root_key browser label relative_path root browser_path
  local -A seen_browsers=()

  if [[ -n "$xdg_config_home" ]]; then
    config_home=$xdg_config_home
  elif [[ -n "$home" ]]; then
    config_home=$home/.config
  fi

  for spec in "${BROWSER_PROFILE_SPECS[@]}"; do
    IFS=$'\t' read -r root_key browser label relative_path <<<"$spec"
    resolve_browser_root "$root_key" "$config_home" "$home" root
    [[ -n "$root" ]] || continue
    browser_path="$root/$relative_path"
    [[ -e "$browser_path" ]] || continue
    [[ -n "${seen_browsers[$browser]+x}" ]] && continue
    seen_browsers[$browser]=1
    printf '%s\t%s\n' "$browser" "$label"
  done
}

passthrough_has_cookie_option() {
  local arg option

  for arg in "$@"; do
    for option in "${COOKIE_PASSTHROUGH_OPTIONS[@]}"; do
      [[ "$arg" == "$option" || "$arg" == "$option="* ]] && return 0
    done
  done

  return 1
}

die_metadata_fetch() {
  local message=$1
  local details=${2:-}

  [[ -z "$details" ]] || log_warning "$details"
  die "$message"
}

fetch_metadata_with_cookie_spec() {
  local url=$1
  local cookie_spec=$2
  local -n passthrough_ref=$3
  local -n metadata_ref=$4
  local -n error_ref=$5
  local log_file metadata_file
  local -a metadata_args=("${YT_DLP_BASE_ARGS[@]}")

  if [[ -n "$cookie_spec" ]]; then
    metadata_args+=(--cookies-from-browser "$cookie_spec")
  fi
  make_temp_file metadata_file
  metadata_args+=(
    "${passthrough_ref[@]}"
    --simulate
    --print-to-file "${METADATA_PRINT_WHEN}:${METADATA_PRINT_TEMPLATE}" "$metadata_file"
    -- "$url"
  )

  make_temp_file log_file
  if yt-dlp "${metadata_args[@]}" > /dev/null 2>"$log_file"; then
    rm -f -- "$log_file"
    error_ref=''
    metadata_ref=$(<"$metadata_file")
    jq -e 'type == "object"' >/dev/null <<<"$metadata_ref" \
      || die "yt-dlp returned invalid metadata JSON object."
    return 0
  fi

  # Assigned through a nameref output parameter.
  # shellcheck disable=SC2034
  error_ref=$(head -n "$METADATA_ERROR_LINE_LIMIT" "$log_file")
  rm -f -- "$log_file"
  metadata_ref=''
  return 1
}

select_metadata_and_browser_cookies() {
  local url=$1
  local browser_cookie_mode=$2
  local passthrough_name=$3
  local -n output_metadata_ref=$4
  local -n output_cookie_spec_ref=$5
  local -n passthrough_ref=$passthrough_name
  local candidate_metadata='' fetch_error=''
  local candidate_cookie_spec cookie_label

  if passthrough_has_cookie_option "${passthrough_ref[@]}"; then
    log_info "yt-dlp cookie option supplied; not auto-selecting browser cookies."
    fetch_metadata_with_cookie_spec "$url" "" "$passthrough_name" candidate_metadata fetch_error \
      || die_metadata_fetch "Failed to fetch video metadata." "$fetch_error"
    output_metadata_ref=$candidate_metadata
    output_cookie_spec_ref=''
    return 0
  fi

  case "$browser_cookie_mode" in
    "$DISABLED_BROWSER_COOKIE_MODE")
      log_info "Browser cookies disabled by flag."
      fetch_metadata_with_cookie_spec "$url" "" "$passthrough_name" candidate_metadata fetch_error \
        || die_metadata_fetch "Failed to fetch video metadata." "$fetch_error"
      output_metadata_ref=$candidate_metadata
      output_cookie_spec_ref=''
      return 0
      ;;
    "$DEFAULT_BROWSER_COOKIE_MODE") ;;
    *)
      log_info "Preferring browser cookies from: ${browser_cookie_mode}"
      fetch_metadata_with_cookie_spec "$url" "$browser_cookie_mode" "$passthrough_name" candidate_metadata fetch_error \
        || die_metadata_fetch \
          "Failed to fetch video metadata with browser cookies '${browser_cookie_mode}'." "$fetch_error"
      output_metadata_ref=$candidate_metadata
      output_cookie_spec_ref=$browser_cookie_mode
      return 0
      ;;
  esac

  if fetch_metadata_with_cookie_spec "$url" "" "$passthrough_name" candidate_metadata fetch_error; then
    output_metadata_ref=$candidate_metadata
    output_cookie_spec_ref=''
    log_info "Anonymous extraction succeeded; browser cookies are not needed."
    return 0
  fi

  log_warning "Anonymous extraction failed; trying installed browsers."
  if [[ -n "$fetch_error" ]]; then
    log_warning "$fetch_error"
  fi

  while IFS=$'\t' read -r candidate_cookie_spec cookie_label; do
    [[ -n "$candidate_cookie_spec" ]] || continue
    if fetch_metadata_with_cookie_spec "$url" "$candidate_cookie_spec" "$passthrough_name" candidate_metadata fetch_error; then
      # shellcheck disable=SC2034
      output_metadata_ref=$candidate_metadata
      # shellcheck disable=SC2034
      output_cookie_spec_ref=$candidate_cookie_spec
      log_info "Using the newest cookie profile found by yt-dlp for: ${cookie_label}"
      return 0
    fi

    log_warning "Browser cookies from ${cookie_label} did not work for this URL; trying the next candidate."
    if [[ -n "$fetch_error" ]]; then
      log_warning "$fetch_error"
    fi
  done < <(discover_browser_cookie_candidates)

  die "Failed to fetch video metadata anonymously or with cookies from installed browsers."
}

parse_time_ms() {
  local value=$1
  local -a parts=()
  local part whole fraction fraction_ms
  local prefix_seconds=0
  local index

  [[ -n "$value" ]] || return 1
  IFS=: read -r -a parts <<<"$value"
  ((${#parts[@]} >= 1 && ${#parts[@]} <= MAX_TIME_COMPONENTS)) || return 1

  for index in "${!parts[@]}"; do
    part=${parts[$index]}
    [[ "$part" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1

    if ((index < ${#parts[@]} - 1)); then
      [[ "$part" != *.* ]] || return 1
      prefix_seconds=$((prefix_seconds * SECONDS_PER_MINUTE + 10#$part))
      continue
    fi

    whole=${part%%.*}
    if [[ "$part" == *.* ]]; then
      fraction=${part#*.}
      fraction=${fraction:0:FRACTIONAL_SECOND_DIGITS}
      while ((${#fraction} < FRACTIONAL_SECOND_DIGITS)); do
        fraction+="0"
      done
      fraction_ms=$((10#$fraction))
    else
      fraction_ms=0
    fi

    printf '%s\n' $((prefix_seconds * MILLISECONDS_PER_MINUTE + 10#$whole * MILLISECONDS_PER_SECOND + fraction_ms))
  done
}

split_time_range() {
  local range=$1
  local -n start_ref=$2
  local -n end_ref=$3
  local range_pattern
  local parsed_start parsed_end

  range_pattern='^(-?[0-9]+(:[0-9]+){0,2}([.][0-9]+)?)?-(-?[0-9]+(:[0-9]+){0,2}([.][0-9]+)?|inf|infinite)?$'
  [[ "$range" =~ $range_pattern ]] || return 1
  parsed_start=${BASH_REMATCH[1]}
  parsed_end=${BASH_REMATCH[4]}
  [[ -n "$parsed_start" || -n "$parsed_end" ]] || return 1
  parsed_start=${parsed_start:-0}
  parsed_end=${parsed_end:-inf}
  [[ "$parsed_end" != infinite ]] || parsed_end=inf
  # Assigned through nameref output parameters.
  # shellcheck disable=SC2034
  start_ref=$parsed_start
  # shellcheck disable=SC2034
  end_ref=$parsed_end
}

is_time_endpoint() {
  [[ "$1" == "inf" || "$1" =~ $TIME_ENDPOINT_PATTERN ]]
}

resolve_time_endpoint_ms() {
  local value=$1
  local duration_ms=$2
  local -n output_ref=$3
  local raw_ms resolved_ms

  if [[ "$value" == "inf" ]]; then
    [[ -n "$duration_ms" ]] || return 1
    output_ref=$duration_ms
    return 0
  fi

  if [[ "$value" == -* ]]; then
    [[ -n "$duration_ms" ]] || return 1
    raw_ms=$(parse_time_ms "${value#-}") || return 1
    resolved_ms=$((duration_ms - raw_ms))
  else
    resolved_ms=$(parse_time_ms "$value") || return 1
  fi

  output_ref=$resolved_ms
}

validate_time_range() {
  local range=$1
  local duration=$2
  local start end start_ms end_ms duration_ms=''

  split_time_range "$range" start end \
    || die "Invalid time range '$range'. Expected START-END, for example 30-60."

  if [[ "$start" == "inf" ]]; then
    die "Invalid time range '$range'. Start time cannot be inf."
  fi

  is_time_endpoint "$start" \
    || die "Invalid time range start '$start'. Use seconds, HH:MM:SS, or a negative timestamp."
  is_time_endpoint "$end" \
    || die "Invalid time range end '$end'. Use seconds, HH:MM:SS, inf, or a negative timestamp."

  if [[ -n "$duration" && "$duration" != "null" ]]; then
    if ! duration_ms=$(parse_time_ms "$duration"); then
      log_warning "Could not parse video duration '$duration'. Skipping time range bounds validation."
      duration_ms=''
    fi
  fi

  if [[ -z "$duration_ms" && ("$start" == -* || "$end" == -* || "$end" == "inf") ]]; then
    log_warning "Could not determine video duration. Skipping negative/inf time range validation."
    return 0
  fi

  resolve_time_endpoint_ms "$start" "$duration_ms" start_ms \
    || die "Invalid time range start '$start'. Use seconds or HH:MM:SS."
  resolve_time_endpoint_ms "$end" "$duration_ms" end_ms \
    || die "Invalid time range end '$end'. Use seconds, HH:MM:SS, or inf."

  ((start_ms >= 0 && end_ms >= 0)) \
    || die "Invalid time range '$range'. Negative timestamps must resolve within the video duration."
  ((start_ms <= end_ms)) \
    || die "Invalid time range '$range'. Start must be less than or equal to end."

  [[ -z "$duration_ms" ]] || ((end_ms <= duration_ms)) \
    || die "Invalid time range '$range'. Video duration is ${duration}s."
}

quote_command() {
  local arg
  printf '%q' "$1"
  shift
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
  printf '\n'
}

first_downloaded_file() {
  local directory=$1
  local -a files=()
  local file

  for file in "$directory"/*; do
    [[ -f "$file" && "$file" != *.part ]] || continue
    files+=("$file")
  done

  ((${#files[@]} > 0)) || return 1
  printf '%s\n' "${files[0]}"
}

first_recorded_path() {
  local path_file=$1
  local path

  [[ -s "$path_file" ]] || return 1
  IFS= read -r path <"$path_file" || return 1
  [[ -n "$path" ]] || return 1
  printf '%s\n' "$path"
}

next_available_path() {
  local stem=$1
  local ext=$2
  local candidate="./${stem}.${ext}"
  local counter=1

  if [[ ! -e "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  while :; do
    candidate="./${stem}-${counter}.${ext}"
    if [[ ! -e "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    ((counter++))
  done
}

compress_video() {
  local input_file=$1
  local crf=$2
  local -n output_ref=$3
  local base_name output_file

  [[ -f "$input_file" ]] || die "Downloaded file not found for compression."
  base_name=${input_file##*/}
  base_name=${base_name%.*}
  if [[ -e "./${base_name}.${COMPRESSION_OUTPUT_EXTENSION}" ]]; then
    output_file=$(next_available_path "${base_name}-compressed" "$COMPRESSION_OUTPUT_EXTENSION")
  else
    output_file="./${base_name}.${COMPRESSION_OUTPUT_EXTENSION}"
  fi

  log_info "Compressing video with CRF ${crf}..."
  log_info "  Input:  ${input_file}"
  log_info "  Output: ${output_file}"

  ffmpeg "${FFMPEG_BASE_ARGS[@]}" -i "$input_file" \
    "${COMPRESSION_ARGS[@]}" -crf "$crf" "$output_file" \
    || die "Compression failed."

  # Assigned through a nameref output parameter.
  # shellcheck disable=SC2034
  output_ref=$output_file
  log_success "Compression finished successfully."
}

change_file_date() {
  local upload_date=$1
  local downloaded_path=${2:-}
  local file_to_touch

  if [[ -z "$upload_date" || "$upload_date" == "null" ]]; then
    log_warning "Upload date not found. Skipping file date modification."
    return 0
  fi

  if [[ ! "$upload_date" =~ $UPLOAD_DATE_PATTERN ]]; then
    log_warning "Upload date '$upload_date' is not in YYYYMMDD format. Skipping file date modification."
    return 0
  fi

  if [[ -n "$downloaded_path" && -e "$downloaded_path" ]]; then
    file_to_touch=$downloaded_path
  else
    log_warning "Could not determine the final media file to modify the date for."
    return 0
  fi

  log_info "Setting file modification time of '${file_to_touch}' to ${upload_date}..."
  touch -t "${upload_date}${UPLOAD_DATE_TIME_SUFFIX}" "$file_to_touch"
}

run_yt_dlp() {
  log_info "Executing: $(quote_command yt-dlp "$@")"
  printf '\n'
  yt-dlp "$@" || die "yt-dlp download failed."
  log_success "Download completed."
}

download_media() {
  local output_tmpl=$1
  local media_url=$2
  local passthrough_name=$3
  local -n output_path_file_ref=$4
  local -n passthrough_ref=$passthrough_name
  local path_file
  local -a download_args=()
  shift 4

  make_temp_file path_file
  download_args=(
    "$@"
    --output "$output_tmpl"
    --print-to-file after_move:filepath "$path_file"
    --no-simulate
    "${passthrough_ref[@]}"
    -- "$media_url"
  )
  run_yt_dlp "${download_args[@]}"
  # Assigned through a nameref output parameter.
  # shellcheck disable=SC2034
  output_path_file_ref=$path_file
}

main() {
  local format url time_range=''
  local compress=false
  local browser_cookie_mode=$DEFAULT_BROWSER_COOKIE_MODE
  local crf=$DEFAULT_CRF
  local -a passthrough=()
  local -a cookie_args=()
  local -a args=()
  local base_format requires_time_range supports_compression force_precise_cuts
  local metadata duration upload_date
  local metadata_cookie_spec=''
  local time_suffix=''
  local temp_dir=''
  local downloaded_paths=''
  local downloaded_path=''
  local compressed_path=''
  local output_tmpl

  if (($# == 0)); then
    usage
    exit 2
  fi

  case "${1:-}" in
    -h | --help)
      usage
      exit 0
      ;;
  esac

  (($# >= 2)) || die "Missing required FORMAT and URL arguments."
  format=$1
  url=$2
  shift 2

  read_format_spec \
    "$format" base_format requires_time_range supports_compression force_precise_cuts \
    || die "Invalid format '$format'. Must be one of: $(supported_formats)."

  while (($# > 0)); do
    case "$1" in
      --)
        shift
        passthrough+=("$@")
        break
        ;;
      --compress)
        compress=true
        shift
        ;;
      --crf)
        (($# >= 2)) || die "Missing value for --crf."
        crf=$2
        is_valid_crf "$crf" || die "Invalid --crf value '$crf'. Expected an integer from $MIN_CRF to $MAX_CRF."
        shift 2
        ;;
      --crf=*)
        crf=${1#*=}
        is_valid_crf "$crf" || die "Invalid --crf value '$crf'. Expected an integer from $MIN_CRF to $MAX_CRF."
        shift
        ;;
      --no-browser-cookies)
        browser_cookie_mode=$DISABLED_BROWSER_COOKIE_MODE
        shift
        ;;
      --browser-cookies)
        (($# >= 2)) || die "Missing value for --browser-cookies."
        browser_cookie_mode=$2
        shift 2
        ;;
      --browser-cookies=*)
        browser_cookie_mode=${1#*=}
        [[ -n "$browser_cookie_mode" ]] || die "Missing value for --browser-cookies."
        shift
        ;;
      -*)
        if [[ -z "$time_range" && "$requires_time_range" == true ]]; then
          time_range=$1
          shift
        else
          die "Unknown option '$1'. Pass yt-dlp options after --."
        fi
        ;;
      *)
        [[ -z "$time_range" ]] || die "Unexpected argument '$1'. Pass yt-dlp options after --."
        time_range=$1
        shift
        ;;
    esac
  done

  if [[ "$requires_time_range" == true && -z "$time_range" ]]; then
    die "Missing time range for a '-cut' format."
  fi

  if [[ "$compress" == true && "$supports_compression" != true ]]; then
    die "--compress is only supported for mp4 formats."
  fi

  log_info "Using yt-dlp: $(command -v yt-dlp)"
  log_info "Fetching video metadata..."
  select_metadata_and_browser_cookies \
    "$url" "$browser_cookie_mode" passthrough \
    metadata metadata_cookie_spec
  if [[ -n "$metadata_cookie_spec" ]]; then
    cookie_args=(--cookies-from-browser "$metadata_cookie_spec")
  fi

  duration=$(jq -r '.duration // empty' <<<"$metadata") \
    || die "Failed to read video duration from metadata."
  upload_date=$(jq -r '.upload_date // empty' <<<"$metadata") \
    || die "Failed to read upload date from metadata."

  if [[ -n "$time_range" ]]; then
    validate_time_range "$time_range" "$duration"
  fi

  args=("${YT_DLP_BASE_ARGS[@]}" "${DOWNLOAD_BEHAVIOR_ARGS[@]}" "${cookie_args[@]}")
  append_format_args args "$base_format"
  args+=("${DOWNLOAD_FINAL_ARGS[@]}")

  if [[ -n "$time_range" ]]; then
    args+=(--download-sections "*${time_range}")
    if [[ "$force_precise_cuts" == true ]]; then
      args+=(--force-keyframes-at-cuts)
    fi
    time_suffix="-${time_range//:/_}"
  fi

  if [[ "$compress" == true ]]; then
    make_temp_dir temp_dir
    output_tmpl="${temp_dir}/${OUTPUT_ID_TEMPLATE}.%(ext)s"
    download_media "$output_tmpl" "$url" passthrough downloaded_paths "${args[@]}"

    downloaded_path=$(first_recorded_path "$downloaded_paths") \
      || downloaded_path=$(first_downloaded_file "$temp_dir") \
      || die "Downloaded file not found for compression."
    compress_video "$downloaded_path" "$crf" compressed_path
  else
    output_tmpl="${OUTPUT_ID_TEMPLATE}${time_suffix}.%(ext)s"
    download_media "$output_tmpl" "$url" passthrough downloaded_paths "${args[@]}"
    downloaded_path=$(first_recorded_path "$downloaded_paths" || true)
  fi

  change_file_date "$upload_date" "${compressed_path:-$downloaded_path}"
  log_success "All operations completed successfully."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
