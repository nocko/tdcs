#!/bin/bash

# The MIT License (MIT)
# Copyright (c) 2013 Shawn Nock

# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:

# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


## generate-gerbers.sh
##
## This script is designed to (for each gEDA-pcb file in the parent
## directory) generate:
##
## 1. A directory named after the pcb filename containing gerbers
##    renamed to work with OSHPark's fabrication service.
##
## 2. A zipfile containing the directory that can up uploaded
##    directly, without modification to OSHPark for fabrication.
##
## Assumptions made by this script:
##
##   1. This script expects to live in a subdirectory of the folder
##      containing your .pcb files.
##
##   2. Internal layers will be stacked in order of group
##      number. For example, in a design with the following groups:
##
##       Group 1 (top-side): Component
##       Group 2 (bottom-side): Solder
##       Group 3: Vcc
##       Group 4: GND
##       Group 5: outline
##
##      What happens is: pcb will output the gerbers with fixed-names
##      for the layers it knows about. So Group 1 (flagged as top),
##      will be output as <name>.top.gbr . Group 2 (flagged as
##      bottom), will similarly be named <name>.bottom.gbr . outline
##      layers are also detected and named appropriately by the pcb
##      export functionality.
##
##      When pcb reaches layers that it doesn't know about, it names
##      them with the absolute group number. So the internal layers on
##      this board will be exported as <name>.group3.gbr and
##      <name>.group4.gbr
##
##      This script assumes that internal layers should be stacked in
##      order of their group number (ascending). So in this example
##      the gerbers will specify a board stacking of: Component, Vcc,
##      GND, Solder . If you wanted the GND layer to appear above the
##      Vcc layer, you'd need to change the GND layer to a smaller
##      group number than Vcc in File->Preferences->Layers under the
##      "Groups" Tab.
##
##   3. This script assumes that if a layer group exists, that it is
##      important. The default pcb template has several unused (empty)
##      layers. If you don't remove them from your pcb file, this
##      script will assume you want a four layer board where the
##      internal layers are empty. This is expensive and (most-likely)
##      stupid. Remove any unused layers in your design.

## Variables
MAX_LAYERS=4 # Currently OSHPark maxes out at 4 layer boards, we'll
	     # emit a warning if this is exceeded

MAX_GROUPS=32  # What's the highest group number we should expect
	       # gEDA-pcb to have? NUM_LAYERS+1, generally. There may
	       # be workflows where this is not true. There isn't a
	       # problem setting this high

function get_layer_name {
    filename=$1
    name=$(head $filename | sed -n -e '/Title/s/.*, \([^\*]*\).*/\1/p')
    echo $name
}

# Remove any old files
find . -maxdepth 1 -name \*.zip -delete
find . -maxdepth 1 -type d -and -not -name '.' -exec rm -rf {} \;

# Generate Gerbers for each pcb file in the parent directory
for pcbname in `ls .. |sed -n -e '/\.pcb/s/\.pcb$//p'`; do
    if [[ ! -e $pcbname ]]; then
	mkdir $pcbname
    fi
    pcb -x gerber --all-layers --name-style fixed --gerberfile $pcbname/$pcbname ../$pcbname.pcb
done

# Remove Paste files, OSHPark doesn't do stencils
find . -name \*paste\* -delete

# Remove empty silk layers
find . -name \*silk\* -size -380c -delete

# Oshpark is picky about internal layer naming (4 layer boards).
count=0
for pcbname in `ls .. |sed -n -e '/\.pcb/s/\.pcb$//p'`; do
    for layer in `seq 1 $MAX_GROUPS`; do
	if [[ -e $pcbname/$pcbname.group$layer.gbr ]]; then
	    if [[ `stat -c%s $pcbname/$pcbname.group$layer.gbr` -lt 2500 ]]; then
		layer_name=$(get_layer_name $pcbname/$pcbname.group$layer.gbr)
		echo "WARNING: Layer '$layer_name' is probably empty"
	    fi
	    mv $pcbname/$pcbname.group$layer.gbr $pcbname/$pcbname.G$(($count+2))L
	    count=$(( $count+1 ))
	fi
    done

    # Warn if non-standard layer count
    if [[ $(( $count % 2 )) = 1 ]]; then
	echo "WARNING: There are $(( $count+2 )) layers, did you mean to have a $(( $count+3 )) layer board? If so, add another empty layer."
    fi

    # Warn if more layers than OSHPark can do
    if [[ $(( $count+2 )) -gt $MAX_LAYERS ]]; then
	echo "WARNING: Detected $(( $count+2 )) layer board; OSHPark maxes out at $MAX_LAYERS"
    fi

    # Write a summary of the generated layers and their ordering
    echo -n "Processed $pcbname.pcb: $(( $count+2 )) layers. "
    layers="$pcbname/$pcbname.top.gbr"
    if [[ ! $count -eq 0 ]]; then
	for i in `seq 2 $(( $count+1 ))`; do
	    layers+=" $pcbname/$pcbname.G${i}L"
	done
    fi
    layers+=" $pcbname/$pcbname.bottom.gbr"
    i=0
    for layer in $layers; do
	name=$(get_layer_name $layer)
	if [[ $i -eq 0 ]]; then
	    echo -n "[ $name |"
	elif [[ $i -eq $(( $count+1 )) ]]; then
	    echo " $name ]"
	else
	    echo -n " $name |"
	fi
	i=$(( $i+1 ))
    done
    count=0
done

# Compress Gerbers
find . -maxdepth 1 -type d -and -not -name '.' -exec zip -r {} {} \; > /dev/null
