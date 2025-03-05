# Auto Configure

All contained ps1 script files contained in this folder will be applied in alphabetical order for **ALL** images. It's up to the script itself to decide if needs to be applied or not (e.g. only prepare / configure docker if docker.exe exists).

## Execution time

The scripts will be executed **after** all image and package specific prepare / configure scripts are processed.

## Excluding scripts

To exclude scripts from execution prefix their name with **x_**!