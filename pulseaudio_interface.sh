#!/bin/bash

# options - modify them

SINK="" # leave empty for auto-detecting
DZEN2_DISPLAY_LENGTH=5 # in seconds

PACMD_PATH="pacmd"
DZEN2_PATH="dzen2"
NOTIFY_SEND_PATH="notify-send"
PID_PATH="/tmp/pulseaudio_interface.pid" # only needed for dzen2 output



# do not modify below here

if [[ -z $SINK ]] # sink autodetection
	then SINK=$( "$PACMD_PATH" dump | sed  -ne "s/set-default-sink \(.*\)/\1/p" )
fi

DZEN2_OSD_UPDATE_INTERVALL=0.2
DZEN2_OSD_UPDATE_TIMES=$( echo "$DZEN2_DISPLAY_LENGTH/$DZEN2_OSD_UPDATE_INTERVALL" | bc )
MAX_VOLUME=65536
DZEN2_OSD=0
NOTIFY_OSD_OSD=0

get_volume()
{
	echo $(( $( "$PACMD_PATH" dump | sed -ne "s/set-sink-volume $SINK \(0x[0-9a-f]\+\)/\1/p" ) ))
}

get_volume_percent()
{
	echo $(( $( get_volume ) * 100 / $MAX_VOLUME ))
}

set_volume()
{
	if [[ $1 -gt $MAX_VOLUME ]]
		then NEW_VOL=$MAX_VOLUME
	elif [[ $1 -lt 0 ]]
		then NEW_VOL=0
	else
		NEW_VOL=$1
	fi

	"$PACMD_PATH" set-sink-volume $SINK $NEW_VOL | sed -ne "s/\(>>> \)\+\(.*\)/\2/p"
}

inc_volume()
{
	set_volume $(( $( get_volume ) + $1 ))
}

dec_volume()
{
	set_volume $(( $( get_volume ) - $1 ))
}

get_mute()
{
	"$PACMD_PATH" dump | sed -ne "s/set-sink-mute $SINK \(yes\|no\)/\1/p"
}

set_mute()
{
	"$PACMD_PATH" set-sink-mute $SINK $1 | sed -ne "s/\(>>> \)\+\(.*\)/\2/p"
}

toggle_mute()
{
	MUTE=$( get_mute )
	if [[ $MUTE = "yes" ]]
		then set_mute no
	else
		set_mute yes
	fi
}

dzen2_osd_text()
{
	TIMES_UPDATED=0

	OLD_VOLUME=$( get_volume )
	OLD_MUTE=$( get_mute )
	while [[ $TIMES_UPDATED -lt DZEN2_OSD_UPDATE_TIMES ]]
		do MUTE=$( get_mute )
		VOLUME=$( get_volume )
		VOLUME_PERCENT=$( get_volume_percent )
		
		#if the volume has changed, reset the time
		if [[ $OLD_VOLUME -ne $VOLUME ]] || [[ $OLD_MUTE != $MUTE ]]
			then TIMES_UPDATED=0
		fi

		if [[ $MUTE = "yes" ]]
			then printf "[      ^fg(red)MUTE^fg()      ]"
		else
			printf "["
			for i in $( seq $( echo "scale=2; x=$VOLUME_PERCENT / 6.25 + .5; scale=0; x/=1; x" | bc ) )
				do printf "#"
			done
			for i in $( seq $( echo "scale=2; x=(100 - $VOLUME_PERCENT) / 6.25 + .5; scale=0; x/=1; x" | bc ) )
				do printf " "
			done
			printf "]"
		fi
		printf "%3d %%\n" $( echo "scale=2; x=$VOLUME_PERCENT + 0.5; scale=0; x/=1; x" | bc )

		sleep $DZEN2_OSD_UPDATE_INTERVALL
		TIMES_UPDATED=$(( $TIMES_UPDATED + 1 ))
		OLD_VOLUME=$VOLUME
		OLD_MUTE=$MUTE
	done
}

dzen2_osd()
{
	# Allow only one osd at once
	if [[ -e "$PID_PATH" ]]
		then PID=$(cat "$PID_PATH")
		if (( $(ps p $PID o pid h) ))
			then return
		else
			rm "$PID_PATH"
		fi
	fi

	(
		# Definitely remove the pid file after the osd is closed
		trap "{ rm $PID_PATH ; }" EXIT
		echo $$ > "$PID_PATH"
		dzen2_osd_text | "$DZEN2_PATH" -fg white -bg "#222222" -x 400 -w 145 -h 16 -ta c -fn "-*-terminus-*-*-*-*-12-*-*-*-*-*-*-*"
	)
}

notify-osd_osd()
{
	VOLUME_PERCENT=$( get_volume_percent )
	MUTE=$( get_mute )

	if [[ $MUTE = "yes" ]]
		then ICON="notification-audio-volume-muted"
	elif [[ $VOLUME_PERCENT -eq 0 ]] 
		then ICON="notification-audio-volume-off"
	elif [[ $VOLUME_PERCENT -le 33 ]] 
		then ICON="notification-audio-volume-low"
	elif [[ $VOLUME_PERCENT -le 66 ]] 
		then ICON="notification-audio-volume-medium"
	else
		ICON="notification-audio-volume-high"
	fi

	"$NOTIFY_SEND_PATH" -i $ICON -h int:value:$VOLUME_PERCENT -h string:synchronous:volume " "
}

print_usage()
{
	echo "Usage: pulseaudio_interface.sh [-hgsmkidtnz]"
	echo "-h			display this message"
	echo "-g			get current volume"
	echo "-s <value>	set volume to value"
	echo "-m <yes|no>	set mute to value"
	echo "-t			toggle mute"
	echo "-k <sink>		select this sink"
	echo "-i <value>	increase volume by value"
	echo "-d <value>	decrease volume by value"
	echo "-n			display volume using notify-osd"
	echo "-z 			display volume using dzen2"
}

while getopts "hgs:m:k:i:d:znt" OPT
	do case $OPT in 
		h)	print_usage
			exit 1
			;;
		g)	printf "%d\n" $( get_volume_percent )
			;;
		s)	set_volume $(( $MAX_VOLUME * $OPTARG / 100 ))
			;;
		m)	set_mute $OPTARG
			;;
		t)	toggle_mute
			;;
		k)	SINK="$OPTARG"
			;;
		i)	inc_volume $(( $OPTARG * $MAX_VOLUME / 100 ))
			;;
		d)	dec_volume $(( $OPTARG * $MAX_VOLUME / 100 ))
			;;
		z)	DZEN2_OSD=1
			;;
		n)	NOTIFY_OSD_OSD=1
			;;
	esac
done

if (( $NOTIFY_OSD_OSD ))
	then notify-osd_osd
fi

if (( $DZEN2_OSD ))
	then dzen2_osd
fi

