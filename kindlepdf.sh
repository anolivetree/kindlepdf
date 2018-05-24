#!/bin/sh

SWIPE_MS=30 # should not be too fast
FAILMAX=3

capture_png () {
	fname=$1
	# adb shell uses pty which mangles binary output.
	# https://stackoverflow.com/questions/13578416/read-binary-stdout-data-from-adb-shell
	echo get catpure
	adb exec-out screencap -p > $fname.tmp
	# remove unnecessary text like "capture from screenshot!"
	ofs=`LANG=C grep -obUaP "\x89PNG" $fname.tmp | cut -f 1 -d ':'`
	ofs=$((ofs + 1))
	echo ofs=$ofs
	tail -c +$ofs $fname.tmp > $fname
	rm $fname.tmp
}

rm -f *.png

capture_png 00000.png
hash0=`md5sum 00000.png|awk '{print $1}'`

w=`identify -ping -format "%w" 00000.png`
h=`identify -ping -format "%h" 00000.png`
swipeL=10
swipeR=$((w - 10))
swipeY=$((h / 2))

# try to swipe from L to R.
adb shell input swipe $swipeL $swipeY $swipeR $swipeY $SWIPE_MS
sleep 2
capture_png 00001.png
hash1=`md5sum 00001.png|awk '{print $1}'`

# if image didn't change, swipe the opposite direction
if [ "$hash0" = "$hash1" ];then
	swipeS=$swipeR
	swipeE=$swipeL

	adb shell input swipe $swipeS $swipeY $swipeE $swipeY $SWIPE_MS
	sleep 2
	capture_png 00001.png
else
	swipeS=$swipeL
	swipeE=$swipeR
fi

#echo $swipeL $swipeR $swipeY 



prevhash=$hash1
prevfname="00001.png"
failcount=0

for i in $(seq -f "%05g" 2 99999)
do
	while true; do
		fname=$i.png
		echo $fname
		adb shell input swipe $swipeS $swipeY $swipeE $swipeY $SWIPE_MS
		sleep 2
		capture_png $fname
		hash=`md5sum $fname|awk '{print $1}'`
		if [ "$prevhash" = "$hash" ];then
			failcount=$((failcount+1))
			if [ $failcount -gt $FAILMAX ]; then
				rm $prevfname
				rm $fname
				break
			fi
			echo failcount=$failcount
			continue
		fi
		failcount=0
		prevhash=$hash
		prevfname=$fname
		break
	done

	if [ $failcount -gt $FAILMAX ]; then
		break
	fi
done

# Don't know how many gray shades e-ink supports. 256 should be enough.
mogrify -format png -colorspace Gray -colors 256 *.png

convert `ls *.png | sort -n` file.pdf


