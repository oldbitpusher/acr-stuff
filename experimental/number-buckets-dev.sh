declare -a BUCKETS
declare -a CHUNKS
declare -a PAILS
declare -i BUCKET_SIZE=10
declare -i BUCKET_COUNT=10

set -u

function fodder()
{
	#DEBUG trap "set +x;" RETURN; set -x
	local -i i_count=$1
	local    i_modulo=${2:-3}

	local -a t_out
	while [[ ${#t_out[@]} -lt $i_count ]]; do
		t_num=${RANDOM:$i_modulo}
		while [[ $t_num =~ ^0 ]]; do
			t_num=${t_num#0}
		done
		t_out+=( $t_num )
	done
	echo ${t_out[@]}
}

function bucket()
{
	#DEBUG trap "set +x;" RETURN; set -x
	local    i_value=${1:?Missing arg 1}

	for x_value in $*; do
		CHUNKS+=( $x_value )
		local -i t_bucket=$(( $x_value / $BUCKET_SIZE ))
		[[ -n ${BUCKETS[$t_bucket]:-} ]] || BUCKETS[$t_bucket]=0
		BUCKETS[$t_bucket]=$(( ${BUCKETS[$t_bucket]} + 1 ))
		local -i t_weight=${BUCKETS[$t_bucket]}
	done
}
	
function weight()
{
	local i_value=${1:?Missing arg 1}
	#DEBUG trap "set +x;" RETURN; set -x
		echo "load ${#CHUNKS[@]}"
	for i_value in $*; do
		local -i t_bucket=$(( $i_value / $BUCKET_SIZE ))
		local -i t_weight=${BUCKETS[$t_bucket]}
		# echo "local -i t_load=$(( ( $t_weight * 100 ) / ${#CHUNKS[@]:-1} ))
		local -i t_load=$(( ( $t_weight * 100 ) / ( ( ${#CHUNKS[@]:-1} * 10) / $BUCKET_COUNT ) ))
		printf "%8d %8d %8d\n" $i_value $t_weight $t_load
	done
}

function make_buckets()
{
	#DEBUG trap "set +x;" RETURN; set -x
	local -i i_values=${1:?Missing arg 1}

	declare -A BUCKETS
	sorted=( $(printf -- "%s\n" $* | sort -r -n ) )
	local -i t_max=${sorted[0]}
	local -i t_min=${sorted[-1]}
	
	local -i t_range=$(( $t_max - $t_min ))
	local -i t_span=$(( $t_range / $BUCKET_COUNT ))

	BUCKET_SIZE=$t_span
	if [[ $t_span -eq 0 ]]; then
		t_span=1
		BUCKET_SIZE=$t_span
	else
		local -i ws=$(( $t_span % $BUCKET_COUNT ))
		local -i wd=$(( $t_span / $BUCKET_COUNT ))
		if [[ $ws -ge 5 ]]; then
			BUCKET_SIZE=$(( ( wd + 1 ) * $BUCKET_COUNT ))
		else
			BUCKET_SIZE=$(( wd * $BUCKET_COUNT ))
		fi
	fi
	# echo make_buckets: DATA_POINTS=${#@} MAX_VALUE=$t_max MIN_VALUE=$t_min VALUE_RANGE=$t_range SPAN=$t_span BUCKET_SIZE=$BUCKET_SIZE
}

samples=$( fodder 50 2 )

BUCKET_COUNT=15
make_buckets $samples
bucket $samples
weight $samples
#readarray results <<<"$(weight $samples)"
#echo ${results[@]}



