#!/usr/bin/env nu

def log_error [msg: string] { print -e $"(ansi red_bold)[error](ansi reset) ($msg)" }
def log_info [msg: string] { print $"(ansi blue_bold)[info](ansi reset) ($msg)" }
def log_success [msg: string] { print $"(ansi green_bold)[success](ansi reset) ($msg)" }
def log_warning [msg: string] { print -e $"(ansi yellow_bold)[warning](ansi reset) ($msg)" }

def fail [msg: string] {
    log_error $msg
    error make --unspanned { msg: $msg }
}

def is_valid_format [format: string] {
    $format in [mp4 mp3 m4a mp4-cut mp3-cut m4a-cut]
}

def is_valid_crf [crf: int] {
    $crf >= 0 and $crf <= 51
}

def path_has_cookie_db [profile: string] {
    ([($profile | path join "Cookies") ($profile | path join "Network" "Cookies")]
        | any {|path| $path | path exists })
}

def cookie_db_mtime [profile: string] {
    let network_cookies = ($profile | path join "Network" "Cookies")
    let cookies = ($profile | path join "Cookies")
    let cookie_db = if ($network_cookies | path exists) {
        $network_cookies
    } else if ($cookies | path exists) {
        $cookies
    } else {
        return null
    }

    let run = (^stat -c "%Y" $cookie_db | complete)
    if $run.exit_code == 0 {
        $run.stdout | str trim | into int
    } else {
        null
    }
}

def find_cookie_files [user_data_dir: string] {
    if not ($user_data_dir | path exists) {
        return []
    }

    let run = (^find $user_data_dir -maxdepth 3 -type f "(" -path "*/Network/Cookies" "-o" "-name" "Cookies" ")" -print0 | complete)
    if $run.exit_code != 0 {
        return []
    }

    $run.stdout
        | split row (char nul)
        | where {|path| not ($path | is-empty) }
        | sort
}

def list_cookie_profiles_in_user_data_dir [user_data_dir: string] {
    if not ($user_data_dir | path exists) {
        return []
    }

    let direct = if (path_has_cookie_db $user_data_dir) { [$user_data_dir] } else { [] }
    let default_profile = ($user_data_dir | path join "Default")
    let named_profiles = ([$default_profile] ++ (glob ($user_data_dir | path join "Profile *")))
        | where {|profile| ($profile | path type) == "dir" and (path_has_cookie_db $profile) }

    let discovered_profiles = (find_cookie_files $user_data_dir)
        | each {|cookie_file|
            let parent = ($cookie_file | path dirname)
            if ($parent | path basename) == "Network" {
                $parent | path dirname
            } else {
                $parent
            }
        }

    ($direct ++ $named_profiles ++ $discovered_profiles) | uniq
}

def browser_cookie_profiles [browser: string, label: string, user_data_dir: string] {
    list_cookie_profiles_in_user_data_dir $user_data_dir
        | each {|profile|
            let mtime = (cookie_db_mtime $profile)
            if $mtime == null {
                null
            } else {
                {
                    mtime: $mtime
                    cookie_spec: $"($browser):($profile)"
                    cookie_label: $"($label) (($profile))"
                }
            }
        }
        | where {|candidate| $candidate != null }
}

def generic_chromium_cookie_profiles [search_root: string] {
    if not ($search_root | path exists) {
        return []
    }

    let run = (^find $search_root -maxdepth 3 -type f -name "Local State" -print0 | complete)
    if $run.exit_code != 0 {
        return []
    }

    $run.stdout
        | split row (char nul)
        | where {|path| not ($path | is-empty) }
        | sort
        | each {|local_state|
            browser_cookie_profiles chromium "Chromium-compatible profile" ($local_state | path dirname)
        }
        | flatten
}

