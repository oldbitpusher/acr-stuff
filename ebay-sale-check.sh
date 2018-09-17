#!/bin/bash
#
# Tool for quick and dirty EBAY sale lookup
#
# Searching EBAY can be done via the URL and does not require authentication
# maybe unless you were hitting hit hundreds of time ber second :-)
#
# Lots of mungling IFS in this script - sometimes to make bash do tokenizing 
# on specified characters, others to prevent breaking up of strings with imbedded spaces
# being assigned and expanded.
#
# Usage: $0 [search item]
#
PS4='$LINENO: '
set -u			# Complain about unset variables

#
# Template for EBay search request:
#
# &LH_Sold=1	 Item sold 
# &LH_Complete=1 Transaction complete
# &rt=nc&
# LH_ItemCondition=4	Pre-owned/used

fipipe=$(mktemp)

declare -r SEARCH="https://www.ebay.com/sch/i.html?_nkw=%s&LH_Sold=1&LH_Complete=1&rt=nc&LH_ItemCondition=4"

#
# Round - take DD.cc and round to nearest DD
#
function round()
{
	local raw=${1:-}
	local dol=${raw/.*/}
	local cents=${raw/*./}
	cents=${cents#0}
	[[ $cents -gt 50 ]] && ((++dol))
	echo $dol
}

declare -i current_pos=0		# Current line 
declare -i current_pct=0		# Current percent
declare    current_line=''		# Current line content

#
# next_line - iterate to the next line of INPUT
#
function next_line()
{
	unset IFS
	[[ $current_pos -ge $INPUT_MAX ]] && return 1
	current_pos=$(( $current_pos + ${1:-1} ))
	current_line="${INPUT[$current_pos]:-}"
	current_pct=$(( ( $current_pos * 100) / $INPUT_MAX ))
	return 0
}

#
# urlencode - URL encode string
#
function url_encode() {
    local length="${#1}"
    for (( i = 0; i < length; i++ )); do
        local c="${1:i:1}"
        case $c in
            [a-zA-Z0-9.~_-])	printf "$c" ;;
            *) 			printf '%%%02X' "'$c" ;;
        esac
    done
}

#
# MAIN
#
exec 3>&1			# Set up FDs for dialog

#
# If $* not empty, take as search item else pop text entry dialog box
#
if [[ -n ${1:-} ]]; then 
	search_for="$@"
else
	search_for="$(dialog --title "Enter item" \
		--clear \
		--inputbox "Enter item to search for" \
		10 50 2>&1 1>&3)"
	rc=$?
	[[ -n ${search_for:-} ]] || exit 0
fi
 
SEARCH_URL="$(printf "$SEARCH" "$(url_encode "$search_for")")"

#
# Fetch web page using "lynx -dump" - dont care about HTML, just want content
#
INPUT="$(lynx -dump -width=1024 "$SEARCH_URL" | sed 's/^[ \t]*//')"
IFS=$'\n' INPUT=( ${INPUT} ) ; unset IFS
INPUT_MAX=${#INPUT[@]}

#
# What a sales record looks like:
# (rubbish)
# (rubbish)
# SOLD Sep 16, 2018
#> Canon AE-1 Program 35mm Film Camera Body Tested
# Pre-Owned
#> $56.00
# (rubbish)
# 
declare -i ITEM_COUNT=0
declare -A description
declare -A price

while next_line; do
	if [[ $current_line =~ SOLD ]]; then
		next_line
		description[$ITEM_COUNT]="$current_line"
		while next_line; do
			[[ $current_line =~ \$[0-9]* ]] && break
		done
		price[$ITEM_COUNT]="$current_line"
		((++ITEM_COUNT))
	fi
done

if [[ $ITEM_COUNT -eq 0 ]]; then
	dialog -title "No results" \
		--msgbox "The search for \"$search_for\" did not return any items" \
		10 20
	exit 0
fi
#
# Collapse info arrays into one assoc array index by price
#
declare -A ITEMS
BASE=()
for (( ix=0 ; $ix < $ITEM_COUNT; ((ix++)) )); do
	x_index=$(round ${price[$ix]/\$/})
	ITEMS[$x_index]="$(printf "'%s' '%s@%s %s' 'on'\n" "$x_index" "${price[$ix]}" "${description[$ix]}")"
done

#
# Sort prices high to low
#
IFS=' ' read -a BASE_ORDER <<<"$(echo "${!ITEMS[@]}" | tr ' '  '\012' | sort -r -n | tr '\012' ' ')";
ORDER=( ${BASE_ORDER[@]} )
unset IFS

#
# The dialog command has to be written to fie then executed
# Quoting of strings with embedded spaces is too weird to make work
# direct exec.
# 
script_temp=$(mktemp)
trap "rm -f $script_temp; clear;" 0
 
while true; do
	# Window lines => 80% screen lines
	# Window cols = 80% screen cols
	# text lines = 80% screen lines
	declare -i tty_lines=$(tput lines)
	declare -i tty_cols=$(tput cols)
	if [[ -z ${tty_lines:=} ]] ||  [[ -z ${tty_cols:-} ]]; then
		read spl spv spx rl rows cl cols junk <<<"$(stty -a | grep rows)"
		tty_lines=${rows/;//}
		tty_cols=${cols/;//}
	fi
	declare -i win_lines=$((  ( $tty_lines / 10 ) * 8 ))
	declare -i win_cols=$((   ( $tty_cols  / 10 ) * 8 ))
	declare -i text_lines=$(( ( $win_lines / 10 ) * 8 ))

	X_ORDER="${ORDER[@]}"
	t_ave=$(( ( $(printf -- "%s + " ${ORDER[@]} | sed 's/+ $//') ) / ${#ORDER[@]} ))
	(
	cat <<_EOF_
	dialog --column-separator @ --title 'Price search "$search_for"' \
		--extra-button --extra-label 'New Item' \
		--cancel-label Done \
		--ok-label Update \
		--checklist "Found ${#ORDER[@]} items, average price \\\$$t_ave" $win_lines $win_cols $text_lines
_EOF_
	for x_seq in ${ORDER[@]}; do
		IFS='';
		echo "${ITEMS[$x_seq]} ";
		unset IFS
	done
	echo ''
	) | tr '\012' ' ' > $script_temp
	resp=$(sh $script_temp 2>&1 1>&3)
	rcode=$?
	corder="${ORDER[@]}"
	case $rcode in
		0) 	# OK
			[[ "$resp" == "$X_ORDER" ]] && exit 0
			ORDER=( $resp )
			;;
		3)	# EXTRA
			exec sh $0
			;;
		255)	# ESCAPE
			if [[ $resp =~ Error ]]; then
				echo "$resp"
				exit $rcode
			fi
			clear
			exit 0
			;;
		*)	exit $rcode
			;;
	esac
done
