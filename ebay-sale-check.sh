#!/bin/bash

set -u

item=()
desc=()
prices=()

SEARCH="https://www.ebay.com/sch/i.html?_nkw=%s&LH_Sold=1&LH_Complete=1&rt=nc&LH_ItemCondition=4"

current_pos=0
current_line=''

item="$@"
item=${item/ /+}

SEARCH_URL=$(printf "$SEARCH" "$item")

INPUT="$(curl -s -k "$SEARCH_URL")"
IFS='>' INPUT=( ${INPUT} )
limit=${#INPUT[@]}
INPUT_BLOCK=0

function round()
{
	local dol=${1/.*/}
	local cents=${1/*./}
	cents=${cents#0}
	[[ $cents -gt 50 ]] && ((++dol))
	echo $dol
}

function next_line()
{
	local inc=${1:-1}
	current_pos=$(( $current_pos + $inc ))
	[[ $current_pos -eq $limit ]] && return 1
	current_line="${INPUT[current_pos]}"
	current_data="${INPUT[current_pos]}"
	return 0
}

while next_line; do
	case $current_line in
		*class=\"s-item\"*)
			((++INPUT_BLOCK))
			;;
		*SECONDARY_INFO*)
			next_line
			details+=( ${current_data/<*/} )
			;;
		*item__price*)
			next_line 2
			t=${current_data/<*/}
			prices+=( $(round ${t/$/}) )
			;;
		*item__title*)
			next_line 3
			[[ $current_data =~ \</h3 ]] && items+=( ${current_data/<*/} )
			;; 
		*)	;;
	esac
done

OUTPUT=()
TMPF=/tmp/ebh$$
for (( xhit=0 ; $xhit < ${#items[@]}; ++xhit)); do
	printf "%6s | %8s | %s\n" \
		"${prices[$xhit]:-}" \
		"${details[$xhit]:-}" \
		"${items[$xhit]:-}"
done | sort -r -n > $TMPF

[[ -n ${EDITOR:-} ]] && $EDITOR $TMPF

sed 's/^/$/' $TMPF
echo "-----"
echo "$(wc -l < $TMPF) Matches; Average sale price: \$$(round $(awk '{ sum += $1; count++; } END { print sum / count }' $TMPF))"


