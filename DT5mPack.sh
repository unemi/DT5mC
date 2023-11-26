#! /bin/zsh
setopt nonomatch
cd /Volumes
if [ ! -d DT5mC* ]
then open ~/Program/MediaArt/DT5mC_stuffs/DT5mC-x.dmg; sleep 1
	if [ ! -d DT5mC* ]; then echo "Could not mount the disk image.";  exit; fi
fi
A=`echo DT5mC*`
B=DT5mC`date +%y%m%d`
if [ $A != $B ]; then diskutil rename $A $B; sleep 1; fi
if open $B; then; else exit; fi
C=0
#
copyApp () {
	AD=~/Library/Developer/Xcode/Archives
	cd $AD
	D=x; for d in 20*/DT5m$1*; do D=$d; done
	if [ ! -d "$D" ]; then echo "Could not find an archive of DT5m$1."; exit; fi
	AD="$AD/$D/Products/Applications"
	if [ ! -d "$AD/DT5m$1.app" ]; then echo "Could not find DT5m$1.app in the archive."; exit; fi
	cd /Volumes/$B
	if [ -d DT5m$1.app ]
	then if [ "$AD/DT5m$1.app" -nt DT5m$1.app ]
		then echo "Remove old version of DT5m$1."; rm -rf DT5m$1.app
		else echo "DT5m$1 is not new."; C=$((C+1)); return; fi
	fi
	echo "Copy new version of DT5m$1 to $B."
	if cp -R -p "$AD/DT5m$1.app" .; then; else exit; fi
	echo -n "Position new version's icon of DT5m$1. "
	osascript -e 'tell application "Finder"
tell window "'$B'" to set position of item "'DT5m$1'" to {130, '$2'}
end tell'
}
#
copyApp C 70
copyApp S 220
cd ~/Program/MediaArt/DT5mC_stuffs
sleep 1
diskutil eject $B
sleep 1
if [ $C = 2 ]; then exit; fi
R=DT5mC-`date +%Y-%m-%d`
echo "Convert disk image to compressed format $R."
hdiutil convert DT5mC-x.dmg -format UDZO -o $R
open .
osascript -e 'tell application "Finder" to select item "'$R'.dmg" of window "DT5mC_stuffs"' > /dev/null
echo "Done."