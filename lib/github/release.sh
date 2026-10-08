# shellcheck shell=sh

GH_RELEASE_FIELDS=tagName,name,body,url,author,isDraft,isPrerelease,createdAt,publishedAt,assets

# gh release view --json and the REST API name the same things differently.
GH_RELEASE_DEF='
def blank_null: if . == "" then null else . end;
def gh_release: {
    tag: .tagName,
    name,
    notes: (.body | blank_null),
    url,
    author: .author.login,
    draft: .isDraft,
    prerelease: .isPrerelease,
    created_at: .createdAt,
    published_at: .publishedAt,
    assets: [(.assets // [])[] | {name, url}]
};
def gh_release_rest: {
    tag: .tag_name,
    name,
    notes: (.body | blank_null),
    url: .html_url,
    author: .author.login,
    draft,
    prerelease,
    created_at,
    published_at,
    assets: [(.assets // [])[] | {name, url: .browser_download_url}]
};
'

# forge_capture that stays quiet on "not found": for existence checks, where missing is an answer.
github_release_probe() {
    gh_probe_err=$(forge_tmp)
    gh_probe_status=0
    forge_capture "$@" 2>"$gh_probe_err" || gh_probe_status=$?
    [ "$gh_probe_status" -eq "$FORGE_EXIT_NOT_FOUND" ] || cat "$gh_probe_err" >&2
    rm -f "$gh_probe_err"
    return "$gh_probe_status"
}

github_release_list() {
    if ! forge_json_mode; then
        forge_capture gh release list -R "$FORGE_R" --limit "$opt_limit"
        return
    fi
    # gh release list --json lacks notes, url, author and assets; REST has them all.
    if [ "$opt_limit" -le 100 ]; then
        gh_rel_list=$(forge_capture github_api "$FORGE_API/releases?per_page=$opt_limit") || return $?
    else
        gh_rel_list=$(forge_capture github_api "$FORGE_API/releases?per_page=100" --paginate --slurp) ||
            return $?
        gh_rel_list=$(printf '%s\n' "$gh_rel_list" | _jq --argjson n "$opt_limit" '[.[][]] | .[:$n]')
    fi
    forge_emit_doc "$gh_rel_list" "$GH_RELEASE_DEF [.[] | gh_release_rest]"
}

github_release_view() {
    if ! forge_json_mode; then
        forge_capture gh release view "$1" -R "$FORGE_R"
        return
    fi
    gh_rel_doc=$(forge_capture gh release view "$1" -R "$FORGE_R" --json "$GH_RELEASE_FIELDS") || return $?
    forge_emit_doc "$gh_rel_doc" "$GH_RELEASE_DEF gh_release"
}

github_release_url() {
    forge_capture gh release view "$1" -R "$FORGE_R" --json url --jq .url
}

github_release_latest() {
    gh_rel_doc=$(forge_capture github_api "$FORGE_API/releases/latest") || return $?
    if forge_json_mode; then
        forge_emit_doc "$gh_rel_doc" "$GH_RELEASE_DEF gh_release_rest"
    else
        printf '%s\n' "$gh_rel_doc" | _jq -r '.tag_name'
    fi
}

github_release_create() {
    set -- release create "$1" -R "$FORGE_R" --title "${opt_title:-$1}" --notes "${FORGE_BODY:-}"
    [ -z "$opt_target" ] || set -- "$@" --target "$opt_target"
    [ -z "$opt_draft" ] || set -- "$@" --draft
    [ -z "$opt_prerelease" ] || set -- "$@" --prerelease
    while IFS= read -r gh_rel_file; do
        [ -z "$gh_rel_file" ] || set -- "$@" "$gh_rel_file"
    done <<EOF
$opt_files
EOF
    forge_capture gh "$@" >/dev/null
}

github_release_edit() {
    set -- release edit "$1" -R "$FORGE_R"
    [ -z "$opt_title" ] || set -- "$@" --title "$opt_title"
    [ -z "${FORGE_BODY_SET:-}" ] || set -- "$@" --notes "$FORGE_BODY"
    [ -z "$opt_draft" ] || set -- "$@" "--draft=$opt_draft"
    [ -z "$opt_prerelease" ] || set -- "$@" "--prerelease=$opt_prerelease"
    forge_capture gh "$@" >/dev/null
}

github_release_publish() {
    # Without this check gh would tag the default branch; publish only releases what was pushed.
    gh_pub_status=0
    github_release_probe github_api "$FORGE_API/git/ref/tags/$(github_ref_path "$1")" >/dev/null || gh_pub_status=$?
    case $gh_pub_status in
        0) ;;
        "$FORGE_EXIT_NOT_FOUND") forge_not_found "tag $1 does not exist on $FORGE_HOST: push it first" ;;
        *) return "$gh_pub_status" ;;
    esac
    gh_pub_status=0
    github_release_probe gh release view "$1" -R "$FORGE_R" --json tagName >/dev/null || gh_pub_status=$?
    case $gh_pub_status in
        0)
            set -- release edit "$1" -R "$FORGE_R" --draft=false
            [ -z "$opt_title" ] || set -- "$@" --title "$opt_title"
            [ -z "${FORGE_BODY_SET:-}" ] || set -- "$@" --notes "$FORGE_BODY"
            ;;
        "$FORGE_EXIT_NOT_FOUND")
            set -- release create "$1" -R "$FORGE_R" --verify-tag --title "${opt_title:-$1}" \
                --notes "${FORGE_BODY:-}"
            ;;
        *) return "$gh_pub_status" ;;
    esac
    forge_capture gh "$@" >/dev/null
}

github_release_delete() {
    set -- release delete "$1" -R "$FORGE_R" --yes
    [ -z "$opt_cleanup_tag" ] || set -- "$@" --cleanup-tag
    forge_capture gh "$@" >/dev/null
}

github_release_upload() {
    set -- release upload "$1" -R "$FORGE_R"
    [ -z "$opt_clobber" ] || set -- "$@" --clobber
    while IFS= read -r gh_rel_file; do
        [ -z "$gh_rel_file" ] || set -- "$@" "$gh_rel_file"
    done <<EOF
$opt_files
EOF
    forge_capture gh "$@" >/dev/null
}

github_release_download() {
    set -- release download "$1" -R "$FORGE_R" --dir "$opt_dir"
    [ -z "$opt_pattern" ] || set -- "$@" --pattern "$opt_pattern"
    forge_capture gh "$@" >&2
}
