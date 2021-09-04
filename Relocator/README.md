## Relocator ##

__Relocator__ is a [Bash](https://en.wikipedia.org/wiki/Bash_(Unix_shell)) [shell script](https://en.wikipedia.org/wiki/Shell_script) that assists in automating the renaming and relocation of image files from one directory to another while avoiding the possibility of overwriting files with identical names.

The script was developed by the author in response to his pressing need to clean up his Windows computer's "Downloads" folder and move its collection of image files to his "Pictures" folder. However, as there were a number of images in both directories sharing the same names, the script was built to prefix the images in the "Downloads" folder with a text fragment to preclude the possibility of files being overwritten during the move.

The script takes three command line arguments to function, namely, the path to the source directory, the path to the destination directory, and the string to use as the filename prefix. If these are not supplied, the script prompts the user to enter them manually. 
