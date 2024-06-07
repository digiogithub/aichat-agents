#!/usr/bin/env bash
set -e

# @describe Create a boilplate tool scriptfile.
#
# It automatically generate declaration json for `*.py` and `*.js` and generate `@option` tags for `.sh`.
# Examples:
#   argc create abc.sh foo bar! baz+ qux*
#   ./scripts/create-tool.sh test.py foo bar! baz+ qux*
#
# @flag --force Override the exist tool file
# @arg name! The script file name.
# @arg params* The script parameters

main() {
    output="tools/$argc_name"
    if [[ -f "$output" ]] && [[ -z "$argc_force" ]]; then
        _die "$output already exists"
    fi
    ext="${argc_name##*.}"
    support_exts=('.sh' '.js' '.py')
    if [[ "$ext" == "$argc_name" ]]; then
        _die "No extension name, pelease add one of ${support_exts[*]}" 
    fi
    case $ext in
    sh) create_sh ;;
    js) create_js ;;
    py) create_py ;;
    *) _die "Invalid extension name: $ext, must be one of ${support_exts[*]}" ;; 
    esac
    _die "$output generated"
}

create_sh() {
    cat <<-'EOF' | sed 's/__DESCRIBE_TAG__/# @describe/g' > "$output"
#!/usr/bin/env bash
set -e

__DESCRIBE_TAG__
EOF
    for param in "${argc_params[@]}"; do
        echo "# @option --$(echo $param | sed 's/-/_/g')" >> "$output"
    done
    cat <<-'EOF' >> "$output"

main() {
    ( set -o posix ; set ) | grep ^argc_ # inspect all argc variables
}

eval "$(argc --argc-eval "$0" "$@")"
EOF
    chmod +x "$output"
}

create_js() {
    properties=''
    for param in "${argc_params[@]}"; do
        if [[ "$param" == *'!' ]]; then
            param="${param:0:$((${#param}-1))}"
            property=" * @property {string} $param - "
        elif [[ "$param" == *'+' ]]; then
            param="${param:0:$((${#param}-1))}"
            property=" * @property {string[]} $param - "
        elif [[ "$param" == *'*' ]]; then
            param="${param:0:$((${#param}-1))}"
            property=" * @property {string[]} [$param] - "
        else
            property=" * @property {string} [$param] - "
        fi
        properties+=$'\n'"$property"
    done
    cat <<EOF > "$output"
/**
 *
 * @typedef {Object} Args${properties}
 * @param {Args} args
 */
exports.main = function main(args) {
  console.log(args);
}
EOF
}

create_py() {
    has_array_param=false
    has_optional_pram=false
    required_properties=''
    optional_properties=''
    required_arguments=()
    optional_arguments=()
    indent="    "
    for param in "${argc_params[@]}"; do
        optional=false
        if [[ "$param" == *'!' ]]; then
            param="${param:0:$((${#param}-1))}"
            type="str"
        elif [[ "$param" == *'+' ]]; then
            param="${param:0:$((${#param}-1))}"
            type="List[str]"
            has_array_param=true
        elif [[ "$param" == *'*' ]]; then
            param="${param:0:$((${#param}-1))}"
            type="Optional[List[str]] = None"
            optional=true
            has_array_param=true
        else
            optional=true
            type="Optional[str] = None"
        fi
        if [[ "$optional" == "true" ]]; then
            has_optional_pram=true
            optional_arguments+="$param: $type, "
            optional_properties+=$'\n'"$indent$indent$param: -"
        else
            required_arguments+="$param: $type, "
            required_properties+=$'\n'"$indent$indent$param: -"
        fi
    done
    import_typing_members=()
    if [[ "$has_array_param" == "true" ]]; then
        import_typing_members+=("List")
    fi
    if [[ "$has_optional_pram" == "true" ]]; then
        import_typing_members+=("Optional")
    fi
    imports=""
    if [[ -n "$import_typing_members" ]]; then
        members="$(echo "${import_typing_members[*]}" | sed 's/ /, /')"
        imports="from typing import $members"$'\n'
    fi
    if [[ -n "$imports" ]]; then
        imports="$imports"$'\n'
    fi
    cat <<EOF > "$output"
${imports}
def main(${required_arguments}${optional_arguments}):
    """
    Args:${required_properties}${optional_properties}
    """
    pass
EOF
}

build_schema() {
    echo '{
        "name": "'"${argc_name%%.*}"'",
        "description": "",
        "parameters": '"$(build_properties)"'
    }' | jq '.' | sed '2,$s/^/  /g'
}

build_properties() {
    required_params=()
    properties=''
    for param in "${argc_params[@]}"; do
        if [[ "$param" == *'!' ]]; then
            param="${param:0:$((${#param}-1))}"
            required_params+=("$param")
            property='{"'"$param"'":{"type":"string","description":""}}'
        elif [[ "$param" == *'+' ]]; then
            param="${param:0:$((${#param}-1))}"
            required_params+=("$param")
            property='{"'"$param"'":{"type":"array","description":"","items": {"type":"string"}}}'
        elif [[ "$param" == *'*' ]]; then
            param="${param:0:$((${#param}-1))}"
            property='{"'"$param"'":{"type":"array","description":"","items": {"type":"string"}}}'
        else
            property='{"'"$param"'":{"type":"string","description":""}}'
        fi
        properties+="$property"
    done
    required=''
    for param in "${required_params[@]}"; do
        if [[ -z "$required" ]]; then
            required=',"required":['
        fi
        required+="\"$param\","
    done
    if [[ -n "$required" ]]; then
        required="${required:0:$((${#required}-1))}"
        required+="]"
    fi
    echo '{
        "type": "object",
        "properties": '"$(echo "$properties" | jq -s 'add')$required"'
    }' | jq '.'
}

_die() {
    echo "$*"
    exit 1
}

# See more details at https://github.com/sigoden/argc
eval "$(argc --argc-eval "$0" "$@")"