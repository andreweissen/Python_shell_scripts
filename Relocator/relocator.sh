#!/usr/bin/env bash

##
# This simple Bash script is used to rename image files (jpg, png, gif, and
# jpeg extensions) with a user-input prefix and move them from their source
# directory into a target destination directory. It was created by the
# author to help automate his clenaing out of his Downloads folder, which at
# the time contained a host of files with the same names as files in his
# Pictures folder. By prefixing the Downloads files with a text fragment of
# his choosing, this script helped to ensure there would be no file
# overriding when moving the Downloads images into the Pictures directory.
#
# Author: Andrew Eissen <andrew@andreweissen.com>
##

# Prompt the user for input if not all command line args are passed
if [ $# -lt 3 ]
then
  read -p "Source directory: " source_dir
  read -p "Destination directory: " destination_dir
  read -p "Prefix: " prefix
else
  source_dir="$1"
  destination_dir="$2"
  prefix="$3"
fi

# Image-based array of supported file extensions
declare -a extensions=("jpg" "png" "jpeg" "gif")

# Assemble regex for use in acquiring only image files
regex=".*\.\("
for (( i=0; i<${#extensions[@]}; i++ ))
do
  # Add both lowercase and uppercase extensions to regex
  regex+="${extensions[$i]}\|${extensions[$i]^^}"

  if [ "$i" -lt "$(( ${#extensions[@]}-1 ))" ]
  then
    regex+="\|"
  fi
done
regex+="\)"

# Grab all image files and iterate-move through each
find "$source_dir" -regex $regex -print0 | while read -r -d $'\0' file
do
  # Establish new file name and destination directory
  new_file="$destination_dir/${prefix}${file##*/}"

  # Provide status message in stdout
  echo "Moving $file to $new_file" 

  # Perform the move itself
  mv $file $new_file 
done

