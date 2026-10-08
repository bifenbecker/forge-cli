# shellcheck shell=sh

# REST lists tags without their annotation; GraphQL has both in one query, and real ordering.
GH_TAG_TARGET='target { __typename oid ... on Tag { message target { oid } } }'

GH_TAG_DEF='
def gh_tag($web): {
    name,
    sha: (if .target.__typename == "Tag" then .target.target.oid else .target.oid end),
    message: (if .target.__typename == "Tag" then (.target.message // "" | sub("\n+$"; "")
        | if . == "" then null else . end) else null end),
    url: ($web + "/tree/" + (.name | @uri | gsub("%2F"; "/")))
};
'

github_tag_list() {
    gh_tag_query="query(\$owner: String!, \$repo: String!, \$first: Int!, \$endCursor: String) {
      repository(owner: \$owner, name: \$repo) {
        refs(refPrefix: \"refs/tags/\", first: \$first, after: \$endCursor,
             orderBy: {field: TAG_COMMIT_DATE, direction: DESC}) {
          nodes { name $GH_TAG_TARGET }
          pageInfo { hasNextPage endCursor }
        }
      }
    }"
    set -- graphql -f owner="$(github_owner)" -f repo="$(github_name)" -f query="$gh_tag_query"
    if [ "$opt_limit" -le 100 ]; then
        set -- "$@" -F first="$opt_limit"
    else
        set -- "$@" -F first=100 --paginate --slurp
    fi
    gh_tag_doc=$(forge_capture github_api "$@") || return $?
    # One page is an object, --slurp makes an array of them; both become one list of refs.
    gh_tag_doc=$(printf '%s\n' "$gh_tag_doc" | _jq --argjson n "$opt_limit" \
        '[if type == "array" then .[] else . end | .data.repository.refs.nodes[]] | .[:$n]')
    if forge_json_mode; then
        forge_emit_doc "$gh_tag_doc" "$GH_TAG_DEF [.[] | gh_tag(\$web)]" --arg web "$(github_web_url)"
    else
        printf '%s\n' "$gh_tag_doc" | _jq -r '.[].name'
    fi
}

github_tag_view() {
    gh_tag_doc=$(forge_capture github_api graphql -f owner="$(github_owner)" -f repo="$(github_name)" \
        -f qualified="refs/tags/$1" -f query="query(\$owner: String!, \$repo: String!, \$qualified: String!) {
          repository(owner: \$owner, name: \$repo) { ref(qualifiedName: \$qualified) { name $GH_TAG_TARGET } }
        }") || return $?
    gh_tag_ref=$(printf '%s\n' "$gh_tag_doc" | _jq -c '.data.repository.ref')
    [ "$gh_tag_ref" != null ] || forge_not_found "no tag '$1' on $FORGE_HOST/$FORGE_REPO_PATH"
    forge_emit_doc "$gh_tag_ref" "$GH_TAG_DEF gh_tag(\$web)" --arg web "$(github_web_url)"
}

# Any ref, or the default branch, to the commit SHA it names.
github_tag_commit() {
    gh_tc_ref=$1
    if [ -z "$gh_tc_ref" ]; then
        gh_tc_repo=$(forge_capture github_api "$FORGE_API") || return $?
        gh_tc_ref=$(printf '%s\n' "$gh_tc_repo" | _jq -r '.default_branch')
    fi
    gh_tc_commit=$(forge_capture github_api "$FORGE_API/commits/$(github_ref_path "$gh_tc_ref")") || return $?
    printf '%s\n' "$gh_tc_commit" | _jq -r '.sha'
}

github_tag_create() {
    gh_tag_sha=$(github_tag_commit "$opt_ref") || return $?
    if [ -n "$opt_message" ]; then
        # An annotated tag is a tag object first, then a ref pointing at it.
        gh_tag_obj=$(forge_capture github_api "$FORGE_API/git/tags" -X POST -f "tag=$1" \
            -f "message=$opt_message" -f "object=$gh_tag_sha" -f type=commit) || return $?
        gh_tag_sha=$(printf '%s\n' "$gh_tag_obj" | _jq -r '.sha')
    fi
    forge_capture github_api "$FORGE_API/git/refs" -X POST -f "ref=refs/tags/$1" -f "sha=$gh_tag_sha" >/dev/null
}

github_tag_delete() {
    forge_capture github_api "$FORGE_API/git/refs/tags/$(github_ref_path "$1")" -X DELETE >/dev/null
}
