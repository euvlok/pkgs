#!/usr/bin/env nix-shell
#!nix-shell -i bash -p jq nix-update
# shellcheck shell=bash
#
# Author: FlameFlag
#
#/ Usage: SCRIPTNAME [OPTIONS]... <nix-file>
#/
#/ OPTIONS
#/   -h, --help
#/                Print this help message.
#/   --version <version>
#/                Specify version for nix-update (default: branch).
#/
#/ EXAMPLES
#/   # Update a by-name package using default branch version
#/   SCRIPTNAME pkgs/by-name/yt/yt-dlp/package.nix
#/
#/   # Update a by-name package to a specific version
#/   SCRIPTNAME --version "1.1.0" pkgs/by-name/yt/yt-dlp/package.nix

set -euo pipefail

#{{{ Variables

# Split on newlines and tabs, not spaces.
IFS=$'\t\n'

script_name=$(basename "${0}")
readonly script_name

readonly TEMP_WRAPPER="temp-wrapper.nix"

VERSION="branch"
NIX_FILE=""
ABS_NIX_FILE=""
OWNER=""
REPO=""
HAS_UPDATE_SCRIPT=""
#}}}

main() {
	printf "::group::%s\n" "Package update: ${NIX_FILE:-unknown}"
	parse_arguments "${@}"
	validate_arguments
	extract_metadata
	update_package

	log_success "Package update completed successfully!"
	printf "::endgroup::\n"
}

#{{{ Helper functions
log_error() {
	printf "::error::%s\n" "$*" >&2
}
log_info() {
	printf "::debug::%s\n" "$*"
}
log_notice() {
	printf "::notice::%s\n" "$*"
}
log_success() {
	printf "::notice::%s\n" "$*"
}
log_warning() {
	printf "::warning::%s\n" "$*"
}

show_help() {
	grep '^#/' <"${BASH_SOURCE[0]}" | cut -c4- | sed "s/SCRIPTNAME/${script_name}/g"
}

cleanup() {
	if [[ -f "${TEMP_WRAPPER}" ]]; then
		rm -f "${TEMP_WRAPPER}"
		log_info "Cleaned up temporary wrapper file."
	fi
}

parse_arguments() {
	while [[ $# -gt 0 ]]; do
		case "${1}" in
		-h | --help)
			show_help
			exit 0
			;;
		--version)
			# Use ${2-} to avoid unbound variable error in strict mode
			if [[ -z "${2-}" ]]; then
				log_error "--version requires a value."
				show_help
				exit 1
			fi
			VERSION="${2}"
			shift 2
			;;
		-*)
			log_error "Unknown option: ${1}"
			show_help
			exit 1
			;;
		*)
			if [[ -z "${NIX_FILE}" ]]; then
				NIX_FILE="${1}"
			else
				log_error "Unexpected argument: '${1}'. A Nix file has already been provided."
				show_help
				exit 1
			fi
			shift
			;;
		esac
	done
}

validate_arguments() {
	if [[ -z "${NIX_FILE}" ]]; then
		log_error "Missing Nix file argument."
		show_help
		exit 1
	fi

	local abs_path
	abs_path=$(realpath "${NIX_FILE}")
	ABS_NIX_FILE="${abs_path}"

	if [[ ! -f "${ABS_NIX_FILE}" ]]; then
		log_error "File '${NIX_FILE}' does not exist."
		printf "::error file=%s::File does not exist\n" "${NIX_FILE}"
		exit 1
	fi
}

extract_metadata() {
	log_info "Checking for updateScript in '${ABS_NIX_FILE}'..."

	local temp_eval_wrapper
	temp_eval_wrapper="temp-wrapper.nix"

	cat >"${temp_eval_wrapper}" <<EOF
let pkgs = import <nixpkgs> {}; in (pkgs.callPackage ${ABS_NIX_FILE} {})
EOF

	_cleanup_eval() {
		if [[ -f "${temp_eval_wrapper}" ]]; then
			rm -f "${temp_eval_wrapper}"
		fi
	}

	trap _cleanup_eval EXIT

	local update_check
	update_check=$(nix eval --impure --expr "(import ./temp-wrapper.nix).passthru.updateScript or null" 2>/dev/null || echo "null")

	if [[ "${update_check}" != "null" ]]; then
		local update_type
		update_type=$(nix eval --impure --expr "builtins.typeOf (import ./temp-wrapper.nix).passthru.updateScript" --raw 2>/dev/null || echo "")

		if [[ "${update_type}" == "string" ]] || [[ "${update_type}" == "path" ]]; then
			HAS_UPDATE_SCRIPT="true"
			log_info "Found custom passthru.updateScript (${update_type}) in package"

			OWNER=$(nix eval --impure --expr "(import ./temp-wrapper.nix).meta.homepage or \"\"" --raw 2>/dev/null | sed -E 's|https://github.com/([^/]+)/([^/]+).*|\1|' || echo "")
			REPO=$(nix eval --impure --expr "(import ./temp-wrapper.nix).meta.homepage or \"\"" --raw 2>/dev/null | sed -E 's|https://github.com/([^/]+)/([^/]+).*|\2|' || echo "")

			if [[ -z "${OWNER}" ]] || [[ -z "${REPO}" ]]; then
				OWNER="unknown"
				REPO="unknown"
			fi
		else
			log_info "Found passthru.updateScript but it's type is '${update_type}', falling back to nix-update"
		fi
	fi

	if [[ "${HAS_UPDATE_SCRIPT}" != "true" ]]; then
		log_info "Extracting owner and repo..."

		OWNER=$(nix eval --impure --expr "(import ./temp-wrapper.nix).src.owner" --raw 2>/dev/null || echo "")
		REPO=$(nix eval --impure --expr "(import ./temp-wrapper.nix).src.repo" --raw 2>/dev/null || echo "")

		if [[ -z "${OWNER}" ]] || [[ -z "${REPO}" ]]; then
			log_error "Could not extract owner/repo from '${ABS_NIX_FILE}'."
			log_error "Make sure that file contains 'owner' and 'repo' attributes."
			printf "::error file=%s::Missing 'owner' or 'repo' attributes in source definition\n" "${ABS_NIX_FILE}"
			exit 1
		fi
	fi

	trap - EXIT
	_cleanup_eval

	log_info "Found repository: ${OWNER}/${REPO}"
}

