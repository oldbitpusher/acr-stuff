#!/bin/bash
#
# Tool for quick and dirty EBAY sale lookup
#
# Searching EBAY can be done via the URL and does not require authentication
# maybe unless you were hitting hit hundreds of time ber second :-)
#
# A bit of mungling $IFS, usually to make bash do tokenizing 
# on specified characters
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

declare -r SEARCH="https://www.ebay.com/sch/i.html?_nkw=%s&LH_Sold=1&LH_Complete=1&rt=nc&LH_ItemCondition=4"

OPT_DEBUG=false
OPT_LOG=''

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

function debug()
{
	$OPT_DEBUG && echo "debug: $*" 1>&2
	[[ -n ${OPT_LOG:-} ]] && echo "debug: $*" 1>&2 >> $OPT_LOG
}

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

function pct()
{
	local -i i_value=${1:?Missing pct arg 1}
	local -i i_base=${2:?Missing pct arg 2}
	echo $(( ( $i_base * 100 ) / $i_value ))
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

while getopts dl: x_opt; do
	case $x_opt in
	d)	OPT_DEBUG=true;;
	l)	OPT_LOG=$OPTARG; >$OPT_LOG;;
	*)	;;
	esac
done
shift $(( $OPTIND - 1 ))

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
debug "Search item \"$search_for\""
 
SEARCH_URL="$(printf "$SEARCH" "$(url_encode "$search_for")")"

debug "Search URL \"$SEARCH_URL\""

#
# Fetch web page using "lynx -dump" - dont care about HTML, just want content
#
INPUT="$(lynx -dump -width=1024 "$SEARCH_URL" | sed 's/^[ \t]*//')"
IFS=$'\n' INPUT=( ${INPUT} ) ; unset IFS
INPUT_MAX=${#INPUT[@]}
debug "Query response ${INPUT_MAX} lines"

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
	debug "No results for \"$search_for\""
	dialog -title "No results" \
		--msgbox "The search for \"$search_for\" did not return any items" \
		10 20
	exit 0
fi
debug "Found $ITEM_COUNT transactions"

#
# Collapse info arrays into one assoc array index by price
#
declare -A ITEMS KEYS
BASE=()

for (( ix=0 ; $ix < $ITEM_COUNT; ix++ )); do
	x_index=$(round ${price[$ix]/\$/})
	ITEMS[$x_index]="${price[$ix]}@%s@${description[$ix]}"
	KEYS[$x_index]=$x_index
	debug "ITEM $x_index |${ITEMS[$x_index]}|"
done
#
# Sort prices high to low
#
IFS=' ' read -a BASE_ORDER <<<"$(echo "${!ITEMS[@]}" | tr ' '  '\012' | sort -r -n | tr '\012' ' ')";
ORDER=( ${BASE_ORDER[@]} )
unset IFS

debug "Base order: ${ORDER[@]}"

$OPT_DEBUG || trap 'clear' 0

while true; do
	# Window lines => 80% screen lines
	# Window cols = 80% screen cols
	# text lines = 80% screen lines
	declare -i tty_lines=$(tput lines 2>/dev/tty)	# Need stderr > /dev/tty to get actual window size
	declare -i tty_cols=$(tput cols 2>/dev/tty)		# Need stderr > /dev/tty to get actual window size
	#
	# If tput isn't there, fall back to stty
	#
	if [[ -z ${tty_lines:=} ]] ||  [[ -z ${tty_cols:-} ]]; then
		read spl spv spx rl rows cl cols junk <<<"$(stty -a | grep rows)"
		tty_lines=${rows/;//}
		tty_cols=${cols/;//}
	fi
	# Lines = 90% of window height
	declare -i win_lines=$((  ( $tty_lines / 10 ) * 9 ))

	# Columns = 80% of window height
	declare -i win_cols=$((   ( $tty_cols  / 10 ) * 8 ))

	# Text lines = 90% of panel height
	declare -i text_lines=$(( ( $win_lines / 10 ) * 9 ))

	X_ORDER="${ORDER[@]}"
	#
	# This one-liner genrates the average of the numeric values
	# of the elements of ${ORDER[@]} -- which are dollar-rounded prices
	#
	t_ave=$(( ( $(printf -- "%s + " ${ORDER[@]}) 0 ) / ${#ORDER[@]} ))
	#
	# Build dialog checkbox entires
	# Each entry is weighed against the computed average
	#
	x_args=()
	for x_seq in ${ORDER[@]}; do
		t_price=${KEYS[$x_seq]}
		t_rank=$(( ( $t_price * 10 ) / $t_ave ))	# Rank == price percent compared to average
		status='on'									# Hook for turning on/off based upon rank
		t_rank="$(printf "%3d" $t_rank)"
		t_rank=${t_rank:0:-1}.${t_rank: -1}			# Change NN to N.N
		t_rank=${t_rank/ \./0.}						# Add '0' to sub-1 value
		x_args+=( ${KEYS[$x_seq]} "$(printf "${ITEMS[$x_seq]}" "[$t_rank]")" $status )
	done
	#
	# Output of dialog is list of tags from selected rows
	# Since the rows are sorted by price, the selection keys will
	# be sorted high to low.
	#
	resp=$(dialog --column-separator @ --title "Price search $search_for" \
		--colors \
		--extra-button --extra-label 'New Item' \
		--cancel-label Done \
		--ok-label Update \
		--checklist "Found ${#ORDER[@]} items, average price \$$t_ave" \
		$win_lines $win_cols $text_lines \
		"${x_args[@]}" 2>&1 1>&3)
	rcode=$?
	corder="${ORDER[@]}"
	case $rcode in
		0) 	# Pressed 'OK' button
			[[ "$resp" == "$X_ORDER" ]] && exit 0
			ORDER=( $resp )
			;;
		3)	# Pressed 'EXTRA' button
			exec bash $0
			;;
		255)	# Pressed 'ESCAPE' button
			if [[ $resp =~ Error ]]; then
				echo "$resp"
				exit $rcode
			fi
			exit 0
			;;
		*)	echo "Weird exit code from dialog: $rcode" 1>&2
			exit $rcode
			;;
	esac
done
# notreached