def discover_browser_cookie_candidates [] {
    let xdg_config_home = ($env.XDG_CONFIG_HOME? | default "")
    let home = ($env.HOME? | default "")
    let config_home = if not ($xdg_config_home | is-empty) {
        $xdg_config_home
    } else if not ($home | is-empty) {
        $home | path join ".config"
    } else {
        ""
    }

    mut candidates = []

    if not ($config_home | is-empty) {
        $candidates = ($candidates
            ++ (browser_cookie_profiles chromium "Chromium" ($config_home | path join "chromium"))
            ++ (browser_cookie_profiles chrome "Google Chrome" ($config_home | path join "google-chrome"))
            ++ (browser_cookie_profiles brave "Brave" ($config_home | path join "BraveSoftware" "Brave-Browser"))
            ++ (browser_cookie_profiles edge "Microsoft Edge" ($config_home | path join "microsoft-edge"))
            ++ (browser_cookie_profiles vivaldi "Vivaldi" ($config_home | path join "vivaldi"))
            ++ (browser_cookie_profiles opera "Opera" ($config_home | path join "opera"))
            ++ (generic_chromium_cookie_profiles $config_home))
    }

    if not ($home | is-empty) {
        let app_support = ($home | path join "Library" "Application Support")
        $candidates = ($candidates
            ++ (browser_cookie_profiles chrome "Google Chrome" ($app_support | path join "Google" "Chrome"))
            ++ (browser_cookie_profiles brave "Brave" ($app_support | path join "BraveSoftware" "Brave-Browser"))
            ++ (browser_cookie_profiles edge "Microsoft Edge" ($app_support | path join "Microsoft Edge"))
            ++ (browser_cookie_profiles vivaldi "Vivaldi" ($app_support | path join "Vivaldi"))
            ++ (generic_chromium_cookie_profiles $app_support))
    }

    $candidates | sort-by --reverse mtime
}

def passthrough_has_cookie_option [passthrough: list<string>] {
    $passthrough | any {|arg|
        ($arg in [--cookies --no-cookies --cookies-from-browser --no-cookies-from-browser]) or ($arg | str starts-with "--cookies=") or ($arg | str starts-with "--cookies-from-browser=")
    }
}

def fetch_metadata_with_cookie_spec [url: string, cookie_spec: string, passthrough: list<string>] {
    mut args = [--ignore-config --no-playlist]

    if not ($cookie_spec | is-empty) {
        $args = ($args ++ [--cookies-from-browser $cookie_spec])
    }

    $args = ($args ++ [--dump-json $url] ++ $passthrough)

    let run = (^yt-dlp ...$args | complete)
    if $run.exit_code == 0 {
        let metadata = try {
            $run.stdout | from json
        } catch {
            fail "yt-dlp returned invalid metadata JSON."
        }

        {
            ok: true
            metadata: $metadata
            error: ""
        }
    } else {
        {
            ok: false
            metadata: null
            error: ($run.stderr | lines | first 3 | str join (char nl))
        }
    }
}

def metadata_score [metadata: record, has_cookies: bool] {
    (((($metadata.formats? | default []) | length) * 100) + (if $has_cookies { 1 } else { 0 }))
}

def select_metadata_and_browser_cookies [url: string, browser_cookie_mode: string, passthrough: list<string>] {
    if (passthrough_has_cookie_option $passthrough) {
        log_info "yt-dlp cookie option supplied; not auto-selecting browser cookies."
        let result = (fetch_metadata_with_cookie_spec $url "" $passthrough)
        if not $result.ok {
            fail "Failed to fetch video metadata."
        }

        return { metadata: $result.metadata, cookie_spec: "", cookie_label: "" }
    }

    if $browser_cookie_mode == "none" {
        log_info "Browser cookies disabled by flag."
        let result = (fetch_metadata_with_cookie_spec $url "" $passthrough)
        if not $result.ok {
            fail "Failed to fetch video metadata."
        }

        return { metadata: $result.metadata, cookie_spec: "", cookie_label: "" }
    }

    if $browser_cookie_mode != "auto" {
        log_info $"Preferring browser cookies from: ($browser_cookie_mode)"
        let result = (fetch_metadata_with_cookie_spec $url $browser_cookie_mode $passthrough)
        if not $result.ok {
            fail $"Failed to fetch video metadata with browser cookies '($browser_cookie_mode)'."
        }

        return { metadata: $result.metadata, cookie_spec: $browser_cookie_mode, cookie_label: $browser_cookie_mode }
    }

    mut best = { score: -1, metadata: null, cookie_spec: "", cookie_label: "" }
    mut tried_browser_cookies = false
    mut seen_cookie_specs = []

    for candidate in (discover_browser_cookie_candidates) {
        if ($candidate.cookie_spec | is-empty) or ($candidate.cookie_spec in $seen_cookie_specs) {
            continue
        }

        $seen_cookie_specs = ($seen_cookie_specs ++ [$candidate.cookie_spec])
        $tried_browser_cookies = true

        let result = (fetch_metadata_with_cookie_spec $url $candidate.cookie_spec $passthrough)
        if $result.ok {
            let score = ((metadata_score $result.metadata true) + (($candidate.mtime / 1000000000) | math floor))
            if $score > $best.score {
                $best = {
                    score: $score
                    metadata: $result.metadata
                    cookie_spec: $candidate.cookie_spec
                    cookie_label: $candidate.cookie_label
                }
            }
        } else {
            log_warning $"Browser cookies from ($candidate.cookie_label) did not work for this URL; trying the next candidate."
            if not ($result.error | is-empty) {
                log_warning $result.error
            }
        }
    }

    if $best.score < 0 {
        let result = (fetch_metadata_with_cookie_spec $url "" $passthrough)
        if not $result.ok {
            fail "Failed to fetch video metadata."
        }

        $best = {
            score: (metadata_score $result.metadata false)
            metadata: $result.metadata
            cookie_spec: ""
            cookie_label: ""
        }
    }

    if not ($best.cookie_spec | is-empty) {
        log_info $"Preferring browser cookies from: ($best.cookie_label)"
    } else if $tried_browser_cookies {
        log_info "Continuing without browser cookies; anonymous extraction worked best for this URL."
    } else {
        log_info "No browser cookie database found. Continuing without browser cookies."
    }

    { metadata: $best.metadata, cookie_spec: $best.cookie_spec, cookie_label: $best.cookie_label }
}

