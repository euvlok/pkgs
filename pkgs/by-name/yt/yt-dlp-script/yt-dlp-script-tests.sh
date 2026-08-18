#!/usr/bin/env bash
# shellcheck shell=bash

set -Eeuo pipefail

# The script path is supplied by package.nix.
# shellcheck disable=SC1090
source "$1"

fail_test() {
  printf 'test failed: %s\n' "$*" >&2
  exit 1
}

assert_equals() {
  local expected=$1
  local actual=$2
  local context=$3

  [[ "$actual" == "$expected" ]] \
    || fail_test "$context: expected '$expected', got '$actual'"
}

assert_file_has_line() {
  local expected=$1
  local file=$2
  local line

  while IFS= read -r line; do
    [[ "$line" == "$expected" ]] && return 0
  done <"$file"
  fail_test "expected '$file' to contain argument '$expected'"
}

assert_file_lacks_line() {
  local unexpected=$1
  local file=$2
  local line

  while IFS= read -r line; do
    [[ "$line" != "$unexpected" ]] || fail_test "did not expect '$file' to contain argument '$unexpected'"
  done <"$file"
}

write_mock_metadata() {
  local arg previous=''

  for arg in "$@"; do
    if [[ "$previous" == "${METADATA_PRINT_WHEN}:${METADATA_PRINT_TEMPLATE}" ]]; then
      printf '%s\n' '{"duration": 60, "upload_date": "20260101"}' >"$arg"
      return 0
    fi
    previous=$arg
  done
  return 1
}

