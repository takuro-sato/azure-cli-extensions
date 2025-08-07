#!/bin/bash

# Check if the correct number of arguments is provided
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <new_region_name_lowercase> <new_region_name_titlecase>"
  exit 1
fi

OLD_REGION="westeurope"
OLD_REGION_TITLE="West Europe"
NEW_REGION=$1
NEW_REGION_TITLE=$2

# Copy and rename the region specific workflow files
for FILE in .github/workflows/*$OLD_REGION.yml;
do
  NEW_FILE=$(echo $FILE | sed "s/$OLD_REGION/$NEW_REGION/")
  cp $FILE $NEW_FILE

  # Find and replace the old region name with the new region name in the new file
  sed -i "s/$OLD_REGION/$NEW_REGION/g" $NEW_FILE
  sed -i "s/$OLD_REGION_TITLE/$NEW_REGION_TITLE/g" $NEW_FILE

  echo "Processed $FILE to $NEW_FILE"
done

# Add new region workflows to README
for README in "README.md" "MORE-TESTS.md"; do
  while IFS= read -r line
  do
    # Replace both lowercase and title case occurrences of the old region
    if echo "$line" | grep -q "$OLD_REGION\|$OLD_REGION_TITLE"; then
      newline="${line//$OLD_REGION/$NEW_REGION}"
      newline="${newline//$OLD_REGION_TITLE/$NEW_REGION_TITLE}"
      echo "$newline" >> temp_readme.md
    fi
    echo "$line" >> temp_readme.md
  done < $README

  mv temp_readme.md $README
done

echo "All region specific workflows have been copied, renamed, and README.md updated."