def parse_time_ms [value: string] {
    if ($value | is-empty) {
        fail "Invalid empty time value."
    }

    let parts = ($value | split row ":")
    if (($parts | length) < 1) or (($parts | length) > 3) {
        fail $"Invalid time value '($value)'."
    }

    let last_index = (($parts | length) - 1)
    let prefix_parts = if $last_index > 0 { $parts | first $last_index } else { [] }
    mut prefix_seconds = 0

    for part in $prefix_parts {
        if not ($part =~ '^[0-9]+$') {
            fail $"Invalid time value '($value)'."
        }

        $prefix_seconds = ($prefix_seconds * 60 + ($part | into int))
    }

    let last = ($parts | last)
    if not ($last =~ '^[0-9]+([.][0-9]+)?$') {
        fail $"Invalid time value '($value)'."
    }

    let last_parts = ($last | split row ".")
    let whole = (($last_parts | get 0) | into int)
    let fraction_ms = if ($last_parts | length) > 1 {
        let fraction = (((($last_parts | get 1) | str substring 0..2) + "000") | str substring 0..2)
        $fraction | into int
    } else {
        0
    }

    ($prefix_seconds * 60000 + $whole * 1000 + $fraction_ms)
}

def split_time_range [range: string] {
    let parsed = ($range | parse --regex '^(?P<start>inf|-?[0-9]+(?::[0-9]+){0,2}(?:[.][0-9]+)?)-(?P<end>inf|-?[0-9]+(?::[0-9]+){0,2}(?:[.][0-9]+)?)$')
    if ($parsed | is-empty) {
        fail $"Invalid time range '($range)'. Expected START-END, for example 30-60."
    }

    $parsed | first
}

def is_time_endpoint [value: string] {
    $value == "inf" or ($value =~ '^-?[0-9]+(:[0-9]+){0,2}([.][0-9]+)?$')
}

def resolve_time_endpoint_ms [value: string, duration_ms: any] {
    if $value == "inf" {
        if $duration_ms == null {
            fail $"Invalid time range end '($value)'. Use seconds, HH:MM:SS, or inf."
        }

        return $duration_ms
    }

    if ($value | str starts-with "-") {
        if $duration_ms == null {
            fail $"Invalid time range start '($value)'. Use seconds or HH:MM:SS."
        }

        return ($duration_ms - (parse_time_ms ($value | str substring 1..)))
    }

    parse_time_ms $value
}

def validate_time_range [range: string, duration: any] {
    let parsed = (split_time_range $range)
    let start = $parsed.start
    let end = $parsed.end

    if $start == "inf" {
        fail $"Invalid time range '($range)'. Start time cannot be inf."
    }

    if not (is_time_endpoint $start) {
        fail $"Invalid time range start '($start)'. Use seconds, HH:MM:SS, or a negative timestamp."
    }

    if not (is_time_endpoint $end) {
        fail $"Invalid time range end '($end)'. Use seconds, HH:MM:SS, inf, or a negative timestamp."
    }

    let duration_text = if $duration == null { "" } else { $duration | into string }
    mut duration_ms = null
    if not ($duration_text | is-empty) {
        $duration_ms = try {
            parse_time_ms $duration_text
        } catch {
            log_warning $"Could not parse video duration '($duration_text)'. Skipping time range bounds validation."
            null
        }
    }

    if ($duration_ms == null) and (($start | str starts-with "-") or ($end | str starts-with "-") or $end == "inf") {
        log_warning "Could not determine video duration. Skipping negative/inf time range validation."
        return
    }

    let start_ms = (resolve_time_endpoint_ms $start $duration_ms)
    let end_ms = (resolve_time_endpoint_ms $end $duration_ms)

    if ($start_ms < 0) or ($end_ms < 0) {
        fail $"Invalid time range '($range)'. Negative timestamps must resolve within the video duration."
    }

    if $start_ms > $end_ms {
        fail $"Invalid time range '($range)'. Start must be less than or equal to end."
    }

    if $duration_ms != null {
        if $end_ms > $duration_ms {
            fail $"Invalid time range '($range)'. Video duration is ($duration_text)s."
        }
    }
}

