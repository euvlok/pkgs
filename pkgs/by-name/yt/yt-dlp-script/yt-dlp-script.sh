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
  local path
  path=$(mktemp)
  TEMP_PATHS+=("$path")
  printf '%s\n' "$path"
}

make_temp_dir() {
  local path
  path=$(mktemp -d)
  TEMP_PATHS+=("$path")
  printf '%s\n' "$path"
}

usage() {
  cat <<EOF
Usage:
  $PROGRAM_NAME FORMAT URL [TIME_RANGE] [--compress] [--crf CRF] [--no-browser-cookies] [--browser-cookies SPEC] [-- YT_DLP_ARGS...]

Formats:
  mp4, mp3, m4a, mp4-cut, mp3-cut, m4a-cut

Examples:
  $PROGRAM_NAME mp4 'https://example.invalid/watch?v=id'
  $PROGRAM_NAME mp3-cut 'https://example.invalid/watch?v=id' 30-60
  $PROGRAM_NAME mp4 'https://example.invalid/watch?v=id' --no-browser-cookies
  $PROGRAM_NAME mp4 'https://example.invalid/watch?v=id' --browser-cookies 'chromium:/path/to/Profile'
  $PROGRAM_NAME mp4 'https://example.invalid/watch?v=id' -- --cookies-from-browser firefox
EOF
}

is_valid_format() {
  case "$1" in
    mp4 | mp3 | m4a | mp4-cut | mp3-cut | m4a-cut) return 0 ;;
    *) return 1 ;;
  esac
}

is_unsigned_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

is_valid_crf() {
  is_unsigned_integer "$1" && (($1 <= 51))
}

path_has_cookie_db() {
  [[ -f "$1/Cookies" || -f "$1/Network/Cookies" ]]
}

cookie_db_mtime() {
  local profile=$1
  local cookie_db=''

  if [[ -f "$profile/Network/Cookies" ]]; then
    cookie_db=$profile/Network/Cookies
  elif [[ -f "$profile/Cookies" ]]; then
    cookie_db=$profile/Cookies
  else
    return 1
  fi

  stat -c '%Y' "$cookie_db"
}

