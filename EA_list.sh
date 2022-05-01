#!/bin/zsh

# cis v2 - Audit List

echo "<result>"
/usr/libexec/PlistBuddy -c "Print" /Library/Preferences/org.cis_lvl2_suncorp.audit.plist \
  | grep -B 1 "finding = true"
echo "</result>"