def quote_arg [arg: string] {
    if $arg =~ '^[A-Za-z0-9_@%+=:,./-]+$' {
        $arg
    } else {
        $arg | to json --raw
    }
}

def quote_command [args: list<string>] {
    $args | each {|arg| quote_arg $arg } | str join " "
}

def first_downloaded_file [directory: string] {
    let files = (glob ($directory | path join "*"))
        | where {|path| ($path | path type) == "file" and not ($path | str ends-with ".part") }
        | sort

    if ($files | is-empty) { null } else { $files | first }
}

def first_recorded_path [path_file: string] {
    if not ($path_file | path exists) {
        return null
    }

    let paths = (open --raw $path_file | lines)
    if ($paths | is-empty) {
        null
    } else {
        let path = ($paths | first)
        if ($path | is-empty) { null } else { $path }
    }
}

def compress_video [input_file: string, crf: int] {
    if not ($input_file | path exists) {
        fail "Downloaded file not found for compression."
    }

    let base_name = ($input_file | path parse | get stem)
    let output_file = $"./($base_name).mp4"

    log_info $"Compressing video with CRF ($crf)..."
    log_info $"  Input:  ($input_file)"
    log_info $"  Output: ($output_file)"

    try {
        ^ffmpeg -nostdin -hide_banner -i $input_file -map 0:v:0 -map "0:a?" -map_metadata 0 -c:v libx264 -preset slow -crf $crf -c:a copy -movflags +faststart -y $output_file
    } catch {
        fail "Compression failed."
    }

    log_success "Compression finished successfully."
    $output_file
}

def change_file_date [upload_date: any, downloaded_path: string] {
    let upload_date_text = if $upload_date == null { "" } else { $upload_date | into string }

    if ($upload_date_text | is-empty) {
        log_warning "Upload date not found. Skipping file date modification."
        return
    }

    if not ($upload_date_text =~ '^[0-9]{8}$') {
        log_warning $"Upload date '($upload_date_text)' is not in YYYYMMDD format. Skipping file date modification."
        return
    }

    if ($downloaded_path | is-empty) or not ($downloaded_path | path exists) {
        log_warning "Could not determine the final media file to modify the date for."
        return
    }

    log_info $"Setting file modification time of '($downloaded_path)' to ($upload_date_text)..."
    ^touch -t $"($upload_date_text)0000" $downloaded_path
}

def run_download [args: list<string>] {
    log_info $"Executing: (quote_command (["yt-dlp"] ++ $args))"
    print ""

    try {
        ^yt-dlp ...$args
    } catch {
        fail "yt-dlp download failed."
    }

    log_success "Download completed."
}

def cleanup_paths [paths: list<string>] {
    let existing = ($paths | where {|path| not ($path | is-empty) and ($path | path exists) })
    if not ($existing | is-empty) {
        ^rm -rf -- ...$existing
    }
}