list_cookie_profiles_in_user_data_dir() {
  local user_data_dir=$1
  local profile cookie_file profile_dir
  local -A seen=()

  [[ -d "$user_data_dir" ]] || return 1

  if path_has_cookie_db "$user_data_dir"; then
    printf '%s\n' "$user_data_dir"
    seen[$user_data_dir]=1
  fi

  for profile in "$user_data_dir/Default" "$user_data_dir"/Profile\ *; do
    [[ -d "$profile" ]] || continue
    if path_has_cookie_db "$profile"; then
      printf '%s\n' "$profile"
      seen[$profile]=1
    fi
  done

  while IFS= read -r -d '' cookie_file; do
    if [[ "${cookie_file%/*}" == */Network ]]; then
      profile_dir=${cookie_file%/*/*}
    else
      profile_dir=${cookie_file%/*}
    fi

    [[ -n "${seen[$profile_dir]+x}" ]] && continue
    seen[$profile_dir]=1
    printf '%s\n' "$profile_dir"
  done < <(find "$user_data_dir" -maxdepth 3 -type f \( -path '*/Network/Cookies' -o -name Cookies \) -print0 | sort -z)
}

emit_browser_cookie_profiles() {
  local browser=$1
  local label=$2
  local user_data_dir=$3
  local profile mtime

  while IFS= read -r profile; do
    mtime=$(cookie_db_mtime "$profile") || continue
    printf '%s\t%s:%s\t%s (%s)\n' "$mtime" "$browser" "$profile" "$label" "$profile"
  done < <(list_cookie_profiles_in_user_data_dir "$user_data_dir")
}

emit_generic_chromium_cookie_profiles() {
  local search_root=$1
  local local_state user_data_dir

  [[ -d "$search_root" ]] || return 0

  while IFS= read -r -d '' local_state; do
    user_data_dir=${local_state%/*}
    emit_browser_cookie_profiles chromium "Chromium-compatible profile" "$user_data_dir"
  done < <(find "$search_root" -maxdepth 3 -type f -name 'Local State' -print0 | sort -z)
}

discover_browser_cookie_candidates() {
  local xdg_config_home=${XDG_CONFIG_HOME:-}
  local home=${HOME:-}
  local config_home=''

  if [[ -n "$xdg_config_home" ]]; then
    config_home=$xdg_config_home
  elif [[ -n "$home" ]]; then
    config_home=$home/.config
  fi

  if [[ -n "$config_home" ]]; then
    emit_browser_cookie_profiles chromium "Chromium" "$config_home/chromium"
    emit_browser_cookie_profiles chrome "Google Chrome" "$config_home/google-chrome"
    emit_browser_cookie_profiles brave "Brave" "$config_home/BraveSoftware/Brave-Browser"
    emit_browser_cookie_profiles edge "Microsoft Edge" "$config_home/microsoft-edge"
    emit_browser_cookie_profiles vivaldi "Vivaldi" "$config_home/vivaldi"
    emit_browser_cookie_profiles opera "Opera" "$config_home/opera"
    emit_generic_chromium_cookie_profiles "$config_home"
  fi

  if [[ -n "$home" ]]; then
    emit_browser_cookie_profiles chrome "Google Chrome" "$home/Library/Application Support/Google/Chrome"
    emit_browser_cookie_profiles brave "Brave" "$home/Library/Application Support/BraveSoftware/Brave-Browser"
    emit_browser_cookie_profiles edge "Microsoft Edge" "$home/Library/Application Support/Microsoft Edge"
    emit_browser_cookie_profiles vivaldi "Vivaldi" "$home/Library/Application Support/Vivaldi"
    emit_generic_chromium_cookie_profiles "$home/Library/Application Support"
  fi
}

passthrough_has_cookie_option() {
  local arg

  for arg in "$@"; do
    case "$arg" in
      --cookies | --cookies=* | --no-cookies | --cookies-from-browser | --cookies-from-browser=* | --no-cookies-from-browser)
        return 0
        ;;
    esac
  done

  return 1
}

METADATA=''
METADATA_COOKIE_SPEC=''
METADATA_COOKIE_LABEL=''
METADATA_ERROR=''

fetch_metadata_with_cookie_spec() {
  local url=$1
  local cookie_spec=$2
  local log_file
  local -a metadata_args=(--ignore-config --no-playlist)

  if [[ -n "$cookie_spec" ]]; then
    metadata_args+=(--cookies-from-browser "$cookie_spec")
  fi
  metadata_args+=(--dump-json "$url" "${passthrough[@]}")

  log_file=$(mktemp)
  if METADATA=$(yt-dlp "${metadata_args[@]}" 2>"$log_file"); then
    rm -f -- "$log_file"
    METADATA_ERROR=''
    jq -e type >/dev/null <<<"$METADATA" \
      || die "yt-dlp returned invalid metadata JSON."
    return 0
  fi

  METADATA_ERROR=$(head -n 3 "$log_file")
  rm -f -- "$log_file"
  METADATA=''
  return 1
}

metadata_score() {
  local has_cookies=$1

  jq -r --argjson has_cookies "$has_cookies" '
    (((.formats // []) | length) * 10000000000) + (if $has_cookies then 1 else 0 end)
  ' <<<"$METADATA"
}

select_metadata_and_browser_cookies() {
  local url=$1
  local browser_cookie_mode=$2
  local best_metadata=''
  local best_cookie_spec=''
  local best_cookie_label=''
  local best_score=-1
  local score mtime cookie_spec cookie_label
  local tried_browser_cookies=false
  local -A seen_cookie_specs=()

  if passthrough_has_cookie_option "${passthrough[@]}"; then
    log_info "yt-dlp cookie option supplied; not auto-selecting browser cookies."
    fetch_metadata_with_cookie_spec "$url" "" \
      || die "Failed to fetch video metadata."
    METADATA_COOKIE_SPEC=''
    METADATA_COOKIE_LABEL=''
    return 0
  fi

  case "$browser_cookie_mode" in
    none)
      log_info "Browser cookies disabled by flag."
      fetch_metadata_with_cookie_spec "$url" "" \
        || die "Failed to fetch video metadata."
      METADATA_COOKIE_SPEC=''
      METADATA_COOKIE_LABEL=''
      return 0
      ;;
    auto) ;;
    *)
      log_info "Preferring browser cookies from: ${browser_cookie_mode}"
      fetch_metadata_with_cookie_spec "$url" "$browser_cookie_mode" \
        || die "Failed to fetch video metadata with browser cookies '${browser_cookie_mode}'."
      METADATA_COOKIE_SPEC=$browser_cookie_mode
      METADATA_COOKIE_LABEL=$browser_cookie_mode
      return 0
      ;;
  esac

  while IFS=$'\t' read -r mtime cookie_spec cookie_label; do
    [[ -n "$cookie_spec" ]] || continue
    [[ -n "${seen_cookie_specs[$cookie_spec]+x}" ]] && continue
    seen_cookie_specs[$cookie_spec]=1
    tried_browser_cookies=true

    if fetch_metadata_with_cookie_spec "$url" "$cookie_spec"; then
      score=$(metadata_score true)
      score=$((score + mtime))
      if ((score > best_score)); then
        best_score=$score
        best_metadata=$METADATA
        best_cookie_spec=$cookie_spec
        best_cookie_label=$cookie_label
      fi
    else
      log_warning "Browser cookies from ${cookie_label} did not work for this URL; trying the next candidate."
      if [[ -n "$METADATA_ERROR" ]]; then
        log_warning "$METADATA_ERROR"
      fi
    fi
  done < <(discover_browser_cookie_candidates | sort -rn)

  if ((best_score < 0)); then
    if fetch_metadata_with_cookie_spec "$url" ""; then
      best_score=$(metadata_score false)
      best_metadata=$METADATA
      best_cookie_spec=''
      best_cookie_label=''
    else
      die "Failed to fetch video metadata."
    fi
  fi

  METADATA=$best_metadata
  METADATA_COOKIE_SPEC=$best_cookie_spec
  METADATA_COOKIE_LABEL=$best_cookie_label

  if [[ -n "$METADATA_COOKIE_SPEC" ]]; then
    log_info "Preferring browser cookies from: ${METADATA_COOKIE_LABEL}"
  elif [[ "$tried_browser_cookies" == true ]]; then
    log_info "Continuing without browser cookies; anonymous extraction worked best for this URL."
  else
    log_info "No browser cookie database found. Continuing without browser cookies."
  fi
}

parse_time_ms() {
  local value=$1
  local -a parts=()
  local part whole fraction fraction_ms
  local prefix_seconds=0
  local index

  [[ -n "$value" ]] || return 1
  IFS=: read -r -a parts <<<"$value"
  ((${#parts[@]} >= 1 && ${#parts[@]} <= 3)) || return 1

  for index in "${!parts[@]}"; do
    part=${parts[$index]}
    [[ "$part" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1

    if ((index < ${#parts[@]} - 1)); then
      [[ "$part" != *.* ]] || return 1
      prefix_seconds=$((prefix_seconds * 60 + 10#$part))
      continue
    fi

    whole=${part%%.*}
    if [[ "$part" == *.* ]]; then
      fraction=${part#*.}
      fraction=${fraction:0:3}
      while ((${#fraction} < 3)); do
        fraction+="0"
      done
      fraction_ms=$((10#$fraction))
    else
      fraction_ms=0
    fi

    printf '%s\n' $((prefix_seconds * 60000 + 10#$whole * 1000 + fraction_ms))
  done
}

split_time_range() {
  local range=$1
  local start_var=$2
  local end_var=$3
  local parsed_start parsed_end rest

  if [[ "$range" == -* ]]; then
    rest=${range:1}
    [[ "$rest" == *-* ]] || return 1
    parsed_start="-${rest%%-*}"
    parsed_end=${rest#*-}
  else
    [[ "$range" == *-* ]] || return 1
    parsed_start=${range%%-*}
    parsed_end=${range#*-}
  fi

  [[ -n "$parsed_start" && -n "$parsed_end" ]] || return 1
  printf -v "$start_var" '%s' "$parsed_start"
  printf -v "$end_var" '%s' "$parsed_end"
}

is_time_endpoint() {
  [[ "$1" == "inf" || "$1" =~ ^-?[0-9]+(:[0-9]+){0,2}([.][0-9]+)?$ ]]
}

resolve_time_endpoint_ms() {
  local value=$1
  local duration_ms=$2
  local output_var=$3
  local raw_ms resolved_ms

  if [[ "$value" == "inf" ]]; then
    [[ -n "$duration_ms" ]] || return 1
    printf -v "$output_var" '%s' "$duration_ms"
    return 0
  fi

  if [[ "$value" == -* ]]; then
    [[ -n "$duration_ms" ]] || return 1
    raw_ms=$(parse_time_ms "${value#-}") || return 1
    resolved_ms=$((duration_ms - raw_ms))
  else
    resolved_ms=$(parse_time_ms "$value") || return 1
  fi

  printf -v "$output_var" '%s' "$resolved_ms"
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

  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(find "$directory" -maxdepth 1 -type f ! -name '*.part' -print0 | sort -z)

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
  local output_var=$3
  local base_name output_file

  [[ -f "$input_file" ]] || die "Downloaded file not found for compression."
  base_name=${input_file##*/}
  base_name=${base_name%.*}
  if [[ -e "./${base_name}.mp4" ]]; then
    output_file=$(next_available_path "${base_name}-compressed" mp4)
  else
    output_file="./${base_name}.mp4"
  fi

  log_info "Compressing video with CRF ${crf}..."
  log_info "  Input:  ${input_file}"
  log_info "  Output: ${output_file}"

  ffmpeg -nostdin -hide_banner -i "$input_file" \
    -map 0:v:0 -map '0:a?' -map_metadata 0 \
    -c:v libx264 -preset slow -crf "$crf" -c:a copy \
    -movflags +faststart -n "$output_file" \
    || die "Compression failed."

  printf -v "$output_var" '%s' "$output_file"
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

  if [[ ! "$upload_date" =~ ^[0-9]{8}$ ]]; then
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
  touch -t "${upload_date}0000" "$file_to_touch"
}

run_yt_dlp() {
  log_info "Executing: $(quote_command yt-dlp "$@")"
  printf '\n'
  yt-dlp "$@" || die "yt-dlp download failed."
  log_success "Download completed."
}

download_media() {
  local output_tmpl=$1
  local path_file_var=$2
  local path_file
  local -a download_args=()
  shift 2

  path_file=$(make_temp_file)
  download_args=("$@" --output "$output_tmpl" --print-to-file after_move:filepath "$path_file" "$url" "${passthrough[@]}")
  run_yt_dlp "${download_args[@]}"
  printf -v "$path_file_var" '%s' "$path_file"
}

main() {
  local format url time_range=''
  local compress=false
  local browser_cookie_mode=auto
  local crf=26
  local -a passthrough=()
  local -a cookie_args=()
  local -a args=()
  local base_format is_cut=false
  local metadata duration upload_date
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

  is_valid_format "$format" \
    || die "Invalid format '$format'. Must be one of: mp4, mp3, m4a, mp4-cut, mp3-cut, m4a-cut."

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
        is_valid_crf "$crf" || die "Invalid --crf value '$crf'. Expected an integer from 0 to 51."
        shift 2
        ;;
      --crf=*)
        crf=${1#*=}
        is_valid_crf "$crf" || die "Invalid --crf value '$crf'. Expected an integer from 0 to 51."
        shift
        ;;
      --no-browser-cookies)
        browser_cookie_mode=none
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
        if [[ -z "$time_range" && "$format" == *-cut ]]; then
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

  [[ "$format" == *-cut ]] && is_cut=true
  if [[ "$is_cut" == true && -z "$time_range" ]]; then
    die "Missing time range for a '-cut' format."
  fi

  base_format=${format%-cut}
  if [[ "$compress" == true && "$base_format" != mp4 ]]; then
    die "--compress is only supported for mp4 formats."
  fi

  log_info "Using yt-dlp: $(command -v yt-dlp)"
  log_info "Fetching video metadata..."
  select_metadata_and_browser_cookies "$url" "$browser_cookie_mode"
  metadata=$METADATA
  if [[ -n "$METADATA_COOKIE_SPEC" ]]; then
    cookie_args=(--cookies-from-browser "$METADATA_COOKIE_SPEC")
  fi

  duration=$(jq -r '.duration // empty' <<<"$metadata") \
    || die "Failed to read video duration from metadata."
  upload_date=$(jq -r '.upload_date // empty' <<<"$metadata") \
    || die "Failed to read upload date from metadata."

  if [[ -n "$time_range" ]]; then
    validate_time_range "$time_range" "$duration"
  fi

  args=(--ignore-config --no-playlist --mtime --trim-filenames 220 "${cookie_args[@]}")
  case "$base_format" in
    m4a)
      args+=(--extract-audio --audio-format m4a --audio-quality 0 --embed-thumbnail)
      ;;
    mp3)
      args+=(--extract-audio --audio-format mp3 --audio-quality 0 --embed-thumbnail)
      ;;
    mp4)
      args+=(
        --format 'bestvideo[ext=mp4][height<=1080]+bestaudio[ext=m4a]/best[ext=mp4]/best'
        --format-sort 'vcodec:h264,acodec:aac,res:1080'
        --merge-output-format mp4
        --remux-video mp4
      )
      ;;
  esac

  args+=(--embed-metadata --console-title)

  if [[ -n "$time_range" ]]; then
    args+=(--download-sections "*${time_range}" --force-keyframes-at-cuts)
    time_suffix="-${time_range//:/_}"
  fi

  if [[ "$compress" == true ]]; then
    temp_dir=$(make_temp_dir)
    output_tmpl="${temp_dir}/%(display_id)s.%(ext)s"
    download_media "$output_tmpl" downloaded_paths "${args[@]}"

    downloaded_path=$(first_recorded_path "$downloaded_paths") \
      || downloaded_path=$(first_downloaded_file "$temp_dir") \
      || die "Downloaded file not found for compression."
    compress_video "$downloaded_path" "$crf" compressed_path
  else
    output_tmpl="%(display_id)s${time_suffix}.%(ext)s"
    download_media "$output_tmpl" downloaded_paths "${args[@]}"
    downloaded_path=$(first_recorded_path "$downloaded_paths" || true)
  fi

  change_file_date "$upload_date" "${compressed_path:-$downloaded_path}"
  log_success "All operations completed successfully."
}

main "$@"
