#!/bin/sh

if [ -z "$1" ]; then
	echo Specify output name
	echo
	echo Usage: $0 '<outname>'
	exit 0
fi

outname=$1

rm -rf $outname
mkdir -p $outname
cd $outname

SWIPE_MS=30 # should not be too fast
FAILMAX=3 # detect the end of a book when screenshot doesn't change for this amount of times

capture_png () {
	fname=$1
	#echo get catpure

	# adb shell uses pty which mangles binary output.
	# https://stackoverflow.com/questions/13578416/read-binary-stdout-data-from-adb-shell
	adb exec-out screencap -p > $fname.tmp

	# remove unnecessary text like "capture from screenshot!"
	ofs=`LANG=C grep -obUaP "\x89PNG" $fname.tmp | cut -f 1 -d ':'`
	ofs=$((ofs + 1))
	#echo ofs=$ofs
	tail -c +$ofs $fname.tmp > $fname
	rm $fname.tmp

	echo $fname
}

calc_filehash() {
	fname=$1
	cropped=$1.cropped.bmp # converting to png doesn't create identical file, so convert to bmp

	# remove status area so that it ignores date or battery change
	# the height of tall cutout is around 126 on Pixel. I guess 126 is enough.
	convert $fname -crop +0+126 $cropped
	md5sum $cropped | awk '{print $1}'
	rm $cropped
}

rm -f *.png

capture_png 00000.png
hash0=$(calc_filehash 00000.png)

w=`identify -ping -format "%w" 00000.png`
h=`identify -ping -format "%h" 00000.png`
swipeL=10
swipeR=$((w - 10))
swipeY=$((h / 2))

# try to swipe from L to R.
adb shell input swipe $swipeL $swipeY $swipeR $swipeY $SWIPE_MS
sleep 2
capture_png 00001.png
hash1=$(calc_filehash 00001.png)

# if image didn't change, swipe the opposite direction
if [ "$hash0" = "$hash1" ];then
	R2L=0
	swipeS=$swipeR
	swipeE=$swipeL

	adb shell input swipe $swipeS $swipeY $swipeE $swipeY $SWIPE_MS
	sleep 2
	capture_png 00001.png
else
	R2L=1
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
		adb shell input swipe $swipeS $swipeY $swipeE $swipeY $SWIPE_MS
		sleep 2
		capture_png $fname
		hash=$(calc_filehash $fname)
		if [ "$prevhash" = "$hash" ];then
			failcount=$((failcount+1))
			if [ $failcount -gt $FAILMAX ]; then
				# skip the last page as it's likely an ad 
				echo Delete $prevfname and $fname
				rm $prevfname
				rm $fname
				break
			fi
			echo Identical png. It\'s an end of a book? Retrycnt=$failcount
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

if [ $R2L = 0 ]; then
	convert `ls *.png | sort -n` $outname.pdf
else
	convert 00000.png `ls *.png | sort -r -n` $outname.pdf
fi

# exit outout directory
cd ../