def --wrapped main [
    format?: string          # Download format: mp4, mp3, m4a, mp4-cut, mp3-cut, m4a-cut
    url?: string             # Video URL
    time_range?: string      # Time range for -cut formats, for example 30-60
    --compress               # Compress mp4 output after downloading
    --crf: int = 26          # CRF value for compression
    --no-browser-cookies     # Disable automatic browser cookie discovery
    --browser-cookies: string # Explicit yt-dlp --cookies-from-browser spec
    ...passthrough: string   # Additional args passed to yt-dlp after --
] {
    if ($format == null) or ($url == null) {
        print "Usage:"
        print "  yt-dlp-script FORMAT URL [TIME_RANGE] [--compress] [--crf CRF] [--no-browser-cookies] [--browser-cookies SPEC] [-- YT_DLP_ARGS...]"
        print ""
        print "Formats:"
        print "  mp4, mp3, m4a, mp4-cut, mp3-cut, m4a-cut"
        exit 2
    }

    if not (is_valid_format $format) {
        fail $"Invalid format '($format)'. Must be one of: mp4, mp3, m4a, mp4-cut, mp3-cut, m4a-cut."
    }

    if not (is_valid_crf $crf) {
        fail $"Invalid --crf value '($crf)'. Expected an integer from 0 to 51."
    }

    let effective_time_range = if $time_range == "--" { null } else { $time_range }

    let is_cut = ($format | str ends-with "-cut")
    if $is_cut and ($effective_time_range == null) {
        fail "Missing time range for a '-cut' format."
    }

    let base_format = if $is_cut { $format | str replace "-cut" "" } else { $format }
    if $compress and $base_format != "mp4" {
        fail "--compress is only supported for mp4 formats."
    }

    let browser_cookie_mode = if ($browser_cookies != null) {
        $browser_cookies
    } else if $no_browser_cookies {
        "none"
    } else {
        "auto"
    }

    log_info $"Using yt-dlp: (which yt-dlp | get path | first)"
    log_info "Fetching video metadata..."
    let selected = (select_metadata_and_browser_cookies $url $browser_cookie_mode $passthrough)
    let metadata = $selected.metadata
    let cookie_args = if not ($selected.cookie_spec | is-empty) {
        [--cookies-from-browser $selected.cookie_spec]
    } else {
        []
    }

    let duration = ($metadata.duration? | default null)
    let upload_date = ($metadata.upload_date? | default "")

    if $effective_time_range != null {
        validate_time_range $effective_time_range $duration
    }

    mut args = [--ignore-config --no-playlist --mtime --trim-filenames "220"]
    $args = ($args ++ $cookie_args)

    match $base_format {
        "m4a" => { $args = ($args ++ [--extract-audio --audio-format m4a --audio-quality "0" --embed-thumbnail]) }
        "mp3" => { $args = ($args ++ [--extract-audio --audio-format mp3 --audio-quality "0" --embed-thumbnail]) }
        "mp4" => {
            $args = ($args ++ [
                --format "bestvideo[ext=mp4][height<=1080]+bestaudio[ext=m4a]/best[ext=mp4]/best"
                --format-sort "vcodec:h264,acodec:aac,res:1080"
                --merge-output-format mp4
                --remux-video mp4
            ])
        }
    }

    $args = ($args ++ [--embed-metadata --console-title])

    mut time_suffix = ""
    if $effective_time_range != null {
        $args = ($args ++ [--download-sections $"*($effective_time_range)" --force-keyframes-at-cuts])
        $time_suffix = $"-($effective_time_range | str replace --all ':' '_')"
    }

    if $compress {
        let temp_dir = (^mktemp -d | str trim)
        let downloaded_paths = (^mktemp | str trim)

        try {
            let output_tmpl = ($temp_dir | path join "%(display_id)s.%(ext)s")
            let download_args = ($args ++ [--output $output_tmpl --print-to-file "after_move:filepath" $downloaded_paths $url] ++ $passthrough)
            run_download $download_args

            let recorded_path = (first_recorded_path $downloaded_paths)
            let downloaded_path = if $recorded_path != null { $recorded_path } else { first_downloaded_file $temp_dir }
            if $downloaded_path == null {
                fail "Downloaded file not found for compression."
            }

            let compressed_path = (compress_video $downloaded_path $crf)
            cleanup_paths [$temp_dir $downloaded_paths]
            change_file_date $upload_date $compressed_path
        } catch {|err|
            cleanup_paths [$temp_dir $downloaded_paths]
            error make --unspanned { msg: $err.msg }
        }
    } else {
        let downloaded_paths = (^mktemp | str trim)

        try {
            let output_tmpl = ("%(display_id)s" + $time_suffix + ".%(ext)s")
            let download_args = ($args ++ [--output $output_tmpl --print-to-file "after_move:filepath" $downloaded_paths $url] ++ $passthrough)
            run_download $download_args

            let downloaded_path = (first_recorded_path $downloaded_paths)
            cleanup_paths [$downloaded_paths]
            change_file_date $upload_date (if $downloaded_path == null { "" } else { $downloaded_path })
        } catch {|err|
            cleanup_paths [$downloaded_paths]
            error make --unspanned { msg: $err.msg }
        }
    }

    log_success "All operations completed successfully."
}
