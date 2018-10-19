#!/bin/bash
#
# Tool for quick and dirty EBAY sale lookup
#
# Searching EBAY can be done via the URL and does not require authentication
# maybe unless you were hitting hit hundreds of time ber second :-)
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

#
# Template for EBAY search URI
#
declare -r SEARCH="https://www.ebay.com/sch/i.html?_nkw=%s&LH_Sold=1&LH_Complete=1&rt=nc&LH_ItemCondition=4"

declare    OPT_DEBUG=false

#
# Size of alert message box
#
declare -r MSGBOX_W=30 
declare -r MSGBOX_H=10 

#
# Return codes from dialog
#
export DIALOG_OK=0
export DIALOG_CANCEL=1
export DIALOG_HELP=2
export DIALOG_EXTRA=3
export DIALOG_HELP_ITEM=4
export DIALOG_ESC=5
export DIALOG_ERROR=6

#
# print message to stderr in debug mode
#
function debug()
{
	$OPT_DEBUG && echo "debug: $*" 1>&2
}

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
function price_tag()
{
	local searchItem=''

	if [[ -n ${1:-} ]]; then 
		searchItem="$@"
	else
		searchItem="$(dialog --title "Enter item" \
			--clear \
			--inputbox "Enter item to search for" \
			10 50 2>&1 1>&3)"
		local rc=$?
		if [[ -z ${searchItem:-} ]]; then
			debug "No search item"
			dialog --msgbox "No search Item" $MSGBOX_H $MSGBOX_W
			return 2
		fi
	fi
	debug "Search item \"$searchItem\""
	SEARCH_URL="$(printf "$SEARCH" "$(url_encode "$searchItem")")"
	debug "Search URL \"$SEARCH_URL\""
	#
	# Fetch web page using "lynx -dump" - dont care about HTML, just want content
	#
	local -a inputLines=()
	local -i currentLine=0
	readarray -t inputLines <<<"$(lynx -dump -width=1024 "$SEARCH_URL" | sed 's/^[ \t]*//')"
	debug "Query response ${#inputLines[@]} lines"
	if [[ ${#inputLines[@]} -eq 0 ]]; then
		debug "No response to query"
		dialog --msgbox "No data" $MSGBOX_H $MSGBOX_W
		return 1
	fi
	
	local -i itemCount=0
	local -a itemDetails=()
	local -a itemPrices=()

	while [[ $currentLine -lt ${#inputLines[@]} ]]; do
		if [[ ${inputLines[$currentLine]} =~ SOLD ]]; then
			((++currentLine))
			itemDetails[$itemCount]="${inputLines[$currentLine]}"
			((++currentLine))
			while [[ ! ${inputLines[$currentLine]} =~ \$[0-9]* ]] && \
			      [[ $currentLine -lt ${#inputLines[@]} ]]; do
				((++currentLine))
			done
			local t_price="${inputLines[$currentLine]/ */}"
			t_price="${t_price//,}"
			itemPrices[$itemCount]="${t_price}"
			((++itemCount))
		fi
		((++currentLine))
	done
	if [[ $itemCount -eq 0 ]]; then
		debug "No results for \"$searchItem\""
		dialog  --title "No results" \
			--msgbox "The search for \"$searchItem\" did not return any items" \
			$MSGBOX_H $MSGBOX_W
		return 0
	fi
	debug "Found $itemCount transactions"
	#
	# Collapse info arrays into one assoc array index by price
	#
	local -A itemList=()
	local -A itemKeys=()
	local -i x_item
	for (( x_item=0; $x_item < $itemCount; x_item++ )); do
		x_index=$(round ${itemPrices[$x_item]/\$/})
		itemList[$x_index]="${itemPrices[$x_item]}@%s@${itemDetails[$x_item]}"
		itemKeys[$x_index]=$x_index
		debug "ITEM $x_index |${itemList[$x_index]}|"
	done

	#
	# Sort prices high to low
	#
	local -a sortedIndex
	readarray -t sortedIndex <<<"$(printf -- '%s\n' ${!itemList[@]} | sort -r -n)"
	debug "Sorted index: ${sortedIndex[@]}"
	#
	# Loop while the index order is changing
	#
	displayIndex=( ${sortedIndex[@]} )

	while true; do
		#
		# This one-liner genrates the average of the numeric values
		# of the elements of ${displayIndex[@]} -- which are dollar-rounded prices
		#
		local -i t_AveragePrice=$(( ( $(printf -- "%s + " ${displayIndex[@]}) 0 ) / ${#displayIndex[@]} ))
		#
		# Build dialog checkbox entires
		# Each entry is weighed against the computed average
		#
		local itemDialog=()
		for x_display in ${displayIndex[@]}; do
			t_price=${itemKeys[$x_display]}
			t_rank=$(( ( $t_price * 10 ) / $t_AveragePrice ))	# Rank == price percent compared to average
			local t_status='on'									# Hook for turning on/off based upon rank
			t_rank="$(printf "%d.%d" $(( $t_rank / 10)) $(( $t_rank % 10 )) )"
			itemDialog+=( ${itemKeys[$x_display]} "$(printf "${itemList[$x_display]}" "[$t_rank]")" $t_status )
		done
		#
		# Output of dialog is list of tags from selected rows
		# Since the rows are sorted by price, the selection keys will
		# be sorted high to low.
		#
		local response=$(dialog --column-separator @ \
			--title "Price search $searchItem" \
			--colors \
			--extra-button --extra-label 'New Item' \
			--cancel-label Done \
			--ok-label Update \
			--checklist "Found ${#displayIndex[@]} items, average price \$$t_AveragePrice" \
			$win_lines $win_cols $text_lines \
			"${itemDialog[@]}" 2>&1 1>&3)
		local rcode=$?
		debug "DIALOG EXIT $rcode"
		case $rcode in
			$DIALOG_OK) # Pressed 'OK' button - redo unless no changes (REFRESH)
				debug "DIALOG_OK"
				t_list="${displayIndex[@]}"
				[ "$response" == "$t_list" ] && return 0
				displayIndex=( $response )
				;;
			$DIALOG_EXTRA)	# Pressed 'EXTRA' button - reset and go again (NEW)
				debug "DIALOG_EXTRA"
				return 1
				;;
			$DIALOG_ESC)	# Pressed 'ESCAPE' key
				debug "DIALOG_ESCAPE"
				if [[ $resp =~ Error ]]; then
					dialog --msgbox "Error: $resp" $MSGBOX_H $MSGBOX_W
					return 
				fi
				exit $rcode
				;;
			$DIALOG_CANCEL)	# Selected "DONE" (button CANCEL) on panel
				debug "DIALOG_DONE"
				clear
				exit 0
				;;
			$DIALOG_ERROR)	# Selected "DONE" (button CANCEL) on panel
				debug "DIALOG_ERROR"
				clear
				exit $DIALOG_ERROR
				;;
			*)	debug "Weird exit code from dialog: $rcode" 
				exit $rcode
				;;
		esac
	done
}

# -----------------------------------------------------------
# MAIN
# -----------------------------------------------------------
while getopts d x_opt; do
	case $x_opt in
	d)	OPT_DEBUG=true;;
	*)	;;
	esac
done
shift $(( $OPTIND - 1 ))

exec 3>&1			# Set up FDs for dialog
$OPT_DEBUG || trap 'clear' 0

#
# Compute size of dialog box and subparts
#
declare -i tty_lines=$(tput lines 2>/dev/tty)		# Supress any 'not found' errors
declare -i tty_cols=$(tput cols 2>/dev/tty)
#
# If the script is being debugged (stderr to file) redirect stderr to /dev/tty
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

#
# The first iteration will pass command line arguments
# Subsequent iterations will pass empty argument list
# Program exit is controlled by price_tag()
#
ARGS="$*"
while true; do
	price_tag ${ARGS:-}
	ARGS=''
done
# notreached
