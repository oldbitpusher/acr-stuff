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

declare    OPT_DEBUG=false
declare    OPT_LOG=''

declare -A descriptions
declare -A priceList
declare -A itemList
declare -A itemKeys
declare    searchItem

declare -r -i DI_OK=0
declare -r -i DI_EXTRA=3
declare -r -i DI_ESCAPE=255`

declare -r -i RC_OK=0
declare -r -i RC_HARD_ERROR=1
declare -r -i RC_SOFT_ERROR=2
declare -r -i RC_RESET=3

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

function debug()
{
	$OPT_DEBUG && echo "debug: $*" 1>&2
	[[ -n ${OPT_LOG:-} ]] && echo "debug: $*" 1>&2 >> $OPT_LOG
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
# What a sales record looks like:
# (rubbish)
# (rubbish)
# SOLD Sep 16, 2018
#> Canon AE-1 Program 35mm Film Camera Body Tested
# Pre-Owned
#> $56.00
# (rubbish)
# 

#
# next_line - iterate to the next line from lineBuffer
#




function doit()
{
	local -i currentPos=0
	local    currentLine
	local -a lineBuffer=()
	local -i currentPos=0		# Current line 
	local    currentLine=''		# Current line content
	local -i lineCount

	function next_line()
	{
		[[ $currentPos -ge ${#inputLines[@]} ]] && return 1
		((++currentPos))
		currentLine="${lineBuffer[$currentPos]:-}"
		return 0
	}

	if [[ -n ${1:-} ]]; then 
		local searchItem="$@"
	else
		local searchItem="$(dialog --title "Enter item" \
			--clear \
			--inputbox "Enter item to search for" \
			10 50 2>&1 1>&3)"
		rc=$?
		if [[ -n ${searchItem:-} ]]; then
			echo "No search item"
			exit 0
		fi
	fi
	debug "Search item \"$searchItem\""
	SEARCH_URL="$(printf "$SEARCH" "$(url_encode "$searchItem")")"
	debug "Search URL \"$SEARCH_URL\""
	#
	# Fetch web page using "lynx -dump" - dont care about HTML, just want content
	#
	local -a inputLines=()
	readarray -t inputLines <<<"$(lynx -dump -width=1024 "$SEARCH_URL" | sed 's/^[ \t]*//')"
	debug "Query response ${#inputLines[@]} lines"

	if [[ ${#inputLines[@]} -eq 0 ]]; then
		debug "No response to query"
		dialog --msgbox "No data"
		return $RC_SOFT_ERROR
	fi
	
	local -i itemCount=0
	local -a descriptions=()
	local -a priceList=()

	while next_line; do
		if [[ currentLine =~ SOLD ]]; then
			next_line
			descriptions[$itemCount]=$currentLine
			while next_line; do
				if [[ $currentLine =~ \$[0-9]* ]]; then
					priceList[$itemCount]="$currentLine"
					((++itemCount))
					break # inner while
				fi
			done
		fi
	done

	if [[ $itemCount -eq 0 ]]; then
		debug "No results for \"$searchItem\""
		dialog -title "No resul> VARSXts" \
			--msgbox "The search for \"$searchItem\" did not return any items" \
			10 20
		exit 0
	fi
	debug "Found $itemCount transactions"
	
	#
	# Collapse info arrays into one assoc array index by price
	#
	BASE=()
	for (( ix=0 ; $ix < $itemCount; ix++ )); do
		x_index=$(round ${priceList[$ix]/\$/})
		itemList[$x_index]="${priceList[$ix]}@%s@${descriptions[$ix]}"
		itemKeys[$x_index]=$x_index
		debug "ITEM $x_index |${itemList[$x_index]}|"
	done
	#
	# Sort prices high to low
	#
	IFS=' ' read -a BASE_ORDER <<<"$(echo "${!itemList[@]}" | tr ' '  '\012' | sort -r -n | tr '\012' ' ')";
	ORDER=( ${BASE_ORDER[@]} )
	unset IFS

	debug "Base order: ${ORDER[@]}"

	while true; do
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
			t_price=${itemKeys[$x_seq]}
			t_rank=$(( ( $t_price * 10 ) / $t_ave ))	# Rank == price percent compared to average
			status='on'									# Hook for turning on/off based upon rank
			t_rank="$(printf "%3d" $t_rank)"
			t_rank=${t_rank:0:-1}.${t_rank:-1}			# Change NN to N.N
			t_rank=${t_rank/ \./0.}						# Add '0' to sub-1 value
			x_args+=( ${itemKeys[$x_seq]} "$(printf "${itemList[$x_seq]}" "[$t_rank]")" $status )
		done
		#
		# Output of dialog is list of tags from selected rows
		# Since the rows are sorted by price, the selection keys will
		# be sorted high to low.
		#
		resp=$(dialog --column-separator @ --title "Price search $searchItem" \
			--colors \
			--extra-button --extra-label 'New Item' \
			--cancel-label Done \
			--ok-label Update \
			--checklist "Found ${#ORDER[@]} items, average price \$$t_ave" \
			$win_lines $win_cols $text_lines \
			"${x_args[@]}" 2>&1 1>&3)
		rcode=$?
		# corder="${ORDER[@]}"
		case $rcode in
			$DI_OK) # Pressed 'OK' button - redo unless no changes (REFRESH)
				[[ "$resp" == "$X_ORDER" ]] && return $DI_EXTRA
				ORDER=( $resp )
				continue	# Big loop
				;;
			$DI_EXTRA)	# Pressed 'EXTRA' button - reset and go again (NEW)
				ARGS=''
				return $DI_EXTRA
				;;
			$DI_ESCAPE)	# Pressed 'ESCAPE' button (DONE)
				if [[ $resp =~ Error ]]; then
					dialog --msgbox "Error: $resp"
					return 
				fi
				exit 0
				;;
			*)	echo "Weird exit code from dialog: $rcode" 1>&2
				exit $rcode
				;;
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
$OPT_DEBUG || trap 'clear' 0

# Window lines => 80% screen lines
# Window cols = 80% screen cols
# text lines = 80% screen lines
declare -i tty_lines=$(tput lines 2>/dev/tty)	# Need stderr > /dev/tty to get actual window size
declare -i tty_cols=$(tput cols 2>/dev/tty)		# Need stderr > /dev/tty to get actual window size
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

ARGS="$*"
while true; do
	doit $ARGS
	[[ $? -eq $DI_EXTRA ]] ||  break
done

# notreached
