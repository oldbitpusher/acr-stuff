function readTable()
{
	table=$1
	eval "x_res=$(printf -- '%s\n' "\${!${table}[@]}" | sort)"
	for xobj in $x_res; do
		eval "xval=\${$table[$xobj]}"
		echo "VALUE / $xobj / $xval"
	done
}

function changeTable()
{
	src=$1
	dst=$2

	echo "SRC \"$src\" DST \"$dst\""
	eval "attrs=$(printf -- '%s\n' "\${!${src}[@]}" | sort)"
	for x_attr in $attrs; do
		eval "s_val=\${$src[$x_attr]:-}"
		eval "d_val=\${$dst[$x_attr]:-}"
		[[ $s_val == $d_val ]] && label='YES' || label='NO'
		printf "%-4s \"%-25s\" src \"%-30s\" dst \"%s\"\n" $label "$x_attr" "${s_val:-}" "${d_val:-}"
		if [[ -z ${d_val:-} ]] && [[ -n ${s_val:-} ]]; then
			eval "$dst[$x_attr]=\"\$s_val\""
		fi
	done
}