test_format_declarations() {
  local spec format base_format requires_time_range supports_compression force_precise_cuts
  local -a format_args=()

  assert_equals \
    'mp4, mp3, m4a, mp4-cut, mp3-cut, m4a-cut' \
    "$(supported_formats)" \
    'supported format list'

  read_format_spec mp4-cut base_format requires_time_range supports_compression force_precise_cuts \
    || fail_test "mp4-cut format declaration was not found"
  assert_equals mp4 "$base_format" 'mp4-cut base format'
  assert_equals true "$requires_time_range" 'mp4-cut time-range policy'
  assert_equals true "$supports_compression" 'mp4-cut compression policy'
  assert_equals true "$force_precise_cuts" 'mp4-cut precision policy'

  read_format_spec mp3-cut base_format requires_time_range supports_compression force_precise_cuts \
    || fail_test "mp3-cut format declaration was not found"
  assert_equals false "$force_precise_cuts" 'mp3-cut precision policy'

  format_args=()
  append_format_args format_args mp4
  assert_equals \
    "--preset-alias|mp4|--format-sort|res:${MAX_VIDEO_HEIGHT}" \
    "$(join_by '|' "${format_args[@]}")" \
    'mp4 yt-dlp arguments'

  format_args=()
  append_format_args format_args mp3
  assert_equals \
    "--preset-alias|mp3|--audio-quality|${AUDIO_QUALITY}|--embed-thumbnail" \
    "$(join_by '|' "${format_args[@]}")" \
    'mp3 yt-dlp arguments'

  format_args=()
  append_format_args format_args m4a
  assert_equals \
    "--format|ba[acodec^=mp4a]/ba/b|--extract-audio|--audio-format|m4a|--audio-quality|${AUDIO_QUALITY}|--embed-thumbnail" \
    "$(join_by '|' "${format_args[@]}")" \
    'm4a yt-dlp arguments'

  if read_format_spec unknown-format base_format requires_time_range supports_compression force_precise_cuts; then
    fail_test "unknown format unexpectedly had a declaration"
  fi

  for spec in "${FORMAT_SPECS[@]}"; do
    IFS=$'\t' read -r \
      format base_format requires_time_range supports_compression force_precise_cuts <<<"$spec"
    [[ -n "$format" && -n "$base_format" ]] || fail_test "incomplete format declaration: $spec"
    [[ "$requires_time_range" == true || "$requires_time_range" == false ]] \
      || fail_test "invalid time-range policy in format declaration: $spec"
    [[ "$supports_compression" == true || "$supports_compression" == false ]] \
      || fail_test "invalid compression policy in format declaration: $spec"
    [[ "$force_precise_cuts" == true || "$force_precise_cuts" == false ]] \
      || fail_test "invalid precise-cut policy in format declaration: $spec"
    format_args=()
    append_format_args format_args "$base_format"
    ((${#format_args[@]} > 0)) || fail_test "$base_format has no declared yt-dlp arguments"
  done
}

test_browser_declaration_schema() {
  local spec root_key browser label relative_path
  local -A declared_browsers=()
  local -a expected_browsers=(brave chrome chromium edge firefox opera safari vivaldi)

  for spec in "${BROWSER_PROFILE_SPECS[@]}"; do
    IFS=$'\t' read -r root_key browser label relative_path <<<"$spec"
    [[ -n "$root_key" && -n "$browser" && -n "$label" && -n "$relative_path" ]] \
      || fail_test "incomplete browser profile declaration: $spec"
    [[ "$root_key" == config || "$root_key" == home ]] \
      || fail_test "invalid browser root key in declaration: $spec"
    declared_browsers[$browser]=1
  done

  for browser in "${expected_browsers[@]}"; do
    [[ -n "${declared_browsers[$browser]+x}" ]] \
      || fail_test "supported yt-dlp browser '$browser' is missing from auto-discovery"
  done
}

test_temp_path_cleanup() {
  local temp_file temp_dir

  make_temp_file temp_file
  make_temp_dir temp_dir

  [[ -f "$temp_file" ]] || fail_test "temporary file was not created"
  [[ -d "$temp_dir" ]] || fail_test "temporary directory was not created"
  ((${#TEMP_PATHS[@]} == 2)) || fail_test "temporary paths were not registered for cleanup"

  cleanup_temp_paths
  [[ ! -e "$temp_file" ]] || fail_test "temporary file was not removed"
  [[ ! -e "$temp_dir" ]] || fail_test "temporary directory was not removed"
  TEMP_PATHS=()
}

test_cookie_discovery_is_bounded() {
  local test_home browser_root discovery_output

  make_temp_dir test_home
  mkdir -p "$test_home/Library/Application Support"
  browser_root="$test_home/.config/chromium"
  mkdir -p "$browser_root"

  find() {
    printf 'cookie discovery called find unexpectedly\n' >&2
    return 1
  }

  discovery_output=$(HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" discover_browser_cookie_candidates 2>&1)
  [[ "$discovery_output" != *"called find unexpectedly"* ]] \
    || fail_test "cookie discovery performed an unbounded filesystem search"
  [[ "$discovery_output" == *$'chromium\tChromium'* ]] \
    || fail_test "cookie discovery did not find an installed Chromium browser"
}

test_auto_cookie_fallback() {
  # metadata and passthrough are populated/read through namerefs in the sourced script.
  # shellcheck disable=SC2034
  local test_home call_log metadata cookie_spec
  # shellcheck disable=SC2034
  local -a passthrough=()

  make_temp_dir test_home
  mkdir -p "$test_home/.config/google-chrome"
  call_log="$test_home/cookie-attempts"
  export YT_DLP_TEST_COOKIE_LOG=$call_log

  # shellcheck disable=SC2329
  yt-dlp() {
    local arg previous='' selected_cookie_spec=''

    for arg in "$@"; do
      if [[ "$previous" == --cookies-from-browser ]]; then
        selected_cookie_spec=$arg
      fi
      previous=$arg
    done
    printf '%s\n' "${selected_cookie_spec:-anonymous}" >>"$YT_DLP_TEST_COOKIE_LOG"

    if [[ -z "$selected_cookie_spec" ]]; then
      printf 'authentication required\n' >&2
      return 1
    fi
    write_mock_metadata "$@" || fail_test "metadata invocation omitted its private output file"
  }

  HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" \
    select_metadata_and_browser_cookies \
    'https://example.invalid/video' auto passthrough metadata cookie_spec >/dev/null

  assert_equals chrome "$cookie_spec" 'auto-selected yt-dlp browser specification'
  assert_file_has_line anonymous "$call_log"
  assert_file_has_line chrome "$call_log"
}

test_metadata_output_is_isolated() {
  # metadata, fetch_error, and passthrough are populated/read through namerefs.
  # shellcheck disable=SC2034
  local metadata fetch_error
  # shellcheck disable=SC2034
  local -a passthrough=(--print title --dump-json)

  # shellcheck disable=SC2329
  yt-dlp() {
    write_mock_metadata "$@" || fail_test "metadata invocation omitted its private output file"
    printf '%s\n' 'user-requested title output' '{"unrelated": "dump-json output"}'
  }

  fetch_metadata_with_cookie_spec \
    'https://example.invalid/video' '' passthrough metadata fetch_error

  assert_equals \
    '{"duration": 60, "upload_date": "20260101"}' \
    "$metadata" \
    'metadata isolated from user-requested stdout'
}

test_time_range_parsing() {
  local start end

  split_time_range -20 start end || fail_test "open-start range was rejected"
  assert_equals 0 "$start" 'open-start range start'
  assert_equals 20 "$end" 'open-start range end'

  split_time_range 10- start end || fail_test "open-end range was rejected"
  assert_equals 10 "$start" 'open-end range start'
  assert_equals inf "$end" 'open-end range end'

  split_time_range 10-infinite start end || fail_test "infinite range end was rejected"
  assert_equals inf "$end" 'infinite range normalization'

  split_time_range --5 start end || fail_test "negative open-start range end was rejected"
  assert_equals 0 "$start" 'negative open-start range start'
  assert_equals -5 "$end" 'negative open-start range end'

  validate_time_range -10- 60
  validate_time_range --5 60

  if (validate_time_range - 60) >/dev/null 2>&1; then
    fail_test "empty time range unexpectedly passed validation"
  fi
  if (validate_time_range inf-20 60) >/dev/null 2>&1; then
    fail_test "infinite start unexpectedly passed validation"
  fi
  if (validate_time_range 70- 60) >/dev/null 2>&1; then
    fail_test "out-of-bounds open-ended range unexpectedly passed validation"
  fi
}

test_main_assembles_declared_arguments() {
  local work_dir argument_log

  make_temp_dir work_dir
  argument_log="$work_dir/yt-dlp-arguments"
  export YT_DLP_TEST_ARGUMENT_LOG=$argument_log

  # shellcheck disable=SC2329
  yt-dlp() {
    local arg previous='' path_file='' argument_count
    local metadata_query=false
    local -a invoked_args=("$@")

    argument_count=${#invoked_args[@]}
    ((argument_count >= 2)) || fail_test "yt-dlp invocation omitted the URL boundary"
    assert_equals -- "${invoked_args[argument_count - 2]}" 'yt-dlp URL option terminator'
    assert_equals \
      'https://example.invalid/video' \
      "${invoked_args[argument_count - 1]}" \
      'yt-dlp final URL argument'

    printf '%s\n' "$@" >>"$YT_DLP_TEST_ARGUMENT_LOG"
    for arg in "$@"; do
      [[ "$arg" == "${METADATA_PRINT_WHEN}:${METADATA_PRINT_TEMPLATE}" ]] && metadata_query=true
      if [[ "$previous" == after_move:filepath ]]; then
        path_file=$arg
      fi
      previous=$arg
    done

    if [[ "$metadata_query" == true ]]; then
      write_mock_metadata "$@" || fail_test "metadata invocation omitted its private output file"
      return 0
    fi

    [[ -n "$path_file" ]] || fail_test "download invocation omitted --print-to-file path"
    touch "$PWD/downloaded.mp4"
    printf '%s\n' "$PWD/downloaded.mp4" >"$path_file"
  }

  (
    cd "$work_dir"
    main mp4 'https://example.invalid/video' --no-browser-cookies -- --retries 7
  ) >/dev/null

  assert_file_has_line --trim-filenames "$argument_log"
  assert_file_has_line "$MAX_FILENAME_LENGTH" "$argument_log"
  assert_file_has_line --preset-alias "$argument_log"
  assert_file_has_line mp4 "$argument_log"
  assert_file_has_line "res:${MAX_VIDEO_HEIGHT}" "$argument_log"
  assert_file_has_line --no-simulate "$argument_log"
  assert_file_has_line --simulate "$argument_log"
  assert_file_has_line "${METADATA_PRINT_WHEN}:${METADATA_PRINT_TEMPLATE}" "$argument_log"
  assert_file_has_line --retries "$argument_log"
  assert_file_has_line 7 "$argument_log"
  assert_file_lacks_line --dump-json "$argument_log"
  assert_file_lacks_line --mtime "$argument_log"
  [[ -f "$work_dir/downloaded.mp4" ]] || fail_test "mock download did not produce its recorded output"
}

test_cut_precision_assembly() {
  local audio_dir audio_log video_dir video_log

  yt-dlp() {
    local arg previous='' path_file=''
    local metadata_query=false

    printf '%s\n' "$@" >>"$YT_DLP_TEST_ARGUMENT_LOG"
    for arg in "$@"; do
      [[ "$arg" == "${METADATA_PRINT_WHEN}:${METADATA_PRINT_TEMPLATE}" ]] && metadata_query=true
      if [[ "$previous" == after_move:filepath ]]; then
        path_file=$arg
      fi
      previous=$arg
    done

    if [[ "$metadata_query" == true ]]; then
      write_mock_metadata "$@" || fail_test "metadata invocation omitted its private output file"
      return 0
    fi

    [[ -n "$path_file" ]] || fail_test "cut download omitted --print-to-file path"
    touch "$PWD/downloaded.media"
    printf '%s\n' "$PWD/downloaded.media" >"$path_file"
  }

  make_temp_dir audio_dir
  audio_log="$audio_dir/yt-dlp-arguments"
  export YT_DLP_TEST_ARGUMENT_LOG=$audio_log
  (
    cd "$audio_dir"
    main mp3-cut 'https://example.invalid/audio' 5-10 --no-browser-cookies
  ) >/dev/null
  assert_file_has_line '*5-10' "$audio_log"
  assert_file_lacks_line --force-keyframes-at-cuts "$audio_log"

  make_temp_dir video_dir
  video_log="$video_dir/yt-dlp-arguments"
  export YT_DLP_TEST_ARGUMENT_LOG=$video_log
  (
    cd "$video_dir"
    main mp4-cut 'https://example.invalid/video' 5-10 --no-browser-cookies
  ) >/dev/null
  assert_file_has_line '*5-10' "$video_log"
  assert_file_has_line --force-keyframes-at-cuts "$video_log"
}

test_format_declarations
test_browser_declaration_schema
test_temp_path_cleanup
test_cookie_discovery_is_bounded
test_auto_cookie_fallback
test_metadata_output_is_isolated
test_time_range_parsing
test_main_assembles_declared_arguments
test_cut_precision_assembly