update_package() {
	trap cleanup EXIT

	log_info "Updating '${ABS_NIX_FILE}' for ${OWNER}/${REPO}..."
	printf "::notice file=%s::Updating %s/%s\n" "${ABS_NIX_FILE}" "${OWNER}" "${REPO}"

 	cat >"${TEMP_WRAPPER}" <<EOF
{ pkgs ? import <nixpkgs> {} }:
rec {
  pkg = pkgs.callPackage ${ABS_NIX_FILE} {};
}
EOF

	if [[ "${HAS_UPDATE_SCRIPT}" == "true" ]]; then
		log_info "Executing updateScript..."
		printf "\n"

		local pkg_name
		pkg_name=$(basename "${ABS_NIX_FILE}" .nix)

		cat >"${TEMP_WRAPPER}" <<EOF
{ pkgs ? import <nixpkgs> {} }:
let
  pkg = pkgs.callPackage ${ABS_NIX_FILE} {};
in pkgs.writeShellScriptBin "${pkg_name}-update-script" (builtins.readFile pkg.passthru.updateScript)
EOF

		local update_link="${TEMP_DIR:-/tmp}/update-script-result"
		rm -rf "${update_link}"

		if ! nix build --impure --file ./"${TEMP_WRAPPER}" --out-link "${update_link}" --print-build-logs; then
			log_error "Failed to build updateScript"
			printf "::error file=%s::Failed to build updateScript for %s/%s\n" "${ABS_NIX_FILE}" "${OWNER}" "${REPO}"
			exit 1
		fi

		local bin_dir="${update_link}/bin"
		local update_script_binary

		update_script_binary=$(find "$bin_dir" -maxdepth 1 -type f -executable 2>/dev/null | head -n 1)

		if [[ -z "${update_script_binary}" ]]; then
			log_error "No executable found in ${bin_dir}"
			printf "::error file=%s::No executable found in update script build output\n" "${ABS_NIX_FILE}"
			exit 1
		fi

		if ! UPDATE_FILE="${ABS_NIX_FILE}" "${update_script_binary}"; then
			log_error "updateScript failed"
			printf "::error file=%s::updateScript failed for %s/%s\n" "${ABS_NIX_FILE}" "${OWNER}" "${REPO}"
			exit 1
		fi

		rm -f "${update_link}"
	else
		cat >"${TEMP_WRAPPER}" <<EOF
{ pkgs ? import <nixpkgs> {} }:
rec {
  pkg = pkgs.callPackage ${ABS_NIX_FILE} {};
}
EOF

		log_info "Executing nix-update with version '${VERSION}'..."
		printf "\n"

		if ! nix-update --version="${VERSION}" \
			-f ./"${TEMP_WRAPPER}" \
			--override-filename "${ABS_NIX_FILE}" \
			"pkg"; then
			log_error "nix-update failed"
			printf "::error file=%s::nix-update failed for %s/%s\n" "${ABS_NIX_FILE}" "${OWNER}" "${REPO}"
			exit 1
		fi
	fi

	local pkg_name
	pkg_name=$(basename "${ABS_NIX_FILE}" .nix)
	if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
		printf "### %s\n" "${pkg_name}" >> "${GITHUB_STEP_SUMMARY}"
		printf -- "- Repository: \`%s/%s\`\n" "${OWNER}" "${REPO}" >> "${GITHUB_STEP_SUMMARY}"
		if [[ "${HAS_UPDATE_SCRIPT}" != "true" ]]; then
			printf -- "- Version: \`%s\`\n" "${VERSION}" >> "${GITHUB_STEP_SUMMARY}"
		fi
		printf -- "- File: \`%s\`\n" "${ABS_NIX_FILE}" >> "${GITHUB_STEP_SUMMARY}"
	fi
}

#}}}

main "${@}"
