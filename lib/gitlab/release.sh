# shellcheck shell=sh

# GitLab has no drafts or pre-releases: every release is published.
GL_RELEASE_DEF='
def gl_release: {
    tag: .tag_name,
    name,
    notes: .description,
    url: ._links.self,
    author: .author.username,
    draft: false,
    prerelease: null,
    created_at,
    published_at: .released_at,
    assets: [(.assets.links // [])[] | {name, url: (.direct_asset_url // .url)}]
};
'

# forge_capture that stays quiet on "not found": for existence checks, where missing is an answer.
gitlab_release_probe() {
    gl_probe_err=$(forge_tmp)
    gl_probe_status=0
    forge_capture "$@" 2>"$gl_probe_err" || gl_probe_status=$?
    [ "$gl_probe_status" -eq "$FORGE_EXIT_NOT_FOUND" ] || cat "$gl_probe_err" >&2
    rm -f "$gl_probe_err"
    return "$gl_probe_status"
}

gitlab_release_path() {
    printf '%s/releases/%s' "$FORGE_API" "$(forge_urlencode "$1")"
}

gitlab_release_list() {
    if ! forge_json_mode; then
        forge_capture glab release list -R "$FORGE_R" --per-page "$opt_limit"
        return
    fi
    if [ "$opt_limit" -le 100 ]; then
        gl_rel_list=$(forge_capture gitlab_api "$FORGE_API/releases?per_page=$opt_limit") || return $?
    else
        gl_rel_list=$(forge_capture gitlab_api_all "$FORGE_API/releases?per_page=100") || return $?
        gl_rel_list=$(printf '%s\n' "$gl_rel_list" | _jq --argjson n "$opt_limit" '.[:$n]')
    fi
    forge_emit_doc "$gl_rel_list" "$GL_RELEASE_DEF [.[] | gl_release]"
}

gitlab_release_view() {
    if ! forge_json_mode; then
        forge_capture glab release view "$1" -R "$FORGE_R"
        return
    fi
    gl_rel_doc=$(forge_capture gitlab_api "$(gitlab_release_path "$1")") || return $?
    forge_emit_doc "$gl_rel_doc" "$GL_RELEASE_DEF gl_release"
}

gitlab_release_url() {
    gl_rel_doc=$(forge_capture gitlab_api "$(gitlab_release_path "$1")") || return $?
    printf '%s\n' "$gl_rel_doc" | _jq -r '._links.self'
}

gitlab_release_latest() {
    gl_rel_doc=$(forge_capture gitlab_api "$FORGE_API/releases/permalink/latest") || return $?
    if forge_json_mode; then
        forge_emit_doc "$gl_rel_doc" "$GL_RELEASE_DEF gl_release"
    else
        printf '%s\n' "$gl_rel_doc" | _jq -r '.tag_name'
    fi
}

gitlab_default_branch() {
    gl_db_doc=$(forge_capture gitlab_api "$FORGE_API") || return $?
    printf '%s\n' "$gl_db_doc" | _jq -r '.default_branch // empty'
}

# Upload through glab: it stores each file in the project and links it to the release.
gitlab_release_attach() {
    set -- release upload "$1" -R "$FORGE_R"
    while IFS= read -r gl_rel_file; do
        [ -z "$gl_rel_file" ] || set -- "$@" "$gl_rel_file"
    done <<EOF
$opt_files
EOF
    forge_capture glab "$@" >&2
}

gitlab_release_create() {
    [ -z "$opt_draft" ] || forge_unsupported "--draft"
    [ -z "$opt_prerelease" ] || forge_unsupported "--prerelease"
    # The API ignores ref when the tag exists and needs it when it does not, as gh does.
    gl_rel_ref=$opt_target
    if [ -z "$gl_rel_ref" ]; then
        gl_rel_ref=$(gitlab_default_branch) || return $?
    fi
    # glab release create would update an existing release; create must fail on one instead.
    forge_capture gitlab_api "$FORGE_API/releases" -X POST -f "tag_name=$1" -f "name=${opt_title:-$1}" \
        -f "description=${FORGE_BODY:-}" -f "ref=$gl_rel_ref" >/dev/null || return $?
    [ -z "$opt_files" ] || gitlab_release_attach "$1"
}

gitlab_release_edit() {
    [ -z "$opt_draft" ] || forge_unsupported "--draft"
    [ -z "$opt_prerelease" ] || forge_unsupported "--prerelease"
    set -- "$(gitlab_release_path "$1")" -X PUT
    [ -z "$opt_title" ] || set -- "$@" -f "name=$opt_title"
    [ -z "${FORGE_BODY_SET:-}" ] || set -- "$@" -f "description=$FORGE_BODY"
    forge_capture gitlab_api "$@" >/dev/null
}

gitlab_release_publish() {
    gl_pub_status=0
    gitlab_release_probe gitlab_api "$FORGE_API/repository/tags/$(forge_urlencode "$1")" >/dev/null || gl_pub_status=$?
    case $gl_pub_status in
        0) ;;
        "$FORGE_EXIT_NOT_FOUND") forge_not_found "tag $1 does not exist on $FORGE_HOST: push it first" ;;
        *) return "$gl_pub_status" ;;
    esac
    gl_pub_status=0
    gitlab_release_probe gitlab_api "$(gitlab_release_path "$1")" >/dev/null || gl_pub_status=$?
    case $gl_pub_status in
        0)
            # Nothing given means nothing to replace; a PUT without fields is refused.
            [ -n "$opt_title${FORGE_BODY_SET:-}" ] || return 0
            set -- "$(gitlab_release_path "$1")" -X PUT
            [ -z "$opt_title" ] || set -- "$@" -f "name=$opt_title"
            [ -z "${FORGE_BODY_SET:-}" ] || set -- "$@" -f "description=$FORGE_BODY"
            ;;
        "$FORGE_EXIT_NOT_FOUND")
            set -- "$FORGE_API/releases" -X POST -f "tag_name=$1" -f "name=${opt_title:-$1}" \
                -f "description=${FORGE_BODY:-}"
            ;;
        *) return "$gl_pub_status" ;;
    esac
    forge_capture gitlab_api "$@" >/dev/null
}

gitlab_release_delete() {
    set -- release delete "$1" -R "$FORGE_R" --yes
    [ -z "$opt_cleanup_tag" ] || set -- "$@" --with-tag
    forge_capture glab "$@" >&2
}

gitlab_release_upload() {
    [ -z "$opt_clobber" ] || forge_unsupported "--clobber"
    # glab reports a missing release vaguely; asking first gives exit 4.
    forge_capture gitlab_api "$(gitlab_release_path "$1")" >/dev/null || return $?
    gitlab_release_attach "$1"
}

gitlab_release_download() {
    set -- release download "$1" -R "$FORGE_R" --dir "$opt_dir"
    [ -z "$opt_pattern" ] || set -- "$@" --asset-name "$opt_pattern"
    forge_capture glab "$@" >&2
}
